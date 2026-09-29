# OPNsense Remote Management and Automation Architecture

This document explains the architecture, security model, and rationale for managing the OPNsense appliance (`26.1.11_10-amd64`) via decoupled Terraform state and dedicated Ansible operations.

---

## The Core Problem

In virtualized firewall infrastructure (such as an OPNsense VM running on Proxmox VE), managing network policy and hypervisor provisioning within the same Terraform root creates severe coupling risks:

```text
Problem: Coupled Monolithic State
--------------------------------------------------------------------------------
1. Hypervisor State (Proxmox VE): VM IDs, CPU cores, disks, bridge interfaces (vmbr0, vmbr1)
2. Network State (OPNsense): Filter rules, aliases, DHCP reservations, DNS overrides

Circular Deadlock:
- Modifying a firewall rule requires the OPNsense API to be reachable.
- If OPNsense is restarting or being reconfigured, PVE hypervisor operations fail.
- If a PVE bridge or VM disk operation stalls, firewall updates are blocked.
--------------------------------------------------------------------------------
```

---

## Architectural Decision: Independent Tool Responsibility & Decoupled State

To eliminate circular dependencies and minimize blast radius:

```text
                               +------------------------------------------+
                               |        OPERATOR / CI AUTOMATION          |
                               +--------------------+---------------------+
                                                    |
                         +--------------------------+--------------------------+
                         |                                                     |
                         v                                                     v
          +-----------------------------+                       +-----------------------------+
          |      Terraform Engine       |                       |       Ansible Engine        |
          |  (terraform/live/opnsense)  |                       |    (ansible/opnsense-ops)   |
          +--------------+--------------+                       +--------------+--------------+
                         |                                                     |
                         | Declarative State                                   | Imperative Tasks
                         | (Aliases, Rules, DNS, NAT)                          | (Backups, Firmware, Day-2)
                         |                                                     |
                         +--------------------------+--------------------------+
                                                    |
                                                    v
                               +------------------------------------------+
                               |     NETWORK BOUNDARY (Tailscale / pf)    |
                               |  - Tailscale Overlay: 100.x.y.z:443, 22  |
                               |  - Management LAN: 192.0.2.1:443, 22     |
                               |  - WAN: Default Deny (Blocked)           |
                               +--------------------+---------------------+
                                                    |
                                                    v
                               +------------------------------------------+
                               |    OPNsense APPLIANCE (26.1.11_10-amd64) |
                               |  - svc-terraform-opnsense (API Key)      |
                               |  - svc-ansible-opnsense   (API Key)      |
                               +------------------------------------------+
```

### 1. Responsibility Boundary

* **Terraform (`terraform/live/opnsense/`)**:
  * **Role:** Declarative desired-state definition.
  * **Scope:** Foundational network resources that must be versioned, reviewed via plan diffs, and tracked in state:
    * Firewall aliases (host lists, CIDR blocks, port sets).
    * Firewall filter rules and inter-VLAN segmentation policies.
    * NAT policies (Source NAT / masquerading and Destination NAT / port forwarding).
    * Static Unbound DNS host overrides and Kea DHCPv4 static leases.
* **Ansible (`ansible/opnsense-ops/`)**:
  * **Role:** Procedural Day-2 operations and appliance lifecycle management.
  * **Scope:** Tasks that are imperative or dynamic rather than declarative state:
    * Configuration backup exports (`config.xml`) before change windows.
    * Firmware update availability checks and staged upgrades.
    * Operational state flushes (`pfctl -F state`) and lockout table flushes.
    * Appliance graceful reboot coordination.

### 2. State Decoupling Boundary

The OPNsense live root (`terraform/live/opnsense/`) maintains its own remote state key in SeaweedFS S3:

* **Bucket:** `platform-tfstate`
* **Key:** `live/opnsense/terraform.tfstate`

This state is completely decoupled from `live/onprem-pve/terraform.tfstate`. The two roots share no provider instances, no state locks, and no resource definitions. Hypervisor changes never block network automation, and firewall updates never touch hypervisor resources.

---

## Defense-in-Depth Identity & Access Management (IAM)

The integration implements strict enterprise IAM principles:

1. **Separation of Machine and Human Identities:**
   Automated pipelines interact with OPNsense exclusively via dedicated machine service accounts (`svc-terraform-opnsense` and `svc-ansible-opnsense`), preventing any dependency on interactive human accounts.
2. **Principle of Least Privilege (PoLP):**
   Service accounts do not belong to the administrative `wheel` or `admins` groups. They are assigned to purpose-built privilege groups (`grp-terraform-engine` and `grp-ansible-ops`) granting only the specific MVC API endpoints required for their workload.
3. **No Shell or Web GUI Interactive Access:**
   Service accounts have disabled/scrambled passwords and shells set to `/sbin/nologin`. They cannot log into the Web GUI dashboard or establish interactive SSH sessions.
4. **Network Perimeter Access Control:**
   API keys are useless on external networks. The OPNsense packet filter (`pf`) enforces default deny on the WAN interface. Remote API requests and SSH connections are only accepted from authorized Tailscale overlay IPs (`TSC` / `opt2`) and the local PVE management bridge (`vmbr1` / `192.0.2.0/24`).

---

## Version Compatibility & Supply-Chain Integrity

The integrations are pinned to exact upstream versions verified against the target environment:

| Tool | Component | Version | Verification Rationale |
|---|---|---|---|
| **Target Appliance** | OPNsense Core | `26.1.11_10-amd64` | Running appliance firmware on FreeBSD 14.3. |
| **Terraform Provider** | `browningluke/opnsense` | `= 0.26.0` | Active community provider communicating natively with OPNsense REST/MVC API. |
| **Ansible Collection** | `oxlorg.opnsense` | `26.1.11` | Tagged by maintainer specifically matching OPNsense `26.1.11` firmware. |
| **Python Tooling** | `httpx` | `0.28.1` | Pinned dependency for Ansible collection REST API transport. |

Multi-platform provider lockfiles (`.terraform.lock.hcl`) are maintained across `linux_amd64`, `linux_arm64`, and `darwin_arm64` to guarantee identical binary execution across local developer workstations and CI runners.

---

## Architectural Decision: Independent Ansible Projects (`infra-ops` vs. `opnsense-ops`)

During architecture review, we evaluated whether OPNsense operational playbooks should be merged into the primary `ansible/infra-ops/` project. The decision was made to keep **`ansible/opnsense-ops/` completely independent**.

### Key Drivers for Isolation

1. **Eliminating the `hosts: all` Collision:**
   In `infra-ops/`, standard playbooks such as `playbooks/users.yml` and `site.yml` target `hosts: "{{ target | default('all') }}"` with `become: true` and `gather_facts: true`. Placing OPNsense in `infra-ops/inventory/hosts.yml` would mean running generic VM playbooks without explicit host filtering would attempt to execute Linux `useradd` and Debian Python fact gathering against FreeBSD, risking configuration corruption.
2. **Divergent Connection Models:**
   - `infra-ops`: Manages Linux OS nodes via **remote SSH execution** with `become = True` (sudo) enabled globally in `ansible.cfg`.
   - `opnsense-ops`: Orchestrates a network appliance via **local REST API requests** (`ansible_connection: local`, `become: false`).
3. **Blast Radius & Perimeter Security:**
   The firewall gateway secures all guest virtual machines. Keeping the inventory and vault credentials isolated ensures day-to-day guest OS updates cannot inadvertently touch network perimeter state.

---

## Declarative State Boundary: Human-Made vs. System-Generated Resources

When reflecting appliance configuration into Terraform, a strict boundary must be maintained between user-defined policies and internal appliance state.

```text
+-------------------------------------------------------------------------------+
|                       OPNSENSE APPLIANCE INTERNAL LAYERS                      |
+-------------------------------------------------------------------------------+
| [USER POLICY LAYER] - MANAGED BY TERRAFORM / IMPORTED                         |
|   - Custom Aliases (e.g. mgmt_subnets, pve_host, web_ports)                   |
|   - Custom Filter Rules (Inter-VLAN, Tailscale management, port forwards)     |
|   - Custom Unbound Host Overrides (e.g. pve.home.arpa, seaweedfs.home.arpa)   |
|   * Identified by standard 36-char RFC 4122 UUIDs (xxxxxxxx-xxxx-...)         |
+-------------------------------------------------------------------------------+
| [SYSTEM / KERNEL LAYER] - NEVER IMPORTED INTO TERRAFORM                       |
|   - Anti-Lockout Rule (Auto-generated on LAN to prevent admin lockout)        |
|   - Interface Subnet Macros (e.g. __lan_network, __wan_network, __opt2_...)   |
|   - Kernel Security Tables (e.g. bogons, bogonsv6, sshlockout, virusprot)     |
|   - DHCP & Loopback (lo0) daemon rules                                        |
|   * Identified by literal string names ("uuid": "bogons", "__lan_network")   |
+-------------------------------------------------------------------------------+
```

### Why System Resources Must Never Be Managed via IaC

1. **Host Lockout Risk:** If an auto-generated anti-lockout rule is managed in Terraform and subsequently modified or destroyed, operator access to the Web GUI and SSH will be immediately dropped.
2. **Perpetual State Drift:** OPNsense dynamically reorders, recalculates, and updates system rules and bogon tables during reboots, interface flaps, and cron executions, creating false drift in `terraform plan`.
3. **API Immutability:** The OPNsense REST API rejects modification requests against system-owned objects with validation errors.

---

## HTTP Transport & Authentication Nuances

OPNsense's Web GUI webserver (lighttpd/php-fpm) uses a session-based redirection pattern for unauthenticated web requests. When an HTTP client connects without authorization headers, OPNsense does **not** return a standard `HTTP 401 Unauthorized` challenge; instead, it redirects (`HTTP 302`/`200`) to the HTML login page (`/ui/session/index`).

Because standard Ansible HTTP modules (`ansible.builtin.get_url` and `ansible.builtin.uri`) only send HTTP Basic Auth credentials *after* receiving a `401` challenge by default:
- Unauthenticated requests download the HTML login page rather than the expected API payload.
- **Solution:** Both playbooks explicitly configure `force_basic_auth: true` to send the `Authorization: Basic ...` header proactively in the initial request.
- **Credential Loading:** Playbooks automatically search for and load uncommitted `secrets/vault.yml` if present, with exported XML configuration snapshots protected in `.gitignore` under `backups/`.
