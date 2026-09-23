# Configure TLS and HTTPS for SeaweedFS S3 Gateway

Use this guide to enable, configure, and verify TLS encryption for the SeaweedFS S3 gateway on Proxmox VE guest VM `seaweedfs-state` (`192.0.2.51`) using the Infrastructure Ansible operations suite.

## Scope

This procedure secures S3 API transactions between management workstations, CI pipelines, and SeaweedFS by terminating TLS directly within the native SeaweedFS daemon. It covers automated Let's Encrypt issuance via Cloudflare ACME DNS-01, operator-supplied certificates, dual-stack HTTP/HTTPS transition, and end-to-end verification.

Target endpoint:

| Parameter | Value |
|---|---|
| Target Host | `seaweedfs-state` (`192.0.2.51`) |
| Endpoint Hostname | `seaweedfs.example.invalid` |
| Default HTTP Port | `8333` (Plaintext, toggleable) |
| Default HTTPS Port | `8334` (TLS v1.3 / v1.2) |
| Certificate Storage | `/etc/seaweedfs/tls/` (`root:seaweedfs`, mode `0750`) |
| Private Key Permissions | Mode `0600`, owned by `seaweedfs:seaweedfs` |

---

## Prerequisites

1. **SeaweedFS running:** Daemon verified active on VM 151 (`192.0.2.51`).
2. **DNS resolution:** `seaweedfs.example.invalid` must resolve to `192.0.2.51` on all client machines and the gateway (via OPNsense Unbound host override or Cloudflare DNS record).
3. **Authentication secrets:** `secrets/seaweedfs/admin.yml` configured with `terraform-admin` credentials.
4. **Certificate source readiness:**
   - **For ACME DNS-01 (Recommended):** Cloudflare API token with `Zone:DNS:Edit` permissions for `example.invalid`.
   - **For Local Payload:** Certificate (`s3.crt`) and private key (`s3.key`) available locally.

---

## Step-by-step procedures

All commands are executed from the Ansible operations project root:

```bash
cd ansible/infra-ops
```

### 1. Configure DNS resolution

Ensure `seaweedfs.example.invalid` resolves to `192.0.2.51`. In OPNsense:
1. Navigate to **Services > Unbound DNS > Overrides**.
2. Add a Host Override: Host `seaweedfs`, Domain `example.invalid`, IP `192.0.2.51`.
3. Apply changes and test from your workstation:

```bash
getent hosts seaweedfs.example.invalid
# Expected: 192.0.2.51 seaweedfs.example.invalid
```

---

### 2. Supply secret payload

#### Option A: Cloudflare API token for ACME DNS-01 (Recommended)

Create `secrets/seaweedfs/cloudflare.yml` with mode `0600`:

```yaml
---
seaweedfs_cloudflare_api_token: "<YOUR_CLOUDFLARE_API_TOKEN>"
```

Ensure restrictive file permissions:

```bash
chmod 600 secrets/seaweedfs/cloudflare.yml
```

#### Option B: Operator-supplied local certificates

If using pre-issued certificates, create `secrets/seaweedfs/tls/` and copy your certificate and private key:

```bash
mkdir -p secrets/seaweedfs/tls
cp /path/to/fullchain.pem secrets/seaweedfs/tls/s3.crt
cp /path/to/privkey.pem secrets/seaweedfs/tls/s3.key
chmod 600 secrets/seaweedfs/tls/s3.key
chmod 644 secrets/seaweedfs/tls/s3.crt
```

---

### 3. Enable TLS in group variables

Edit `ansible/infra-ops/inventory/group_vars/seaweedfs_hosts.yml` to declare the desired TLS state:

```yaml
---
seaweedfs_data_device: "/dev/sdb"
seaweedfs_data_mount_point: "/srv/seaweedfs"

# TLS Configuration
seaweedfs_tls_enabled: true
seaweedfs_tls_certificate_source: "acme_dns01" # Or "local_payload"
seaweedfs_s3_enable_http: true                 # Dual-stack during migration
seaweedfs_s3_port_https: 8334
seaweedfs_endpoint_hostname: "seaweedfs.example.invalid"
```

---

### 4. Deploy TLS configuration

Execute the playbook to issue certificates, configure the systemd unit, and restart the service:

```bash
# Syntax and dry-run check
ansible-playbook playbooks/seaweedfs.yml --syntax-check

# Apply TLS configuration
ansible-playbook playbooks/seaweedfs.yml --diff
```

To run only the TLS and verification stages:

```bash
ansible-playbook playbooks/seaweedfs.yml --tags tls,config,verify --diff
```

---

### 5. Verify TLS and HTTPS health

#### A. Inspect listening ports on VM

Verify both HTTP (:8333) and HTTPS (:8334) ports are active:

```bash
ssh ubuntu@192.0.2.51 "ss -tulpn | grep -E ':(8333|8334)'"
```

#### B. Validate TLS certificate handshake

Inspect the negotiated certificate parameters, issuer, and validity dates:

```bash
openssl s_client -connect 192.0.2.51:8334 -servername seaweedfs.example.invalid </dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer
```

#### C. Probe S3 HTTPS endpoint with curl

```bash
curl -s -i https://seaweedfs.example.invalid:8334/
```

*Expected response (HTTP 403 AccessDenied S3 XML payload):*

```xml
HTTP/2 403 
content-type: application/xml
...
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>AccessDenied</Code><Message>Access Denied.</Message><Resource>/</Resource>...</Error>
```

#### D. Perform AWS CLI S3 operations over HTTPS

```bash
export AWS_ACCESS_KEY_ID="<ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<SECRET_KEY>"
export AWS_DEFAULT_REGION="us-east-1"

aws --endpoint-url https://seaweedfs.example.invalid:8334 s3 ls
```

---

### 6. Transition to HTTPS-only (Hardening)

Once all Terraform roots and client tools are updated to connect via HTTPS on `:8334` (or if moving HTTPS to port `:8333`), disable plaintext HTTP:

In `inventory/group_vars/seaweedfs_hosts.yml`:

```yaml
seaweedfs_s3_enable_http: false
seaweedfs_s3_port_https: 8334 # Or 8333 to keep the original port
```

Re-run the playbook:

```bash
ansible-playbook playbooks/seaweedfs.yml --diff
```

The systemd unit will start SeaweedFS with `-s3.port=0`, fully closing the unencrypted HTTP port.

---

## Rollback and recovery

1. **Certificate Failure:** If ACME issuance fails due to network or DNS propagation, inspect logs via `journalctl -u seaweedfs -e` and verify Cloudflare API permissions.
2. **Revert to Plaintext HTTP:** Set `seaweedfs_tls_enabled: false` and `seaweedfs_s3_enable_http: true` in `group_vars/seaweedfs_hosts.yml` and re-run `ansible-playbook playbooks/seaweedfs.yml`.
3. **Manual Certificate Renewal:** Run `sudo certbot renew` on the host; the renewal post-hook at `/etc/letsencrypt/renewal-hooks/post/seaweedfs-reload.sh` will automatically sync new certificates and restart the service.
