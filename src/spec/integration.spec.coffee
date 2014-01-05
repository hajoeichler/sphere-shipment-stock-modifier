_ = require('underscore')._
Config = require '../config'
ShipmentStockModifier = require('../main').ShipmentStockModifier
Q = require('q')

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 20000

describe '#run', ->
  beforeEach ->
    @modifier = new ShipmentStockModifier Config

  it 'Nothing to do', (done) ->
    @modifier.run [], (msg) ->
      expect(msg.status).toBe true
      expect(msg.message).toBe 'Nothing to do.'
      done()

  it 'reduce stock', (done) ->
    unique = new Date().getTime()
    sku = "mySKU-#{unique}"
    order =
      id: "ID#{unique}"
      shipmentState: 'Shipped'
      lineItems: [ {
        sku: sku
        variant:
          sku: sku
        quantity: 3
      } ]

    inventoryEntry =
      sku: sku
      quantityOnStock: 7
      
    @modifier.rest.POST '/inventory', JSON.stringify(inventoryEntry), (error, response, body) =>
      @modifier.run [order], (msg) =>
        expect(msg.status).toBe true
        expect(msg.message).toBe 'Inventory updated.'
        @modifier.rest.GET "/inventory?where=" + encodeURIComponent("sku=\"#{sku}\""), (error, response, body) =>
          inventoryEntries = JSON.parse(body).results
          expect(inventoryEntries[0].quantityOnStock).toBe 4
          @modifier.run [order], (msg) =>
            expect(msg.status).toBe true
            @modifier.rest.GET "/inventory?where=" + encodeURIComponent("sku=\"#{sku}\""), (error, response, body) ->
              inventoryEntries = JSON.parse(body).results
              expect(inventoryEntries[0].quantityOnStock).toBe 4
              done()
      .fail (msg) ->
        console.log msg
        expect(false).toBe true
        done()
