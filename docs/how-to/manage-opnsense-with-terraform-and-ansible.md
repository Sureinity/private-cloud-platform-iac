# Manage OPNsense with Terraform and Ansible

This guide provides the operational procedures to manage the OPNsense firewall (`26.1.11_10-amd64`) using the decoupled Terraform live root and dedicated Ansible operational playbooks.

---

## Prerequisites

- OPNsense appliance running and reachable over the management network (`192.0.2.1` on `vmbr1` or Tailscale overlay).
- Administrative access to the OPNsense Web GUI.
- SeaweedFS S3 endpoint running (`http://192.0.2.51:8333`) with active bucket `platform-tfstate`.
- Local tooling: Terraform `>= 1.10.5`, Ansible `>= 2.14`, and Python `httpx == 0.28.1`.

---

## Procedure

### Step 1: One-Time IAM Setup in OPNsense Web GUI

1. Log into the OPNsense Web GUI.
2. Navigate to **System > Access > Groups**:
   - Create group **`grp-terraform-engine`** and assign privileges:
     - `Firewall: Rules [new]`
     - `Firewall: Rules`
     - `Firewall: Rules: Edit`
     - `Firewall: Aliases`
     - `Firewall: Alias: Edit`
     - `Firewall: Categories`
     - `Firewall: NAT: Source NAT`
     - `Firewall: NAT: Destination NAT`
     - `Interfaces: Assign network ports`
     - `Interfaces: VLAN`
     - `Interfaces: Virtual IPs: Settings`
     - `Services: Unbound`
     - `Services: DHCP: Kea(v4)`
   - Create group **`grp-ansible-ops`** and assign privileges:
     - `System: Configuration: Backups`
     - `System: Firmware`
     - `Diagnostics: Configuration History`
     - `Status: Services`
     - `Diagnostics: PF Table IP addresses`
     - `Diagnostics: Show States`
     - `Firewall: Aliases`
     - `Firewall: Alias: Edit`

3. Navigate to **System > Access > Users**:
   - Create user **`svc-terraform-opnsense`**:
     - Group: `grp-terraform-engine`
     - Login shell: `/sbin/nologin`
     - Password: Leave disabled/scrambled
   - Create user **`svc-ansible-opnsense`**:
     - Group: `grp-ansible-ops`
     - Login shell: `/sbin/nologin`
     - Password: Leave disabled/scrambled

4. Generate API Keys:
   - Edit `svc-terraform-opnsense`, scroll to **API Keys**, click **`+`**, and save the downloaded key/secret.
   - Edit `svc-ansible-opnsense`, scroll to **API Keys**, click **`+`**, and save the downloaded key/secret.

---

### Step 2: Configure Local Credentials

#### 1. Terraform Local Variables

Create the ignored file `terraform/live/opnsense/terraform.tfvars`:

```bash
cat << 'EOF' > terraform/live/opnsense/terraform.tfvars
opnsense_url            = "https://192.0.2.1"
opnsense_api_key        = "YOUR_TERRAFORM_API_KEY"
opnsense_api_secret     = "YOUR_TERRAFORM_API_SECRET"
opnsense_allow_insecure = true

firewall_aliases = {
  mgmt_subnets = {
    type        = "network"
    description = "Trusted administrative subnets and Tailscale overlay"
    content = [
      "192.0.2.0/24",
      "198.51.100.100/10"
    ]
  }
  pve_host = {
    type        = "host"
    description = "Home Proxmox VE hypervisor management IP"
    content = [
      "192.0.2.10"
    ]
  }
  mgmt_services = {
    type        = "port"
    description = "Administrative service ports (SSH and HTTPS)"
    content = [
      "22",
      "443"
    ]
  }
}

firewall_filter_rules = {
  allow_mgmt_inbound = {
    enabled          = true
    description      = "Allow SSH and Web GUI management from trusted networks"
    interfaces       = ["lan", "opt2"]
    interface_invert = false
    action           = "pass"
    direction        = "in"
    protocol         = "TCP"
    ip_protocol      = "inet"
    quick            = true
    log              = false
    source_net       = "mgmt_subnets"
    destination_net  = "any"
    destination_port = "mgmt_services"
  }
}

unbound_host_overrides = {
  pve_node = {
    hostname    = "pve"
    domain      = "home.arpa"
    server      = "192.0.2.10"
    type        = "A"
    description = "On-Premises PVE hypervisor node FQDN"
    enabled     = true
  }
  seaweedfs_node = {
    hostname    = "seaweedfs"
    domain      = "home.arpa"
    server      = "192.0.2.51"
    type        = "A"
    description = "SeaweedFS S3 storage appliance FQDN"
    enabled     = true
  }
}
EOF
```

#### 2. Ansible Secrets Payload

Create the ignored file `ansible/opnsense-ops/secrets/vault.yml`:

```bash
mkdir -p ansible/opnsense-ops/secrets
cat << 'EOF' > ansible/opnsense-ops/secrets/vault.yml
---
vault_opnsense_api_key: "YOUR_ANSIBLE_API_KEY"
vault_opnsense_api_secret: "YOUR_ANSIBLE_API_SECRET"
EOF
chmod 0600 ansible/opnsense-ops/secrets/vault.yml
```

---

### Step 3: Managing State with Terraform

Navigate to the OPNsense live root:

```bash
cd terraform/live/opnsense
```

#### 1. Plan Declarative Changes

Run a plan to preview the declarative aliases:

```bash
terraform plan
```

#### 2. Apply Declarative Changes

Apply the configuration:

```bash
terraform apply
```

#### 3. Verify Decoupled Remote State

Confirm the state file was written to the decoupled S3 key:

```bash
aws --endpoint-url=https://seaweedfs.example.invalid:8334 s3 ls s3://platform-tfstate/live/opnsense/
```

---

### Step 4: Adopting Pre-Existing Human-Made Resources (Import)

If your OPNsense appliance already has pre-existing custom aliases, rules, or DNS overrides that you want to bring into Terraform:

> [!WARNING]
> **Import ONLY human-made custom resources.** Do not attempt to import system-generated built-ins (such as `bogons`, `sshlockout`, `virusprot`, or interface macros `__*`). System items lack RFC 4122 UUIDs and managing them in IaC can trigger host lockouts or constant state drift.

#### 1. Discover Custom Resource UUIDs

Use `curl` and `jq` to query the OPNsense REST API, filtering out built-ins:

```bash
# Export API credentials in your shell:
export OPNSENSE_API_KEY="<your-api-key>"
export OPNSENSE_API_SECRET="<your-api-secret>"

# Discover custom human-made aliases:
curl -k -s -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" "https://192.0.2.1/api/firewall/alias/searchItem" \
  | jq '.rows[] | select(.uuid | test("^[0-9a-f]{8}-[0-9a-f]{4}")) | {uuid, name, type, content}'

# Discover custom filter rules:
curl -k -s -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" "https://192.0.2.1/api/firewall/filter/searchItem" \
  | jq '.rows[] | select(.uuid | test("^[0-9a-f]{8}-[0-9a-f]{4}")) | {uuid, description, action, interface}'

# Discover custom Unbound host overrides:
curl -k -s -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" "https://192.0.2.1/api/unbound/settings/searchHostOverride" \
  | jq '.rows[] | {uuid, hostname, domain, server}'
```

#### 2. Define the Matching Resource in Code

Add the resource into `terraform/live/opnsense/terraform.tfvars`:

```hcl
firewall_aliases = {
  custom_lan_services = {
    type        = "port"
    description = "Existing human-made service port list"
    content     = ["8080", "8443"]
  }
}
```

#### 3. Create an `imports.tf` Block

Declare the mapping in a temporary `terraform/live/opnsense/imports.tf`:

```hcl
import {
  to = module.aliases.opnsense_firewall_alias.alias["custom_lan_services"]
  id = "ACTUAL_OPNSENSE_UUID_HERE"
}
```

#### 4. Preview and Commit Import

```bash
terraform plan
# Verify the plan states: Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.

terraform apply
# Once apply succeeds, delete imports.tf
rm imports.tf
```

---

### Step 5: Running Operational Maintenance with Ansible

Navigate to the OPNsense Ansible project:

```bash
cd ansible/opnsense-ops
```

*Note: Playbooks automatically load `secrets/vault.yml` if present.*

#### 1. Export Configuration Backup

Before making major network changes or applying upgrades, export the active XML configuration:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/backup-config.yml
```

Backups are saved to `ansible/opnsense-ops/backups/config-opnsense-primary-<timestamp>.xml`. The `backups/` directory is automatically ignored by Git to protect system secrets.

#### 2. Check Firmware Status

Query update availability non-disruptively:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/check-firmware.yml
```

---

## Validation & Health Verification

1. **Verify API Authentication:**
   Confirm that `terraform plan` completes without HTTP 401/403 errors.
2. **Verify Backup Validity:**
   Inspect the exported backup XML to confirm it starts with `<opnsense>`:
   ```bash
   head -n 5 backups/config-opnsense-primary-*.xml
   ```
3. **Verify State Independence:**
   Confirm that running `terraform plan` in `terraform/live/onprem-pve` does not trigger, reference, or lock `live/opnsense/terraform.tfstate`.

---

## Rollback Procedure

- **Terraform Configuration:** To remove managed aliases, delete them from `firewall_aliases` in `terraform.tfvars` and run `terraform apply`.
- **Appliance Configuration Restore:** If an erroneous change causes connectivity loss, restore the previous XML backup via the Web GUI (**System > Configuration > Backups**) or Proxmox VE console (`/conf/backup/`).
