/* ===========================================================
# sphere-shipment-stock-modifier - v0.0.4
# ==============================================================
# Copyright (c) 2013 Hajo Eichler
# Licensed under the MIT license.
*/
var CommonUpdater, Q, Rest, ShipmentStockModifier, _,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

_ = require('underscore')._;

Rest = require('sphere-node-connect').Rest;

CommonUpdater = require('sphere-node-sync').CommonUpdater;

Q = require('q');

ShipmentStockModifier = (function(_super) {
  __extends(ShipmentStockModifier, _super);

  function ShipmentStockModifier(options) {
    if (options == null) {
      options = {};
    }
    if (!options.config) {
      throw new Error('No configuration in options!');
    }
    this.rest = new Rest({
      config: options.config
    });
    this.NAMESPACE = 'ShipmentStockModifier';
    this.STATE_INIT = 0;
    this.STATE_MODIFING = -1;
    this.STATE_SHIPPED = 1;
    this.STATE_NOT_SHIPPED = 2;
  }

  ShipmentStockModifier.prototype.elasticio = function(msg, cfg, cb, snapshot) {
    var orders;
    if (msg.body) {
      orders = msg.body.results;
      return this.run(orders, cb);
    } else {
      return this.returnResult(false, 'No data found in elastic.io msg!', cb);
    }
  };

  ShipmentStockModifier.prototype.getOrders = function(rest) {
    var deferred;
    deferred = Q.defer();
    this.rest.GET("/orders?limit=0", function(error, response, body) {
      var orders;
      if (error) {
        return deferred.reject("Error on fetching orders: " + error);
      } else if (response.statusCode !== 200) {
        return deferred.reject(("Problem on fetching orders (status: " + response.statusCode + "): ") + body);
      } else {
        orders = JSON.parse(body).results;
        return deferred.resolve(orders);
      }
    });
    return deferred.promise;
  };

  ShipmentStockModifier.prototype.run = function(orders, callback) {
    var order, promises, _i, _len,
      _this = this;
    if (!_.isFunction(callback)) {
      throw new Error('Callback must be a function!');
    }
    if (_.size(orders) === 0) {
      this.returnResult(true, 'Nothing to do.', callback);
      return;
    }
    promises = [];
    for (_i = 0, _len = orders.length; _i < _len; _i++) {
      order = orders[_i];
      promises.push(this.modifyOrder(order));
    }
    return Q.all(promises).then(function(msg) {
      return _this.returnResult(true, msg, callback);
    }).fail(function(msg) {
      return _this.returnResult(false, msg, callback);
    });
  };

  ShipmentStockModifier.prototype.modifyOrder = function(order) {
    var deferred,
      _this = this;
    deferred = Q.defer();
    this.getState(order).then(function(state) {
      var action, mod, posts, result, _i, _len, _ref;
      result = _this.modifyState(order, state);
      posts = [];
      _ref = result.actions;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        action = _ref[_i];
        posts.push(_this.updateInventoryEntry(action));
      }
      _this.tickProgress();
      if (_.size(posts) === 0) {
        return deferred.resolve("Nothing to update.");
      } else {
        mod = _.clone(state);
        mod.status = _this.STATE_MODIFING;
        return _this.saveState(order, mod).then(function(msg) {
          return Q.all(posts).then(function(msg) {
            return _this.saveState(order, result.state).then(function(msg) {
              return deferred.resolve("Inventory updated.");
            }).fail(function(msg) {
              return deferred.reject(msg);
            });
          }).fail(function(msg) {
            return deferred.reject(msg);
          });
        }).fail(function(msg) {
          return deferred.reject(msg);
        });
      }
    }).fail(function(msg) {
      return deferred.reject(msg);
    });
    return deferred.promise;
  };

  ShipmentStockModifier.prototype.initState = function(order) {
    var obj;
    obj = {
      status: this.STATE_INIT,
      changes: {}
    };
    this.eachSKU(order, function(sku, lineItem) {
      return obj.changes[sku] = 0;
    });
    return obj;
  };

  ShipmentStockModifier.prototype.getState = function(order) {
    var deferred,
      _this = this;
    deferred = Q.defer();
    this.rest.GET("/custom-objects/" + this.NAMESPACE + "/" + order.id, function(error, response, body) {
      var obj;
      if (error) {
        return deferred.reject('Error on fetching modifier state info: ' + error);
      } else {
        if (response.statusCode === 200) {
          return deferred.resolve(JSON.parse(body).value);
        } else if (response.statusCode === 404) {
          obj = _this.initState(order);
          return deferred.resolve(obj);
        } else {
          return deferred.reject('Problem on fetching modifier state info: ' + body);
        }
      }
    });
    return deferred.promise;
  };

  ShipmentStockModifier.prototype.modifyState = function(order, state) {
    var res;
    res = {
      state: state,
      actions: []
    };
    if (order.shipmentState === 'Shipped' && state.status !== this.STATE_SHIPPED) {
      this.eachSKU(order, function(sku, lineItem) {
        var a;
        res.state.changes[sku] = lineItem.quantity;
        a = {
          sku: sku,
          quantity: lineItem.quantity,
          action: 'removeQuantity'
        };
        return res.actions.push(a);
      });
      res.state.status = this.STATE_SHIPPED;
    } else if (order.shipmentState !== 'Shipped' && state.status === this.STATE_SHIPPED) {
      this.eachSKU(order, function(sku, lineItem) {
        var a;
        res.state.changes[sku] = 0;
        a = {
          sku: sku,
          quantity: lineItem.quantity,
          action: 'addQuantity'
        };
        return res.actions.push(a);
      });
      res.state.status = this.STATE_NOT_SHIPPED;
    }
    return res;
  };

  ShipmentStockModifier.prototype.eachSKU = function(order, each) {
    var li, sku, _i, _len, _ref, _results;
    if (order.lineItems) {
      _ref = order.lineItems;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        li = _ref[_i];
        if (li.variant && li.variant.sku) {
          sku = li.variant.sku;
          _results.push(each(sku, li));
        } else {
          _results.push(void 0);
        }
      }
      return _results;
    }
  };

  ShipmentStockModifier.prototype.validateState = function(order, state) {};

  ShipmentStockModifier.prototype.saveState = function(order, state) {
    var deferred, obj;
    deferred = Q.defer();
    obj = {
      container: this.NAMESPACE,
      key: order.id,
      value: state
    };
    this.rest.POST("/custom-objects", JSON.stringify(obj), function(error, response, body) {
      if (error) {
        return deferred.reject("Error on updating modifier state info: " + error);
      } else {
        if (response.statusCode === 201 || response.statusCode === 200) {
          return deferred.resolve("Modifier state saved.");
        } else {
          return deferred.reject(("Problem on updating modifier state (status: " + response.statusCode + "): ") + body);
        }
      }
    });
    return deferred.promise;
  };

  ShipmentStockModifier.prototype.updateInventoryEntry = function(action) {
    var deferred, query,
      _this = this;
    deferred = Q.defer();
    query = encodeURIComponent("sku=\"" + action.sku + "\"");
    this.rest.GET("/inventory?where=" + query, function(error, response, body) {
      var data, entries, inventoryEntry;
      if (error) {
        return deferred.reject('Error on getting inventory entry: ' + error);
      } else {
        if (response.statusCode === 200) {
          entries = JSON.parse(body).results;
          if (_.size(entries) === 0) {
            return deferred.reject("Can't find inventory entry for SKU '" + action.sku + "'");
          } else {
            inventoryEntry = entries[0];
            data = {
              version: inventoryEntry.version,
              actions: [action]
            };
            return _this.rest.POST("/inventory/" + inventoryEntry.id, JSON.stringify(data), function(error, response, body) {
              if (error) {
                return deferred.reject('Error on updating inventory entry: ' + error);
              } else {
                if (response.statusCode === 201 || response.statusCode === 200) {
                  return deferred.resolve("Inventory entry unpdated.");
                } else {
                  return deferred.reject(("Problem on updating inventory entry (status: " + response.statusCode + "): ") + body);
                }
              }
            });
          }
        } else {
          return deferred.reject(("Problem on getting inventory entry (status: " + response.statusCode + "): ") + body);
        }
      }
    });
    return deferred.promise;
  };

  return ShipmentStockModifier;

})(CommonUpdater);

module.exports = ShipmentStockModifier;
