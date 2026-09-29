resource "opnsense_firewall_alias" "alias" {
  for_each = var.aliases

  name        = each.key
  type        = each.value.type
  description = each.value.description
  content     = each.value.content
  enabled     = each.value.enabled
}
