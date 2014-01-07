/* ===========================================================
# sphere-shipment-stock-modifier - v0.0.6
# ==============================================================
# Copyright (c) 2013 Hajo Eichler
# Licensed under the MIT license.
*/
var ShipmentStockModifier, argv, modifier, options;

argv = require('optimist').usage('Usage: $0 --projectKey key --clientId id --clientSecret secret').demand(['projectKey', 'clientId', 'clientSecret']).argv;

ShipmentStockModifier = require('../main').ShipmentStockModifier;

options = {
  config: {
    project_key: argv.projectKey,
    client_id: argv.clientId,
    client_secret: argv.clientSecret
  }
};

modifier = new ShipmentStockModifier(options);

modifier.getOrders(modifier.rest).then(function(orders) {
  return modifier.run(orders, function(msg) {
    console.log(msg);
    if (!msg.status) {
      return process.exit(1);
    }
  });
}).fail(function(msg) {
  console.log(msg);
  return process.exit(2);
});
