merge = Array.prototype.concat
LazyLoad.js(merge.apply(scripts.textcomplete))

_check_alive_rgb2hex = (rgb) ->
  if rgb.search("rgb") is -1
    return rgb
  else
    rgb = rgb.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*(\d+))?\)$/)
    hex = (x) ->
      return ("0" + parseInt(x).toString(16)).slice(-2);
    return "#" + hex(rgb[1]) + hex(rgb[2]) + hex(rgb[3])

$(document).on 'templateinit', (event) ->

  class CheckAliveSystemItem extends pimatic.SwitchItem
    constructor: (templData, @device) ->
      super(templData, @device)

      @switchState.subscribe(@_updateColor)
      @_switchEle = null
      @alertColor = ''
      @_initialColor = ''

    afterRender: (elements) =>
      super(elements)

      @_switchEle = $(elements).find('.ui-flipswitch')

      @_initialColor = @_switchEle.css("background-color")
      if @_initialColor?
        @_initialColor = _check_alive_rgb2hex(@_initialColor)
      colorAttr = @getAttribute('color')
      if colorAttr?
        @alertColor = @getAttribute('color').value()

      @_updateColor(@switchState())

    _updateColor: (state) =>
      return unless @alertColor
      return unless @_switchEle?
      return unless @_switchEle[0]?
      newcolor = (if state is 'on' then @alertColor else @_initialColor)
      #console.log('_updateColor to ' + newcolor + ', State: ' + state)
      pimatic.try => @_switchEle.css("background-color", newcolor)

  # register the item-class
  pimatic.templateClasses['check-alive-device'] = CheckAliveSystemItem

$(document).on "pagebeforeshow", '#edit-device-page', (event) ->
  unless pimatic.pages.editDevice? then return

  PARAM_CHECK_TIMEOUT = "check timeout"
  PARAM_CHECK_RANGE = "check range"

  lastTerm = null

  customReplace = (pre, value) ->
    commonPart = this.ac.getCommonPart(pre, value)
    return pre.substring(0, pre.length - commonPart.length) + value

  customTemplate = (value) ->
    commonPart = this.ac.getCommonPart(lastTerm, value)
    remainder = value.substring(commonPart.length, value.length)
    return "<strong>#{commonPart}</strong>#{remainder}"

  p = pimatic.pages.editDevice
  p.configSchema.subscribe( (schema) =>
    if schema? and typeof schema is "object"
      deviceClass = p.deviceClass()
      if deviceClass is 'CheckAliveSystem'
        if schema.properties?
          addAutoComplete = (value) =>
            return unless value
            list = $('div.popup-overlay').find('input')
            for obj in list
              data = ko.dataFor(obj)
              if data? and data.schema?
                obj2 = $(obj)
                if (data.schema.name is "name") and (obj2.attr('type') is 'text')
                  obj2.textcomplete([
                    match: /(\$[^\s\;]*)$/
                    search: (term, callback) ->
                      p.autocompleteAjax?.abort()
                      result = {autocomplete: [], format: []}
                      p.autocompleteAjax = pimatic.client.rest.getRuleConditionHints(
                        {conditionInput: term},
                        {global: false}
                      ).done( (data) =>
                        result.autocomplete = data.hints?.autocomplete or []
                        if (result.autocomplete.length > 0) and (result.autocomplete[0] is ' * ')
                          result.autocomplete = [';']
                        result.format = [];
                        if data.error then console.log data.error
                        lastTerm = term
                        callback result
                      ).fail( => callback result )
                    index: 1
                    replace: (pre, value) ->
                      textValue = customReplace.call(this, pre, value)
                      # p.ruleCondition(textValue)
                      return textValue
                    change: (text) ->
                      # p.ruleCondition(text)
                      return
                    template: customTemplate
                  ])
                  break

          if PARAM_CHECK_TIMEOUT of schema.properties
            prop = schema.properties[PARAM_CHECK_TIMEOUT]
            prop.items.editingItem.subscribe( addAutoComplete )

          if PARAM_CHECK_RANGE of schema.properties
            prop = schema.properties[PARAM_CHECK_RANGE]
            prop.items.editingItem.subscribe( addAutoComplete )

        list = $('input')
        for obj in list
          data = ko.dataFor(obj)
          if data? and data.schema?
            obj2 = $(obj)
            if (data.schema.name is "custom switch color") and (obj2.attr('type') is 'text')
              bg = $('div.ui-header').css('background-color')
              if bg then bg = _check_alive_rgb2hex(bg)
              col = obj2.colorPicker(
                customBG: bg
                color: obj2.val()
                cssAddon: ".cp-color-picker {z-index: 9999; background-color: #{bg}}"
                renderCallback: (elem, toggled) ->
                  hexcolor = '#' + @color.colors.HEX
                  obj2.val(hexcolor)
                  data.value(hexcolor)
              )
              break
  )