# galegis-api -- Structured Importing and RESTful providing of GA General Assembly Activity.
# Copyright (C) 2013 Matthew Farmer - Distributed Under the GNU AGPL 3.0. See LICENSE at project root.
helpers = require '../util/helpers'
ifSuccessful = helpers.ifSuccessful

soap = require 'soap'
ObjectId = require('mongodb').ObjectID
legislationSvcUri = "./wsdl/Legislation.svc.xml"

# Data returned by node-soap that was nil in the output is represented
# as an empty object for some reason...
stringOrUndefined = (input) ->
  if typeof input == 'string'
    input
  else
    null

eliminateUndefineds = (obj) ->
  for key, val of obj
    if typeof val == 'undefined' || val == null
      delete obj[key]
    else if typeof val == 'object'
      if Object.getOwnPropertyNames(val).length == 0
        delete obj[key]

  obj

persistLegislationDetail = (legislationId, legislationDetail, db, callback) ->
  parseStatus = (status) ->
    code: status.Code
    date: new Date(status.Date)
    description: stringOrUndefined(status.Description)

  parseLatestVersion = (latestVersion) ->
    description: latestVersion.Description
    assemblyId: Number(latestVersion.Id)
    version: Number(latestVersion.Version)
    url: latestVersion.Url

  legislationDetail =
    summary: stringOrUndefined(legislationDetail.Summary)
    actVetoNumber: stringOrUndefined(legislationDetail.ActVetoNumber)
    footnotes: stringOrUndefined(legislationDetail.Footnotes)
    status: parseStatus(legislationDetail.Status)
    latestVersion: parseLatestVersion(legislationDetail.LatestVersion)

  db.collection("legislation").update
    _id: legislationId
  ,
    "$set": eliminateUndefineds(legislationDetail)
  , (err, doc) ->
    ifSuccessful err, callback, ->
      callback()

persistLegislationIndex = (session, legislationIndex, db, callback) ->
  assemblyIdForLegislation = Number(legislationIndex.Id)

  codeParts = legislationIndex.Description.split(" ")
  chamber = if codeParts[0][0] == 'H' then 'house' else 'senate'
  legType = if codeParts[0][1] == 'R' then 'resolution' else 'bill'
  number = codeParts[1]

  legislationIndex =
    sessionId: session._id,
    title: legislationIndex.Caption,
    code: legislationIndex.Description,
    chamber: chamber,
    type: legType,
    number: number

  db.collection("legislation").update
    assemblyId: assemblyIdForLegislation
  ,
    "$set": legislationIndex
  ,
    upsert: true,
    safe: true
  , (err, doc) ->
    ifSuccessful err, callback, ->
      callback()

module.exports = (jobs, db) -> soap.createClient legislationSvcUri, (err, client) ->
  throw err if err

  jobs.process 'import legislation detail', 5, (job, callback) ->
    # Ensure legislation object ID is in the proper format
    job.data.legislation._id = new ObjectId(job.data.legislation._id)

    getLegislationDetailArgs =
      LegislationId: job.data.legislation.assemblyId

    client.LegislationService.BasicHttpBinding_LegislationSearch.GetLegislationDetail getLegislationDetailArgs, (err, result, raw) -> ifSuccessful err, callback, ->
      persistLegislationDetail(job.data.legislation._id, result.GetLegislationDetailResult, db, callback)

  jobs.process 'import legislation detail for session', 5, (job, callback) ->
    # Ensure object IDs are in the correct format.
    job.data.session._id = new ObjectId(job.data.session._id)

    db.collection("legislation").find(sessionId: job.data.session._id).toArray (err, results) -> ifSuccessful err, callback, ->
      results.forEach(legislation) ->
        jobs.create('import legislation detail', legislation: legislation)

      callback()

  jobs.process 'import legislation for session', 5, (job, callback) ->
    # Ensure object IDs are in the correct format.
    job.data.session._id = new ObjectId(job.data.session._id)

    getLegislationArgs =
      SessionId: job.data.session.assemblyId

    client.LegislationService.BasicHttpBinding_LegislationSearch.GetLegislationForSession getLegislationArgs, (err, result, raw) -> ifSuccessful err, callback, ->
      result.GetLegislationForSessionResult.LegislationIndex.forEach (legislationIndex) ->
        persistLegislationIndex job.data.session, legislationIndex, db, callback

  jobs.process 'import legislation', (job, callback) ->
    db.collection("sessions").find().toArray (err, results) -> ifSuccessful err, callback, ->
      results.forEach (session) ->
        jobs.create('import legislation for session', session: session).save()

      callback()
