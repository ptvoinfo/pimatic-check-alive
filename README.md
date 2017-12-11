#Pimatic "Check Alive" plugin
=======================

This plugin can control many variables in one place without long list of built-in rules. If a variable was not updated in the specified time interval the plugin sets the "state" attribute to "true". It allows you to control activity of remote devices that must send data periodically. You may just control changing of the "state" attribute in your rule and execute necessary actions. The plugin can also log alerts to a log file.

Rules example:

test-check-alive is turned on for 5 seconds 
send sms "Alert for $test-check-alive.trigger"

Bonus: you may control numeric variables that should match a some criteria. For example, check a value is in the specified range.

##Config in the "plugins" section:
-------

```json
{
"plugin": "check-alive",
"active": true
}
```

##Config in the "devices" section:
-------
```json
{
  "check timeout": [
    {
      "name": "$mqtt-device-present.module01",
      "timeout": 12000
    },
    {
      "name": "$mqtt-device-present.module03",
      "timeout": 120002
    },
    {
      "name": "$mqtt-device-present.module10",
      "timeout": 10000
    }
  ],
  "check range": [
    {
      "name": "$bme280-outside.Temperature",
      "min": 0,
      "timeout": 15000,
      "logLow": "Very cold! #{value} outside",
      "state attribute": ""
    }
  ],
  "id": "test-check-alive",
  "name": "test-check-alive",
  "class": "CheckAliveSystem",
  "custom switch color": "#865353"
}
```