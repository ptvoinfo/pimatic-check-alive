module.exports = (env) ->
  # ##Dependencies
  util = require 'util'

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types
  _ = env.require 'lodash'

  STATE_LOW = 0       # no alert
  STATE_LOW_HIGH = 1  # transition state from 'not alerted' -> 'alerted'
  STATE_HIGH = 2      # alerted state
  STATE_HIGH_LOW = 3  # transition state from 'alerted' -> 'not alerted'

  TIME_SECOND = 1000
  TIME_MINUTE =  60 * TIME_SECOND
  TIME_HOUR = 60 * TIME_MINUTE

  PARAM_CHECK_TIMEOUT = "check timeout"
  PARAM_CHECK_RANGE = "check range"
  PARAM_CUSTOM_COLOR = "custom switch color"
  PARAM_STATE_ATTR = "state attribute"
  PARAM_STATE_ATTR_PREFIX = 'alert_'
  PARAM_STATE_ATTR_AUTO = '<empty>'

  @_templatePrepared = false

  # ##The CheckAlivePlugin
  class CheckAlivePlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      @_afterInit = false
      @deviceCount = 0

      @deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("CheckAliveSystem", {
        configDef: @deviceConfigDef.CheckAliveSystem,
        createCallback: (config, lastState) =>
          device = new CheckAliveSystem(config, lastState, @, @deviceCount)
          @deviceCount++
          return device
      })

      @framework.on 'after init', =>
        @_afterInit = true
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-check-alive/app/check-alive-device.coffee"
          mobileFrontend.registerAssetFile 'js', "pimatic-check-alive/app/vendor/jqColorPicker.min.js"
          mobileFrontend.registerAssetFile 'html', "pimatic-check-alive/app/check-alive-device.jade"
        return

    afterInit: () =>
      return @_afterInit

  checkPlugin = new CheckAlivePlugin

  # ##CheckAliveSystem Device
  class CheckAliveSystem extends env.devices.DummySwitch
    _trigger: ""
    _color: ""

    attributes:
      trigger:
        description: "Last variable triggered the alert state"
        type: t.string
      state:
        description: "The current state of the switch"
        type: t.boolean
        labels: ['on', 'off']
      color:
        description: ""
        type: t.string
        hidden: true
        displaySparkline: false

    template: "check-alive-device"

    getTrigger: () -> Promise.resolve(@_trigger)
    getColor: () -> Promise.resolve(@_color)

    _updateTrigger: (trigger) ->
      oldTrigger = @_trigger
      trigger_time_max = 0
      trigger_item = undefined

      for name, item of @variables_alive
        if item.triggertime? and (item.triggertime > trigger_time_max)
          trigger_time_max = item.triggertime
          trigger_item = item

      for name, item of @variables_range
        if item.triggertime? and (item.triggertime > trigger_time_max)
          trigger_time_max = item.triggertime
          trigger_item = item

      if trigger_item? and trigger_item.description
        @_trigger = trigger_item.description
      else
        @_trigger = ''

      if @_trigger isnt oldTrigger
        @emit 'trigger', @_trigger

    changeStateTo: (state, force) ->
      if force
        super(state)
      else if not state
        @_color = ''
        @_clearSignals()
        @_updateTrigger()
        super(state)
      else
        super(state).then( => super(false))

    constructor: (@config, lastState, @plugin, @deviceNum) ->
      #console.log('constructor. Last state: ', lastState)

      @attributes = _.cloneDeep(@attributes)

      @env = env
      @name = @config.name
      @id = @config.id
      @env.logger.debug("Creating CheckAliveSystem")

      if @config[PARAM_CUSTOM_COLOR]? and @config[PARAM_CUSTOM_COLOR]
        @_color = @config[PARAM_CUSTOM_COLOR]

      @_vars = @plugin.framework.variableManager
      @_exprChangeListeners = {}
      @_checkTimeoutTimer = null
      @_checkReinitTimer = null
      @_alertStateForAttr = {}

      @variables_alive = {}
      @variables_range = {}

      @_removeStateAttributes()
      @_createStateAttributes(@config[PARAM_CHECK_TIMEOUT])
      @_createStateAttributes(@config[PARAM_CHECK_RANGE])

      super(@config, lastState)

      if @plugin.afterInit()
        # initialize only on recreation of the device
        # skip initialization if we are called the
        # first time during startup
        @_initDevice('constructor', false)

      @plugin.framework.on 'after init', =>
        # wait for the 'after init' event
        # until all devices are loaded
        @_initDevice('after init', true)

    destroy: () ->
      # remove event handlers from sensor devices
      @env.logger.debug("Destroying CheckAliveSystem")
      if @_checkTimeoutTimer? and @_checkTimeoutTimer
        clearInterval @_checkTimeoutTimer
      if @_checkReinitTimer? and @_checkReinitTimer
        clearTimeout @_checkReinitTimer

      for name, cl of @_exprChangeListeners
        if cl?
          @_vars.cancelNotifyOnChange(cl)

      for name, item of @variables_range
        @_cancelDelayedTimer(item)

      super()

    _getTimestamp: =>
      return (new Date()).getTime()

    _replacePlaceholders: (item, str, state) =>
      _item = _.clone(item)
      d = new Date()
      tz = d.getTimezoneOffset() * 60 * 1000
      ts = d.getTime()
      d1 = new Date()
      d1.setTime(ts - _item.time + tz)
      _item.lasttimediff = d1.toLocaleTimeString()
      d1.setTime(_item.time)
      _item.lasttime = d1.toLocaleString()
      _item.time = d.toLocaleTimeString()
      _item.date = d.toLocaleDateString()
      _item.timestamp = d.toLocaleString()
      _item.now = _item.timestamp
      if state?
        _item.state = state

      val = str.replace(new RegExp("[\#\$]\{([^\{]+)\}", "g"), (_unused, varName) =>
        return (if _item[varName]? then _item[varName] else '')
      )
      return val

    _logStateChange: (item, label, state) =>
      if label
        val = @_replacePlaceholders(item, label, state)
        if val then @env.logger.info val

    _getAlertStateForAttr: (attr) =>
      for name, item of @variables_alive
        if item.alert_attr? and (item.alert_attr is attr)
          return true if item.state is STATE_HIGH

      for name, item of @variables_range
        if item.alert_attr? and (item.alert_attr is attr)
          return true if item.state is STATE_HIGH

      return false     

    _varStateChange: (item, state) =>
      @env.logger.debug("Changing variable alert state '#{item.name}': #{item.state} -> #{state}")
      # console.log("Changing variable alert state '#{item.name}': #{item.state} -> #{state}", item)
      if state is STATE_HIGH_LOW
        item.state = STATE_LOW
        item.triggertime = undefined
        @_updateTrigger()
        if item.logLow?
          @_logStateChange item, item.logLow, 'HIGH -> LOW'
      else if state is STATE_LOW_HIGH
        item.state = STATE_HIGH
        item.triggertime = @_getTimestamp()
        @_updateTrigger()
        if item.logHigh?
          @_logStateChange item, item.logHigh, 'LOW -> HIGH'

      if item.alert_attr
        oldState = @_alertStateForAttr[item.alert_attr]        
        @_alertStateForAttr[item.alert_attr] = @_getAlertStateForAttr(item.alert_attr)
        # console.log('Set alert attr ' + item.alert_attr + ' to ' + @_alertStateForAttr[item.alert_attr])
        if oldState isnt @_alertStateForAttr[item.alert_attr]
          # console.log('Emit alert attr ' + item.alert_attr)
          @emit item.alert_attr, @_alertStateForAttr[item.alert_attr]

    _checkAliveVars: (name, varobj, value) =>
      if name of @variables_alive
        item = @variables_alive[name]
        item.value = value
        item.time = @_getTimestamp()
        if item.state
          @_varStateChange(item, STATE_HIGH_LOW)

    _cancelDelayedTimer: (item) =>
      if item.delayedStateChangeTimer?
        tmp = item.delayedStateChangeTimer
        delete item.delayedStateChangeTimer
        clearTimeout(tmp)

    _checkRangeVars: (name, varobj, value) =>
      if name of @variables_range
        item = @variables_range[name]
        item.value = value
        item.time = @_getTimestamp()
        try
          if value?
            bSignalled = false
            if item.min? and (value < item.min)
              bSignalled = true
            else if item.max? and (value > item.max)
              bSignalled = true

            if bSignalled and (item.state is STATE_LOW)
              if item.timeout? and (item.timeout > 0)
                unless item.delayedStateChangeTimer?
                  item.delayedStateChangeTimer = setTimeout( (=>
                    @_cancelDelayedTimer(item)
                    if item.state is STATE_LOW
                      @_varStateChange(item, STATE_LOW_HIGH)
                    ), item.timeout)
              else
                @_varStateChange(item, STATE_LOW_HIGH)
            else if (not bSignalled) and (item.state isnt STATE_LOW)
              @_cancelDelayedTimer(item)
              @_varStateChange(item, STATE_HIGH_LOW)

        catch error
          @env.logger.error "Variable '#{name}' is not numeric: " + error

      return

    _checkVars: (name, varobj, value) =>
      @_checkAliveVars(name, varobj, value)
      @_checkRangeVars(name, varobj, value)
      @_checkSignals()

    _clearSignal: (item) =>
        item.state = STATE_LOW
        item.trigger = undefined
        item.triggertime = undefined

    _clearSignals: =>
      now = @_getTimestamp()
      for name, item of @variables_alive
        @_clearSignal(item)
      for name, item of @variables_range
        @_clearSignal(item)

    _checkSignals: =>
      now = @_getTimestamp()
      signalled_count = 0
      for name, item of @variables_alive
        if item.state is STATE_LOW
          if (now - item.time) > item.timeout
            @_varStateChange(item, STATE_LOW_HIGH)
            signalled_count++
        else
          signalled_count++

      for name, item of @variables_range
        if item.state isnt STATE_LOW
          signalled_count++

      if signalled_count > 0
        unless @_state
          @changeStateTo(true, true)
      else
        if @_state
          @changeStateTo(false, true)
        if @_trigger
          @_updateTrigger()

    _copyDefaultAttributes: (item, schema) =>
      unless schema.properties? then return
      required = schema.required || []
      for name, prop of schema.properties
        if (not (name of item)) and (name in required)
          if prop.type is 'number'
            item[name] = (if prop.default? then parseFloat(prop.default) else null)
          else if prop.type is 'boolean'
            item[name] = (if prop.default? and prop.default is 'true' then true else false)
          else
            item[name] = prop.default

    _copyConfigValues: (item, schema, config) =>
      unless schema.properties? then return
      unless config? then return

      for name, value of config
        if name of schema.properties
          prop = schema.properties[name]
          if prop.type is 'number'
            item[name] = (if value? then parseFloat(value) else null)
          else if prop.type is 'boolean'
            item[name] = (if value? and value then true else false)
          else
            item[name] = value

    _getAlertAttrName: (config) =>
      return unless config[PARAM_STATE_ATTR]?

      config_attr = config[PARAM_STATE_ATTR].trim()
      isdefined = config_attr and (config_attr isnt PARAM_STATE_ATTR_AUTO)

      names = config.name.trim().split(';')
      attr_name = names[0]
      return unless attr_name

      # remove any symbols
      attr_name = attr_name.replace('$', '')
      re = /[\x00-\x2F,\x3A-\x40,\x7B-\x7F]/g
      unless isdefined
        attr_name = 'alert_' + attr_name.replace(re, '_')
      else
        attr_name = config_attr.replace(re, '_')
      return attr_name

    _removeStateAttributes: (list_from) =>
      for attr_name of @attributes
        if attr_name.substr(0, PARAM_STATE_ATTR_PREFIX.length) is PARAM_STATE_ATTR_PREFIX
          delete @attributes[attr_name]

    _createStateAttributes: (list_from) =>
      for configvar in list_from
        do (configvar) =>
          _name = configvar.name.trim()

          attr_name = @_getAlertAttrName(configvar)
          return unless attr_name

          @_alertStateForAttr[attr_name] = false
          unless attr_name of @attributes
            @attributes[attr_name] = {
              description: "Alert state of '#{_name}'"
              type: t.string
              hidden: true
              displaySparkline: false
            }

          @_createGetter(attr_name, =>
            value = @_alertStateForAttr[attr_name]
            return Promise.resolve(value)
          )

    _strToTimeout: (str) =>
      return 0 unless str
      return str if _.isNumber(str)
      if str.indexOf(':') >= 0
        parts = str.trim().split('.')
        timeout = (if parts.length > 1 then _.parseInt(parts[1]) else 0)
        if isNaN timeout then timeout = 0
        if parts.length > 0
          parts = parts[0].split(':')
          if parts.length > 2
            hr = _.parseInt(parts[0])
            min = _.parseInt(parts[1])
            sec = _.parseInt(parts[2])
          else if parts.length > 1
            hr = 0
            min = _.parseInt(parts[0])
            sec = _.parseInt(parts[1])
          else
            hr = 0
            min = 0
            sec = _.parseInt(parts[0])
          unless isNaN hr then timeout += hr * TIME_HOUR
          unless isNaN min then timeout += min * TIME_MINUTE
          unless isNaN sec then timeout += sec * TIME_SECOND
      else
        timeout = _.parseInt(str)
        if isNaN timeout then timeout = 0
      return timeout

    _createListeners: (list_from, list_to, schema, reinit = false) =>

      minInterval = 0
      for configvar in list_from
        do (configvar) =>
          _name = configvar.name.trim()
          _attr_name = @_getAlertAttrName(configvar)

          names = _name.split(';')
          for n in names
            n1 = n.trim()
            continue unless n1

            variable = _.clone(configvar)
            variable.name = n1
            do (variable) =>
              name = variable.name
              info = null

              try
                if list_to[name]?
                  unless reinit
                    @env.logger.error "Variable with the same name \"#{name}\" is alredy defined in the configuration. Ignored"
                    return

                if name of @_exprChangeListeners
                  if (not reinit) or @_exprChangeListeners[name]?
                    return

                if reinit and (name of list_to)
                  item = list_to[name]
                else
                  item = {}
                  @_copyDefaultAttributes(item, schema)
                  @_copyConfigValues(item, schema, variable)
                  item.name = name
                  item.type = variable.type or "string"
                  item.state = STATE_LOW
                  item.time = @_getTimestamp()
                  item.triggertime = undefined
                  item.lastErrorReported = 0
                  if _attr_name
                    item.alert_attr = _attr_name
                  if variable.timeout?
                    item.timeout = @_strToTimeout(variable.timeout)
                  unless item.timeout? then item.timeout = 10 * TIME_SECOND

                  if variable.description?
                    item.description = @_replacePlaceholders(item, item.description, null)
                  else
                    item.description = name

                  list_to[name] = item
                  @_exprChangeListeners[name] = null

                if (minInterval == 0) or (item.timeout < minInterval)
                  minInterval = item.timeout

                parseExprAndAddListener = ( () =>
                  info = @_vars.parseVariableExpression(name)
                  @_vars.notifyOnChange(info.tokens, onChangedVar)
                  item.tokens = info.tokens
                  @_exprChangeListeners[name] = onChangedVar
                )

                evaluateExpr = ( (varsInEvaluation) =>
                  lastChangedVarName = name
                  # console.log("evaluateExpr '#{info.datatype}' for '#{lastChangedVarName}'")
                  switch info.datatype
                    when "numeric" then @_vars.evaluateNumericExpression(info.tokens, varsInEvaluation)
                    when "string" then @_vars.evaluateStringExpression(info.tokens, varsInEvaluation)
                    else assert false
                )

                onChangedVar = ( (changedVar) =>
                  lastChangedVar = changedVar
                  lastChangedVarName = name
                  evaluateExpr().then( (val) =>
                    @_checkVars(lastChangedVarName, lastChangedVar, val)
                  )
                )

                getValue = ( (varsInEvaluation) =>
                  # wait till variableManager is ready
                  return @_vars.waitForInit().then( =>
                    unless info?
                      parseExprAndAddListener()
                    return evaluateExpr(varsInEvaluation)
                  ).then( (val) =>
                    # console.log("getValue #{name} = #{val}")
                    if val?
                      @_checkVars(name, item, val)
                    return val
                  ).catch((error) =>
                    if @_checkReinitTimer then clearTimeout @_checkReinitTimer
                    @_checkReinitTimer = setTimeout(@_reinitDevice, 30 * TIME_SECOND)
                    now = @_getTimestamp()
                    if (now - item.lastErrorReported) > (3 * TIME_MINUTE)
                      item.lastErrorReported = now
                      @env.logger.error "Unable to add variable '#{name}' for device '#{@config.id}':", error.message
                  )

                )
                getValue()

              catch error
                @env.logger.error "Unable prepare config for '#{name}': " + error

      return minInterval

    _reinitDevice: =>
      @_initDevice('timer', true)

    _initDevice: (event, reinit) =>
      @env.logger.debug("Initializing from [#{event}]")
      # console.log("Initializing from [#{event}]")

      if @_checkTimeoutTimer? and @_checkTimeoutTimer
        clearInterval @_checkTimeoutTimer
        @_checkTimeoutTimer = null

      schema = @plugin.deviceConfigDef.CheckAliveSystem.properties[PARAM_CHECK_TIMEOUT].items
      minInterval = @_createListeners(@config[PARAM_CHECK_TIMEOUT], @variables_alive, schema, reinit)

      schema = @plugin.deviceConfigDef.CheckAliveSystem.properties[PARAM_CHECK_RANGE].items
      @_createListeners(@config[PARAM_CHECK_RANGE], @variables_range, schema, reinit)

      # at least Pimatic 0.9 does not create newly defined dynamic attributes on re-creation
      # create new variables for new attributes (after re-creation)
      attrName2 = @.id + '.state'
      origVar = @_vars.getVariableByName(attrName2)
      if origVar?
        for attrName, attr of @attributes
          attrName2 = @.id + '.' + attrName
          unless @_vars.isVariableDefined(attrName2)
            _newVar = new origVar.__proto__.constructor(@_vars, @, attrName)
            @_vars._addVariable(_newVar)

      if minInterval > 0
        @_checkTimeoutTimer = setInterval(@_checkSignals, parseInt(minInterval / 3))

  return checkPlugin