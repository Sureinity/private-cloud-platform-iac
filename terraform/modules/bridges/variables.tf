variable "target_node_name" {
  type = string
}

variable "bridges" {
  type = map(object({
    ports      = optional(list(string), [])
    address    = optional(string)
    gateway    = optional(string)
    comment    = optional(string)
    vlan_aware = optional(bool, false)
  }))
}
