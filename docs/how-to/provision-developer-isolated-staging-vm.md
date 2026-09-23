# Provision an isolated SampleApp staging VM

Use this guide to provision the persistent staging VM for the `~/Zeraynce/sample-app` Docker Compose application. It records the agreed network, access, deployment, ingress, recovery, and operator boundaries before Terraform, Ansible, OPNsense, Cloudflare, or Tailnet configuration changes are made.

## Scope and decisions

The staging VM is a dedicated application host. It runs the dedicated SampleApp Cloudflare Tunnel Compose stack: `cloudflared`, `sample-app`, and a private PostgreSQL container. It does not run Traefik, Redis, object storage, or a local queue service.

| Area | Decision |
| --- | --- |
| VM lifecycle | Persistent while staging is being stabilized; later reassess whether it can become disposable. |
| Application runtime | Docker Compose from the SampleApp repository: `cloudflared`, `sample-app`, and `postgres` on a private Docker network. |
| Database | Private PostgreSQL container named `postgres`, persisted through the staging Compose volume. |
| Object storage | Cloudflare R2. |
| Background work | Trigger.dev; no self-hosted Redis or queue service. |
| Developer access | Individual Tailnet identity, SSH, and permanent Docker-group access on this dedicated VM. |
| CI/CD access | GitHub Actions joins the Tailnet temporarily through the Tailscale GitHub Action. |
| Public application ingress | Named Cloudflare Tunnel terminating at Cloudflare; `cloudflared` routes directly to `sample-app:3002`. |
| Private network | Dedicated staging VLAN/subnet routed and enforced by OPNsense. |
| PVE connection | Use `vmbr1` as a VLAN-aware trunk; do not create a dedicated PVE bridge initially. |
| Recovery posture | Persistent and backed up; infrastructure remains reproducible through Terraform, Ansible, and GitHub Actions. |

## Security risk assessment

| Risk | Degree | Why it matters | Required control |
| --- | --- | --- | --- |
| Broad lateral access through shared subnet routes | Critical | Access to `192.0.2.0/24` could expose PVE, OPNsense, monitoring, and other workloads. | Put staging in a dedicated VLAN/subnet; explicitly deny access to management and home networks. |
| Direct access to PVE or OPNsense management | Critical | Hypervisor or firewall access can expose all guests or alter network policy. | Do not permit developer or CI tags to access PVE `192.0.2.10`, OPNsense management `192.0.2.1`, firewall node names, or management ports. |
| Compromised developer device or identity | High | A developer Tailnet identity can use every granted path. | Individual identity, MFA, device approval, narrow ACLs, review dates, and offboarding. |
| Permanent Docker-group membership | High | Docker group membership is root-equivalent on the guest VM. | Keep the VM dedicated and segmented; do not treat Docker access as PVE, OPNsense, Tailnet-admin, or shared-secret access. |
| Compromised GitHub deploy identity | High | CI can pull images and restart the application. | Use a short-lived, tagged Tailscale CI identity; least-privilege SSH and GHCR credentials; GitHub Environment protection. |
| Public staging exposure | High | Unfinished features, debug routes, and test accounts can be exposed. | Use Cloudflare Tunnel with WAF/rate controls. Cloudflare Access is intentionally deferred; enable it before broader or sensitive external access. |
| Cloudflare Tunnel credential exposure | High | A tunnel credential can provide a route to the local origin. | Store it only as a VM runtime secret; never commit it, bake it into an image, or expose it to the developer unnecessarily. |
| Secrets or production-like data in staging | High | Staging can accumulate API keys, database data, deploy credentials, and uploaded files. | Use distinct staging secrets and least-privilege credentials; avoid production data unless explicitly approved. |
| Incorrect inter-VLAN policy | Medium-High | A compromised VM could otherwise reach management or home devices. | Enforce default-deny and explicit allow rules at OPNsense; log denials. |
| Loss of audit attribution behind subnet-router SNAT | Medium | Routed traffic may appear to originate from the router. | Run Tailscale directly on the VM for SSH/CI and correlate Tailnet, OPNsense, and guest logs. |
| Same-host backups treated as disaster recovery | Medium-High | A single PVE host and its local storage can fail together. | Keep off-host copies and test restores before claiming a disaster-recovery capability. |
| Availability impact from application workloads | Medium | Docker images, logs, and workloads can pressure the shared on-premises PVE host. | Set VM limits, monitor disk/RAM/CPU, and avoid building images on the VM. |

## Target architecture

```text
Public tester
     |
     | HTTPS: sample-staging.novaryn.tech
     v
Cloudflare edge
     | TLS, WAF, rate controls
     v
Cloudflare Tunnel: outbound-only connection
     v
cloudflared on sample-staging-01
     v
sample-app:3002 on the private Docker network
     |-- postgres:5432 on the same private Docker network
     |-- Cloudflare R2
     `-- Trigger.dev

Developer / operator / GitHub Actions
     |
     | Tailscale only: named/tagged identity, SSH access
     v
sample-staging-01
     |
     `-- dedicated OPNsense staging VLAN/subnet
```

## SampleApp staging deployment contract

Provision the VM to run the staging stack defined in the SampleApp application repository's `docker-compose.staging.yml`. Do not substitute the legacy `docker-compose.yml`, which contains a Traefik topology intended for a different deployment model.

| Item | Required staging value or behavior |
| --- | --- |
| Public hostname | `sample-staging.novaryn.tech` |
| Cloudflare tunnel | Named tunnel `sample-staging`, configured in Cloudflare Zero Trust as a Docker connector. |
| Tunnel origin | `http://sample-app:3002` |
| Runtime services | `cloudflared`, `sample-app`, and `postgres` only. |
| Docker network | `sample-staging-internal`; no host-published application or database ports. |
| Public URL configuration | `APP_PUBLIC_URL=https://sample-staging.novaryn.tech` and `ATELIER_HOST=sample-staging.novaryn.tech`. |
| Database connection | `postgresql://sample-app_user:<password>@postgres:5432/sample-app_db?schema=public` for both `DATABASE_URL` and `DIRECT_URL` when the Compose database is used. |
| Image source | `ghcr.io/zeraynce-studio/sample-app:staging`, with immutable `staging-<short-sha>` tags for rollback. |
| Initial access policy | Public through the Cloudflare hostname; Cloudflare Access is deferred by decision and must be introduced before broader or sensitive external access. |

Before first startup, create `.env.staging` from `.env.staging.example`, set its mode to `0600`, and provide real values for the required tunnel, database, and application secrets. Do not record those values in this guide.

```bash
cd <sample-app-checkout>
cp .env.staging.example .env.staging
chmod 600 .env.staging
docker compose --env-file .env.staging -f docker-compose.staging.yml pull
docker compose --env-file .env.staging -f docker-compose.staging.yml up -d
docker compose --env-file .env.staging -f docker-compose.staging.yml ps
```

Validate the deployment from the VM and Cloudflare:

```bash
docker compose --env-file .env.staging -f docker-compose.staging.yml logs --tail=100 cloudflared sample-app postgres
docker compose --env-file .env.staging -f docker-compose.staging.yml exec sample-app wget -qO- http://127.0.0.1:3002/api/health
```

The Cloudflare Tunnel dashboard must report a healthy connector, and `https://sample-staging.novaryn.tech/api/health` must return a successful response. No router port-forwarding or inbound VM firewall opening is required for `80`, `443`, `3002`, or `5432`.

No inbound WAN port forwarding is required for the application. The Cloudflare Tunnel connector initiates outbound connections from the VM to Cloudflare. Do not expose the PVE host or the VM SSH service publicly to make deployment or app ingress work.

## Private network isolation

### Boundary ownership

Use all three layers, with OPNsense as the primary boundary:

| Layer | Responsibility |
| --- | --- |
| OPNsense | Primary inter-VLAN routing, default-deny policy, logging, and egress control. |
| PVE | Attach the VM NIC to the staging VLAN and enable the VM NIC firewall as defense in depth. |
| Guest VM | Limit locally reachable services and restrict SSH to Tailscale paths. |

PVE connects the VM; OPNsense isolates the network; the guest protects itself.

### VLAN-aware `vmbr1` design

Do not create a separate PVE bridge for staging initially. Make `vmbr1` VLAN-aware and use it as the PVE-to-OPNsense trunk.

```text
PVE vmbr1: VLAN-aware trunk
  |
  +-- untagged/native network: existing 192.0.2.0/24 management and lab segment
  |
  `-- VLAN <staging-vlan-id>: staging subnet, for example 10.0.60.0/24
        |
        +-- OPNsense VLAN interface/gateway: 10.0.60.1/24
        `-- sample-staging-01 NIC: tagged VLAN <staging-vlan-id>
```

`10.0.60.0/24` and the VLAN ID are examples only. Allocate both after verifying they do not conflict with existing OPNsense, DHCP, static, or Tailnet route allocations.

Requirements:

1. Enable VLAN-aware behavior on `vmbr1`.
2. Configure the matching VLAN interface on the OPNsense LAN-side interface connected to `vmbr1`.
3. Assign the staging VM NIC to the VLAN ID. The existing Terraform VM module already supports `network_devices[*].vlan_id`.
4. Keep the PVE host without an IP address on the staging VLAN.
5. Enable the PVE firewall for the staging VM NIC, but do not use it as the only segmentation control.

Create a separate bridge only if a future requirement needs an entirely separate Layer-2 path with no shared trunk, or if the current PVE-to-OPNsense topology cannot carry VLAN tags.

### OPNsense policy intent

Create OPNsense rules with default deny semantics:

```text
Allow staging -> required DNS and NTP resolvers
Allow staging -> OS package sources and approved outbound internet services
Allow staging -> GitHub, GHCR, Cloudflare, Tailscale, Trigger.dev
Allow staging -> Cloudflare R2 endpoints

Deny and log staging -> 192.0.2.0/24 management/lab subnet
Deny and log staging -> PVE 192.0.2.10
Deny and log staging -> OPNsense management 192.0.2.1
Deny and log staging -> home-LAN networks
Deny and log staging -> OPNsense HA/pfsync/sync and WAN-transit networks
Deny and log staging -> all other private networks unless explicitly approved
```

Use actual provider FQDN/IP requirements only after verifying each service's documented network endpoints. Do not create a broad private-network allow rule simply to make an integration work.

### Current implementation: VLAN 60 and temporary firewall posture

As of August 22, 2026, the first staging network path is implemented and validated with ARP between the guest and OPNsense. This is an operational record of the current configuration, not approval of the final firewall posture.

| Component | Current configuration |
| --- | --- |
| PVE bridge | `vmbr1` is VLAN-aware. |
| Staging VLAN | VLAN tag `60`, named `ATELIER_STAGING_VLAN60` in OPNsense. |
| VLAN parent | OPNsense LAN parent `vtnet1`, which carries the existing untagged `192.0.2.0/24` management/lab segment. |
| OPNsense staging interface | `vlan01`, assigned as `ATELIER_STAGING` (`opt3`), enabled with static IPv4 `10.0.60.1/24`. IPv6 is disabled. |
| Staging guest | `sample-staging-01` (VMID `142`) connects to `vmbr1` with VLAN tag `60` and uses `10.0.60.10/24` with gateway `10.0.60.1`. |
| Layer-2 validation | `arping` from `sample-staging-01` receives replies from `10.0.60.1`; OPNsense packet capture on `vtnet1` shows VLAN-60 ARP requests and replies. |

The OPNsense VLAN was created with parent `vtnet1`, VLAN tag `60`, and description `ATELIER_STAGING_VLAN60`. The assigned interface does not enable OPNsense's `Block private networks` or `Block bogon networks` settings. Those settings are inappropriate for this internal RFC1918 VLAN and can break intended local operation.

The current `ATELIER_STAGING` interface rule order contains these blocks before a temporary broad pass rule:

1. Block staging access to the OPNsense `LAN network` and `WAN network` objects. In this topology, the WAN network is the directly connected upstream home-router subnet; this blocks access to that home segment without blocking general Internet egress.
2. Block staging access to `192.168.50.0/24`.
3. Block staging access to the PVE host at `192.0.2.10`.
4. Block staging access to all services on `This Firewall`.
5. Block staging access to the `OPT1 network`.
6. Pass `ATELIER_STAGING network` to any destination and port, described as a temporary catch-all testing rule.

The final pass rule is knowingly unsafe as a lasting policy. It permits every destination and service not caught by the preceding blocks, including any future or unlisted private network. It exists only while the service dependencies are being discovered and must be removed before staging is treated as a dependable environment.

#### Required firewall hardening before declaring staging ready

Replace the temporary catch-all rule with explicit egress allows, then retain an explicit logged final deny. The final rule set needs, at minimum:

- a logged block for the entire `192.0.2.0/24` management/lab subnet, not only `192.0.2.10`;
- logged blocks for every OPNsense HA, pfsync, configuration-sync, CARP, and transit subnet;
- logged blocks for all other RFC1918 ranges unless an approved exception exists;
- explicit DNS and NTP allows to approved resolvers/time sources;
- narrowly reviewed outbound access for Tailscale, OS updates, GitHub/GHCR, Cloudflare, Cloudflare R2, and Trigger.dev;
- a validation run proving the guest can reach required public dependencies but cannot reach PVE, OPNsense management, home networks, HA/sync networks, or unapproved private networks.

Do not remove the existing targeted blocks until their broader replacement aliases and validation evidence exist. The current rule set protects known networks, but it is not a default-deny egress design.

## VM allocation and host posture

Start with the following persistent-service allocation, then adjust from observed CPU, RAM, disk, and Docker metrics:

| Resource | Initial value |
| --- | --- |
| Name | `sample-staging-01` |
| VMID | `142`, after confirming it is unused at implementation time |
| Operating system | Ubuntu 24.04 LTS cloud image |
| vCPU | 2 |
| RAM | 3 GiB |
| Disk | 40 GiB |
| Primary guest disk datastore | `local-lvm` |
| Firmware | OVMF / UEFI |
| QEMU guest agent | Enabled |
| PVE NIC firewall | Enabled |
| Start at boot | Enabled |
| Startup order | After OPNsense; assign the exact order during Terraform implementation |

Keep the boot disk on `local-lvm`. The `usb-ssd` datastore provides useful capacity but introduces a USB-link dependency and is not redundancy. Use it only after a separately reviewed storage decision, such as for backups or noncritical data.

GitHub Actions must build application images and publish them to GHCR. Do not build normal release images on this VM.

## Terraform provisioning

Terraform now models the PVE-side portion of this design in `terraform/live/onprem-pve/`:

- the reusable bridges module exposes `vlan_aware`; `opnsense_lan_bridge_vlan_aware` controls the existing `vmbr1` bridge and defaults to `false`;
- `module.sample_staging_server` creates `sample-staging-01` only when `sample_staging_server_enabled` is `true`;
- the VM uses VMID `142`, Ubuntu cloud image, OVMF/UEFI, QEMU guest agent, 2 vCPU, 3072 MiB RAM, a 40 GiB `local-lvm` boot disk, PVE NIC firewall, boot-on-host-start, and startup order `20` (after OPNsense at order `10`);
- its only NIC attaches to `vmbr1` with the configured `sample_staging_server_vlan_id` tag.

The safe defaults do **not** enable VLAN-aware switching or create the VM. The VLAN ID, guest IPv4 CIDR, OPNsense gateway, and DNS resolvers default to unset values because this guide intentionally leaves the real allocation open. The `home-vm` public key is included for initial operator access; it is public material, but it does not replace dedicated developer and deployment identities configured later through Ansible.

### Required non-secret inputs

After completing the OPNsense VLAN/subnet allocation and firewall policy, copy the staging block in `terraform/live/onprem-pve/terraform.tfvars.example` to the ignored local `terraform/live/onprem-pve/terraform.tfvars` and set:

```hcl
opnsense_lan_bridge_vlan_aware       = true
sample_staging_server_enabled       = true
sample_staging_server_vlan_id       = <approved-vlan-id>
sample_staging_server_ipv4_address  = "<approved-static-ip>/<prefix>"
sample_staging_server_ipv4_gateway  = "<opnsense-vlan-gateway>"
sample_staging_server_dns_servers   = ["<approved-dns-server>"]
sample_staging_server_ssh_public_keys = [
  "ssh-ed25519 <operator-public-key> operator",
]
```

Keep the staging boot and EFI disks on `local-lvm` unless a separate storage review approves another datastore. Do not add passwords, SSH private keys, Cloudflare tunnel credentials, GHCR credentials, or Proxmox tokens to Terraform input files. Configure those runtime secrets after provisioning through an approved secret-management process.

### Plan, validation, and rollback

Run these commands from `terraform/live/onprem-pve/` only after verifying VMID `142` is unused, the OPNsense VLAN interface is configured, the connected path carries the tagged VLAN, and the OPNsense default-deny rules are ready:

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -out=sample-staging.tfplan
```

Expected plan impact is limited to updating `vmbr1` with `vlan_aware = true` and creating `sample-staging-01` plus its local cloud-init/EFI/boot disks. The plan must not destroy or replace existing VMs, change host addressing/gateways, modify unrelated bridges, or include unexpected networking changes. Do not apply if it does.

`vmbr1` is the PVE management bridge, so enabling VLAN awareness is network-sensitive even though it preserves the existing untagged management path. Do not reboot PVE or restart host networking as part of this work. Preserve a tested console/physical access path and a backup of the PVE network configuration before applying.

Apply only a reviewed safe plan:

```bash
terraform apply sample-staging.tfplan
```

Validate the result with PVE console/API inspection, then confirm the guest receives its assigned tagged-VLAN address, the PVE host has no address on that VLAN, and OPNsense deny/log rules block management, home-LAN, HA/sync, and other unapproved private destinations. Confirm `qemu-guest-agent` reports from PVE before handing the VM to guest-configuration automation.

If validation fails, stop workload access first. For a bridge-only rollback before workloads depend on the VLAN, set `sample_staging_server_enabled = false` and `opnsense_lan_bridge_vlan_aware = false`, review the destructive VM plan carefully, and apply only after preserving any needed guest data. Do not use Terraform to destroy a staging VM that contains data requiring recovery; restore service or extract data first. Coordinate any OPNsense VLAN/rule rollback separately, and never restart PVE networking remotely without an approved console recovery path.

## Tailnet access model

### Human access

- Invite the developer under an individual Tailnet identity; do not share a Tailnet owner or admin account.
- Require MFA and device approval before granting staging access.
- Install Tailscale directly on `sample-staging-01`.
- Give the developer a dedicated key-only local account, for example `sample-app-dev`.
- The developer receives permanent Docker-group membership for the current collaboration phase. Treat this as guest-root-equivalent access.
- Disable password authentication and root SSH login.
- Do not grant the developer Tailnet admin, ACL editing, DNS administration, subnet-router, exit-node, PVE, OPNsense, or other VM access.

### CI access

GitHub Actions must join the Tailnet temporarily with the Tailscale GitHub Action. Prefer workload identity federation and a short-lived tagged CI identity over a long-lived reusable auth key.

Policy intent:

```text
Source: tag:sample-app-developer
Allow:  tag:sample-staging TCP 22
Allow:  tag:sample-staging TCP 443 when a private smoke test requires it

Source: tag:sample-staging-ci
Allow:  tag:sample-staging TCP 22
Allow:  tag:sample-staging TCP 443 when a private smoke test requires it

Deny: both roles to PVE, OPNsense, all other Tailnet devices, all other subnet routes,
      home devices, and Tailnet administration services
```

The GitHub deploy identity must use a separate local account, for example `sample-deploy`. Give it only the permissions needed to run the approved Docker Compose deployment commands. Do not use the developer account for CI.

Pin the staging VM SSH host key in the GitHub Environment configuration. Do not rely on `ssh-keyscan` during each deployment, because it trusts whatever host responds at that moment.

### Current implementation: Tailscale

As of August 22, 2026, Tailscale is installed directly on `sample-staging-01`. The machine is connected, has no subnet routes, and is not permitted to act as an exit node. Direct Tailnet access is therefore the intended private-management path; staging does not rely on OPNsense subnet routing for developer SSH.

| Component | Current configuration |
| --- | --- |
| Staging node | `sample-staging-01` |
| Tailnet IPv4 | `198.51.100.100` |
| Server tag | `tag:sample-app-hosts` |
| Tag owner | `group:sample-app-developers` |
| Human group | `group:sample-app-developers`, currently containing two members |
| Developer access | `group:sample-app-developers` may reach `tag:sample-app-hosts` on TCP `22`. |
| CI access | `tag:cicd` may reach `tag:sample-app-hosts` on TCP `22`. |
| Routes and exit node | No subnets are advertised; exit-node use is not allowed. |
| Node lifecycle | Key expiry is disabled. |

The current Tailscale rules are sufficient for initial SSH connectivity, but they are not yet the final access model described earlier in this guide. In particular, the staging host tag is owned by the developer group, and the CI identity has access based on the generic `tag:cicd` tag.

#### Required Tailnet hardening before developer handoff

Subject the current policy to the following changes before treating staging access as stable:

1. Change ownership of the staging-server tag to an operator-only group. Developers must not be able to assign themselves the `tag:sample-app-hosts` server identity or tag arbitrary devices as staging hosts.
2. Split the current generic `tag:sample-app-hosts` into a dedicated staging tag, for example `tag:sample-staging`, if that tag will later need different access or lifecycle controls from other SampleApp hosts.
3. Replace generic `tag:cicd` access with a dedicated `tag:sample-staging-ci` identity for GitHub Actions. Restrict it to the staging host and its required deployment port only.
4. Keep developer access limited to the approved staging SSH port. Add a separate explicit rule only if a controlled private application smoke test needs TCP `443`.
5. Require MFA, device approval, and offboarding review for every human member of `group:sample-app-developers`.
6. Implement the GitHub Actions Tailscale connection through short-lived workload identity federation or another reviewed ephemeral CI identity. Do not store a reusable high-privilege auth key in the repository or workflow configuration.
7. Document the local SSH accounts separately from Tailnet policy. Tailnet authorization to TCP `22` does not remove the need for key-only SSH, disabled root/password login, a dedicated developer account, and a separate deploy account.

The existing VM is correctly not advertising the staging subnet. Keep it that way unless a later design explicitly requires a reviewed subnet router. Advertising `10.0.60.0/24` would extend access beyond the intended direct connection to the staging host and complicate OPNsense policy enforcement.

## Public ingress through Cloudflare Tunnel

Use the SampleApp staging Compose stack's `cloudflared` service as the Cloudflare Tunnel connector. The intended flow is:

```text
Cloudflare Tunnel -> cloudflared -> sample-app:3002
```

For the initial implementation:

- Do not run Traefik or publish `80`, `443`, `3002`, or `5432` on the VM LAN interface.
- Do not configure Let’s Encrypt, ACME state, inbound HTTP validation, or router port forwarding for this staging deployment.
- Keep `cloudflared`, `sample-app`, and `postgres` on the private `sample-staging-internal` Docker network.
- Terminate public TLS at Cloudflare initially; use Cloudflare-to-origin HTTP only on the private Docker network.
- Create the named, remotely managed tunnel `sample-staging` and map `sample-staging.novaryn.tech` to `http://sample-app:3002`; never reuse a production tunnel credential.
- Store its connector token as `CLOUDFLARE_TUNNEL_TOKEN` only in the protected `.env.staging` file. Never commit it, include it in an image, or give it to the developer by default.

Cloudflare Access is deferred for the initial staging launch. Treat the hostname as public, maintain Cloudflare WAF/rate controls, and enable Access with an explicit allow-list before broader external testing or sensitive staging data is introduced.

## Deployment, release, and rollback model

The current deployment model is GitHub Actions build -> GHCR publish -> SSH -> Docker Compose pull/restart. Retain that high-level flow while adding Tailscale connectivity and stronger controls.

Required improvements before treating staging as dependable:

1. Use the Tailscale GitHub Action for temporary private CI-to-VM connectivity.
2. Keep GitHub Environment approvals and staging-only secrets separate from production.
3. Use a dedicated least-privilege GHCR package-read credential on the VM; do not use a personal owner/admin token.
4. Keep runtime secrets in a protected `.env.staging` file and keep selected image/tag state in a separate non-secret release file. Do not mix secret material and mutable release state.
5. Run `docker compose config` before deployment.
6. Define one serialized Prisma migration process before application rollout. Migrations must be reviewed for backward compatibility; Prisma does not provide automatic safe down-migration rollback.
7. Run a post-deploy private smoke test through Tailscale or another controlled internal path. `docker compose ps` alone is insufficient.
8. Retain the previous immutable image tag and document a rollback command that switches to it. Do not automate rollback until migration behavior and health semantics have been proven.

## Persistent recovery and backups

The staging VM is persistent, but it must also be recoverable by code.

Initial recovery targets:

| Objective | Initial target |
| --- | --- |
| VM-local configuration/state RPO | Up to 24 hours |
| Service recovery RTO | Same day / a few hours |
| VM backup cadence | Daily |
| Restore verification | Before relying on backups operationally |

Back up and protect:

- VM configuration and guest disk through PVE backups;
- runtime secrets through a separate encrypted and access-controlled process;
- Cloudflare Tunnel configuration/credential recovery material without putting the credential in Git;
- the private `sample-staging-postgres-data` Docker volume and a tested PostgreSQL restore procedure;
- Cloudflare R2 object versioning/lifecycle configuration if uploaded staging media matters.

A backup stored only on the PVE host or its attached storage is not disaster recovery. Add an off-host copy before claiming protection from host loss, theft, power events, or local storage failure.

## Validation checklist

Before granting developer or public tester access, verify all of the following:

```text
[ ] Staging VM is on its tagged staging VLAN, not the 192.0.2.0/24 management network.
[ ] PVE has no IP address on the staging VLAN.
[ ] OPNsense deny/log rules block staging access to PVE, OPNsense, management, home-LAN, and HA/sync networks.
[ ] Developer and CI Tailnet roles can reach only sample-staging-01 on approved ports.
[ ] SSH root and password login are disabled.
[ ] Developer Docker access works only on the dedicated staging guest.
[ ] GitHub Actions uses temporary Tailnet access and a pinned SSH host key.
[ ] No inbound WAN port forwarding exists for the VM application or SSH service.
[ ] Cloudflare Tunnel `sample-staging` reaches `sample-app:3002` without public VM ports.
[ ] `docker compose --env-file .env.staging -f docker-compose.staging.yml config` succeeds and renders no host `ports:` mappings.
[ ] `cloudflared`, `sample-app`, and `postgres` are healthy, and `https://sample-staging.novaryn.tech/api/health` succeeds.
[ ] Cloudflare Access is either explicitly deferred or enabled with a documented allow-list before sensitive/broader external access.
[ ] Application health endpoint, deployment smoke test, monitoring, backups, and a restore test are documented and working.
```

## Open decisions

Resolve these before implementing the corresponding components:

1. Allocate and record the real staging VLAN ID, subnet, gateway, DNS behavior, and IP reservation.
2. Define the Cloudflare WAF/rate-control policy and the trigger for enabling Cloudflare Access.
3. Define the exact deployment-account command scope and the database migration procedure.
4. Select off-host backup storage for VM state and the `sample-staging-postgres-data` volume, then schedule a restore test.

## Future implementation backlog

The following work is required before this VM should be described as a dependable developer staging environment. These entries are intentionally concrete enough to become implementation tasks, runbooks, Ansible variables, or acceptance criteria. They do not describe completed work.

### Network and PVE

- Replace the temporary OPNsense `ATELIER_STAGING` catch-all pass rule with reviewed, minimal egress allows and a final logged deny.
- Create and document OPNsense aliases for management, home-LAN, HA/pfsync/configuration-sync, transit, and other RFC1918 networks. Use those aliases in logged block rules rather than relying on individual host blocks.
- Record the complete OPNsense interface-to-subnet map, including WAN, LAN, `ATELIER_STAGING`, `OPT1`, HA, pfsync, configuration-sync, and transit interfaces. Do not record public addresses, credentials, or secrets.
- Decide whether VLAN 60 is static-address-only or has DHCP. If DHCP is enabled, document its pool, reservations, exclusions, DNS, lease policy, and the reserved address for `sample-staging-01`.
- Document the PVE firewall state for VM `142` and OPNsense VM `100`, including whether it remains enabled, what it protects, and the VLAN traffic validation required after any change.
- Add a recovery procedure for VLAN 60 connectivity: check guest address/route, verify PVE NIC tag and bridge VLAN membership, verify OPNsense `vtnet1.60`/`vlan01`, capture ARP on `vtnet1`, and restart only the OPNsense guest when interface changes need reinitialization. Do not restart PVE networking remotely as part of routine diagnosis.
- Create automated or scheduled checks for unexpected staging-to-private-network attempts using OPNsense deny logs.

### Tailnet and operator access

- Create an operator-only Tailnet group and transfer ownership of the staging server tag to it. `group:sample-app-developers` must not own a server tag.
- Decide whether to retain `tag:sample-app-hosts` or migrate the VM to a dedicated `tag:sample-staging`. Document the migration, verification, and rollback steps before changing a live tag.
- Create a dedicated ephemeral CI identity such as `tag:sample-staging-ci`; remove the generic `tag:cicd` access once GitHub Actions uses the dedicated identity.
- Require MFA and device approval for developer Tailnet identities, document the membership review cadence, and add an offboarding procedure that removes Tailnet group membership, SSH keys, local accounts, and deployment credentials.
- Document the direct SSH model: local account names, public-key source, host-key pinning, key rotation, root/password-login settings, break-glass access, and the exact distinction between operator, developer, and CI/deploy accounts.
- Decide whether Tailscale SSH remains disabled or is intentionally adopted. Do not run both ordinary SSH and Tailscale SSH without documenting the separate authorization and audit paths.
- Keep subnet-route advertisement and exit-node capability disabled unless a future design explicitly approves them; document the security review required before enabling either capability.

### Ansible operations

- Create a dedicated `sample_staging` inventory group and document the canonical Ansible connection endpoint, bootstrap user, host-key verification approach, control node, required collections, and supported Ansible version.
- Define role ownership boundaries: which roles manage users, SSH, Docker, Tailscale verification, monitoring, guest firewall, updates, application directories, and deployment support. Do not let multiple playbooks mutate the same service without a declared owner.
- Define the desired local account model: operator/bootstrap, developer, GitHub deploy, and any break-glass account; document UID/GID allocation, groups, authorized-key lifecycle, and sudo scope for each.
- Decide whether direct Docker-group access is accepted. Docker membership is guest-root-equivalent and is incompatible with treating `tailscaled` as protected from the developer. If this risk is not accepted, provide a restricted deployment interface instead of Docker-group membership.
- Define the Tailscale role inputs and limits: installation source, service enablement, version/update policy, health checks, allowed `tailscale up` flags, and the secret-management mechanism for initial enrollment. Do not place auth keys in inventory, group variables, Terraform variables, or Git.
- Define Ubuntu hardening and maintenance policy: unattended upgrades, patch/reboot window, package-source policy, SSH settings, local firewall ownership, DNS resolver, NTP source, and required post-run checks.
- Define Docker policy: package source and version policy, Compose plugin requirement, daemon configuration, log rotation, registry authentication handling, resource limits, and persistent-data paths.
- Add idempotent validation tasks for SSH configuration, service status, Tailscale state, Docker/Compose availability, expected file modes, and—once deployed—the application health endpoint.
- Create a task-oriented Ansible runbook that covers prerequisites, secret injection, `--check` use, syntax/lint checks, normal execution order, verification, and rollback.

### Application runtime, secrets, and delivery

- Deploy the SampleApp repository's `docker-compose.staging.yml` from the chosen application checkout path. Its only staging services are `cloudflared`, `sample-app`, and `postgres`; it must not publish `80`, `443`, `3002`, or `5432` on the VM.
- Use the protected, untracked runtime file `<sample-app-checkout>/.env.staging` with mode `0600`. It contains `CLOUDFLARE_TUNNEL_TOKEN`, `POSTGRES_PASSWORD`, `DATABASE_URL`, `DIRECT_URL`, `AUTH_SECRET`, `SESSION_SECRET`, and integration secrets where enabled. Never commit or expose its values through Terraform, Ansible inventory, CI logs, or Docker image build arguments.
- Configure the named Cloudflare Tunnel `sample-staging` with public hostname `sample-staging.novaryn.tech` and HTTP origin `http://sample-app:3002`. Keep the connector token only in `.env.staging`; do not use a credentials JSON file or local `cert.pem` for this token-managed deployment.
- Keep `ATELIER_HOST=sample-staging.novaryn.tech` and `APP_PUBLIC_URL=https://sample-staging.novaryn.tech` in `.env.staging` so OAuth callbacks, email links, and server redirects use the public Cloudflare origin.
- Back up the named `sample-staging-postgres-data` Docker volume as VM-local application data. Treat it separately from Cloudflare R2 and document its restore verification before relying on the staging database.
- Define the protected runtime secret file and non-secret release-state file. Specify which local account may read each file and whether the deploy account invokes a constrained command rather than reading secrets directly.
- Implement the GitHub Actions deployment design: environment protections, OIDC/Tailscale identity, dedicated deploy account, pinned SSH host key, GHCR credential scope, serialized deployment lock, immutable image tags, smoke test, and rollback command.
- Run database migrations manually after deployment with `docker compose --env-file .env.staging -f docker-compose.staging.yml run --rm sample-app sh -lc 'DATABASE_URL="$DIRECT_URL" npx prisma migrate deploy'`; do not run migrations automatically at app startup.
- Enable Cloudflare Access later, before staging holds sensitive data or serves broader external QA. It should be configured as a perimeter gate for `sample-staging.novaryn.tech` and does not replace SampleApp's application login.

### Monitoring, backup, and incident recovery

- Decide whether this VM is managed by the existing Zabbix environment; if so, document the agent mode, server address, encryption/PSK model, permitted network path, host metadata, alerts, and ownership.
- Define host and application checks: Tailscale, Docker, `cloudflared`, `sample-app`, `postgres`, `/api/health`, disk/RAM/CPU pressure, failed deployments, package update failures, backup failures, and OPNsense deny-log review.
- Implement PVE backup job details: schedule, retention, backup datastore, encryption, off-host copy, responsible operator, and restoration prerequisites.
- Document backup and restore coverage for VM-local configuration, application runtime secrets, Cloudflare Tunnel recovery material, the `sample-staging-postgres-data` volume, and R2 object versioning/lifecycle.
- Run and record a restore test before claiming disaster recovery. Define expected RPO/RTO, restoration order, validation commands, and the criteria for declaring the recovered VM usable.
- Create incident runbooks for a failed release, failed Prisma migration, compromised developer account/device, leaked Tailscale enrollment credential, leaked Cloudflare Tunnel credential, accidental firewall/VLAN change, and lost PVE host/storage.

### Documentation deliverables

- Create a reference page for stable staging network, access, service, and Ansible variables. Keep this provisioning guide focused on sequencing and verification.
- Create how-to guides for tightening VLAN 60 egress, onboarding/offboarding developers, running Ansible against staging, deploying/rolling back staging, and restoring staging from backup.
- Update the validation checklist with evidence-producing commands and expected outcomes as each backlog item is implemented.
- Record each accepted risk, owner, review date, and rollback method when a temporary control is retained beyond initial commissioning.

## Related documentation

- [SampleApp staging Ansible variables](../reference/sample-staging-ansible-variables.md) records the approved non-secret inventory state, host configuration boundary, and temporary secret-file delivery method.
- [SampleApp staging access model](../reference/sample-staging-access-model.md) records the current Tailnet, SSH, account lifecycle, and Docker-risk boundary.
- [Configure SampleApp staging with Ansible](configure-sample-staging-with-ansible.md) gives the ordered controller-side procedure for staging host configuration.
- [OPNsense HA access over Tailguard](../explanation/opnsense-ha-tailguard-design.md) explains overlay and subnet-router safety boundaries.
- [PVE management behind OPNsense](../explanation/pve-management-behind-opnsense.md) explains the protected PVE management design.
- [PVE sizing guidelines](../reference/pve-sizing-guidelines.md) provides host capacity and datastore guidance.
- [USB SSD datastore reference](../reference/usb-ssd-datastore.md) documents the external datastore and its limitations.
- `Provisioning allocation plan` tracks existing VM and network allocations.
- [Run Infrastructure Ansible operations](infrastructure-ansible-operations.md) documents guest configuration workflows.
- [`ansible/infra-ops/roles/ssh/README.md`](../../ansible/infra-ops/roles/ssh/README.md) describes the existing SSH hardening role.
