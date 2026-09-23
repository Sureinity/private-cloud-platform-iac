# PVE sizing guidelines

Reference guidance for choosing VM and container CPU, memory, disk, and network allocations on this Proxmox VE host.

## Host baseline

This baseline is a historical snapshot from a PVE inspection performed on
2026-06-14. Its generated output is not retained in this repository; rerun
``../../scripts/pve-system-inspection.sh``
before making capacity or hardware-health decisions.

| Area | Observed capacity |
|---|---:|
| Host model | Lenovo ThinkCentre M720q |
| Proxmox VE | 9.2.0 / pve-manager 9.2.2 |
| CPU | Intel Core i5-8500 |
| CPU topology | 6 cores / 6 threads, 1 socket, no Hyper-Threading |
| Virtualization | VT-x, EPT, KVM available |
| IOMMU | VT-d / DMAR active |
| Memory | 16 GB installed, about 15 GiB visible |
| Swap | 8 GB |
| VM disk storage | `local-lvm`, about 140.9 GiB thin pool |
| Additional VM disk storage | `usb-ssd`, about 439 GiB, external USB SSD added 2026-08-19 |
| ISO/import/backup storage | `local`, about 60 GiB available |
| Physical network | one Intel I219-V 1 GbE NIC, `nic0` |
| Main management bridge | `vmbr1` on `192.0.2.10/24`, gateway `192.0.2.1` behind OPNsense |
| Existing guests | none detected during inspection |
| OPNsense ISO | `local:iso/OPNsense-26.1.6-dvd-amd64.iso` |

## Capacity budget

Use this as the starting provisioning envelope.

| Resource | Practical budget |
|---|---:|
| Physical CPU threads | 6 |
| Safe always-on vCPU allocation | 6 to 9 total allocated vCPUs |
| Bursty lab vCPU allocation | up to about 12 total allocated vCPUs |
| Host memory reserve | 2 to 3 GB minimum |
| Safe always-on guest memory | 10 to 12 GB total |
| Initial VM disk allocation budget | 100 to 115 GB total on `local-lvm` |
| Additional VM disk allocation budget | up to about 400 GB on `usb-ssd` |
| Network uplink | 1 GbE shared by host and guests |

The primary constraints are memory, storage, and single-NIC network design. CPU is adequate for a small private cloud if vCPU allocation stays modest.

## CPU allocation guidelines

The i5-8500 has 6 physical cores and no Hyper-Threading. Avoid assigning many large vCPU counts by default.

Recommended defaults:

| Workload type | vCPU starting point |
|---|---:|
| OPNsense lab firewall | 2 |
| OPNsense with heavier VPN/IDS features | 4, only if needed |
| Small Linux VM | 1 to 2 |
| Lightweight LXC service | 1 |
| Build or test VM | 2 to 4 temporarily |

Guidelines:

- Prefer smaller vCPU counts and increase only after observing pressure.
- Do not give every VM 4 cores “just in case.”
- Keep always-on vCPU allocations around 6 to 9 total.
- Bursty lab workloads can exceed physical core count, but monitor host load and guest latency.
- Use CPU type `host` for performance-sensitive trusted VMs unless migration compatibility becomes a requirement.

## Memory allocation guidelines

Memory is the main always-on capacity limit.

Recommended defaults:

| Workload type | RAM starting point |
|---|---:|
| OPNsense minimal/lab | 2 GB |
| OPNsense with plugins, VPN, IDS/IPS, or more states | 4 GB |
| Small Linux VM | 1 to 2 GB |
| Lightweight LXC service | 512 MB to 1 GB |
| Temporary test VM | 1 to 4 GB depending on workload |

Guidelines:

- Reserve at least 2 to 3 GB for Proxmox and host services.
- Keep always-on guest memory allocations around 10 to 12 GB total.
- Do not rely on host swap for normal VM operation.
- Use ballooning only as a convenience, not as a substitute for real capacity planning.
- Prefer LXC for small Linux services when isolation requirements allow it.

## Disk allocation guidelines

The host has a single 256 GB internal SATA SSD and no storage redundancy. `local-lvm` remains the correct default for VM and CT disks. The external `usb-ssd` datastore adds capacity but not redundancy, and it can become inactive if the USB link drops.

Recommended defaults:

| Workload type | Disk starting point |
|---|---:|
| OPNsense | 20 to 32 GB |
| Small Debian/Ubuntu VM | 16 to 32 GB |
| Lightweight LXC service | 8 to 16 GB |
| Template VM | 8 to 16 GB |
| Temporary test VM | 16 to 40 GB |

Guidelines:

- Use `local-lvm` for guest disks by default.
- Use `usb-ssd` when a guest needs capacity beyond the internal budget. It is an
  external USB SSD directory datastore added on 2026-08-19, approved for real
  workloads, with roughly 439 GiB available. Keep OPNsense and any guest required
  for host administration on `local-lvm`. See
  [`usb-ssd-datastore.md`](usb-ssd-datastore.md) and
  [`../explanation/usb-backed-vm-storage-tradeoffs.md`](../explanation/usb-backed-vm-storage-tradeoffs.md).
- Use `local` for ISOs, templates, temporary imports, and only short-lived local backups.
- Keep at least 30 GB free for growth, snapshots, and operational margin.
- Avoid aggressive thin-provisioning overcommit; start with 100 to 115 GB total provisioned guest disks.
- Do not treat same-disk local backups as real backups.

## Storage health follow-up

The inspection script detected `/dev/sda`, but the SMART details failed because of command parsing. Before storing important guests, run this directly on the PVE host:

```bash
smartctl -a -d sat /dev/sda
```

Review at minimum:

- `Reallocated_Sector_Ct`
- `Current_Pending_Sector`
- `Offline_Uncorrectable`
- power-on hours
- SSD wear indicators, if exposed by the drive

## Network allocation guidelines

Current network shape:

```text
nic0 -> vmbr0 -> DHCP host-side stanza, no Terraform static IP/gateway
vmbr1 -> 192.0.2.10/24
         gateway 192.0.2.1 through OPNsense
vmbrsync -> no PVE host IP/gateway; OPNsense sync bridge
```

Guidelines:

- Treat `vmbr0` as the physical uplink/WAN bridge for OPNsense with a DHCP host-side stanza. Terraform should not assign static IP/CIDR or gateway values to `vmbr0`.
- Do not make disruptive bridge or gateway changes without a recovery path such as Tailscale, console, or physical access.
- For lab-only firewalling, use `vmbr1` as the isolated bridge without a physical port. The real local PVE tfvars currently use `192.0.2.10/24` on the PVE host side and `192.0.2.1` as the OPNsense LAN peer/gateway.
- For real router/firewall use, prefer a second physical NIC or a carefully designed VLAN trunk.
- PVE management is intended to live behind OPNsense on `vmbr1`; verify WireGuard and Tailscale recovery before changing bridge addressing.

## VM versus LXC decision

Use a VM when the workload needs:

- non-Linux guest support, such as OPNsense or FreeBSD
- its own kernel
- stronger isolation
- custom boot media
- cloud-init VM lifecycle
- Docker or Kubernetes with fewer LXC caveats

Use LXC when the workload is:

- a lightweight Linux service
- trusted enough to share the host kernel
- memory-sensitive
- simple to back up and recreate

## Object ID and IP conventions

Recommended VMID ranges:

| Range | Purpose |
|---:|---|
| `100-109` | network and security appliances |
| `110-149` | core infrastructure services |
| `150-199` | test and lab VMs |
| `200-299` | application VMs |
| `900+` | templates and golden images |

Avoid these observed or reserved IPs:

| IP | Reason |
|---|---|
| `203.0.113.1` | gateway |
| `203.0.113.233` | former PVE host address before management moved behind OPNsense |
| `203.0.113.248` | observed neighbor |
| `203.0.113.249` | observed neighbor |

Suggested static allocation bands:

| Range | Purpose |
|---|---|
| `203.0.113.100-149` | infrastructure |
| `203.0.113.150-199` | lab VMs |
| `203.0.113.200-229` | static services |
| `203.0.113.230-238` | user-allocated host and infrastructure range |
| `203.0.113.239` | reserve for future expansion or avoid unless explicitly assigned |

## Security posture considerations

The inspection showed permissive management defaults:

- SSH root login enabled.
- SSH password authentication enabled.
- PVE firewall disabled.
- PVE UI listens on all addresses.
- Tailscale is active and controls `/etc/resolv.conf`.

Before provisioning internet-facing or semi-trusted workloads:

- move SSH toward key-only access
- restrict root SSH access
- enable and define PVE firewall policy
- limit management ports to trusted LAN or Tailscale sources
- keep Terraform and Ansible secrets out of Git

## Validation commands

Useful host-side checks while sizing and operating guests:

```bash
pvesm status
qm list
pct list
free -h
lscpu
ip -br addr
ip route
systemctl --failed --no-pager
journalctl -p warning..alert -b --no-pager | tail -100
```

## Current Terraform allocation

The active Terraform VM allocation now follows the OPNsense lab-router profile:

| Setting | Value |
|---|---:|
| VMID | `100` |
| Name | `opnsense` |
| vCPU | `2` |
| RAM | `2048 MB` |
| Disk | `24 GB` |
| Storage | `local-lvm` |
| CD-ROM | detached (`none`) |
| Boot order | `scsi0` |
| Bridges | `vmbr0`, `vmbr1`, `vmbrsync` |
| `vmbr1` host address | `192.0.2.10/24` in real local tfvars |
| `vmbr1` gateway | `192.0.2.1` |
| Primary physical/WAN attachment | `vmbr0` with DHCP host-side stanza and no Terraform static IP/gateway |
| Started by Terraform | `true` |
| On boot | `false` |

This allocation is intentionally conservative for the inspected 6-core, 16 GB RAM host.

## Retired helper VM profile

`terraform/live/onprem-pve/variables.tf` retains inputs for a Debian helper VM (VMID
`110`), but `terraform/live/onprem-pve/main.tf` no longer contains a `module "helper_vm"`
call. It is not part of the active Terraform allocation and its retained
inputs must not be treated as a provisioned VM profile. Reintroduce the module
and a deliberate Debian image import only after reviewing a plan.
