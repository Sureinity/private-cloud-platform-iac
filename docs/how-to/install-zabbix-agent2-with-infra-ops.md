# Install Zabbix Agent 2 with Infrastructure Ansible operations

Use this guide to install and configure Zabbix Agent 2 with the general Infrastructure Ansible project.

## Scope

The project `ansible/infra-ops/` includes a local `zabbix_agent2` role adapted for On-Premises PVE operations.

Current target:

| Host | Address | User | Group |
|---|---|---|---|
| `pve-home` | `192.0.2.10` | `root` | `zabbix-agent2-hosts` |
| `zbx-monolith-server` | `192.0.2.30` | `ubuntu` | `zabbix-agent2-hosts` |

The role supports Ubuntu and Debian-family hosts. It aborts on other operating systems.

## Configuration

Group variables are stored in:

```text
ansible/infra-ops/inventory/group_vars/zabbix_agent2_hosts.yml
```

Current values:

```yaml
zabbix_server_address: "192.0.2.30"
zabbix_agent_hostname: "{{ inventory_hostname }}"
zabbix_agent2_enable_active_check: true
zabbix_agent2_enable_passive_check: false
```

## Commands

Run from the Ansible project directory:

```bash
cd ansible/infra-ops
ansible-inventory --graph
ansible-playbook playbooks/zabbix-agent2.yml --syntax-check
ansible-playbook playbooks/zabbix-agent2.yml --check --diff
ansible-playbook playbooks/zabbix-agent2.yml --diff
```

## Validation

On the target host, verify:

```bash
systemctl is-enabled zabbix-agent2
systemctl is-active zabbix-agent2
zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf -T
grep -E '^(Server|ServerActive|Hostname)=' /etc/zabbix/zabbix_agent2.conf
```

## Notes

The role installs the official Zabbix repository, installs `zabbix-agent2`, renders `/etc/zabbix/zabbix_agent2.conf`, and enables/starts the service.
