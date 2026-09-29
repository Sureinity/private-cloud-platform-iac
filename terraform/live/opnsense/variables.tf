variable "opnsense_url" {
  description = "Target base URL for the OPNsense Web GUI and REST API (e.g. https://192.0.2.1 or Tailscale URL)."
  type        = string
}

variable "opnsense_api_key" {
  description = "API Key generated for svc-terraform-opnsense service account."
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "API Secret generated for svc-terraform-opnsense service account."
  type        = string
  sensitive   = true
}

variable "opnsense_allow_insecure" {
  description = "Whether to permit TLS connections without verifying the OPNsense Web GUI certificate."
  type        = bool
  default     = true
}

variable "firewall_aliases" {
  description = "Map of declarative firewall aliases to configure in OPNsense."
  type = map(object({
    type        = string
    description = optional(string, "")
    content     = list(string)
    enabled     = optional(bool, true)
  }))
  default = {}
}

variable "firewall_filter_rules" {
  description = "Map of declarative firewall filter rules to configure in OPNsense."
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

variable "unbound_host_overrides" {
  description = "Map of Unbound DNS host overrides to configure in OPNsense."
  type = map(object({
    hostname    = string
    domain      = string
    server      = optional(string)
    type        = optional(string, "A")
    description = optional(string, "")
    enabled     = optional(bool, true)
    mx_host     = optional(string)
    mx_priority = optional(number)
  }))
  default = {}
}
