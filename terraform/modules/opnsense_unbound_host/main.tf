resource "opnsense_unbound_host_override" "override" {
  for_each = var.host_overrides

  hostname    = each.value.hostname
  domain      = each.value.domain
  server      = each.value.server
  type        = each.value.type
  description = each.value.description
  enabled     = each.value.enabled
  mx_host     = each.value.mx_host
  mx_priority = each.value.mx_priority
}
