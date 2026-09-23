# Ansible projects

This directory contains independent Ansible projects by purpose. It is not a single monolithic Ansible project root.

```text
ansible/
  <project-or-purpose>/
    ansible.cfg
    inventory/
    playbooks/
    roles/
```

Run Ansible commands from the relevant project subdirectory so each project can keep its own inventory, roles, collections, and conventions.

## Current projects

| Project | Purpose |
|---|---|
| `infra-ops/` | General On-Premises PVE operations: user lifecycle, SSH daemon hardening, Docker Engine baseline, Zabbix Agent 2, and SampleApp application VM baseline (staging and production). |
