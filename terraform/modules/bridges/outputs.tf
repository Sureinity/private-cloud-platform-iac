output "bridges" {
  value = {
    for name, bridge in proxmox_network_linux_bridge.bridge : name => {
      name       = bridge.name
      address    = bridge.address
      gateway    = bridge.gateway
      ports      = bridge.ports
      vlan_aware = bridge.vlan_aware
    }
  }
}
