# #check alive plugin configuration options
module.exports = {
  title: "check alive config"
  type: "object"
  properties: {
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
  }
}