helpers = require './testHelpers'
chai = require 'chai'
MongoClient = require 'mongodb'
http = require 'http'

validatePage = helpers.validatePage
chai.should()
MongoClient.MongoClient

describe 'Members', ->

  it 'should return 200 when we hit /api/v1/members', (done) ->
    validatePage("members", done)
