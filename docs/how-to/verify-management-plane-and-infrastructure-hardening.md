# How to verify management-plane and infrastructure hardening

This guide details non-disruptive verification procedures, least-privilege role definitions, credential rotation triggers, and transport security controls for the Proxmox VE and SeaweedFS management planes.

---

## 1. Management-Plane Exposure Verification

The Proxmox VE management web interface and API (port 8006), SSH daemon (port 22), and cluster services must never be exposed directly to external networks or unauthenticated bridge interfaces.

### Network Perimeter Architecture

```text
+-------------------+
| External Network  |
| (WAN / Internet)  |
+---------+---------+
          |
          | Physical Interface: nic0 (Bridge: vmbr0 - No PVE Host IP)
          v
+---------+-----------------------------------------------------------+
| OPNsense Virtual Firewall & Router (VMID 100)                       |
|                                                                     |
|  - WAN Rule: Block all inbound traffic to port 8006 / 22            |
|  - WireGuard Overlay: Admin access only via mutual key auth         |
+---------+-----------------------------------------------------------+
          |
          | Internal Interface: vtnet1 (Bridge: vmbr1 - PVE IP 192.0.2.10)
          v
+---------+-----------------------------------------------------------+
| Proxmox VE Host Management Plane & Infrastructure Services         |
|                                                                     |
|  - PVE Web GUI / REST API: 192.0.2.10:8006 (Internal vmbr1 only)     |
|  - SeaweedFS S3 Storage:   192.0.2.51:8333 (Internal vmbr1 only)     |
|  - Zabbix Server:          192.0.2.30:10051 (Internal vmbr1 only)    |
+---------------------------------------------------------------------+
```

### Non-Disruptive Exposure Checks

Run these read-only checks from an external vantage point (e.g. WAN router or separate workstation) to verify port isolation:

1. **Verify WAN Bridge Socket Ingress**:
   ```bash
   # From WAN network, probe physical interface IP:
   nmap -Pn -p 8006,22,8333,10051 <WAN_UPLINK_IP>
   ```
   **Expected Result**: All ports must report `filtered` or `closed`. No PVE or SeaweedFS service banner should be returned.

2. **Verify Host Interface Binding**:
   On the PVE host, verify that `vmbr0` does not have an assigned IPv4 address or default gateway:
   ```bash
   ip -br addr show vmbr0
   ip -br addr show vmbr1
   ```
   **Expected Result**:
   - `vmbr0`: `UP` with no IPv4 address (`null`).
   - `vmbr1`: `UP 192.0.2.10/24`.

3. **Verify Listening Sockets**:
   ```bash
   ss -tulpn | grep -E ':(8006|22|8333)\b'
   ```
   Ensure services listen on internal IP endpoints or behind firewall packet filters.

---

## 2. Least-Privilege Proxmox Terraform Identity

Using the default `root@pam` account for automated Terraform runs exposes the entire hypervisor to catastrophic destruction in case of credential compromise. A dedicated role with minimal API privileges must be used.

### Role Definition: `TerraformVMProvisioner`

Create a dedicated role granting only the privileges required to clone templates, configure guest networking, and assign disks:

```bash
# Execute on PVE host:
pveum role add TerraformVMProvisioner -privs "\
  VM.Allocate \
  VM.Clone \
  VM.Config.CDROM \
  VM.Config.CPU \
  VM.Config.Disk \
  VM.Config.HWType \
  VM.Config.Memory \
  VM.Config.Network \
  VM.Config.Options \
  VM.PowerMgmt \
  Datastore.Allocate \
  Datastore.AllocateSpace \
  Datastore.AllocateTemplate \
  Datastore.Audit \
  SDN.Use"
```

### Dedicated Service User and API Token

1. **Create the automation user**:
   ```bash
   pveum user add terraform-prov@pve --comment "Automation user for Terraform provisioning"
   ```

2. **Assign role permissions**:
   ```bash
   # Restrict to VM pool and storage paths:
   pveum acl modify /vms -user terraform-prov@pve -role TerraformVMProvisioner
   pveum acl modify /storage/local-lvm -user terraform-prov@pve -role TerraformVMProvisioner
   pveum acl modify /storage/local -user terraform-prov@pve -role TerraformVMProvisioner
   pveum acl modify /sdn/zones/localnetwork -user terraform-prov@pve -role TerraformVMProvisioner
   ```

3. **Generate a scoped API token**:
   ```bash
   pveum user token add terraform-prov@pve tf-token --privsep 1
   pveum acl modify /vms -token 'terraform-prov@pve!tf-token' -role TerraformVMProvisioner
   pveum acl modify /storage/local-lvm -token 'terraform-prov@pve!tf-token' -role TerraformVMProvisioner
   ```

4. **Verify restricted scope**:
   Query the Proxmox cluster status with the generated token:
   ```bash
   curl -s -k -H "Authorization: PVEAPIToken=terraform-prov@pve!tf-token=<TOKEN_SECRET>" \
     https://192.0.2.10:8006/api2/json/access/permissions | jq .
   ```
   Ensure `Sys.PowerMgmt`, `Sys.Modify`, and `Permissions.Modify` are not present.

---

## 3. Credential History and Rotation Triggers

### Rotation Calendar and Event Triggers

| Credential Type | Baseline Lifecycle | Immediate Rotation Trigger |
|---|---|---|
| **Proxmox API Tokens** | 90 days | Uncommitted secret detected by Gitleaks, host migration, personnel change |
| **SeaweedFS S3 Keys** | 180 days | Pipeline artifact leakage, abnormal read volume, state lock collision |
| **Ansible Vault Passwords** | 180 days | Accidental commit, decrypted payload staging, unauthorized host access |
| **Guest Cloud-Init Passwords** | Per-deployment | Post-provisioning initial access complete; replace with SSH keys |
| **Operator SSH Keypairs** | Annual | Private key device loss, unencrypted backup exposure |

### Verification of Clean Credential History

Run automated secret detection across the full Git commit history:

```bash
gitleaks detect --verbose
```

If a secret is ever identified:
1. Immediately revoke the token or credential in Proxmox / SeaweedFS.
2. Generate a new secret and update local ignored files (`terraform.tfvars`, `backend.tfvars`).
3. Re-run `gitleaks detect` to verify the working tree is clean.

---

## 4. SeaweedFS Backend TLS and Least Privilege

### Current Status and Security Exception

SeaweedFS provides S3-compatible remote state storage for Terraform (`terraform/live/onprem-pve/backend.tf`).

> [!NOTE]
> **Active Security Exception**: `CKV2_ANSIBLE_1` is currently registered in `security/exceptions/seaweedfs-bootstrap-http.yaml` with expiration date **December 31, 2026**.
> During Phase 1-2 bootstrap, master API probes and S3 endpoints operate over HTTP within the private isolated subnet (`192.0.2.51`). Unverified runtime TLS remediation is not claimed until Phase 3 deployment.

### Non-Disruptive Health Verification

Test SeaweedFS cluster reachability and bucket status over the internal network without mutating state:

```bash
# 1. Probe Master status API
curl -s http://192.0.2.51:9333/cluster/status | jq .

# 2. Verify S3 endpoint readiness (head-bucket check)
curl -s -I http://192.0.2.51:8333/platform-tfstate
```

### Planned Phase 3 Hardening: S3 TLS Termination

Before the security exception expires on 2026-12-31:
1. **Internal CA Issuance**: Generate an internal CA certificate for `seaweedfs.example.invalid`.
2. **Configure TLS in `filer.toml`**:
   ```toml
   [s3.tls]
   enabled = true
   cert = "/etc/seaweedfs/tls/seaweedfs.crt"
   key  = "/etc/seaweedfs/tls/seaweedfs.key"
   ```
3. **Least-Privilege S3 IAM Policy**:
   Restrict the Terraform state user (`tfstate-writer`) strictly to the `platform-tfstate` prefix, denying access to cluster administrative APIs:
   ```json
   {
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
         "Resource": ["arn:aws:s3:::platform-tfstate/*", "arn:aws:s3:::platform-tfstate"]
       }
     ]
   }
   ```

---

## 5. Recovery, Backup, and Rollback Procedures

### Cold State Backup

Before performing any network or bridge reconfigurations:
1. **Back up Proxmox network interfaces**:
   ```bash
   cp /etc/network/interfaces /etc/network/interfaces.backup-$(date +%F)
   ```
2. **Back up Terraform remote state**:
   ```bash
   cd terraform/live/onprem-pve
   terraform state pull > state-backup-$(date +%F).json
   ```

### Emergency Network Rollback

If management access is lost following a bridge change:
1. Access the physical host console or out-of-band IPMI interface.
2. Restore the backed-up interface file:
   ```bash
   cp /etc/network/interfaces.backup-<DATE> /etc/network/interfaces
   ifreload -a
   ```
3. Verify reachability of `192.0.2.10` from the gateway.
