variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_insecure" {
  type        = bool
  default     = false
  description = "Disable only for a controlled bootstrap endpoint whose certificate cannot yet be verified. Keep false for normal operation."
}

variable "target_node_name" {
  type    = string
  default = "pve"
}

variable "seaweedfs_vm_id" {
  type        = number
  description = "Unused Proxmox VMID selected after a live host inspection."
}

variable "seaweedfs_vm_name" {
  type    = string
  default = "seaweedfs-state"
}

variable "seaweedfs_bridge_name" {
  type    = string
  default = "vmbr1"
}

variable "seaweedfs_ipv4_address" {
  type        = string
  description = "Reserved guest IPv4 address in CIDR notation."
}

variable "seaweedfs_ipv4_gateway" {
  type    = string
  default = "192.0.2.1"
}

variable "seaweedfs_dns_servers" {
  type    = list(string)
  default = ["192.0.2.1"]
}

variable "seaweedfs_endpoint_hostname" {
  type    = string
  default = "seaweedfs.example.invalid"
}

variable "seaweedfs_bios" {
  type    = string
  default = "ovmf"

  validation {
    condition     = contains(["seabios", "ovmf"], var.seaweedfs_bios)
    error_message = "seaweedfs_bios must be either seabios or ovmf."
  }
}

variable "seaweedfs_cpu_cores" {
  type    = number
  default = 2
}

variable "seaweedfs_memory_mb" {
  type    = number
  default = 1024
}

variable "seaweedfs_boot_disk_size_gb" {
  type    = number
  default = 20
}

variable "seaweedfs_boot_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "seaweedfs_data_disk_size_gb" {
  type    = number
  default = 100
}

variable "seaweedfs_data_disk_datastore_id" {
  type    = string
  default = "usb-ssd"
}

variable "seaweedfs_data_disk_interface" {
  type    = string
  default = "scsi1"
}

variable "seaweedfs_efi_disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "seaweedfs_cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "seaweedfs_cloud_init_interface" {
  type    = string
  default = "scsi2"
}

variable "seaweedfs_cloud_init_username" {
  type    = string
  default = "ubuntu"
}

variable "cloud_init_password" {
  type      = string
  default   = null
  nullable  = true
  sensitive = true
}

variable "cloud_init_password_file" {
  type        = string
  default     = "/home/operator/.secrets/lab-vm/pass.txt"
  nullable    = true
  description = "Local operator-only cloud-init password file. Set null when cloud_init_password is supplied directly."
}

variable "seaweedfs_ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "seaweedfs_startup_order" {
  type    = number
  default = 50
}

variable "seaweedfs_started" {
  type    = bool
  default = true
}

variable "seaweedfs_on_boot" {
  type    = bool
  default = true
}

variable "seaweedfs_agent_enabled" {
  type    = bool
  default = true
}

variable "seaweedfs_protection" {
  type        = bool
  default     = true
  description = "Enable Proxmox VM protection flag to block removal of the VM and disks."
}

variable "import_image_file_id" {
  type        = string
  default     = "local:import/ubuntu-26.04-server-cloudimg-amd64.qcow2"
  description = "Existing Proxmox image file ID (e.g. 'local:import/ubuntu-26.04-server-cloudimg-amd64.qcow2') to clone for the VM boot disk."
}
