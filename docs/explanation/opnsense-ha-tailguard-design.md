# OPNsense HA access over Tailguard

This note records the recommended design for making the two-node OPNsense HA pair reachable from the Tailguard/Tailscale overlay while preserving the existing CARP and pfsync high-availability model.

## Summary recommendation

Use **CARP and pfsync for firewall HA** and use **Tailguard/Tailscale subnet-router HA** as a separate overlay layer.

Do not try to float a Tailguard/Tailscale node identity or `100.x` overlay address with CARP. Each OPNsense firewall should have its own Tailguard/Tailscale identity, and both firewalls should advertise the same internal LAN/VLAN prefixes as subnet routers.

```text
                           Tailnet / Tailguard
                                  |
                    +-------------+-------------+
                    |                           |
             opnsense-a                   opnsense-b
          Tailguard node A             Tailguard node B
          advertises LANs              advertises LANs
                    |                           |
                    +-------------+-------------+
                                  |
                              LAN/VLANs
                                  |
                            CARP VIPs active
                                  |
                          Internal services
```

## Keep CARP and pfsync for LAN/WAN gateway HA

Continue using the normal OPNsense HA design:

- **CARP VIPs** provide the active gateway and service addresses for LANs and WAN-facing firewall services.
- **pfsync** replicates firewall state between the two firewalls.
- **XMLRPC config sync** keeps the secondary firewall aligned with the primary where appropriate.

This keeps the firewall HA path independent from the overlay-network access path. The HA sync network should remain private to the two firewalls and should not be advertised into Tailguard/Tailscale.

## Run Tailguard/Tailscale on both OPNsense nodes

Each firewall should join the tailnet as a separate node:

```text
opnsense-a  -> own Tailguard/Tailscale node identity and overlay IP
opnsense-b  -> own Tailguard/Tailscale node identity and overlay IP
```

Use the OPNsense Tailscale plugin or equivalent service configuration on both firewalls. Do not attempt to share or fail over the Tailguard/Tailscale node identity with CARP.

## Advertise the same LAN prefixes from both firewalls

Configure both OPNsense nodes as subnet routers advertising the exact same internal prefixes.

Example:

```text
opnsense-a advertises:
  192.168.10.0/24
  192.168.20.0/24
  192.168.30.0/24

opnsense-b advertises:
  192.168.10.0/24
  192.168.20.0/24
  192.168.30.0/24
```

The prefixes must match exactly for predictable HA behavior. For example, `192.168.10.0/24` and `192.168.0.0/16` are different route advertisements and should not be treated as equivalent failover paths.

With both nodes advertising the same routes, remote Tailguard/Tailscale clients can reach internal services through whichever subnet router is selected by the overlay network:

```text
Remote tailnet client
        |
        | Tailguard/Tailscale chooses available subnet router
        v
opnsense-a or opnsense-b
        |
        v
LAN subnet / CARP VIP / internal hosts
```

## CARP VIP access model

If the LAN CARP VIP is the default gateway, for example:

```text
192.168.10.1
```

and the LAN subnet is:

```text
192.168.10.0/24
```

then advertising `192.168.10.0/24` from both firewalls makes the CARP VIP reachable from Tailguard/Tailscale clients. A separate route for the VIP is not required when the full subnet is advertised.

Remote operators can then access resources such as:

```bash
https://192.168.10.1/
ssh 192.168.10.50
https://192.168.20.10/
```

If the only required remote access is the OPNsense management VIP, advertise a narrow host route instead:

```text
192.168.10.1/32
```

If using a host route, both OPNsense nodes must advertise the exact same `/32` route.

## Node-specific versus service-style management

Use both access patterns intentionally.

### Node-specific maintenance

Use each firewall's Tailguard/Tailscale name or overlay IP when the operator needs to manage a specific node:

```text
https://opnsense-a.<tailnet-name>.ts.net/
https://opnsense-b.<tailnet-name>.ts.net/
```

This is useful for patching, troubleshooting, or checking the standby firewall directly.

### Active-service management

Use the CARP VIP through the advertised LAN subnet when the operator wants to reach whichever firewall currently owns the active management address:

```text
https://192.168.10.1/
```

This follows the normal firewall HA role instead of targeting a specific node.

## Route acceptance and SNAT defaults

For the initial deployment, the OPNsense HA pair should advertise routes but should not accept routes from the tailnet unless there is a specific site-to-site requirement.

Recommended initial behavior:

```text
advertise-routes = yes
accept-routes    = no
exit-node        = no, unless separately required
```

Keeping route acceptance disabled avoids confusing routing where one firewall sends traffic for directly connected networks through the other firewall over the overlay.

Start with the default subnet-router source NAT behavior enabled. With SNAT enabled, LAN systems see traffic as coming from the subnet router/firewall, which usually avoids the need to add return routes on every LAN host.

Only disable subnet-route masquerading if there is a clear need for LAN hosts and logs to see the original tailnet client IPs. If masquerading is disabled, add and validate explicit return routing for the tailnet client ranges.

## Security controls

Apply least-privilege controls at both the tailnet and firewall layers.

Recommended controls:

1. Do not advertise the pfsync or HA sync network.
2. Do not advertise WAN transit networks unless there is a deliberate operational need.
3. Tag both OPNsense nodes in Tailguard/Tailscale, for example:

   ```text
   tag:home-router
   tag:subnet-router
   ```

4. Use tailnet ACLs to restrict who can reach firewall management services.
5. Create OPNsense firewall rules on the Tailguard/Tailscale interface, if exposed by the local plugin/setup.
6. Allow only required traffic, for example:

   ```text
   Tailnet admins -> OPNsense GUI/SSH
   Tailnet admins -> selected LAN management hosts
   Tailnet users  -> selected services only
   Deny all else
   ```

7. Avoid exposing the OPNsense web GUI to the entire tailnet.

## Failover behavior

There are two failover layers.

### CARP failover

CARP controls active firewall ownership for LAN/WAN VIPs:

```text
opnsense-a CARP master -> opnsense-b CARP master
```

pfsync helps preserve firewall state during this transition.

### Tailguard/Tailscale subnet-router failover

Tailguard/Tailscale controls overlay access to advertised subnets. If one firewall is unavailable as a subnet router, clients can use the other firewall advertising the same route.

Do not expect pfsync to make overlay-routed sessions perfectly seamless. Existing TCP sessions may briefly stall or reconnect during subnet-router failover, especially if SNAT makes the LAN-side source address change from one firewall's physical address to the other firewall's physical address.

## Alternative: only the CARP master advertises routes

A more complex design is to use CARP event hooks so that only the current CARP master advertises subnet routes, while the standby firewall withdraws them.

Potential benefits:

- Overlay ingress always follows the CARP master.
- Logging and routing may be easier to reason about in strict active/passive designs.

Tradeoffs:

- Requires custom scripting and lifecycle hooks.
- Adds another failure mode during firewall upgrades or failover testing.
- Depends on route advertisement and withdrawal timing.
- Is less aligned with the native high-availability subnet-router model.

Do not start with this design unless the simpler dual-subnet-router model causes a concrete operational problem.

## Implementation checklist

1. Confirm CARP, pfsync, and config sync are healthy before adding overlay access.
2. Install and enable Tailguard/Tailscale on both OPNsense nodes.
3. Authenticate each firewall as a separate tailnet node.
4. Advertise the same exact LAN/VLAN prefixes from both nodes.
5. Keep `accept-routes` disabled on both OPNsense nodes initially.
6. Keep subnet-router SNAT enabled initially.
7. Do not advertise the HA sync, pfsync, or WAN transit networks.
8. Add Tailguard/Tailscale ACLs for admin and service access.
9. Add OPNsense rules for the Tailguard/Tailscale interface where applicable.
10. Validate access to both node-specific names and the CARP VIP.
11. Test failover by moving CARP mastership or placing one node into maintenance, without rebooting or disrupting the PVE host unless explicitly planned.

## Validation commands

From an authorized Tailguard/Tailscale client, validate node-specific access:

```bash
ping opnsense-a
ping opnsense-b
```

Validate CARP VIP access through the advertised subnet:

```bash
ping 192.168.10.1
curl -kI https://192.168.10.1/
```

Validate access to selected LAN services:

```bash
ping 192.168.10.50
ssh 192.168.10.50
```

On OPNsense, verify the active CARP role and firewall logs before and after failover testing.

## Rollback notes

To roll back overlay access without changing firewall HA:

1. Disable or remove the subnet route advertisements from both OPNsense nodes.
2. Remove or disable Tailguard/Tailscale ACL entries that allowed access to the LAN prefixes.
3. Disable the Tailguard/Tailscale service on the firewalls if direct node access is no longer required.
4. Leave CARP, pfsync, and config sync unchanged unless the rollback specifically targets firewall HA.

## References

- [OPNsense High Availability](https://docs.opnsense.org/manual/hacarp.html)
- [OPNsense CARP how-to](https://docs.opnsense.org/manual/how-tos/carp.html)
- [OPNsense Tailscale plugin API](https://docs.opnsense.org/development/api/plugins/tailscale.html)
- [Tailscale high availability subnet routers](https://tailscale.com/docs/how-to/set-up-high-availability)
- [Tailscale subnet route masquerading](https://tailscale.com/docs/reference/troubleshooting/network-configuration/disable-subnet-route-masquerading)
