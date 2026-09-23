# Manage Zabbix client authorized keys with Ansible

Use this how-to when validating SSH access management on the Ubuntu managed-client fleet before automating Zabbix Agent 2 installation.

Related project: [`../../ansible/infra-ops/`](../../ansible/infra-ops/)

## Goal

Manage the `ubuntu` user's SSH `authorized_keys` on the four Terraform-provisioned managed clients:

- `zbx-client-01` at `192.0.2.33`
- `zbx-client-02` at `192.0.2.34`
- `zbx-client-03` at `192.0.2.35`
- `zbx-client-04` at `192.0.2.36`

## Assumptions

- The VMs already exist and are reachable through OPNsense LAN routing on `vmbr1`.
- The cloud-init `ubuntu` user already exists.
- Public keys are the only key material committed to Git.
- The initial run should not revoke keys; `exclusive` remains `false` until a deliberate rotation decision is made.

## Procedure

From the repository root:

```bash
cd ansible/infra-ops
ansible-inventory --graph
ansible-playbook playbooks/users.yml --check --diff
```

If the dry-run is safe, apply:

```bash
ansible-playbook playbooks/users.yml --diff
```

## Validation

After apply, confirm SSH still works to each host:

```bash
ssh ubuntu@192.0.2.33 true
ssh ubuntu@192.0.2.34 true
ssh ubuntu@192.0.2.35 true
ssh ubuntu@192.0.2.36 true
```

## Current dry-run result

A local syntax check passes, and inventory parsing succeeds. A live `--check` run was attempted against `zbx-client-01` on June 24, 2026, but SSH authentication failed with `Permission denied (publickey)`. Re-run the dry-run after confirming the operator private key or SSH agent can authenticate as `ubuntu`.

## Rollback

If a key change blocks access, recover through the Proxmox console or cloud-init workflow, restore a known-good public key in `ansible/infra-ops/` configuration, and rerun the playbook.
