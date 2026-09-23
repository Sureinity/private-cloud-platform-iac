locals {
  dns_enabled          = var.search_domain != null || length(var.dns_servers) > 0
  user_account_enabled = var.cloud_init_username != null || length(var.ssh_public_keys) > 0 || var.cloud_init_password != null
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  description = var.description
  node_name   = var.target_node_name
  vm_id       = var.vm_id

  started         = var.started
  on_boot         = var.on_boot
  protection      = var.protection
  stop_on_destroy = true
  boot_order      = var.boot_order
  machine         = "q35"
  bios            = var.bios
  scsi_hardware   = "virtio-scsi-single"
  tablet_device   = false
  tags            = var.tags

  agent {
    enabled = var.agent_enabled
    wait_for_ip {
      disabled = true
    }
  }

  startup {
    order = var.startup_order
  }

  cpu {
    cores   = var.cpu_cores
    sockets = 1
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.disk_datastore_id
    import_from  = var.import_image_file_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  dynamic "disk" {
    for_each = var.additional_disks

    content {
      datastore_id = disk.value.datastore_id
      interface    = disk.value.interface
      size         = disk.value.size
      aio          = disk.value.aio
      backup       = disk.value.backup
      cache        = disk.value.cache
      discard      = disk.value.discard
      iothread     = disk.value.iothread
      queues       = disk.value.queues
      replicate    = disk.value.replicate
      ssd          = disk.value.ssd
    }
  }

  dynamic "usb" {
    for_each = var.usb_host_device == null ? [] : [var.usb_host_device]

    content {
      host = usb.value
    }
  }

  dynamic "efi_disk" {
    for_each = var.bios == "ovmf" ? [1] : []

    content {
      datastore_id = coalesce(var.efi_disk_datastore_id, var.disk_datastore_id)
    }
  }

  dynamic "cdrom" {
    for_each = var.cdrom_file_id == null ? [] : [var.cdrom_file_id]

    content {
      file_id   = cdrom.value
      interface = "ide2"
    }
  }

  dynamic "initialization" {
    for_each = var.cloud_init_enabled ? [1] : []

    content {
      datastore_id = var.cloud_init_datastore_id
      interface    = var.cloud_init_interface

      ip_config {
        ipv4 {
          address = var.ipv4_address
          gateway = var.ipv4_gateway
        }
      }

      dynamic "dns" {
        for_each = local.dns_enabled ? [1] : []

        content {
          domain  = var.search_domain
          servers = var.dns_servers
        }
      }

      dynamic "user_account" {
        for_each = local.user_account_enabled ? [1] : []

        content {
          username = var.cloud_init_username
          password = var.cloud_init_password
          keys     = var.ssh_public_keys
        }
      }
    }
  }

  dynamic "network_device" {
    for_each = var.network_devices

    content {
      bridge   = network_device.value.bridge
      model    = network_device.value.model
      firewall = network_device.value.firewall
      vlan_id  = network_device.value.vlan_id
    }
  }

  operating_system {
    type = var.operating_system_type
  }

  serial_device {}

  vga {
    type = var.vga_type
  }
}
