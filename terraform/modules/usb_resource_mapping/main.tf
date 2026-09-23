resource "proxmox_hardware_mapping_usb" "usb_dev" {
  name    = var.name
  comment = var.comment

  map = var.dev_mappings
}
