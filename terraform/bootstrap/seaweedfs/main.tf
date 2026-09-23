locals {
  cloud_init_password = (
    var.cloud_init_password != null
    ? var.cloud_init_password
    : (
      var.cloud_init_password_file != null && fileexists(pathexpand(var.cloud_init_password_file))
      ? sensitive(chomp(file(pathexpand(var.cloud_init_password_file))))
      : null
    )
  )
}

check "cloud_init_password_source" {
  assert {
    condition     = (var.cloud_init_password_file == null) != (var.cloud_init_password == null)
    error_message = "Set exactly one of cloud_init_password_file or cloud_init_password."
  }
  assert {
    condition     = var.cloud_init_password_file == null || fileexists(pathexpand(var.cloud_init_password_file))
    error_message = "The cloud_init_password_file path does not exist on the local filesystem."
  }
}

# ==============================================================================
# NOTICE: SUBJECT TO DATA STORAGE REVAMP
# The current storage topology (100 GB virtual disk on usb-ssd) is an interim
# bootstrap implementation. Planned architectural roadmap includes initializing
# a dedicated node for the SeaweedFS Volume server to decouple persistent state
# storage from the hypervisor VM lifecycle.
# ==============================================================================

module "seaweedfs_vm" {
  source = "../../modules/proxmox_vm"

  target_node_name        = var.target_node_name
  vm_id                   = var.seaweedfs_vm_id
  vm_name                 = var.seaweedfs_vm_name
  description             = "Standalone SeaweedFS Terraform state backend VM"
  protection              = var.seaweedfs_protection
  disk_datastore_id       = var.seaweedfs_boot_disk_datastore_id
  efi_disk_datastore_id   = var.seaweedfs_efi_disk_datastore_id
  cloud_init_datastore_id = var.seaweedfs_cloud_init_datastore_id
  cloud_init_enabled      = true
  cloud_init_interface    = var.seaweedfs_cloud_init_interface
  cloud_init_username     = var.seaweedfs_cloud_init_username
  cloud_init_password     = local.cloud_init_password
  cpu_cores               = var.seaweedfs_cpu_cores
  disk_size_gb            = var.seaweedfs_boot_disk_size_gb
  import_image_file_id    = var.import_image_file_id
  ipv4_address            = var.seaweedfs_ipv4_address
  ipv4_gateway            = var.seaweedfs_ipv4_gateway
  dns_servers             = var.seaweedfs_dns_servers
  memory_mb               = var.seaweedfs_memory_mb
  bios                    = var.seaweedfs_bios
  operating_system_type   = "l26"
  ssh_public_keys         = var.seaweedfs_ssh_public_keys
  startup_order           = var.seaweedfs_startup_order
  started                 = var.seaweedfs_started
  on_boot                 = var.seaweedfs_on_boot
  agent_enabled           = var.seaweedfs_agent_enabled
  tags                    = ["ubuntu", "seaweedfs", "terraform-state", "bootstrap"]
  additional_disks = [
    {
      datastore_id = var.seaweedfs_data_disk_datastore_id
      interface    = var.seaweedfs_data_disk_interface
      size         = var.seaweedfs_data_disk_size_gb
      iothread     = true
      discard      = "on"
      ssd          = true
      backup       = true
    }
  ]
  network_devices = [
    {
      bridge   = var.seaweedfs_bridge_name
      model    = "virtio"
      firewall = true
    }
  ]
}
