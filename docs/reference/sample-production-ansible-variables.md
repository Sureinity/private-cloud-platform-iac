# SampleApp production Ansible variables

This reference defines the non-secret desired state for the SampleApp production VM. The source of truth is `ansible/infra-ops/inventory/hosts.yml` and `ansible/infra-ops/inventory/group_vars/sample_production.yml`. Base role defaults and boundary assertion flags are declared in `ansible/infra-ops/roles/sample_app/defaults/main.yml`.

## Inventory and control path

| Item | Value | Notes |
| --- | --- | --- |
| Inventory host | `sample-app-prod-01` | Dedicated production guest hosted in Azure. |
| Connection address | `20.249.4.99` | Public/Azure host IPv4 address. |
| Bootstrap/control account | `azureuser` | Ansible connects as this account from the designated operator/admin workstation. |
| SSH private key | `secrets/sample-production/SampleApp_key948.pem` | Local ignored key file path referenced via `{{ inventory_dir }}/../secrets/sample-production/SampleApp_key948.pem`. |
| Control node | Designated operator/admin workstation | The production VM must not run Ansible against itself. |
| Host-key policy | Strict verification | Record the expected host key in the operator workstation's `known_hosts` before the first run. Do not disable host-key checking or use runtime `ssh-keyscan`. |
| Minimum controller | Ansible Core `2.16` | Use a supported newer release where available. |
| Required collections | `ansible.posix` | The existing `users` role uses `ansible.posix.authorized_key`; all baseline tasks prefer `ansible.builtin`. |

## Inventory groups

The VM belongs to these groups:

- `sample_production`: dedicated desired state and production-scoped variables.
- `sample-app`: umbrella group containing `sample_staging` and `sample_production`.
- `ubuntu_hosts`: common Ubuntu guest targeting.
- `docker_hosts`: Docker engine baseline targeting.

It does not belong to `zabbix_agent2_hosts` until production monitoring enrollment is approved.

## Account model

| Account | Purpose | SSH | Docker | Sudo | Key source |
| --- | --- | --- | --- | --- | --- |
| `azureuser` | Initial/bootstrap and operator access | Key-only | No by default | Full passwordless sudo for automation become path | Designated operator workstation; key referenced from ignored secrets. |
| `developer` | Named human developer account | Key-only | Yes (`docker` group) | No sudo | Reviewed individual developer public key, supplied out of band. |
| `sample-deploy` | GitHub Actions deployment identity | Key-only | No direct membership | `sudo /usr/local/sbin/sample-app-prod-deploy` only | GitHub Environment-managed public key or equivalent approved deploy-key source. |

UID/GID allocation and account mutation must be reconciled with [`uid-gid-allocation-policy.md`](uid-gid-allocation-policy.md) before adding these accounts to the managed user registry.

### Sudo privilege model

| Account | Initial sudo policy | Permitted scope | Explicit restrictions | Implementation notes |
| --- | --- | --- | --- | --- |
| `azureuser` | Full administrative `NOPASSWD` sudo retained during bootstrap. | Administrative host recovery and the Ansible `become` path from the designated operator workstation. | Do not remove or narrow this access until an independent key-only `azureuser` session and Ansible `become` both work. Do not use it as the GitHub deployment identity. | Cloud-image administrative user. |
| `developer` | No sudo grant. | None through `/etc/sudoers` or the `sudo` group. | Must not receive `ALL`, `NOPASSWD: ALL`, package-manager, service-manager, editor, shell, or host administrative permissions. | Docker-group membership remains root-equivalent: the account can control the Docker daemon and can therefore obtain host-root capability. “No sudo” is an audit and accidental-administration boundary, not an isolation boundary. |
| `sample-deploy` | One passwordless sudo command. | `sudo /usr/local/sbin/sample-app-prod-deploy prod-<short-sha>` only. | Never grant broad `ALL`, direct `docker`, `docker compose`, shell, package-manager, editor, or arbitrary `systemctl` commands. Do not add the account to the `docker` group. | The root-owned wrapper accepts only immutable hexadecimal production tags (`^prod-[0-9a-f]{7,64}$`), protects `.env.production`, serializes releases via lock file, and avoids arbitrary command execution. |

Dedicated sudoers configuration is placed under `/etc/sudoers.d/sample-app-prod-deploy`, mode `0440`, and validated before activation.

## SSH desired state

| Variable | Value |
| --- | --- |
| `ssh_port` | `22` |
| `ssh_permit_root_login` | `no` |
| `ssh_password_authentication` | `no` |
| `ssh_pubkey_authentication` | `yes` |
| `ssh_allowed_users` | `azureuser`, `developer`, `sample-deploy` |

## Docker and application paths

| Item | Desired value |
| --- | --- |
| Docker source | Docker CE from Docker's official apt repository. |
| Compose | Docker Compose plugin required; use the supported plugin packaged with Docker CE. |
| Application root | `/srv/sample-app` |
| Non-secret release state | `/srv/sample-app/.release-state` |
| Runtime environment file | `/srv/sample-app/.env.production` |
| Fixed production Compose file | `/srv/sample-app/docker-compose.prod.yml` |
| Constrained deployment wrapper | `/usr/local/sbin/sample-app-prod-deploy` |
| Deployment lock | `/run/lock/sample-app-prod-deploy.lock` |
| Image tag pattern | `^prod-[0-9a-f]{7,64}$` |
| GHCR package-read token | Ignored controller source `secrets/sample-production/ghcr-pull-token` (`0600`), copied to `/etc/sample-app/ghcr-pull-token` (`root:root`, `0600`) |
| Environment ownership/mode | `root:root`, `0600` |
| Application deployment owner | GitHub Actions, not Ansible. |

Ansible installs Docker, creates application directories, and configures the host baseline, but does not deploy or restart application containers directly.

## Managed payload locations

The Ansible project maintains distinct payload trees:

| Tree | Git status | Purpose |
| --- | --- | --- |
| `ansible/infra-ops/files/sample-production/` | Committed | Reviewed non-secret files copied to managed hosts (`release-state`). |
| `ansible/infra-ops/secrets/sample-production/` | Ignored except `README.md` | Operator-supplied secret files (`.env.production`, `SampleApp_key948.pem`, `access.yml`, `ghcr-pull-token`) copied with `no_log: true`. |

The role copies the committed non-secret `files/sample-production/release-state` payload to `/srv/sample-app/.release-state`. It copies the ignored local secret payload `secrets/sample-production/.env.production` to `/srv/sample-app/.env.production` as `root:root` with mode `0600`.

The ignored `secrets/sample-production/access.yml` file stores the public-key lists for the operator, developer, and deploy accounts. The production playbook loads it automatically via the `local_secrets` role.

## Explicitly deferred ownership

Ansible currently does not manage host firewall rules, DNS resolvers, NTP sources, unattended upgrades, maintenance windows, reboot behavior, backup destinations, or application-level container lifecycle. These concerns remain outside this automation baseline.
