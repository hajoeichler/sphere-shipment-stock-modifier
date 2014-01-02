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
    if orders.length is 0
      @returnResult true, 'Nothing to do.', callback
      return
    promises = []
    for order in orders
      promises.push @modifyOrder(order)
    Q.all(promises).then (msg) =>
      @returnResult true, msg, callback
    .fail (msg) =>
      @returnResult false, msg, callback

  modifyOrder: (order) ->
    deferred = Q.defer()
    @getState(order).then (state) =>
      state.status = @STATE_MODIFING
      @saveState(order, state).then (msg) =>
        result = @modifyState order, state
        posts = []
        for action in result.actions
          posts.push @updateInventoryEntry(action)
        Q.all(posts).then (msg) =>
          @saveState(order, result.state).then (msg) ->
            deferred.resolve "Inventory updated."
          .fail (msg) ->
            deferred.reject msg
        .fail (msg) ->
          deferred.reject msg
      .fail (msg) ->
        deferred.reject msg
    .fail (msg) ->
      deferred.reject msg
    deferred.promise

  returnResult: (positiveFeedback, msg, callback) ->
    if @options.showProgress
      @bar.terminate() if @bar
    d =
      component: 'ShipmentStockModifier'
      status: positiveFeedback
      message: msg
    if @log
      logLevel = if positiveFeedback then 'info' else 'err'
      @log.log logLevel, d
    callback d

  initState: (order) ->
    obj =
      status: @STATE_INIT
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
          deferred.resolve JSON.parse(body).value
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
        a =
          sku: sku
          quantity: lineItem.quantity
          action: 'removeQuantity'
        res.actions.push a
      res.state.status = @STATE_SHIPPED
    else
      @eachSKU order, (sku, lineItem) ->
        res.state.changes[sku] = 0
        a =
          sku: sku
          quantity: lineItem.quantity
          action: 'addQuantity'
        res.actions.push a
      res.state.status = @STATE_NOT_SHIPPED
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
    obj =
      container: @NAMESPACE
      key: order.id
      value: state
    @rest.POST "/custom-objects", JSON.stringify(obj), (error, response, body) ->
      if error
        deferred.reject "Error on updating modifier state info: " + error
      else
        if response.statusCode is 201 or response.statusCode is 200
          deferred.resolve "Modifier state saved."
        else
          deferred.reject "Problem on updating modifier state (status: #{response.statusCode}): " + body
    deferred.promise

  updateInventoryEntry: (action) ->
    deferred = Q.defer()
    query = encodeURIComponent "sku=\"#{action.sku}\""
    @rest.GET "/inventory?where=#{query}", (error, response, body) =>
      if error
        deferred.reject 'Error on getting inventory entry: ' + error
      else
        if response.statusCode is 200
          entries = JSON.parse(body).results
          if entries.length is 0
            deferred.reject "Can't find inventory entry for SKU '#{action.sku}'"
          else
            inventoryEntry = entries[0]
            data =
              version: inventoryEntry.version
              actions: [ action ]
            @rest.POST "/inventory/#{inventoryEntry.id}", JSON.stringify(data), (error, response, body) ->
              if error
                deferred.reject 'Error on updating inventory entry: ' + error
              else
                if response.statusCode is 201 or response.statusCode is 200
                  deferred.resolve "Inventory entry unpdated."
                else
                  deferred.reject "Problem on updating inventory entry (status: #{response.statusCode}): " + body
        else
          deferred.reject "Problem on getting inventory entry (status: #{response.statusCode}): " + body
    deferred.promise

module.exports = ShipmentStockModifier