output "host_overrides" {
  description = "Created Unbound DNS host overrides map."
  value = {
    for k, v in opnsense_unbound_host_override.override : k => {
      id          = v.id
      hostname    = v.hostname
      domain      = v.domain
      server      = v.server
      type        = v.type
      description = v.description
      enabled     = v.enabled
    }
  }
}
