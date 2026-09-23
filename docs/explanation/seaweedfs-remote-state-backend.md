# SeaweedFS Remote State Backend Architecture

This document details the architectural decisions, operational mental model, and configuration design for persisting Proxmox VE live infrastructure state to a self-hosted SeaweedFS S3 remote backend.

## Mental model

Terraform manages state as a single source of truth for real-world infrastructure mappings. In a self-hosted Proxmox environment, using a public cloud object store (AWS S3, GCS) introduces external dependencies, WAN failure domains, and secret propagation risks. SeaweedFS provides a private, fast, S3-compatible blob and object storage system running directly on the local infrastructure.

```text
┌─────────────────────────────────────────────────────────────┐
│                   Terraform Live Client                     │
│               (terraform/live/onprem-pve/)                    │
└──────────────────────────────┬──────────────────────────────┘
                               │
            1. Reads backend.tf + backend.tfvars
            2. Sends S3 API calls (HTTP :8333)
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│          SeaweedFS S3 Gateway (192.0.2.51:8333)             │
├─────────────────────────────────────────────────────────────┤
│  • Authenticates IAM keypairs from /etc/seaweedfs/s3.json    │
│  • Bypasses AWS IMDS / STS checks via skip_* directives     │
│  • Enforces path-style bucket routing                       │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│          SeaweedFS Filer (192.0.2.51:8888)                  │
├─────────────────────────────────────────────────────────────┤
│  • Maps bucket to directory hierarchy:                      │
│    /buckets/platform-tfstate/live/onprem-pve/terraform.tfstate│
│  • Manages directory metadata in LevelDB                    │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│          SeaweedFS Volume Server (192.0.2.51:8080)          │
├─────────────────────────────────────────────────────────────┤
│  • Stores compressed binary needles in /srv/seaweedfs/volume│
│  • Persisted on dedicated secondary virtual disk (/dev/sdb) │
└─────────────────────────────────────────────────────────────┘
```

> **The Key Insight:**
> Terraform backend configuration occurs in an early bootstrap phase **before** input variables (`*.tfvars` or `variables.tf`) are evaluated. As a result, backend parameters cannot reference `var.*` interpolations. Static configuration must live in `backend.tf`, while secret credentials are fed out-of-band via `-backend-config=backend.tfvars` or standard environment variables.

---

## Architecture decisions

### 1. Dedicated `backend.tf` vs `versions.tf`

In standard Terraform root configurations, provider version constraints and backend settings can technically coexist within `versions.tf`. However, decoupling them into:
- `versions.tf`: Pinned Terraform CLI version (`= 1.10.5`) and Proxmox provider requirements (`bpg/proxmox`).
- `backend.tf`: S3 remote state target definitions (`bucket`, `key`, `endpoint`, compatibility flags).

This decoupling ensures that:
- Core provider lockfiles and version requirements remain unchanged when switching between state storage mechanisms.
- Clean isolation exists between provider declarations and state backend storage endpoints.
- Tooling or operators inspecting backend architecture can review a single, isolated file.

### 2. SeaweedFS S3 compatibility flags

SeaweedFS implements the Amazon S3 REST API specification for object operations, but does not implement AWS-proprietary metadata, account, or region validation services. Terraform's AWS S3 backend client requires specific flags to operate reliably without errors:

| Flag | Value | Purpose |
|---|---|---|
| `use_path_style` | `true` | Forces path-style addressing (`http://host:port/bucket/key`) instead of virtual-host addressing (`http://bucket.host:port/key`), which avoids requiring wildcard DNS records. |
| `skip_credentials_validation` | `true` | Disables AWS STS calls (`GetCallerIdentity`) to validate AWS credentials. |
| `skip_metadata_api_check` | `true` | Prevents the client from querying the AWS EC2 Instance Metadata Service (IMDS at `169.254.169.254`). |
| `skip_region_validation` | `true` | Disables AWS endpoint region verification (`us-east-1` is specified as a standard placeholder). |
| `skip_requesting_account_id` | `true` | Skips AWS account ID validation routines unsupported by third-party S3 gateways. |

### 3. State backend bootstrapping sequence

Because the SeaweedFS service runs within a virtual machine on the same Proxmox hypervisor, state management follows a strict two-stage bootstrap sequence:

```text
Stage 1: Bootstrap Root (terraform/bootstrap/seaweedfs/)
├── Uses local state exclusively (never S3)
└── Provisions SeaweedFS VM (VMID 151) and 100 GB storage volume on usb-ssd

Stage 2: Ansible Configuration (ansible/infra-ops/)
├── Installs SeaweedFS 4.47 binary and sandboxed systemd service
├── Mounts /dev/sdb on /srv/seaweedfs
└── Deploys S3 admin credentials to /etc/seaweedfs/s3.json

Stage 3: Bucket Creation
└── Operator or pipeline executes 'aws s3 mb s3://platform-tfstate'

Stage 4: Live Environment Migration (terraform/live/onprem-pve/)
└── Operator runs 'terraform init -backend-config=backend.tfvars -migrate-state'
```

### 4. Storage blast radius mitigation & planned Volume revamp

> [!WARNING]
> **Interim Topology Subject to Storage Revamp:**
> The current setup attaches a 100 GB virtual disk on `usb-ssd` directly to the SeaweedFS VM. Because the Proxmox provider models disks inline within the VM resource, a `terraform destroy` in the bootstrap root purges the VM and deletes the data disk. To protect the remote state stored on this disk, hypervisor-native protection (`protection = true`) is enforced on VM 151.
>
> A subsequent data storage revamp will initialize a dedicated node for the SeaweedFS Volume server, physically decoupling needle/blob storage from hypervisor VM lifecycles and eliminating the single-host destroy risk entirely.

---

## Secret lifecycle & credential ingestion

Backend credentials must never be committed to Git. The repository establishes a single source of truth:

1. **Authoritative secret store:** `ansible/infra-ops/secrets/seaweedfs/admin.yml` (mode `0600`, ignored by Git). Contains `seaweedfs_s3_admin_access_key` and `seaweedfs_s3_admin_secret_key`.
2. **Local backend configuration:** `terraform/live/onprem-pve/backend.tfvars` (mode `0600`, ignored by Git). Populated from the Ansible secret store.
3. **Committed template:** `terraform/live/onprem-pve/backend.tfvars.example` provides the schema and instructions for operators.
4. **Alternative pipeline ingestion:** Workstations and CI/CD pipelines can supply `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` directly in the execution environment.
