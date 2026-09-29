variable "rules" {
  description = "Map of OPNsense firewall filter rules to create and manage."
  type = map(object({
    sequence           = optional(number)
    enabled            = optional(bool, true)
    description        = optional(string, "")
    interfaces         = optional(list(string), [])
    interface_invert   = optional(bool, false)
    action             = string
    direction          = string
    protocol           = string
    ip_protocol        = optional(string, "inet")
    quick              = optional(bool, true)
    log                = optional(bool, false)
    source_net         = optional(string, "any")
    source_port        = optional(string, "")
    source_invert      = optional(bool, false)
    destination_net    = optional(string, "any")
    destination_port   = optional(string, "")
    destination_invert = optional(bool, false)
  }))
  default = {}
}
