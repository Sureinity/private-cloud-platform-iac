variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "target_node_name" {
  type    = string
  default = "pve"
}

variable "vmbr0_name" {
  type    = string
  default = "vmbr0"
}

variable "vmbr0_ports" {
  type    = list(string)
  default = ["nic0"]
}

variable "vmbr0_address" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional PVE host address on vmbr0. Keep null when PVE management is on vmbr1."
}

variable "vmbr0_gateway" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional default gateway on vmbr0. Keep null when vmbr1 is the PVE management/default-gateway bridge."
}

variable "opnsense_lan_bridge_name" {
  type    = string
  default = "vmbr1"
}

variable "opnsense_lan_bridge_address" {
  type    = string
  default = "192.0.2.10/24"
}

variable "opnsense_lan_bridge_gateway" {
  type        = string
  default     = "192.0.2.1"
  description = "Default gateway configured on the PVE-side OPNsense LAN bridge. This is the OPNsense LAN address."
}

variable "opnsense_lan_bridge_vlan_aware" {
  type        = bool
  default     = false
  description = "Enables VLAN-aware switching on the vmbr1/OPNsense LAN bridge. Set true only after the connected OPNsense path is ready to carry the approved staging VLAN tag."
}

variable "opnsense_vm_id" {
  type    = number
  default = 100
}

variable "opnsense_vm_name" {
  type    = string
  default = "opnsense"
}

variable "opnsense_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "opnsense_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "opnsense_cdrom_file_id" {
  type    = string
  default = "none"
}

variable "opnsense_bios" {
  type    = string
  default = "ovmf"
}

variable "opnsense_boot_order" {
  type    = list(string)
  default = ["scsi0"]
}

variable "opnsense_memory_mb" {
  type    = number
  default = 2048
}

variable "opnsense_cpu_cores" {
  type    = number
  default = 2
}

variable "opnsense_disk_size_gb" {
  type    = number
  default = 24
}

variable "opnsense_started" {
  type    = bool
  default = true
}

variable "opnsense_on_boot" {
  type    = bool
  default = false
}



variable "cloud_init_password" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "Direct cloud-init password string, primarily for CI pipeline execution. Set null when cloud_init_password_file is used."
}

variable "cloud_init_password_file" {
  type        = string
  default     = "/home/operator/.secrets/lab-vm/pass.txt"
  nullable    = true
  description = "Local operator-only file containing the shared cloud-init password. The file content is read with pathexpand(), trimmed with chomp(), and must never be committed. Set null when cloud_init_password is supplied directly."
}

variable "download_timeout_seconds" {
  type    = number
  default = 1800
}

variable "import_datastore_id" {
  type    = string
  default = "local"
}

variable "debian_cloud_image_filename" {
  type    = string
  default = "debian-13-generic-amd64-20260220-2394.qcow2"
}

variable "debian_cloud_image_url" {
  type    = string
  default = "https://cdimage.debian.org/images/cloud/trixie/20260220-2394/debian-13-generic-amd64-20260220-2394.qcow2"
}

variable "ubuntu_cloud_image_filename" {
  type    = string
  default = "resolute-server-cloudimg-amd64.qcow2"
}

variable "ubuntu_cloud_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}


variable "sandbox_sync_bridge_name" {
  type    = string
  default = "vmbrsync"
}


variable "helper_vm_id" {
  type    = number
  default = 110
}

variable "helper_vm_name" {
  type    = string
  default = "helper-vm"
}

variable "helper_vm_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "helper_vm_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "helper_vm_bios" {
  type    = string
  default = "ovmf"
}

variable "helper_vm_cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "helper_vm_cloud_init_username" {
  type    = string
  default = "debian"
}

variable "helper_vm_cpu_cores" {
  type    = number
  default = 1
}

variable "helper_vm_disk_size_gb" {
  type    = number
  default = 8
}

variable "helper_vm_ipv4_address" {
  type        = string
  default     = "dhcp"
  description = "Helper VM cloud-init IPv4 configuration. Use dhcp for DHCP, or CIDR notation for a static address."
}

variable "helper_vm_ipv4_gateway" {
  type        = string
  default     = null
  nullable    = true
  description = "Helper VM IPv4 gateway. Keep null when helper_vm_ipv4_address is dhcp."
}

variable "helper_vm_memory_mb" {
  type    = number
  default = 512
}

variable "helper_vm_on_boot" {
  type    = bool
  default = false
}

variable "helper_vm_started" {
  type    = bool
  default = true
}

variable "helper_vm_ssh_public_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEKEYPLACEHOLDER000000000000000000000000000 lab-operator@example.invalid",
  ]
}

variable "zabbix_vm_cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "zabbix_vm_cloud_init_username" {
  type    = string
  default = "debian"
}

variable "zabbix_vm_cpu_cores" {
  type    = number
  default = 1
}

variable "zabbix_vm_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "zabbix_vm_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "zabbix_vm_bios" {
  type    = string
  default = "ovmf"
}

variable "zabbix_vm_disk_size_gb" {
  type    = number
  default = 10
}

variable "zabbix_vm_dns_servers" {
  type    = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

variable "zabbix_vm_ipv4_gateway" {
  type    = string
  default = "192.0.2.1"
}

variable "zabbix_vm_memory_mb" {
  type    = number
  default = 1024
}

variable "zabbix_vm_on_boot" {
  type    = bool
  default = false
}

variable "zabbix_vm_started" {
  type    = bool
  default = true
}

variable "zabbix_vm_ssh_public_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEKEYPLACEHOLDER000000000000000000000000000 lab-operator@example.invalid",
  ]
}

variable "zabbix_vms_enabled" {
  type    = bool
  default = false
}

variable "zabbix_vms" {
  type = map(object({
    vm_id         = number
    vm_name       = string
    description   = string
    ipv4_address  = string
    startup_order = number
    tags          = list(string)
  }))
  default = {
    database = {
      vm_id         = 130
      vm_name       = "zbx-db"
      description   = "Manual Zabbix database VM"
      ipv4_address  = "192.0.2.30/24"
      startup_order = 30
      tags          = ["database"]
    }
    server = {
      vm_id         = 131
      vm_name       = "zbx-server"
      description   = "Manual Zabbix server VM"
      ipv4_address  = "192.0.2.31/24"
      startup_order = 31
      tags          = ["server"]
    }
    frontend = {
      vm_id         = 132
      vm_name       = "zbx-frontend"
      description   = "Manual Zabbix frontend VM"
      ipv4_address  = "192.0.2.32/24"
      startup_order = 32
      tags          = ["frontend"]
    }
    client = {
      vm_id         = 133
      vm_name       = "zbx-client-01"
      description   = "Manual Zabbix monitored client VM"
      ipv4_address  = "192.0.2.33/24"
      startup_order = 33
      tags          = ["client"]
    }
  }
}

variable "zabbix_monolith_cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "zabbix_monolith_cloud_init_username" {
  type    = string
  default = "debian"
}

variable "zabbix_monolith_cpu_cores" {
  type    = number
  default = 2
}

variable "zabbix_monolith_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "zabbix_monolith_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "zabbix_monolith_vm_bios" {
  type    = string
  default = "ovmf"
}

variable "zabbix_monolith_disk_size_gb" {
  type    = number
  default = 20
}

variable "zabbix_monolith_dns_servers" {
  type    = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

variable "zabbix_monolith_image_key" {
  type    = string
  default = "ubuntu"

  validation {
    condition     = contains(["debian", "ubuntu"], var.zabbix_monolith_image_key)
    error_message = "zabbix_monolith_image_key must be debian or ubuntu."
  }
}

variable "zabbix_monolith_ipv4_address" {
  type    = string
  default = "192.0.2.30/24"
}

variable "zabbix_monolith_ipv4_gateway" {
  type    = string
  default = "192.0.2.1"
}

variable "zabbix_monolith_memory_mb" {
  type    = number
  default = 2048
}

variable "zabbix_monolith_on_boot" {
  type    = bool
  default = false
}

variable "zabbix_monolith_started" {
  type    = bool
  default = true
}

variable "zabbix_monolith_ssh_public_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEKEYPLACEHOLDER000000000000000000000000000 lab-operator@example.invalid",
  ]
}

variable "zabbix_monolith_vm_id" {
  type    = number
  default = 130
}

variable "zabbix_monolith_vm_name" {
  type    = string
  default = "zbx-monolith"
}



variable "n8n_server_vm_id" {
  type    = number
  default = 140
}

variable "n8n_server_vm_name" {
  type    = string
  default = "n8n-prod"
}

variable "n8n_server_cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "n8n_server_bios" {
  type    = string
  default = "ovmf"
}

variable "n8n_server_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "n8n_server_cloud_init_username" {
  type    = string
  default = "ubuntu"
}

variable "n8n_server_cpu_cores" {
  type    = number
  default = 1
}

variable "n8n_server_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "n8n_server_disk_size_gb" {
  type    = number
  default = 20
}

variable "n8n_server_dns_servers" {
  type    = list(string)
  default = ["192.0.2.1"]
}

variable "n8n_server_ipv4_address" {
  type    = string
  default = "192.0.2.40/24"
}

variable "n8n_server_ipv4_gateway" {
  type    = string
  default = "192.0.2.1"
}

variable "n8n_server_memory_mb" {
  type    = number
  default = 2048
}

variable "n8n_server_on_boot" {
  type    = bool
  default = true
}

variable "n8n_server_started" {
  type    = bool
  default = true
}

variable "n8n_server_startup_order" {
  type    = number
  default = 40
}

variable "n8n_server_ssh_public_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEKEYPLACEHOLDER000000000000000000000000000 lab-operator@example.invalid",
  ]
}

variable "managed_client_cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "managed_client_cloud_init_username" {
  type    = string
  default = "ubuntu"
}

variable "managed_client_cpu_cores" {
  type    = number
  default = 1
}

variable "managed_client_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "managed_client_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "managed_client_bios" {
  type    = string
  default = "ovmf"
}

variable "managed_client_disk_size_gb" {
  type    = number
  default = 10
}

variable "managed_client_dns_servers" {
  type    = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

variable "managed_client_ipv4_gateway" {
  type    = string
  default = "192.0.2.1"
}

variable "managed_client_memory_mb" {
  type    = number
  default = 1024
}

variable "managed_client_on_boot" {
  type    = bool
  default = false
}

variable "managed_client_started" {
  type    = bool
  default = false
}

variable "managed_client_ssh_public_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEKEYPLACEHOLDER000000000000000000000000000 lab-operator@example.invalid",
  ]
}

variable "managed_clients" {
  type = map(object({
    vm_id         = number
    vm_name       = string
    description   = string
    ipv4_address  = string
    startup_order = number
    tags          = list(string)
  }))
  default = {
    client01 = {
      vm_id         = 133
      vm_name       = "zbx-client-01"
      description   = "Ubuntu managed client for Ansible Zabbix Agent 2 automation testing"
      ipv4_address  = "192.0.2.33/24"
      startup_order = 33
      tags          = ["client01", "ansible"]
    }
    client02 = {
      vm_id         = 134
      vm_name       = "zbx-client-02"
      description   = "Ubuntu managed client for Ansible Zabbix Agent 2 automation testing"
      ipv4_address  = "192.0.2.34/24"
      startup_order = 34
      tags          = ["client02", "ansible"]
    }
    client03 = {
      vm_id         = 135
      vm_name       = "zbx-client-03"
      description   = "Ubuntu managed client for Ansible Zabbix Agent 2 automation testing"
      ipv4_address  = "192.0.2.35/24"
      startup_order = 35
      tags          = ["client03", "ansible"]
    }
    client04 = {
      vm_id         = 136
      vm_name       = "zbx-client-04"
      description   = "Ubuntu managed client for Ansible Zabbix Agent 2 automation testing"
      ipv4_address  = "192.0.2.36/24"
      startup_order = 36
      tags          = ["client04", "ansible"]
    }
  }
}

variable "sample_staging_server_enabled" {
  type        = bool
  default     = false
  description = "Creates and starts the isolated SampleApp staging VM only when all real staging VLAN, network, and SSH key values have been supplied."
}

variable "sample_staging_server_vm_id" {
  type        = number
  default     = 142
  description = "Reserved Proxmox VMID for the SampleApp staging server. Confirm it is unused before enabling the VM."
}

variable "sample_staging_server_vm_name" {
  type        = string
  default     = "sample-staging-01"
  description = "Proxmox name for the isolated SampleApp staging server."
}

variable "sample_staging_server_cloud_init_datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Datastore for the staging VM cloud-init disk. Keep this on resilient local storage unless a storage change is separately reviewed."
}

variable "sample_staging_server_cloud_init_username" {
  type        = string
  default     = "ubuntu"
  description = "Initial cloud-image account for the staging VM. Configure final operator, developer, and deployment accounts through Ansible."
}

variable "sample_staging_server_cpu_cores" {
  type        = number
  default     = 2
  description = "Initial vCPU allocation for the staging VM."
}

variable "sample_staging_server_memory_mb" {
  type        = number
  default     = 3072
  description = "Initial RAM allocation in MiB for the staging VM."
}

variable "sample_staging_server_disk_datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Datastore for the staging VM boot disk. The safe default avoids USB-backed storage."
}

variable "sample_staging_server_efi_disk_datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Datastore for the staging VM EFI disk."
}

variable "sample_staging_server_disk_size_gb" {
  type        = number
  default     = 40
  description = "Initial staging VM boot disk size in GiB."
}

variable "sample_staging_server_bios" {
  type        = string
  default     = "ovmf"
  description = "Firmware for the staging VM; OVMF provides the required UEFI boot mode."
}

variable "sample_staging_server_started" {
  type        = bool
  default     = true
  description = "Starts the staging VM after it is deliberately enabled."
}

variable "sample_staging_server_on_boot" {
  type        = bool
  default     = true
  description = "Starts the staging VM at host boot after OPNsense."
}

variable "sample_staging_server_startup_order" {
  type        = number
  default     = 20
  description = "PVE startup order for staging. Keep this greater than the OPNsense startup order of 10."
}

variable "sample_staging_server_vlan_id" {
  type        = number
  default     = null
  nullable    = true
  description = "Approved isolated staging VLAN tag on vmbr1. It intentionally has no default until OPNsense and network allocation are verified."

  validation {
    condition     = var.sample_staging_server_vlan_id == null || (var.sample_staging_server_vlan_id >= 1 && var.sample_staging_server_vlan_id <= 4094)
    error_message = "sample_staging_server_vlan_id must be null or a valid IEEE 802.1Q VLAN ID from 1 through 4094."
  }
}

variable "sample_staging_server_ipv4_address" {
  type        = string
  default     = null
  nullable    = true
  description = "Static IPv4 CIDR for the staging VM on the allocated staging VLAN. It intentionally has no default."
}

variable "sample_staging_server_ipv4_gateway" {
  type        = string
  default     = null
  nullable    = true
  description = "OPNsense gateway address for the allocated staging VLAN. It intentionally has no default."
}

variable "sample_staging_server_dns_servers" {
  type        = list(string)
  default     = []
  description = "DNS resolvers reachable from the staging VLAN. Supply only after OPNsense DNS policy is defined."
}

variable "sample_staging_server_ssh_public_keys" {
  type        = list(string)
  default     = []
  description = "Non-secret SSH public keys injected into the initial cloud-image account. Do not add private keys or passwords."
}
