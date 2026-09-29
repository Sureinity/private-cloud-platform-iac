# Local Ansible secrets for OPNsense operations

This directory is intentionally ignored by Git. It holds operator-supplied secret payloads for OPNsense Day-2 operations.

Never commit files below this directory.

Expected local payloads:

```text
secrets/
  vault.yml
  vault_pass
```

### `vault.yml` format

```yaml
---
vault_opnsense_api_key: "your_real_api_key_here"
vault_opnsense_api_secret: "your_real_api_secret_here"
```

Set file permissions to `0600`:
```bash
chmod 0600 ansible/opnsense-ops/secrets/vault.yml
```
