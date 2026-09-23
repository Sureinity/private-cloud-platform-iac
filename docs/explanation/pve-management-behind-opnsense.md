# PVE management behind OPNsense

This note records the earlier network-management decision for the PVE host.

## Current status

This layout is active again. PVE management joins the OPNsense LAN bridge on `vmbr1` using `192.0.2.10/24` with gateway `192.0.2.1`. The temporary ``temporary-pve-vmbr0-dhcp.md`` layout is retained as historical rollback context only.

## Decision

Move PVE host management off `vmbr0` and place it behind OPNsense on `vmbr1`:

| Bridge | PVE host addressing | Gateway | Purpose |
|---|---|---|---|
| `vmbr0` | none | none | physical uplink / OPNsense WAN side |
| `vmbr1` | `192.0.2.10/24` | `192.0.2.1` | PVE management and lab LAN behind OPNsense |

The intended management path is:

```text
operator -> WireGuard -> OPNsense -> vmbr1 -> PVE 192.0.2.10
```

Tailscale remains the recovery path while this migration is being validated.

## Rationale

Keeping the PVE management service directly on `vmbr0` exposes it on the upstream/home-LAN side of the lab. Moving the management address to `vmbr1` puts PVE behind OPNsense policy, allowing access to be constrained through WireGuard and firewall rules.

## Operational risks

This is a high-risk host-networking change because it removes the existing `vmbr0` host address and default gateway. A failed OPNsense, WireGuard, firewall, or route configuration can make the PVE web UI/API unreachable over the intended path.

Before applying the bridge change, confirm at least one recovery path:

- Tailscale access to the PVE host is working.
- Console or physical access is available.
- OPNsense LAN address `192.0.2.1` is reachable from `vmbr1`.
- WireGuard can reach `192.0.2.10` or has a documented route to `192.0.2.0/24`.

## vmbr0 DHCP note

`vmbr0` should be DHCP on the PVE host, not static/manual. The bpg Proxmox Terraform Linux bridge resource supports static IP/CIDR `address` values and gateway values, but it does not expose DHCP mode for host bridges. For that reason, Terraform keeps `vmbr0_address = null` and `vmbr0_gateway = null`, while the PVE host-side `/etc/network/interfaces` stanza must be rendered as `iface vmbr0 inet dhcp` by `scripts/configure-pve-vmbr0-dhcp.sh` or an equivalent manual edit.

## Terraform intent

Terraform expresses the desired bridge state:

```hcl
vmbr0_address = null
vmbr0_gateway = null

opnsense_lan_bridge_address = "192.0.2.10/24"
opnsense_lan_bridge_gateway = "192.0.2.1"
```

Apply this only from a path that will survive the network cutover.
