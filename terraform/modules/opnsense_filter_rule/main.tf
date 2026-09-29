resource "opnsense_firewall_filter" "rule" {
  for_each = var.rules

  sequence    = each.value.sequence
  enabled     = each.value.enabled
  description = each.value.description

  interface = {
    interface = each.value.interfaces
    invert    = each.value.interface_invert
  }

  filter = {
    action      = each.value.action
    direction   = each.value.direction
    protocol    = lower(each.value.protocol) == "any" ? "any" : upper(each.value.protocol)
    ip_protocol = each.value.ip_protocol
    quick       = each.value.quick
    log         = each.value.log

    source = {
      net    = replace(each.value.source_net, "/^\\$/", "")
      port   = replace(each.value.source_port, "/^\\$/", "")
      invert = each.value.source_invert
    }

    destination = {
      net    = replace(each.value.destination_net, "/^\\$/", "")
      port   = replace(each.value.destination_port, "/^\\$/", "")
      invert = each.value.destination_invert
    }
  }
}
