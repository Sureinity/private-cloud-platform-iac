output "aliases" {
  description = "Created OPNsense firewall aliases indexed by alias name."
  value = {
    for k, v in opnsense_firewall_alias.alias : k => {
      id          = v.id
      name        = v.name
      type        = v.type
      description = v.description
      content     = v.content
    }
  }
}
