resource "proxmox_network_linux_bridge" "bridge" {
  for_each = var.bridges

  node_name = var.target_node_name
  name      = each.key

  autostart  = true
  address    = try(each.value.address, null)
  gateway    = try(each.value.gateway, null)
  ports      = try(each.value.ports, [])
  comment    = try(each.value.comment, null)
  vlan_aware = try(each.value.vlan_aware, false)
}
