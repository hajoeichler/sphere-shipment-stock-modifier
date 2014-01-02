_ = require('underscore')._
Config = require '../config'
ShipmentStockModifier = require('../main').ShipmentStockModifier
Q = require('q')

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 10000

describe '#run', ->
  beforeEach ->
    @modifier = new ShipmentStockModifier Config

  xit 'Nothing to do', (done) ->
    @modifier.run [], (msg) ->
      expect(msg.status).toBe true
      expect(msg.message).toBe 'Nothing to do.'
      done()

  it 'reduce stock', (done) ->
    unique = new Date().getTime()
    order =
      id: "ID#{unique}"
      shipmentState: 'Shipped'
      lineItems: [ {
        sku: "mySKU"
        variant:
          sku: "mySKU"
        quantity: 3
      } ]

    inventoryEntry =
      sku: "mySKU"
      quantityOnStock: 7
      
    @modifier.rest.POST '/inventory', JSON.stringify(inventoryEntry), (error, response, body) =>
      @modifier.run [order], (msg) ->
        expect(msg.status).toBe true
        expect(msg.message.length).toBe 1
        expect(msg.message[0]).toBe 'Inventory updated'
        done()
      .fail (msg) ->
        console.log msg
        expect(false).toBe true
        done()
