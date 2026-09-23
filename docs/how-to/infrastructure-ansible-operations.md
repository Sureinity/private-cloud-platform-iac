# Run Infrastructure Ansible operations

Use this guide to run the general Infrastructure Ansible project for guest operating-system operations.

## Scope

The current project at `ansible/infra-ops/` manages local users and installs Zabbix Agent 2.

Supported target operating systems:

- Ubuntu
- Debian

The Zabbix Agent 2 role aborts on unsupported operating systems. The users playbook is governed by its inventory-defined UID/GID registry.

## Before running

Confirm the target hosts are intentionally started and reachable. Inspect the
inventory before selecting a playbook target:

```bash
cd ansible/infra-ops
ansible-inventory --graph
```

## Commands

```bash
cd ansible/infra-ops
ansible-inventory --graph
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/site.yml --diff
ansible-playbook playbooks/users.yml --check --diff --limit <host>
```

## Rollback notes

Zabbix Agent 2 removal and user removal should be deliberate, host-scoped changes rather than a rollback of `playbooks/site.yml`.
