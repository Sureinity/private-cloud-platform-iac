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

module "bridges" {
  source = "../../modules/bridges"

  target_node_name = var.target_node_name
  bridges = {
    (var.vmbr0_name) = {
      ports   = var.vmbr0_ports
      address = var.vmbr0_address
      gateway = var.vmbr0_gateway
      comment = "PVE host address intentionally omitted while management is on vmbr1"
    }
    (var.opnsense_lan_bridge_name) = {
      ports      = []
      address    = var.opnsense_lan_bridge_address
      gateway    = var.opnsense_lan_bridge_gateway
      vlan_aware = var.opnsense_lan_bridge_vlan_aware
      comment    = "OPNsense LAN bridge; default gateway is 192.0.2.1"
    }
    (var.sandbox_sync_bridge_name) = {
      ports   = []
      comment = "REF-089 isolated OPNsense sync bridge"
    }
  }
}

module "images" {
  source = "../../modules/images"

  target_node_name         = var.target_node_name
  download_timeout_seconds = var.download_timeout_seconds
  import_images = {
    # debian = {
    #   datastore_id = var.import_datastore_id
    #   url          = var.debian_cloud_image_url
    #   file_name    = var.debian_cloud_image_filename
    # }
    ubuntu = {
      datastore_id = var.import_datastore_id
      url          = var.ubuntu_cloud_image_url
      file_name    = var.ubuntu_cloud_image_filename
    }
  }
}

moved {
  from = module.test_vm
  to   = module.opnsense
}

module "opnsense" {
  source = "../../modules/proxmox_vm"

  target_node_name      = var.target_node_name
  vm_id                 = var.opnsense_vm_id
  vm_name               = var.opnsense_vm_name
  description           = "OPNsense router VM"
  disk_datastore_id     = var.opnsense_disk_datastore_id
  cdrom_file_id         = var.opnsense_cdrom_file_id
  memory_mb             = var.opnsense_memory_mb
  cpu_cores             = var.opnsense_cpu_cores
  disk_size_gb          = var.opnsense_disk_size_gb
  startup_order         = 10
  boot_order            = var.opnsense_boot_order
  bios                  = var.opnsense_bios
  efi_disk_datastore_id = var.opnsense_efi_disk_datastore_id
  started               = var.opnsense_started
  on_boot               = var.opnsense_on_boot
  tags                  = ["router", "opnsense"]
  network_devices = [
    {
      bridge   = var.vmbr0_name
      model    = "virtio"
      firewall = true
    },
    {
      bridge   = var.opnsense_lan_bridge_name
      model    = "virtio"
      firewall = true
    },
    {
      bridge   = var.sandbox_sync_bridge_name
      model    = "virtio"
      firewall = true
    },
  ]
}


module "zabbix_vms" {
  source   = "../../modules/proxmox_vm"
  for_each = var.zabbix_vms_enabled ? var.zabbix_vms : {}

  target_node_name        = var.target_node_name
  vm_id                   = each.value.vm_id
  vm_name                 = each.value.vm_name
  description             = each.value.description
  disk_datastore_id       = var.zabbix_vm_disk_datastore_id
  efi_disk_datastore_id   = var.zabbix_vm_efi_disk_datastore_id
  cloud_init_datastore_id = var.zabbix_vm_cloud_init_datastore_id
  cloud_init_enabled      = true
  cloud_init_username     = var.zabbix_vm_cloud_init_username
  cloud_init_password     = local.cloud_init_password
  cpu_cores               = var.zabbix_vm_cpu_cores
  disk_size_gb            = var.zabbix_vm_disk_size_gb
  import_image_file_id    = module.images.import_images.debian.file_id
  ipv4_address            = each.value.ipv4_address
  ipv4_gateway            = var.zabbix_vm_ipv4_gateway
  dns_servers             = var.zabbix_vm_dns_servers
  memory_mb               = var.zabbix_vm_memory_mb
  bios                    = var.zabbix_vm_bios
  operating_system_type   = "l26"
  ssh_public_keys         = var.zabbix_vm_ssh_public_keys
  startup_order           = each.value.startup_order
  started                 = var.zabbix_vm_started
  on_boot                 = var.zabbix_vm_on_boot
  tags                    = concat(["debian", "zabbix"], each.value.tags)
  network_devices = [
    {
      bridge   = var.opnsense_lan_bridge_name
      model    = "virtio"
      firewall = true
    },
  ]
}

module "zabbix_monolith" {
  source = "../../modules/proxmox_vm"

  target_node_name        = var.target_node_name
  vm_id                   = var.zabbix_monolith_vm_id
  vm_name                 = var.zabbix_monolith_vm_name
  description             = "Manual monolithic Zabbix VM"
  disk_datastore_id       = var.zabbix_monolith_disk_datastore_id
  efi_disk_datastore_id   = var.zabbix_monolith_efi_disk_datastore_id
  cloud_init_datastore_id = var.zabbix_monolith_cloud_init_datastore_id
  cloud_init_enabled      = true
  cloud_init_username     = var.zabbix_monolith_cloud_init_username
  cloud_init_password     = local.cloud_init_password
  cpu_cores               = var.zabbix_monolith_cpu_cores
  disk_size_gb            = var.zabbix_monolith_disk_size_gb
  import_image_file_id    = module.images.import_images[var.zabbix_monolith_image_key].file_id
  ipv4_address            = var.zabbix_monolith_ipv4_address
  ipv4_gateway            = var.zabbix_monolith_ipv4_gateway
  dns_servers             = var.zabbix_monolith_dns_servers
  memory_mb               = var.zabbix_monolith_memory_mb
  operating_system_type   = "l26"
  ssh_public_keys         = var.zabbix_monolith_ssh_public_keys
  startup_order           = 30
  started                 = var.zabbix_monolith_started
  on_boot                 = var.zabbix_monolith_on_boot
  bios                    = var.zabbix_monolith_vm_bios
  tags                    = [var.zabbix_monolith_image_key, "zabbix", "monolith"]
  network_devices = [
    {
      bridge   = var.opnsense_lan_bridge_name
      model    = "virtio"
      firewall = true
    },
  ]
}

module "n8n_server" {
  source = "../../modules/proxmox_vm"

  target_node_name        = var.target_node_name
  vm_id                   = var.n8n_server_vm_id
  vm_name                 = var.n8n_server_vm_name
  description             = "Dedicated production n8n server VM"
  disk_datastore_id       = var.n8n_server_disk_datastore_id
  efi_disk_datastore_id   = var.n8n_server_efi_disk_datastore_id
  cloud_init_datastore_id = var.n8n_server_cloud_init_datastore_id
  cloud_init_enabled      = true
  cloud_init_username     = var.n8n_server_cloud_init_username
  cpu_cores               = var.n8n_server_cpu_cores
  disk_size_gb            = var.n8n_server_disk_size_gb
  import_image_file_id    = module.images.import_images.ubuntu.file_id
  ipv4_address            = var.n8n_server_ipv4_address
  ipv4_gateway            = var.n8n_server_ipv4_gateway
  dns_servers             = var.n8n_server_dns_servers
  memory_mb               = var.n8n_server_memory_mb
  operating_system_type   = "l26"
  ssh_public_keys         = var.n8n_server_ssh_public_keys
  startup_order           = var.n8n_server_startup_order
  started                 = var.n8n_server_started
  on_boot                 = var.n8n_server_on_boot
  bios                    = var.n8n_server_bios
  tags                    = ["ubuntu", "n8n", "dedicated-prod"]
  network_devices = [
    {
      bridge   = var.opnsense_lan_bridge_name
      model    = "virtio"
      firewall = true
    },
  ]
}

module "sample_staging_server" {
  count = var.sample_staging_server_enabled ? 1 : 0

  source = "../../modules/proxmox_vm"

  target_node_name        = var.target_node_name
  vm_id                   = var.sample_staging_server_vm_id
  vm_name                 = var.sample_staging_server_vm_name
  description             = "Isolated SampleApp developer staging server"
  disk_datastore_id       = var.sample_staging_server_disk_datastore_id
  efi_disk_datastore_id   = var.sample_staging_server_efi_disk_datastore_id
  cloud_init_datastore_id = var.sample_staging_server_cloud_init_datastore_id
  cloud_init_enabled      = true
  cloud_init_username     = var.sample_staging_server_cloud_init_username
  cpu_cores               = var.sample_staging_server_cpu_cores
  disk_size_gb            = var.sample_staging_server_disk_size_gb
  import_image_file_id    = module.images.import_images.ubuntu.file_id
  ipv4_address            = var.sample_staging_server_ipv4_address
  ipv4_gateway            = var.sample_staging_server_ipv4_gateway
  dns_servers             = var.sample_staging_server_dns_servers
  memory_mb               = var.sample_staging_server_memory_mb
  operating_system_type   = "l26"
  ssh_public_keys         = var.sample_staging_server_ssh_public_keys
  startup_order           = var.sample_staging_server_startup_order
  started                 = var.sample_staging_server_started
  on_boot                 = var.sample_staging_server_on_boot
  agent_enabled           = false
  bios                    = var.sample_staging_server_bios
  tags                    = ["sample-app", "staging", "isolated", "ubuntu"]
  network_devices = [
    {
      bridge   = var.opnsense_lan_bridge_name
      model    = "virtio"
      firewall = true
      vlan_id  = var.sample_staging_server_vlan_id
    },
  ]

}

moved {
  from = module.managed_client
  to   = module.managed_clients["client01"]
}

module "managed_clients" {
  source   = "../../modules/proxmox_vm"
  for_each = var.managed_clients

  target_node_name        = var.target_node_name
  vm_id                   = each.value.vm_id
  vm_name                 = each.value.vm_name
  description             = each.value.description
  disk_datastore_id       = var.managed_client_disk_datastore_id
  efi_disk_datastore_id   = var.managed_client_efi_disk_datastore_id
  cloud_init_datastore_id = var.managed_client_cloud_init_datastore_id
  cloud_init_enabled      = true
  cloud_init_username     = var.managed_client_cloud_init_username
  cloud_init_password     = local.cloud_init_password
  cpu_cores               = var.managed_client_cpu_cores
  disk_size_gb            = var.managed_client_disk_size_gb
  import_image_file_id    = module.images.import_images.ubuntu.file_id
  ipv4_address            = each.value.ipv4_address
  ipv4_gateway            = var.managed_client_ipv4_gateway
  dns_servers             = var.managed_client_dns_servers
  memory_mb               = var.managed_client_memory_mb
  bios                    = var.managed_client_bios
  operating_system_type   = "l26"
  ssh_public_keys         = var.managed_client_ssh_public_keys
  startup_order           = each.value.startup_order
  started                 = var.managed_client_started
  on_boot                 = var.managed_client_on_boot
  tags                    = concat(["ubuntu", "managed-client", "zabbix"], each.value.tags)
  network_devices = [
    {
      bridge   = var.opnsense_lan_bridge_name
      model    = "virtio"
      firewall = true
    },
  ]
}
