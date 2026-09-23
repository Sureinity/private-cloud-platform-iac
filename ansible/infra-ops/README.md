# On-Premises PVE operations Ansible project

General-purpose Ansible project for guest operating-system operations in the On-Premises PVE environment.

## Scope

Current playbooks:

- manage inventory-defined local users with pinned UID/GID allocations
- install and configure Zabbix Agent 2
- configure the approved host baseline for `sample-staging-01`
- deploy and configure SeaweedFS S3-compatible state store with post-deployment verification

The Zabbix Agent 2 role intentionally supports only Ubuntu and Debian. It aborts on any other OS family or distribution.

## Layout

```text
ansible/infra-ops/
  ansible.cfg
  requirements.yml       Pinned Ansible collections and roles
  files/                 Committed non-secret host payloads
  secrets/               Ignored operator-local runtime secrets
  inventory/
  playbooks/
  roles/docker/
  roles/users/
  roles/sample_app/
  roles/zabbix_agent2/
  roles/seaweedfs/
```

## Inventory

The current inventory contains Zabbix Agent 2 targets, SampleApp targets, and the SeaweedFS backend host:

```text
pve ansible_host=192.0.2.10 ansible_user=root
zbx-monolith ansible_host=192.0.2.30 ansible_user=ubuntu
sample-staging-01 ansible_host=198.51.100.100 ansible_user=ubuntu
sample-app-prod-01 ansible_host=20.249.4.99 ansible_user=azureuser
seaweedfs ansible_host=192.0.2.51 ansible_user=ubuntu
```

`pve`, `zbx-monolith`, and `seaweedfs` belong to `zabbix_agent2_hosts`. `seaweedfs`
also belongs to `seaweedfs_hosts` and `ubuntu_hosts`. The
separate `playbooks/users.yml` playbook targets `all` unless its `target`
variable is set. `sample-staging-01` belongs to `sample_staging`, `sample-app`,
`ubuntu_hosts`, and `docker_hosts`; `sample-app-prod-01` belongs to
`sample_production`, `sample-app`, `ubuntu_hosts`, and `docker_hosts`.

Do not store passwords, tokens, private keys, or Vault secrets in this project.
Committed non-secret payloads belong in `files/`; local runtime secret payloads
belong in the ignored `secrets/` tree. `secrets/README.md` is retained as the
only tracked file under that directory.

## Usage

Run commands from this project directory:

```bash
cd ansible/infra-ops
```

Install pinned collections and roles:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-galaxy role install -r requirements.yml
```

Inspect inventory:

```bash
ansible-inventory --graph
```

Check playbook syntax:

```bash
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/zabbix-agent2.yml --syntax-check
ansible-playbook playbooks/users.yml --syntax-check
ansible-playbook playbooks/sample-app.yml --syntax-check
ansible-playbook playbooks/seaweedfs.yml --syntax-check
```

Dry-run with diff:

```bash
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/zabbix-agent2.yml --check --diff
ansible-playbook playbooks/users.yml --check --diff --limit <host>
ansible-playbook playbooks/sample-app.yml --check --diff --limit sample_staging
ansible-playbook playbooks/seaweedfs.yml --check --diff
```

Apply:

```bash
ansible-playbook playbooks/site.yml --diff
ansible-playbook playbooks/zabbix-agent2.yml --diff
ansible-playbook playbooks/users.yml --diff --limit <host>
ansible-playbook playbooks/sample-app.yml --diff --limit sample_staging
ansible-playbook playbooks/seaweedfs.yml --diff
```

## SeaweedFS deployment baseline

`playbooks/seaweedfs.yml` configures the dedicated SeaweedFS S3-compatible state backend:

- validates target OS, architecture, disk availability, and listening port collisions (fail-fast preflight);
- safely prepares the secondary persistent disk (`/dev/sdb`), formatting only on explicit opt-in (`seaweedfs_format_disk: true`), mounting by UUID to `/srv/seaweedfs`, and scaffolding isolated `master/`, `volume/`, and `filer/` storage paths;
- provisions the unprivileged system account (`seaweedfs:seaweedfs`) with home at `/var/lib/seaweedfs` and shell `/usr/sbin/nologin`;
- installs the official pinned SeaweedFS release binary (`large_disk` build) with SHA-256 verification and build token validation;
- deploys isolated `filer.toml` (`leveldb2` store), sealed S3 identity configuration (`s3.json`), and sealed runtime environment (`seaweedfs.env`) strictly mode `0600`;
- configures and enables the systemd service unit (`seaweedfs.service`) under strict sandboxing (`ProtectSystem=strict`) and the Mount Gate assertion (`AssertPathIsMountPoint=/srv/seaweedfs`);
- executes post-deployment verification testing process supervision, core ports, Master leader status, and S3 XML API responsiveness.

Run verification independently at any time:

```bash
ansible-playbook playbooks/seaweedfs.yml --tags verify
```

## SampleApp application baseline

`playbooks/sample-app.yml` configures only the approved guest baseline:

- reconciles operator, developer, and deploy accounts through the UID/GID registry;
- applies key-only SSH configuration and the environment-specific allow-list;
- installs Docker CE and the Compose plugin with daemon log rotation;
- creates `/srv/sample-app`, safely copies the operator-local `.env.staging` file,
  and creates a non-secret release-state placeholder;
- verifies the already-enrolled Tailscale service and expected hostname when enabled without
  running `tailscale up` or changing Tailnet policy.

The playbook runs `docker` before `sample_app` and `users` because Docker CE creates the
`docker` group and the developer account must join that group. SSH hardening
runs last, after the required accounts and authorized keys are in place. If a
run stopped before this ordering was introduced, safely rerun the same scoped
playbook command; the roles are idempotent.

Docker CE installation is delegated to the `docker` role, which is limited to Ubuntu releases listed in
`docker_supported_distribution_releases` (currently `jammy` and
`noble`). Ubuntu 26.04 (`resolute`) uses the supported Ubuntu `docker.io` and
`docker-compose-v2` packages through `docker_source: ubuntu`,
because Docker CE packages are not published for its matching suite. The `docker` role
fails during preflight for an unsupported source-and-release combination rather
than adding an incompatible repository or using an implicit fallback suite.

It intentionally does not manage OPNsense firewall policy, DNS, NTP, reboot
policy, monitoring, Tailnet enrollment, application releases, Compose service
restarts, database migrations, or backups. See
[`docs/how-to/configure-sample-staging-with-ansible.md`](../../docs/how-to/configure-sample-staging-with-ansible.md)
for prerequisites and safe operation.


## Zabbix Agent 2 behavior

The `zabbix_agent2` role is adapted for On-Premises PVE. It supports Ubuntu and Debian hosts, configures the official Zabbix apt repository, installs `zabbix-agent2`, writes `zabbix_agent2.conf`, and enables the service. The current group variables enable active checks and disable passive checks.
