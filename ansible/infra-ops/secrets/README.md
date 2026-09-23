# Local Ansible secrets

This directory is intentionally ignored by Git. It holds operator-supplied
secret payloads that Ansible copies to managed hosts with `no_log: true`.

Never commit files below this directory. Do not store secret files under
`files/`, inventory, group variables, playbooks, or roles.

Current expected local payloads:

```text
secrets/
  atelier-staging/
    .env.staging
    access.yml
    ghcr-pull-token
  atelier-production/
    .env.production
    access.yml
    ghcr-pull-token
  seaweedfs/
    admin.yml
    cloudflare.yml
    tls/
      s3.crt
      s3.key
```

For each environment, create the environment file and `ghcr-pull-token` with
mode `0600`. The `atelier_app` role copies the environment file to the
configured `atelier_app_env_file`, and the GHCR token to
`/etc/atelier/ghcr-pull-token`, both as `root:root` with mode `0600` and without
printing their contents.

`access.yml` is also ignored and must have mode `0600`. It supplies the
non-empty public-key variables required by `playbooks/atelier-app.yml`:

```yaml
atelier_app_operator_ssh_public_keys:
  - "ssh-ed25519 AAAA... operator"
atelier_app_developer_ssh_public_keys:
  - "ssh-ed25519 AAAA... developer"
atelier_app_deploy_ssh_public_keys:
  - "ssh-ed25519 AAAA... deploy"
```

Public keys are not secret, but this project keeps the operational access
payload out of tracked inventory so key rotation and operator-specific identity
material do not silently become repository configuration. Do not put private
keys in this file. The shared playbook loads the correct environment payload
from `secrets/{{ atelier_app_environment }}/access.yml` automatically; do not
supply it with `--extra-vars`.

`admin.yml` under `secrets/seaweedfs/` is also ignored and must have mode `0600`.
It supplies the S3 administrator identity and access keys required by
`playbooks/seaweedfs.yml`:

```yaml
seaweedfs_s3_admin_identity_name: "terraform-admin"
seaweedfs_s3_admin_access_key: "<ACCESS_KEY>"
seaweedfs_s3_admin_secret_key: "<SECRET_KEY>"
```

The playbook loads `secrets/seaweedfs/admin.yml` automatically via the
`local_secrets` role with `no_log: true` and verifies that the file is mode `0600`
before applying SeaweedFS configuration.

`cloudflare.yml` under `secrets/seaweedfs/` is also ignored and must have mode `0600`.
It supplies the Cloudflare API token required for ACME DNS-01 certificate issuance:

```yaml
seaweedfs_cloudflare_api_token: "<CLOUDFLARE_API_TOKEN>"
```

When using `seaweedfs_tls_certificate_source: "local_payload"`, provide `s3.crt` and `s3.key`
under `secrets/seaweedfs/tls/` with mode `0600` for the private key.
