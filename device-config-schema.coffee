module.exports = {
  title: "pimatic check alive device config schema"
  CheckAliveSystem:
    title: "CheckAliveSystem config"
    type: "object"
    extensions: ["xOnLabel", "xOffLabel"]
    properties:
      "check timeout":
        description: "List of variables that must update periodically"
        type: "array"
        default: []
        items:
          description: "Define control properties"
          type: "object"
          required: ["timeout"]
          properties:
            name:
              description: "Variable name (or several names separed by semicolon)"
              type: "string"
            description:
              description: "Description of the variable"
              type: "string"
              default: ""
            timeout:
              description: """
              Maximum update rate. Set alert state for a variable if no data was received in this time interval. 
              If the value is a number then it defines a timeout in milliseconds. 
              If this values has the 00:00:00.000 format then it defines Hours:Minutes:Seconds.Milliseconds 
              Hours and Milliseconds are optional.
              """
              type: "string"
              default: 10000
            logHigh:
              description: "Message when alert appears (LOW -> HIGH)"
              type: "string"
              default: ""
            logLow:
              description: "Message when alert disappears (HIGH -> LOW)"
              type: "string"
              default: ""
            "state attribute":
              description: "Create a separate state attribute with this name for this alert"
              type: "string"
              default: "<empty>"
      "check range":
        description: "List of numerical variables that must meet the specified conditions"
        type: "array"
        default: []
        items:
          description: "Define control properties"
          type: "object"
          properties:
            name:
              description: "Variable name (or several names separed by semicolon)"
              type: "string"
            description:
              description: "Description of the variable"
              type: "string"
              default: ""
            min:
              description: "Minimum value. If this value is not defined then the device will not check this condition"
              type: "number"
              default: -100
            max:
              description: "Maximum value"
              type: "number"
              default: 100
            timeout:
              description: "Variable should meet the specified condition during this time (ms) before an alert state will be set"
              type: "number"
              default: 5000
            logHigh:
              description: "Message when alert appears (LOW -> HIGH)"
              type: "string"
              default: ""
            logLow:
              description: "Message when alert disappears (HIGH -> LOW)"
              type: "string"
              default: ""
            "state attribute":
              description: "Create a separate state attribute with this name for this alert"
              type: "string"
              default: "<empty>"
      "custom switch color":
        description: "Custom switch color in the alerted state"
        type: "string"
        default: ""
}
