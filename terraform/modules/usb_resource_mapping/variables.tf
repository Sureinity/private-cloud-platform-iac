variable "name" {
  type = string
}

variable "comment" {
  type     = string
  default  = null
  nullable = true
}

variable "dev_mappings" {
  type = set(object({
    id      = string
    node    = string
    comment = optional(string)
    path    = optional(string)
  }))
}
