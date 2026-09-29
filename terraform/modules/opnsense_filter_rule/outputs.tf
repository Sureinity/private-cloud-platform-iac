output "rules" {
  description = "Created OPNsense filter rules map."
  value = {
    for k, v in opnsense_firewall_filter.rule : k => {
      id          = v.id
      description = v.description
      enabled     = v.enabled
    }
  }
}
