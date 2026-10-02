# Deploy SeaweedFS with Infrastructure Ansible Operations

Use this guide to deploy, configure, and verify the SeaweedFS S3-compatible state backend on Proxmox VE guest VM `seaweedfs-state` using the Infrastructure Ansible operations suite.

## Scope

The playbook `ansible/infra-ops/playbooks/seaweedfs.yml` executes the local `seaweedfs` role against the `seaweedfs_hosts` inventory group.

Target host:

| Host | Inventory Name | Address | Role | Group |
|---|---|---|---|---|
| `seaweedfs-state` | `seaweedfs` | `192.0.2.51` | S3 State Store | `seaweedfs_hosts`, `ubuntu_hosts`, `zabbix_agent2_hosts` |

Supported guest operating systems: Ubuntu (Jammy 22.04+, Noble 24.04+), Debian (12+). Architecture: `x86_64` (`amd64`).

## Prerequisites

1. **Bootstrap VM provisioned:** Target VM 151 created and running via `terraform/bootstrap/seaweedfs/`.
2. **Secondary disk attached:** Dedicated 100 GB SCSI drive attached at `/dev/sdb` (or VirtIO block device).
3. **SSH access:** SSH key-based access configured with administrative `sudo` privileges for the `ubuntu` operator.
4. **Ansible control host:** Working Ansible installation with dependencies installed from `ansible/infra-ops/requirements.yml`.

## Configuration

Group variables are stored in:

```text
ansible/infra-ops/inventory/group_vars/seaweedfs_hosts.yml
```

Default inventory values:

```yaml
---
seaweedfs_data_device: "/dev/sdb"
seaweedfs_data_mount_point: "/srv/seaweedfs"
```

Sensitive credentials (S3 admin access and secret keys) are supplied via an operator-local secret payload at `secrets/seaweedfs/admin.yml` (mode `0600`), loaded automatically by the `local_secrets` role:

```yaml
---
seaweedfs_s3_admin_identity_name: "terraform-admin"
seaweedfs_s3_admin_access_key: "<ACCESS_KEY>"
seaweedfs_s3_admin_secret_key: "<SECRET_KEY>"
```

Never commit plaintext credentials. Ensure the file is strictly mode `0600`:

```bash
chmod 600 secrets/seaweedfs/admin.yml
```

## Step-by-step procedures

All commands are executed from the Ansible operations project root:

```bash
cd ansible/infra-ops
```

### 1. Verify inventory resolution

Confirm that the target host resolves under `seaweedfs_hosts`:

```bash
ansible-inventory -i inventory/hosts.yml --graph
ansible-inventory -i inventory/hosts.yml --host seaweedfs
```

### 2. Syntax and dry-run check

Validate playbook syntax and evaluate the proposed changes without modifying the target host:

```bash
# Syntax check
ansible-playbook playbooks/seaweedfs.yml --syntax-check

# Dry-run check with diff
ansible-playbook playbooks/seaweedfs.yml --check --diff
```

### 3. Initial deployment (with storage format opt-in)

On first run, the persistent secondary disk (`/dev/sdb`) is unformatted. SeaweedFS requires an explicit opt-in to format the drive (`seaweedfs_format_disk: true`). This safety guard prevents unintentional data destruction on existing filesystems:

```bash
ansible-playbook playbooks/seaweedfs.yml --diff \
  -e "seaweedfs_format_disk=true"
```

### 4. Day-2 idempotent maintenance

For routine configuration updates or service refreshes, execute without `seaweedfs_format_disk`:

```bash
ansible-playbook playbooks/seaweedfs.yml --diff
```

The preflight stage automatically queries `seaweedfs.service` systemd status. When the service is already active, preflight port collision checks are bypassed to maintain full Day-2 idempotency while retaining greenfield collision protection on new deployments.

### 5. Independent post-deployment verification

The deployment workflow automatically flushes handlers (`meta: flush_handlers`) after configuration tasks so that daemon restarts occur before port and API probes run. You can also run the 4-phase sanity verification pipeline at any time without re-running installation tasks:

```bash
ansible-playbook playbooks/seaweedfs.yml --tags verify
```

### 6. Initialize Terraform state bucket

Once the cluster is running, create the target S3 bucket (e.g. `platform-tfstate`) for Terraform's remote backend:

```bash
export AWS_ACCESS_KEY_ID="<ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<SECRET_KEY>"
export AWS_DEFAULT_REGION="us-east-1"

aws --endpoint-url http://192.0.2.51:8333 s3 mb s3://platform-tfstate
```

See [`./create-seaweedfs-s3-buckets.md`](./create-seaweedfs-s3-buckets.md) for full bucket provisioning, validation probes, and access management.
See [`./configure-seaweedfs-tls.md`](./configure-seaweedfs-tls.md) to enable native TLS encryption and HTTPS on the S3 gateway.

## Verification and diagnostics

On the target guest VM (`192.0.2.51`), confirm service health directly:

```bash
# Verify systemd service status
systemctl status seaweedfs.service

# Check listening ports (9333=Master, 8080=Volume, 8888=Filer, 8333=S3)
ss -tulpn | grep -E ':(9333|8080|8888|8333)'

# Check Master cluster leader API
curl -s http://127.0.0.1:9333/cluster/status | jq .

# Probe S3 XML gateway
curl -s -i http://127.0.0.1:8333/
```

## Rollback and recovery

1. **Mount Gate failure:** If the secondary disk `/srv/seaweedfs` fails to mount, systemd assertion `AssertPathIsMountPoint` halts the service before writing to the 20 GB OS root. Inspect mount state with `findmnt /srv/seaweedfs` and `journalctl -u seaweedfs -e`.
2. **Credential reload:** S3 credentials can be refreshed without restarting the daemon by updating `/etc/seaweedfs/s3.json` and signaling `kill -HUP $(pidof weed)`.
3. **Service restart:** If the process requires a hard restart, run `sudo systemctl restart seaweedfs`.
