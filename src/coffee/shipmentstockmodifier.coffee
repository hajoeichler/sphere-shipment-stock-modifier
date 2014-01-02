_ = require('underscore')._
Rest = require('sphere-node-connect').Rest
ProgressBar = require 'progress'
logentries = require 'node-logentries'
Q = require 'q'

class ShipmentStockModifier
  constructor: (@options) ->
    throw new Error 'No configuration in options!' if not @options or not @options.config
    @rest = new Rest config: @options.config
    @log = logentries.logger token: @options.logentries.token if @options.logentries
    @NAMESPACE = 'ShipmentStockModifier'
    @STATE_INIT = 0
    @STATE_MODIFING = -1
    @STATE_SHIPPED = 1
    @STATE_NOT_SHIPPED = 2

  elasticio: (msg, cfg, cb, snapshot) ->
    if msg.body
      orders = msg.body.results
      @run(orders, cb)
    else
      @returnResult false, 'No data found in elastic.io msg!', cb

  getOrders: (rest) ->
    deferred = Q.defer()
    @rest.GET "/orders?limit=0", (error, response, body) ->
      if error
        deferred.reject "Error on fetching orders: " + error
      else if response.statusCode != 200
        deferred.reject "Problem on fetching orders (status: #{response.statusCode}): " + body
      else
        orders = JSON.parse(body).results
        deferred.resolve orders
    deferred.promise

  run: (orders, callback) ->
    throw new Error 'Callback must be a function!' unless _.isFunction callback
    # TODO

  modifyOrder: (order) ->
    deferred = Q.defer()
    @getState(order).then (state) =>
      state.state = @STATE_MODIFING
      @saveState(state).then (msg) =>
        @modifyState(order, state).then (result) =>
          posts = []
          for action in result.actions
            posts.push updateInventoryItem(action)
          Q.all(posts).then (msg) =>
            @saveState(result.state).then (msg) =>

  returnResult: (positiveFeedback, msg, callback) ->
    if @options.showProgress
      @bar.terminate() if @bar
    d =
      component: 'ShipmentStockModifier'
      status: positiveFeedback
      msg: msg
    if @log
      logLevel = if positiveFeedback then 'info' else 'err'
      @log.log logLevel, d
    callback d

  initState: (order) ->
    obj =
      state: @STATE_INIT
      changes: {}
    @eachSKU order, (sku, lineItem) ->
      obj.changes[sku] = 0
    obj

  getState: (order) ->
    deferred = Q.defer()
    @rest.GET "/custom-objects/#{@NAMESPACE}/#{order.id}", (error, response, body) =>
      if error
        deferred.reject 'Error on fetching modifier state info: ' + error
      else
        if response.statusCode is 200
          deferred.resolve JSON.parse(body)
        else if response.statusCode is 404
          obj = @initState order
          deferred.resolve obj
        else
          deferred.reject 'Problem on fetching modifier state info: ' + body
    deferred.promise

  modifyState: (order, state) ->
    res =
      state: state
      actions: []
    if order.shipmentState is 'Shipped'
      @eachSKU order, (sku, lineItem) ->
        res.state.changes[sku] = lineItem.quantity
        action =
          version: 1
          actions: [
            # TODO
          ]
        res.actions.push action
      res.state.state = @STATE_SHIPPED
    else
      @eachSKU order, (sku, _) ->
        res.state[sku] = 0
      res.state.state = @STATE_NOT_SHIPPED
    res

  eachSKU: (order, each) ->
    if order.lineItems
      for li in order.lineItems
        if li.variant and li.variant.sku
          sku = li.variant.sku
          each(sku, li)

  validateState: (order, state) ->
    # TODO

  saveState: (order, state) ->
    deferred = Q.defer()
    @rest.POST "/custom-objects/#{@NAMESPACE}/#{order.id}", JSON.stringify(state), (error, response, body) ->
      if error
        deferred.reject 'Error on updating modifier state info: ' + error
      else
        if response.statusCode is 200
          deferred.resolve JSON.parse body
        else
          deferred.reject 'Problem on updating order status (status: #{response.statusCode}): ' + body
    deferred.promise

  updateInventory: (action) ->
    deferred = Q.defer()
    @rest.GET "/inventory?where=#{query}", (error, response, body) =>
      if error
        deferred.reject 'Error on getting inventory entry: ' + error
      else
        if response.statusCode is 200
          inventoryEntry = JSON.parse body
          data =
            version: inventoryEntry.version
            actions: [ action ]
          @rest.POST "/inventory/#{inventoryEntry.id}", JSON.stringify(data), (error, response, body) ->
            if error
              deferred.reject 'Error on updating inventory entry: ' + error
            else
              if response.statusCode is 200
                deferred.resolve body
              else
                'Problem on updating inventory entry (status: #{response.statusCode}): ' + body
        else
          deferred.reject 'Problem on getting inventory entry (status: #{response.statusCode}): ' + body
    deferred.promise

module.exports = ShipmentStockModifier