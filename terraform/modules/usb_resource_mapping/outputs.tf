output "usb_mapped_device" {
  value = {
    name = proxmox_hardware_mapping_usb.usb_dev.name
    id   = proxmox_hardware_mapping_usb.usb_dev.id
  }
}
