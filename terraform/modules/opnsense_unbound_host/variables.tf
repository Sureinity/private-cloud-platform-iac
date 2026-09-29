variable "host_overrides" {
  description = "Map of Unbound DNS host overrides to create and manage."
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
