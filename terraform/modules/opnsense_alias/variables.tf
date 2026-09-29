variable "aliases" {
  description = "Map of OPNsense firewall aliases to manage."
  type = map(object({
    type        = string
    description = optional(string, "")
    content     = list(string)
    enabled     = optional(bool, true)
  }))
  default = {}
}
