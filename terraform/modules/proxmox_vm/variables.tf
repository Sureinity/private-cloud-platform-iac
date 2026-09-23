variable "target_node_name" { type = string }
variable "vm_id" { type = number }
variable "vm_name" { type = string }
variable "description" { type = string }
variable "disk_datastore_id" { type = string }
variable "memory_mb" { type = number }
variable "cpu_cores" { type = number }
variable "disk_size_gb" { type = number }
variable "startup_order" { type = number }

variable "agent_enabled" {
  type    = bool
  default = false
}

variable "bios" {
  type    = string
  default = "seabios"

  validation {
    condition     = contains(["seabios", "ovmf"], var.bios)
    error_message = "bios must be either seabios or ovmf."
  }
}

variable "efi_disk_datastore_id" {
  type     = string
  default  = null
  nullable = true
}

variable "boot_order" {
  type    = list(string)
  default = ["scsi0"]
}

variable "cdrom_file_id" {
  type     = string
  default  = null
  nullable = true
}

variable "cloud_init_datastore_id" {
  type     = string
  default  = null
  nullable = true
}

variable "cloud_init_enabled" {
  type    = bool
  default = false
}

variable "cloud_init_interface" {
  type    = string
  default = "scsi2"
}

variable "cloud_init_password" {
  type      = string
  default   = null
  nullable  = true
  sensitive = true
}

variable "cloud_init_username" {
  type     = string
  default  = null
  nullable = true
}

variable "cpu_type" {
  type    = string
  default = "host"
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

variable "import_image_file_id" {
  type     = string
  default  = null
  nullable = true
}

variable "ipv4_address" {
  type     = string
  default  = null
  nullable = true
}

variable "ipv4_gateway" {
  type     = string
  default  = null
  nullable = true
}

variable "on_boot" {
  type    = bool
  default = false
}

variable "protection" {
  type        = bool
  default     = false
  description = "Enable Proxmox VM protection flag to block removal of the VM and its disks."
}

variable "operating_system_type" {
  type    = string
  default = "other"
}

variable "search_domain" {
  type     = string
  default  = null
  nullable = true
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "started" {
  type    = bool
  default = false
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "vga_type" {
  type    = string
  default = "std"
}

variable "usb_host_device" {
  type     = string
  default  = null
  nullable = true
}

variable "additional_disks" {
  type = list(object({
    datastore_id = string
    interface    = string
    size         = number
    aio          = optional(string)
    backup       = optional(bool, true)
    cache        = optional(string)
    discard      = optional(string)
    iothread     = optional(bool, true)
    queues       = optional(number)
    replicate    = optional(bool)
    ssd          = optional(bool, true)
  }))
  default = []
}

variable "network_devices" {
  type = list(object({
    bridge   = string
    model    = optional(string, "virtio")
    firewall = optional(bool, true)
    vlan_id  = optional(number)
  }))
}
