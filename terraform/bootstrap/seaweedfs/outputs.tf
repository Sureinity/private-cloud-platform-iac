output "seaweedfs_vm_id" {
  value = module.seaweedfs_vm.vm_id
}

output "seaweedfs_vm_name" {
  value = module.seaweedfs_vm.vm_name
}

output "seaweedfs_ipv4_address" {
  value = var.seaweedfs_ipv4_address
}

output "seaweedfs_endpoint_hostname" {
  value = var.seaweedfs_endpoint_hostname
}

output "seaweedfs_endpoint_url" {
  value = "https://${var.seaweedfs_endpoint_hostname}"
}
