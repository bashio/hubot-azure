# Description:
#   Implementation of Hubot Brain using Azure Blob Storage
#
# Dependencies:
#   "azure-storage": "~0.2.0"
#
# Configuration:
#   HUBOT_BRAIN_AZURE_CONNSTRING          - Connection string for the Azure blob storage instance
#   HUBOT_BRAIN_AZURE_STORAGE_CONTAINER   - Azure Storage Blob container name (defaults to 'hubot')
#   HUBOT_BRAIN_USE_STORAGE_EMULATOR      - Use the Azure Storage Emulator if defined
#   HUBOT_BRAIN_DISABLED                  - Disable Azure Brain if defined
#
# Commands:
#   None
#

util    = require "util"
azure   = require "azure-storage"

module.exports = (robot) ->

  loaded            = false
  initializing      = false
  connectionString  = process.env.HUBOT_BRAIN_AZURE_CONNSTRING
  containerName     = process.env.HUBOT_BRAIN_AZURE_STORAGE_CONTAINER or "hubot"
  useEmulator       = process.env.HUBOT_BRAIN_USE_STORAGE_EMULATOR
  brainIsDisabled    = process.env.HUBOT_BRAIN_DISABLED
  blobName          = "brain-dump.json"
  lastBrainData     = ""

  ## support deprecation of https://github.com/bfcamara/hubot-azure-scripts/
  account = process.env.HUBOT_BRAIN_AZURE_STORAGE_ACCOUNT
  accessKey = process.env.HUBOT_BRAIN_AZURE_STORAGE_ACCESS_KEY
  if account or accessKey
    robot.logger.warning("HUBOT_BRAIN_AZURE_STORAGE_ACCOUNT and HUBOT_BRAIN_AZURE_STORAGE_ACCESS_KEY are deprecated. You should be using HUBOT_BRAIN_AZURE_CONNSTRING instead.")
  if account and accessKey
    blobSvc = azure.createBlobService account, accessKey
  ## end deprecation code
  else if brainIsDisabled
    robot.logger.debug "hubot-azure-brain has been explicitly disabled, HUBOT_BRAIN_ENABLED=false"
  else if useEmulator
    blobSvc = azure.createBlobService azure.generateDevelopmentStorageCredentials()
  else if !connectionString
    throw new Error "hubot-azure-brain requires HUBOT_BRAIN_AZURE_CONNSTRING"
  else
    blobSvc = azure.createBlobService connectionString

  init = ()->
    if brainIsDisabled
      robot.logger.debug "hubot-azure-brain has been explicitly disabled, initialization failed."
      return

    initializing = true
    blobSvc.createContainerIfNotExists containerName, (err, justCreated, response) ->
      initializing = false

      if err
        robot.logger.error "Error checking if container exists: #{util.inspect(err)}"
        return

      # we have the container already created
      if justCreated.created
        robot.logger.info "Just finished to create the container. There's no data to read."
        robot.brain.mergeData {}
        loaded = true
      else
        robot.logger.info "The container already exists."
        loadBrain()

  saveBrain = (data)->
    if brainIsDisabled
      robot.logger.debug "hubot-azure-brain has been explicitly disabled, save failed."
      return

    if !loaded
      robot.logger.debug "Not saving to Azure Storage Blob, because not loaded yet"
      init() if not initializing
      return

    brainData = JSON.stringify(data)
    if brainData is lastBrainData
      robot.logger.debug "Not saving to Azure Storage Blog, because no changes were detected in brain"
      return

    blobSvc.createBlockBlobFromText containerName, blobName, JSON.stringify(data), (err, blob, res) ->
      if err
        robot.logger.error "Error storing brain to Azure Storage Blob #{containerName}: #{util.inspect(err)}"
        init() if err.statusCode is 404 and not initializing
      else
        lastBrainData = brainData
        robot.logger.debug "Saved brain with success to #{containerName}"

  loadBrain = ->
    if brainIsDisabled
      robot.logger.debug "hubot-azure-brain has been explicitly disabled, load failed."
      return

    blobSvc.getBlobToText containerName, blobName, (err, text)->
      if err
        robot.logger.error "Error getting brain from Azure Storage Blob #{containerName}: #{util.inspect(err)}"
        if err.statusCode is 404
          robot.logger.info "The blob doesn't exist yet. Initialiazing new brain data"
          robot.brain.mergeData {}
          loaded = true
      else
        robot.logger.debug "Brain loaded from blob storage"
        robot.brain.mergeData JSON.parse(text)
        loaded = true

  init()

  robot.brain.on 'save', (data)->
    saveBrain(data)

  robot.brain.on 'close', ->
    saveBrain(robot.brain.data)
