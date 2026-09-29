module "aliases" {
  source = "../../modules/opnsense_alias"

  aliases = var.firewall_aliases
}

module "filter_rules" {
  source = "../../modules/opnsense_filter_rule"

  rules = var.firewall_filter_rules

  # Ensure aliases are provisioned before rules reference them in pf
  depends_on = [module.aliases]
}

module "unbound_hosts" {
  source = "../../modules/opnsense_unbound_host"

  host_overrides = var.unbound_host_overrides
}
