ShipmentStockModifier = require('../main').ShipmentStockModifier

xdescribe 'ShipmentStockModifier', ->
  it 'should throw error that there is no config', ->
    expect(-> new ShipmentStockModifier()).toThrow new Error 'No configuration in options!'
    expect(-> new ShipmentStockModifier({})).toThrow new Error 'No configuration in options!'

createModifier = () ->
  c =
    project_key: 'x'
    client_id: 'y'
    client_secret: 'z'
  new ShipmentStockModifier { config: c }

describe '#run', ->
  beforeEach ->
    @modifier = createModifier()

  it 'should throw error if callback is passed', ->
    expect(=> @modifier.run()).toThrow new Error 'Callback must be a function!'

describe '#initState', ->
  beforeEach ->
    @modifier = createModifier()

  it 'should create simple state obj', ->
    order =
      id: '123'
    s = @modifier.initState order
    expect(s.status).toBe @modifier.STATE_INIT

  it 'should create entry for each line item', ->
    order =
      id: '123'
      lineItems: [
        { variant: { sku: 'mySKU' } }
      ]
    s = @modifier.initState order
    expect(s.status).toBe @modifier.STATE_INIT
    expect(s.changes['mySKU']).toBe 0

describe '#getState', ->
  beforeEach ->
    @modifier = createModifier()

  it 'should get state', (done) ->
    order =
      id: '123'
    spyOn(@modifier.rest, 'GET').andCallFake((path, callback) =>
      body =
        value:
          status: @modifier.STATE_NOT_SHIPPED
      callback(null, {statusCode: 200}, JSON.stringify(body)))
    @modifier.getState(order).then (s) =>
      expect(@modifier.rest.GET).toHaveBeenCalledWith('/custom-objects/ShipmentStockModifier/123', jasmine.any(Function))
      expect(s.status).toBe @modifier.STATE_NOT_SHIPPED
      done()
    .fail (msg) ->
      console.log msg
      expect(false).toBe true
      done()

  it 'should return initial state', ->
    order =
      id: 'xyz'
    spyOn(@modifier.rest, 'GET').andCallFake((path, callback) ->
      callback(null, { statusCode: 404 }, '{}'))
    @modifier.getState(order).then (s) =>
      expect(@modifier.rest.GET).toHaveBeenCalledWith('/custom-objects/ShipmentStockModifier/xyz', jasmine.any(Function))
      expect(s.status).toBe @modifier.STATE_INIT
      done()
    .fail (msg) ->
      console.log msg
      expect(false).toBe true
      done()

describe '#modifyState', ->
  beforeEach ->
    @modifier = createModifier()

  it 'should store quantity if state is shipped', ->
    state =
      status: @modifier.STATE_INIT
      changes: {}
    order =
      id: 'xyz'
      shipmentState: 'Shipped'
      lineItems: [
        { quantity: 3, variant: { sku: 'mySKU' }}
      ]
    res = @modifier.modifyState(order, state)
    s = res.state
    expect(s.status).toBe @modifier.STATE_SHIPPED
    expect(s.changes['mySKU']).toBe 3
    expect(res.actions.length).toBe 1
    a = res.actions[0]
    expect(a.sku).toBe 'mySKU'
    expect(a.quantity).toBe 3
    expect(a.action).toBe 'removeQuantity'

  it 'should store zeros if state is not shipped', ->
    state =
      status: @modifier.STATE_SHIPPED
      changes:
        mySKU: 7
    order =
      id: 'xyz'
      shipmentState: 'Pending'
      lineItems: [
        { quantity: 7, variant: { sku: 'mySKU' }}
      ]
    res = @modifier.modifyState(order, state)
    s = res.state
    expect(s.status).toBe @modifier.STATE_NOT_SHIPPED
    expect(s.changes['mySKU']).toBe 0
    expect(res.actions.length).toBe 1
    a = res.actions[0]
    expect(a.sku).toBe 'mySKU'
    expect(a.quantity).toBe 7
    expect(a.action).toBe 'addQuantity'

describe '#saveState', ->
  beforeEach ->
    @modifier = createModifier()

  it 'should store the state', ->
    state =
      status: @modifier.STATE_SHIPPED
      changes:
        mySKU: 2
    order =
      id: 'abc'
    spyOn(@modifier.rest, 'POST').andCallFake((path, body, callback) ->
      callback(null, { statusCode: 201 }, '{}'))
    @modifier.saveState(order, state).then (res) =>
      expect(@modifier.rest.POST).toHaveBeenCalledWith('/custom-objects/ShipmentStockModifier/abc', jasmine,any(Object), jasmine.any(Function))
      done()
    .fail (msg) ->
      console.log msg
      expect(false).toBe true
      done()