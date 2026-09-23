# Managed host payloads

This directory is the source of truth for **non-secret** files copied to managed
hosts by the `infra-ops` Ansible project.

Use one directory per managed purpose or host class. Files here are committed,
reviewed, and applied through Ansible roles. Do not put credentials, private
keys, API tokens, `.env` files, passwords, Vault material, downloaded release
artifacts, or generated host output in this directory.

Current layout:

```text
files/
  sample-staging/      Non-secret payloads for the SampleApp staging VM
  sample-production/   Non-secret payloads for the SampleApp Azure production VM
```

Runtime secrets use the ignored sibling directory `secrets/`. See
[`../secrets/README.md`](../secrets/README.md).
