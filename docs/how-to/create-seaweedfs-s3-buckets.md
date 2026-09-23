# Create and Manage SeaweedFS S3 Buckets for Terraform State

Use this guide to provision, inspect, and validate S3 buckets on SeaweedFS for consumption by Terraform remote state backends and other infrastructure services.

## Mental model

Terraform's S3 backend client interacts with SeaweedFS as an S3 object store. However, Terraform **does not** automatically create target buckets; it requires pre-existing bucket containers with appropriate write and locking permissions.

```text
┌───────────────────────────┐
│  Terraform CLI / AWS CLI  │
└─────────────┬─────────────┘
              │ S3 API Requests (HTTP :8333)
              ▼
┌───────────────────────────┐
│   SeaweedFS S3 Gateway    │ ───► Validates IAM identity from `/etc/seaweedfs/s3.json`
└─────────────┬─────────────┘
              │
              ▼
┌───────────────────────────┐
│      SeaweedFS Filer      │ ───► Maps buckets to `/buckets/<bucket-name>` in leveldb2
└─────────────┬─────────────┘
              │
              ▼
┌───────────────────────────┐
│     SeaweedFS Volume      │ ───► Persists state blobs inside `/srv/seaweedfs/volume/`
└───────────────────────────┘
```

> **The Key Insight:**
> In SeaweedFS, an S3 bucket is a directory under the Filer hierarchy at `/buckets/<bucket-name>`. Creating a bucket registers this container in the Filer metadata store and exposes it through the S3 Gateway on port 8333.

---

## Prerequisites

1. **SeaweedFS running:** Daemon verified active on VM 151 (`192.0.2.51`).
2. **Ports reachable:** Port `8333` (S3) and `9333` (Master) accessible over LAN or Tailscale.
3. **Operator credentials:** S3 access key and secret key configured in `ansible/infra-ops/secrets/seaweedfs/admin.yml` (identity `terraform-admin`).
4. **Client tooling:** AWS CLI (`aws`) installed on the management workstation, or SSH access to `192.0.2.51`.

---

## Step-by-step procedures

### Method 1: Remote provisioning with AWS CLI (Recommended)

This is the standard approach from an operator workstation or CI pipeline.

#### 1. Export authentication variables

Load the admin credentials in your terminal session without saving them to disk:

```bash
export AWS_ACCESS_KEY_ID="<YOUR_SEAWEEDFS_ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<YOUR_SEAWEEDFS_SECRET_KEY>"
export AWS_DEFAULT_REGION="us-east-1"
```

#### 2. Create the Terraform state bucket

Create the dedicated `platform-tfstate` bucket:

```bash
aws --endpoint-url http://192.0.2.51:8333 s3 mb s3://platform-tfstate
```

*Expected output:*
```text
make_bucket: platform-tfstate
```

#### 3. Verify bucket listing

Confirm the bucket appears in the S3 catalog:

```bash
aws --endpoint-url http://192.0.2.51:8333 s3 ls
```

*Expected output:*
```text
2026-09-19 08:30:00 platform-tfstate
```

---

### Method 2: Host administrative provisioning via `weed shell`

If the AWS CLI is unavailable or for emergency host-level administration, use the built-in SeaweedFS administrative shell on the guest VM:

#### Interactive mode:

```bash
ssh ubuntu@192.0.2.51
weed shell -master=127.0.0.1:9333
```

Inside the shell:

```text
> s3.bucket.create -name platform-tfstate
> s3.bucket.list
> exit
```

#### Non-interactive one-liner:

```bash
ssh ubuntu@192.0.2.51 'echo "s3.bucket.create -name platform-tfstate" | weed shell -master=127.0.0.1:9333'
```

---

## Validation & end-to-end health probe

Test that the newly created bucket accepts writes, reads, and deletes using the configured `terraform-admin` credentials.

### 1. Write probe

Upload a test object:

```bash
echo "seaweedfs-healthcheck" | \
  aws --endpoint-url http://192.0.2.51:8333 s3 cp - s3://platform-tfstate/healthcheck.txt
```

### 2. Read probe

Fetch the test object:

```bash
aws --endpoint-url http://192.0.2.51:8333 s3 cp s3://platform-tfstate/healthcheck.txt -
```

*Expected output:* `seaweedfs-healthcheck`

### 3. Cleanup probe

Remove the test object:

```bash
aws --endpoint-url http://192.0.2.51:8333 s3 rm s3://platform-tfstate/healthcheck.txt
```

### 4. Direct Filer directory verification

Inspect the underlying Filer directory over HTTP (port 8888):

```bash
curl -s http://192.0.2.51:8888/buckets/platform-tfstate/
```

Returns HTTP 200 with directory metadata, confirming the Filer mount is healthy.

---

## Terraform backend consumption

Once created, reference the bucket in your Terraform configuration (`terraform/live/onprem-pve/backend.tf`):

```hcl
terraform {
  backend "s3" {
    bucket                      = "sample-tfstate"
    key                         = "live/onprem-pve/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://192.0.2.51:8333"

    # SeaweedFS compatibility requirements
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
```

Initialize or migrate state with credentials:

```bash
cd terraform/live/onprem-pve

# Method A: Using ignored local backend.tfvars (mode 0600)
terraform init -backend-config=backend.tfvars -migrate-state

# Method B: Using environment variables
export AWS_ACCESS_KEY_ID="<ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<SECRET_KEY>"
terraform init -migrate-state
```

---

## Rollback & bucket deletion

To remove a test bucket or decommission an environment:

### 1. Delete an empty bucket

```bash
aws --endpoint-url http://192.0.2.51:8333 s3 rb s3://platform-tfstate
```

### 2. Force delete a bucket and its contents

```bash
aws --endpoint-url http://192.0.2.51:8333 s3 rb s3://platform-tfstate --force
```

### 3. Via `weed shell`

```bash
ssh ubuntu@192.0.2.51 'echo "s3.bucket.delete -name platform-tfstate" | weed shell -master=127.0.0.1:9333'
```
