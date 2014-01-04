argv = require('optimist')
  .usage('Usage: $0 --projectKey key --clientId id --clientSecret secret')
  .demand(['projectKey','clientId', 'clientSecret'])
  .argv
ShipmentStockModifier = require('../main').ShipmentStockModifier

options =
  config:
    project_key: argv.projectKey
    client_id: argv.clientId
    client_secret: argv.clientSecret

modifier = new ShipmentStockModifier options
modifier.getOrders(modifier.rest).then (orders) ->
  modifier.run orders, (msg) ->
    console.log msg
.fail (msg) ->
  console.log msg
  process.exit -1