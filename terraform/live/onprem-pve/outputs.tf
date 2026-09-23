output "bridges" {
  value = module.bridges.bridges
}

output "import_images" {
  value = module.images.import_images
}

output "opnsense_vm_id" {
  value = module.opnsense.vm_id
}

output "opnsense_vm_name" {
  value = module.opnsense.vm_name
}

output "zabbix_vm_ids" {
  value = {
    for role, vm in module.zabbix_vms : role => vm.vm_id
  }
}

output "zabbix_vm_names" {
  value = {
    for role, vm in module.zabbix_vms : role => vm.vm_name
  }
}

output "zabbix_monolith_vm_id" {
  value = module.zabbix_monolith.vm_id
}

output "zabbix_monolith_vm_name" {
  value = module.zabbix_monolith.vm_name
}

output "n8n_server_vm_id" {
  value = module.n8n_server.vm_id
}

output "n8n_server_vm_name" {
  value = module.n8n_server.vm_name
}

output "sample_staging_server_vm_id" {
  value = one(module.sample_staging_server[*].vm_id)
}

output "sample_staging_server_vm_name" {
  value = one(module.sample_staging_server[*].vm_name)
}

output "managed_client_vm_ids" {
  value = {
    for role, vm in module.managed_clients : role => vm.vm_id
  }
}

output "managed_client_vm_names" {
  value = {
    for role, vm in module.managed_clients : role => vm.vm_name
  }
}
