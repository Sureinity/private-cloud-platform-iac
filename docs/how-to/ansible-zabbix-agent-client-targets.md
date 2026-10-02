# Prepare managed clients for Ansible Zabbix Agent 2 automation

Use this guide when validating Ansible automation that installs and configures Zabbix Agent 2 on Ubuntu clients behind OPNsense.

Related reference: ``../reference/zabbix-vm-allocation.md``.

## Goal

Provision four minimal Ubuntu managed clients on `vmbr1` and use them as repeatable Ansible targets for Zabbix Agent 2 installation testing. The clients are provisioned but intentionally kept stopped by Terraform until an operator starts them for a test window.

## Terraform-provisioned target fleet

| Hostname | Terraform key | VMID | IP address | vCPU | RAM | Disk | Gateway |
|---|---|---:|---:|---:|---:|---:|---:|
| `zbx-client-01` | `client01` | `133` | `192.0.2.33/24` | 1 | 1 GB | 10 GB | `192.0.2.1` |
| `zbx-client-02` | `client02` | `134` | `192.0.2.34/24` | 1 | 1 GB | 10 GB | `192.0.2.1` |
| `zbx-client-03` | `client03` | `135` | `192.0.2.35/24` | 1 | 1 GB | 10 GB | `192.0.2.1` |
| `zbx-client-04` | `client04` | `136` | `192.0.2.36/24` | 1 | 1 GB | 10 GB | `192.0.2.1` |

Common settings:

- OS image: Ubuntu Resolute cloud image
- Cloud-init user: `ubuntu`
- Bridge: `vmbr1`
- DNS: `8.8.8.8`, `1.1.1.1`
- Terraform module: `module.managed_clients`
- Started by Terraform: `false`
- Start on boot: `false`

## Ansible inventory group for client testing

These managed clients are provisioned in a stopped state by Terraform and are intentionally not enrolled in `ansible/infra-ops/inventory/hosts.yml` by default. When running Agent 2 test automation during an active validation window, add this group or an inventory overlay to your project inventory:

```yaml
    zabbix_agent_clients:
      hosts:
        zbx-client-01:
          ansible_host: 192.0.2.33
          ansible_user: ubuntu
        zbx-client-02:
          ansible_host: 192.0.2.34
          ansible_user: ubuntu
        zbx-client-03:
          ansible_host: 192.0.2.35
          ansible_user: ubuntu
        zbx-client-04:
          ansible_host: 192.0.2.36
          ansible_user: ubuntu
```

Or in INI format if using an ad-hoc test inventory:

```ini
[zabbix_agent_clients]
zbx-client-01 ansible_host=192.0.2.33 ansible_user=ubuntu
zbx-client-02 ansible_host=192.0.2.34 ansible_user=ubuntu
zbx-client-03 ansible_host=192.0.2.35 ansible_user=ubuntu
zbx-client-04 ansible_host=192.0.2.36 ansible_user=ubuntu
```

## Validation before running Agent 2 automation

From the operator machine or an existing helper host with routing to `vmbr1`:

```bash
ssh ubuntu@192.0.2.33 true
ssh ubuntu@192.0.2.34 true
ssh ubuntu@192.0.2.35 true
ssh ubuntu@192.0.2.36 true
```

Then verify Ansible connectivity from the project:

```bash
cd ansible/infra-ops
ansible 'zbx-client-*' -i inventory/hosts.yml -m ping
```

## Agent 2 configuration intent

Use the monolithic Zabbix VM as the server endpoint unless the architecture changes:

```text
Server=192.0.2.30
ServerActive=192.0.2.30
Hostname=<matching Zabbix host name>
```

Active checks are the safer first default because they require fewer inbound firewall allowances to each client. Add passive checks only when the OPNsense policy and host firewall policy intentionally allow Zabbix server-to-client Agent 2 traffic.

## Rollback

If the client fleet needs a clean cloud-init rebuild, run `scripts/reprovision-zbx-clients.sh` from the repository root. The script validates Terraform, creates a targeted replacement plan for VMIDs `133-136`, and applies it automatically; it is mutating and must be used only after confirming that all four clients may be destroyed and recreated. If the fleet is no longer needed, remove or reduce entries in `managed_clients`, run `terraform plan`, confirm only the intended clients are destroyed, then apply.
