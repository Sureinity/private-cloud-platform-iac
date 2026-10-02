# ==============================================================================
# OPNsense Resource Imports (Discovered Real Infrastructure)
# ==============================================================================

# --- Unbound Host Overrides ---
import {
  to = module.unbound_hosts.opnsense_unbound_host_override.override["seaweedfs"]
  id = "f6e6e4cf-1316-4921-aa2d-fb441239e979"
}

# --- Core Management Filter Rules ---
import {
  to = module.filter_rules.opnsense_firewall_filter.rule["allow_ssh_tailscale"]
  id = "98624fa5-aa03-462a-a516-1a4118bf9bc5"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["allow_https_tailscale"]
  id = "5497991d-0cc4-48a7-8934-377810993d38"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["allow_lan_internet"]
  id = "87239784-762e-47e6-9eef-10fc1e70569b"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["allow_wan_https"]
  id = "a4e08a24-8444-4a10-8d40-6e22bd23d96a"
}

# --- SampleApp Staging Segmentation Rules (OPT3 / VLAN 60) ---
import {
  to = module.filter_rules.opnsense_firewall_filter.rule["block_atl_lan_wan"]
  id = "ae15b30c-c3bf-4d3e-b852-822165386306"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["block_atl_pve"]
  id = "9c0ee792-7c8c-4fe1-bc2c-35496faa5a31"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["block_atl_home_net"]
  id = "664d1157-6bfa-4fac-978d-15f5d2e69c3b"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["block_atl_opnsense_host"]
  id = "1d2b68c6-60d9-4e2e-84e6-c0a20ee5263e"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["block_atl_opt1"]
  id = "e3811ee0-f599-49db-892b-09c48f3400c7"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["allow_atl_catchall"]
  id = "acc6c140-0c71-49b0-970f-5c9bdd9dd2f5"
}

import {
  to = module.filter_rules.opnsense_firewall_filter.rule["allow_atl_ipv6_catchall"]
  id = "5d9011d0-b0ac-4288-b78a-dbde4ee54670"
}
