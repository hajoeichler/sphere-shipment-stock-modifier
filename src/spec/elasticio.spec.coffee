elasticio = require('../elasticio.js')
Config = require '../config'

describe 'elasticio integration', ->
  it 'no body', (done) ->
    cfg =
      clientId: 'some'
      clientSecret: 'stuff'
      projectKey: 'here'
    msg = ''
    elasticio.process msg, cfg, (next) ->
      expect(next.status).toBe false
      expect(next.message).toBe 'No data found in elastic.io msg!'
      done()

  it 'one order now shipped', (done) ->
    cfg =
      clientId: Config.config.client_id
      clientSecret: Config.config.client_secret
      projectKey: Config.config.project_key
    order =
      id: "id" + new Date().getTime()
      version: 7

    msg =
      body:
        results: [ order ]

    elasticio.process msg, cfg, (next) ->
      expect(next.status).toBe true
      expect(next.message[0]).toBe 'Inventory updated.'
      done()