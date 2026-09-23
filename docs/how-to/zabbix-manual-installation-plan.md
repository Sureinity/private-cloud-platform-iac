# Zabbix manual installation plan

Manual implementation checklist for the first Zabbix deployment on the Proxmox/OPNsense lab network.

Use this with the VM allocation reference: ``../reference/zabbix-vm-allocation.md``.

## Goal

Build Zabbix manually across separate VMs before introducing configuration-as-code automation.

Components:

- Zabbix database VM
- Zabbix server VM
- Zabbix frontend VM
- monitored client VM
- Zabbix Agent 2 on every VM

## Current Terraform status

The historical split Zabbix VM shells are disabled with `zabbix_vms_enabled = false`. The active Terraform-managed Zabbix-related VMs are:

| Role | Module | VM name | IP | OS image |
|---|---|---|---|---|
| Monolithic Zabbix server/front end/database test VM | `module.zabbix_monolith` | `zbx-monolith` | `192.0.2.30/24` | Ubuntu Resolute cloud image |
| Managed client test fleet | `module.managed_clients` | `zbx-client-01` to `zbx-client-04` | `192.0.2.33/24` to `192.0.2.36/24` | Ubuntu Resolute cloud image |

Keep Zabbix package installation, database bootstrap, and frontend setup manual on the monolith. Terraform creates only the VM shells, cloud-init access, and base networking. The managed client fleet is intentionally prepared for later Ansible-based Zabbix Agent 2 installation testing.

## Practical monolithic VM target

The next Zabbix iteration should use one VM for database, server, frontend, and Agent 2:

```text
Hostname: zbx-monolith
IP: 192.0.2.30/24
Gateway: 192.0.2.1
DNS: 8.8.8.8, 1.1.1.1
Bridge: vmbr1
vCPU: 2
RAM: 2 GB
Disk: 20 GB
Start on boot: false during manual build/testing
Components: database, server, frontend, Agent 2
```

Terraform has created the VM shell as `module.zabbix_monolith`.

## Do not automate yet

For the monolithic Zabbix server phase, avoid:

- Terraform automation beyond base VM shell provisioning
- shell scripts that perform server, frontend, or database installation
- unattended database bootstrap
- automatic firewall rule generation

Ansible automation is acceptable for the separate managed-client Agent 2 installation experiment. Keep that automation focused on clients until the manual monolith build is understood.

Manual notes are allowed and should be recorded after each successful step.

## Implementation order

### 1. Provision the VM shells with Terraform

Terraform creates the base Ubuntu VM shells only. Do not use Terraform, Ansible, or shell automation for Zabbix application installation yet.

| Order | VM | Module | IP | Specs |
|---:|---|---|---:|---|
| 1 | `zbx-monolith` | `module.zabbix_monolith` | `192.0.2.30/24` | 2 vCPU, 2 GB RAM, 20 GB disk |
| 2 | `zbx-client-01` | `module.managed_clients["client01"]` | `192.0.2.33/24` | 1 vCPU, 1 GB RAM, 10 GB disk |
| 3 | `zbx-client-02` | `module.managed_clients["client02"]` | `192.0.2.34/24` | 1 vCPU, 1 GB RAM, 10 GB disk |
| 4 | `zbx-client-03` | `module.managed_clients["client03"]` | `192.0.2.35/24` | 1 vCPU, 1 GB RAM, 10 GB disk |
| 5 | `zbx-client-04` | `module.managed_clients["client04"]` | `192.0.2.36/24` | 1 vCPU, 1 GB RAM, 10 GB disk |

The Terraform-created VMs use:

```text
Bridge: vmbr1
Gateway: 192.0.2.1
DNS: 8.8.8.8, 1.1.1.1 via Terraform cloud-init
OS image: Ubuntu Resolute cloud image
```

### 2. Establish baseline OS access

On every VM:

- set hostname
- confirm static IP or DHCP reservation
- confirm default route through `192.0.2.1`
- confirm Terraform cloud-init configured DNS resolvers as `8.8.8.8` and `1.1.1.1`
- confirm DNS resolution
- update packages manually
- install basic operator tools if needed
- confirm SSH access
- record OS version and hostname/IP mapping

### 3. Install the database component

On `zbx-monolith`, install and configure the database engine selected for the lab. Prefer PostgreSQL unless there is a specific reason to test MySQL/MariaDB.

Implement manually:

- database service package
- database listener policy for `192.0.2.0/24` or only required Zabbix VM IPs
- Zabbix database name
- Zabbix database user
- database password stored outside Git
- schema import from Zabbix SQL scripts
- service enable/start
- local and remote connection test

Keep the database password out of repository files and screenshots.

### 4. Install the Zabbix server component

On `zbx-monolith`, install and configure:

- Zabbix repository package for the chosen OS/version
- `zabbix-server` package matching the database backend
- `zabbix-sql-scripts` if schema import was not done from the DB VM
- Zabbix Agent 2
- server configuration pointing to the local database on `zbx-monolith`
- DB name, DB user, and DB password in the local Zabbix server config
- service enable/start

Validate:

- server service is running
- server log can connect to the database
- server listens on the expected Zabbix port
- Agent 2 on `zbx-monolith` can be monitored later

### 5. Install the frontend component

On `zbx-monolith`, install and configure:

- Zabbix frontend package
- supported web server package, such as Nginx or Apache
- PHP packages required by the selected frontend package
- frontend configuration for the database host `192.0.2.30`
- web service enable/start
- OPNsense rule or route needed for operator browser access

Then complete the Zabbix web installer manually in the browser.

Validate:

- frontend loads from the operator network
- frontend reaches the database
- frontend points to the Zabbix server host as intended
- login succeeds

### 6. Install Agent 2 everywhere

Install Zabbix Agent 2 on:

- `zbx-monolith`
- `zbx-client-01`
- `zbx-client-02`
- `zbx-client-03`
- `zbx-client-04`

Configure each agent with the appropriate Zabbix server IP:

```text
Server=192.0.2.30
ServerActive=192.0.2.30
Hostname=<matching Zabbix host name>
```

Use either active checks, passive checks, or both intentionally. For a simple lab, active checks reduce inbound firewall requirements on monitored clients.

### 7. Add hosts in Zabbix UI

In the frontend:

- add `zbx-monolith`
- add `zbx-client-01`
- add `zbx-client-02`
- add `zbx-client-03`
- add `zbx-client-04`
- link Linux by Zabbix agent templates or the appropriate OS template
- verify latest data begins to arrive

### 8. Record manual results

After the manual install works, record:

- exact Zabbix version
- OS distribution and version used for each VM
- database engine and version
- web server choice
- package names used
- firewall rules required
- final hostnames and IPs
- problems encountered
- commands worth automating later

## Initial firewall checklist

Start narrow and expand only when needed.

| Flow | Purpose |
|---|---|
| operator network to `192.0.2.30` web ports | access Zabbix frontend on the monolith |
| `192.0.2.33-36` to `192.0.2.30` Zabbix server port | Agent 2 active checks from managed clients |
| `192.0.2.30` to `192.0.2.33-36` Agent 2 port | passive checks, if used |

## Done criteria

The manual phase is complete when:

- both Terraform-created Zabbix-related VMs are reachable on `vmbr1`
- Zabbix server starts cleanly
- frontend login works
- database is local to the monolith and persistent
- Agent 2 is running on `zbx-monolith` and `zbx-client-01` through `zbx-client-04`
- the monolith and all four managed clients report latest data in Zabbix
- manual installation notes are recorded for later automation design

## Source references

- Zabbix installation requirements: <https://www.zabbix.com/documentation/current/manual/installation/requirements>
- Zabbix installation from sources and component overview: <https://www.zabbix.com/documentation/current/en/manual/installation/install>
- Zabbix frontend installation: <https://www.zabbix.com/documentation/current/en/manual/installation/frontend>
- Zabbix Agent and Agent 2 concepts: <https://www.zabbix.com/documentation/current/en/manual/concepts/agent>
