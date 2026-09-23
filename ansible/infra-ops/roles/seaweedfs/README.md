# Ansible Role: SeaweedFS

Deploy, configure, and secure a standalone SeaweedFS cluster (Master, Volume, Filer, S3 Gateway) with strict systemd process sandboxing, storage safety gates, and native TLS encryption.

## Requirements

- Target OS: Ubuntu (22.04+, 24.04+, 26.04+) or Debian (12+).
- System Architecture: `x86_64` (`amd64`).
- Storage: Dedicated block device (e.g. `/dev/sdb`) or existing mount point for persistent data.
- S3 Credentials: S3 IAM identities declared via `secrets/seaweedfs/admin.yml` (mode `0600`).
- TLS Prerequisites (if enabled):
  - For `acme_dns01`: Cloudflare API token in `secrets/seaweedfs/cloudflare.yml`.
  - For `local_payload`: Certificate and key in `secrets/seaweedfs/tls/`.

## Role Variables

### Core Configuration

| Variable | Default | Description |
|---|---|---|
| `seaweedfs_version` | `"4.47"` | SeaweedFS release version |
| `seaweedfs_build_type` | `"large_disk"` | Build variant (`""`, `"large_disk"`, `"full_disk"`) |
| `seaweedfs_data_device` | `"/dev/sdb"` | Block device for persistent storage |
| `seaweedfs_data_mount_point` | `"/srv/seaweedfs"` | Filesystem mount target |
| `seaweedfs_format_disk` | `false` | Explicit opt-in required to format unformatted disk |
| `seaweedfs_master_port` | `9333` | Master HTTP control plane port |
| `seaweedfs_volume_port` | `8080` | Volume HTTP port |
| `seaweedfs_filer_port` | `8888` | Filer HTTP port |
| `seaweedfs_s3_port` | `8333` | S3 HTTP API port |

### TLS and HTTPS Configuration

| Variable | Default | Description |
|---|---|---|
| `seaweedfs_tls_enabled` | `false` | Enable TLS encryption for S3 gateway |
| `seaweedfs_tls_certificate_source` | `"acme_dns01"` | Source: `"acme_dns01"`, `"local_payload"`, or `"self_signed"` |
| `seaweedfs_tls_dir` | `"/etc/seaweedfs/tls"` | Host directory for TLS certificates |
| `seaweedfs_s3_enable_http` | `true` | Enable plaintext HTTP alongside HTTPS (dual-stack) |
| `seaweedfs_s3_port_https` | `8334` | S3 HTTPS listen port |
| `seaweedfs_s3_cert_file` | `"/etc/seaweedfs/tls/s3.crt"` | Path to S3 TLS certificate |
| `seaweedfs_s3_key_file` | `"/etc/seaweedfs/tls/s3.key"` | Path to S3 TLS private key (mode 0600) |
| `seaweedfs_endpoint_hostname` | `"seaweedfs.example.invalid"` | Endpoint FQDN for certificates and SigV4 |
| `seaweedfs_s3_external_url` | `"https://{{ seaweedfs_endpoint_hostname }}:{{ seaweedfs_s3_port_https }}"` | Advertised external URL for SigV4 |
| `seaweedfs_cloudflare_api_token` | `""` | Cloudflare API token for ACME DNS-01 challenges |
| `seaweedfs_acme_email` | `"admin@example.invalid"` | ACME registration email |

## Example Playbook

```yaml
---
- name: Deploy SeaweedFS with TLS
  hosts: seaweedfs_hosts
  become: true
  roles:
    - role: local_secrets
      vars:
        secret_env: "seaweedfs"
        secret_vars_files:
          - admin.yml
          - cloudflare.yml
    - role: seaweedfs
      vars:
        seaweedfs_tls_enabled: true
        seaweedfs_tls_certificate_source: "acme_dns01"
```

## Verification

Run the 4-phase post-deployment verification pipeline:

```bash
ansible-playbook playbooks/seaweedfs.yml --tags verify
```

## License

MIT-0
