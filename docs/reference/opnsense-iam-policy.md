# OPNsense IAM Policy and Privilege Reference

This reference documents the identity model, privilege groups, machine accounts, and security controls established for automated OPNsense management (`26.1.11_10-amd64`).

---

## Identity Accounts

Two dedicated machine accounts are defined for automation. Neither account is granted interactive login or shell access.

| Service Account | Role / Tool | Privilege Group | Login Shell | Password | Auth Method |
|---|---|---|---|---|---|
| `svc-terraform-opnsense` | Declarative State Engine (Terraform) | `grp-terraform-engine` | `/sbin/nologin` | Disabled / Scrambled | OPNsense API Key & Secret |
| `svc-ansible-opnsense` | Operational Maintenance (Ansible) | `grp-ansible-ops` | `/sbin/nologin` | Disabled / Scrambled | OPNsense API Key & Secret |

---

## Privilege Groups and Verified ACL Catalog

Privileges in OPNsense are managed at the Group level (**System > Access > Groups**). The entries below match the literal string labels used in OPNsense 26.1:

### 1. `grp-terraform-engine`

Grants read and write access to declarative networking, firewall, and DNS objects:

| Subsystem | Exact Privilege Label in OPNsense 26.1 | Type | Purpose |
|---|---|---|---|
| **Rules** | `Firewall: Rules [new]` | MVC API | Grants access to `/api/firewall/filter/*` for modern rule management. |
| **Rules** | `Firewall: Rules` | Legacy UI | Read access for rule list queries. |
| **Rules** | `Firewall: Rules: Edit` | Legacy UI | Edit access for rule changes. |
| **Aliases** | `Firewall: Aliases` | MVC / UI | Read access to list/search firewall aliases (`/api/firewall/alias/*`). |
| **Aliases** | `Firewall: Alias: Edit` | MVC / UI | Write access to create/modify aliases. |
| **Categories** | `Firewall: Categories` | MVC | Organization tags for firewall policies. |
| **NAT (Egress)** | `Firewall: NAT: Source NAT` | MVC / UI | Outbound NAT rules and WAN masquerading. |
| **NAT (Ingress)** | `Firewall: NAT: Destination NAT` | MVC / UI | Inbound port forwarding (DNAT). |
| **NAT (1:1)** | `Firewall: NAT: 1:1` | MVC / UI | 1-to-1 IP translation (optional). |
| **Interfaces** | `Interfaces: Assign network ports` | MVC / UI | Interface assignments and physical bindings. |
| **Interfaces** | `Interfaces: VLAN` | MVC / UI | 802.1Q VLAN sub-interface management. |
| **Interfaces** | `Interfaces: VXLAN` | MVC / UI | VXLAN overlay tunnel endpoints. |
| **Interfaces** | `Interfaces: Virtual IPs: Settings` | MVC / UI | CARP VIPs and IP alias definitions. |
| **Interfaces** | `Interfaces: Settings` | MVC / UI | General interface parameters. |
| **DNS** | `Services: Unbound` | MVC API | Unbound DNS service and configuration endpoints (`/api/unbound/*`). |
| **DHCP** | `Services: DHCP: Kea(v4)` | MVC API | Kea DHCPv4 server settings and static lease reservations. |
| **VPN** | `VPN: WireGuard: Configuration` | MVC API | WireGuard server and client peer definitions. |

> [!NOTE]
> For pairs with `: Edit` (e.g. `Firewall: Aliases` and `Firewall: Alias: Edit`), both privileges are required so Terraform can query existing state during `plan` and commit state during `apply`.

### 2. `grp-ansible-ops`

Grants operational inspection, configuration export, and maintenance privileges:

| Subsystem | Exact Privilege Label in OPNsense 26.1 | Type | Purpose |
|---|---|---|---|
| **Backups** | `System: Configuration: Backups` | API / UI | Export and download of active configuration XML (`/api/core/backup/download/this`). |
| **Firmware** | `System: Firmware` | API / UI | Query firmware update availability (`/api/core/firmware/status`). |
| **History** | `Diagnostics: Configuration History` | API / UI | View configuration change history and diffs. |
| **Services** | `Status: Services` | API / UI | Inspect service runtime status (`/api/core/service/*`). |
| **Tables** | `Diagnostics: PF Table IP addresses` | API / UI | Inspect dynamic alias table contents. |
| **States** | `Diagnostics: Show States` | API / UI | Query and flush packet filter states (`/api/diagnostics/firewall/*`). |
| **Reboot** | `Diagnostics: Reboot System` | API / UI | Coordinated reboot orchestration during maintenance windows. |
| **Aliases** | `Firewall: Aliases` | MVC / UI | Query aliases for operational updates. |
| **Aliases** | `Firewall: Alias: Edit` | MVC / UI | Operational alias synchronization. |

---

## Network Perimeter Boundary

Access to the management services (Web GUI HTTPS on port 443 and OpenSSH on port 22) is enforced by the packet filter (`pf`):

```text
Inbound Management Traffic:
- WAN: Default Deny (All unsolicited traffic dropped)
- Tailscale (TSC / opt2): Pass TCP/443, TCP/22 to (self) from authorized Tailnet admin IPs
- LAN (vmbr1): Pass TCP/443, TCP/22 to (self) from 192.0.2.0/24
```

OpenSSH socket listeners are bound to wildcard (`All (recommended)`) to avoid boot-time startup race conditions with the `tailscaled` daemon ([reference guide](../how-to/configure-opnsense-ssh-service-availability.md)).

---

## Secret Storage and Rotation

* **Terraform Secrets:**
  * Stored in the uncommitted, Git-ignored file `terraform/live/opnsense/terraform.tfvars`:
    ```hcl
    opnsense_url        = "https://192.0.2.1" # or Tailscale URL
    opnsense_api_key    = "<API_KEY>"
    opnsense_api_secret = "<API_SECRET>"
    opnsense_allow_insecure = true
    ```
* **Ansible Secrets:**
  * Stored in the uncommitted, Git-ignored file `ansible/opnsense-ops/secrets/vault.yml` or managed via `ansible-vault`:
    ```yaml
    ---
    vault_opnsense_api_key: "<API_KEY>"
    vault_opnsense_api_secret: "<API_SECRET>"
    ```
* **Credential Rotation Procedure:**
  1. Generate new API key/secret pair in OPNsense Web GUI (**System > Access > Users > Edit User > API Keys (+)**).
  2. Update local `.tfvars` and `vault.yml`.
  3. Validate connectivity via `terraform plan` and `ansible-playbook check-firmware.yml`.
  4. Revoke old API key in OPNsense Web GUI.

---

## API Client Authentication Transport Nuances

* **Proactive Basic Auth:** The OPNsense Web GUI webserver redirects unauthenticated requests to the HTML login page (`/ui/session/index`) rather than returning an `HTTP 401 Unauthorized` challenge. API clients and automation scripts must proactively supply the `Authorization: Basic <base64(key:secret)>` header on the initial request (e.g., `force_basic_auth: true` in Ansible `get_url` and `uri`).
* **Audit Trail:** All API requests are logged under `/var/log/system.log` and the Web GUI Audit Log tagged with the service account name (`svc-terraform-opnsense` or `svc-ansible-opnsense`), providing an immutable trail of machine actions.
