output "aliases" {
  description = "Created OPNsense firewall aliases map."
  value       = module.aliases.aliases
}

output "filter_rules" {
  description = "Created OPNsense firewall filter rules map."
  value       = module.filter_rules.rules
}

output "unbound_hosts" {
  description = "Created Unbound DNS host overrides map."
  value       = module.unbound_hosts.host_overrides
}
