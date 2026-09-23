# SampleApp staging Ansible variables

This reference defines the non-secret desired state for the SampleApp staging VM. The source of truth is `ansible/infra-ops/inventory/hosts.yml` and `ansible/infra-ops/inventory/group_vars/sample_staging.yml`. Base role defaults and boundary assertion flags are declared in `ansible/infra-ops/roles/sample_app/defaults/main.yml`.

Related: [SampleApp production Ansible variables](sample-production-ansible-variables.md).

## Inventory and control path

| Item | Value | Notes |
| --- | --- | --- |
| Inventory host | `sample-staging-01` | Dedicated persistent staging guest. |
| Connection address | `198.51.100.100` | Tailscale IPv4 address. Do not substitute a public route. |
| Bootstrap/control account | `ubuntu` | Ansible connects as this account from the designated operator/admin workstation. |
| Control node | Designated operator/admin workstation | The staging VM must not run Ansible against itself. |
| Host-key policy | Strict verification | Record the expected host key in the operator workstation's `known_hosts` before the first run. Do not disable host-key checking or use runtime `ssh-keyscan`. |
| Minimum controller | Ansible Core `2.16` | Use a supported newer release where available. |
| Required collections | `ansible.posix` | The existing `users` role uses `ansible.posix.authorized_key`; all new baseline tasks should prefer `ansible.builtin`. |

## Inventory groups

The VM belongs to these groups:

- `sample_staging`: dedicated desired state and staging-scoped playbooks.
- `ubuntu_hosts`: common Ubuntu guest targeting.
- `docker_hosts`: Docker engine baseline targeting.

It does not belong to `zabbix-agent2-hosts` until monitoring is explicitly approved.

## Account model

| Account | Purpose | SSH | Docker | Sudo | Key source |
| --- | --- | --- | --- | --- | --- |
| `ubuntu` | Initial/bootstrap and operator access | Key-only | No by default | Existing Ubuntu administrative access; scope must be reviewed before hardening | Designated operator workstation; not committed to inventory. |
| `developer` | Named human development account | Key-only | Yes; root-equivalent risk accepted for this dedicated VM | No by default | Reviewed individual developer public key, supplied out of band. |
| `sample-deploy` | GitHub Actions deployment identity | Key-only | No direct membership | `sudo /usr/local/sbin/sample-staging-deploy staging-<short-sha>` only | GitHub Environment-managed public key or equivalent approved deploy-key source. |

`developer` must not receive Tailnet administration, ACL editing, DNS administration, tag ownership, auth-key rotation, subnet-router, exit-node, PVE, or OPNsense permissions.

The exact UID/GID allocation and any account mutation must be reconciled with `docs/reference/uid-gid-allocation-policy.md` before adding these accounts to the managed user registry.

### Sudo privilege model

| Account | Initial sudo policy | Permitted scope | Explicit restrictions | Implementation notes |
| --- | --- | --- | --- | --- |
| `ubuntu` | Full administrative sudo retained during bootstrap. | Administrative host recovery and the Ansible `become` path from the designated operator workstation. | Do not remove or narrow this access until an independent key-only `ubuntu` session and Ansible `become` both work. Do not use it as the GitHub deployment identity. | Preserve the cloud-image account's existing sudo behavior initially. Prefer password-authenticated sudo where practical; allow `NOPASSWD` only when the reviewed automation path requires non-interactive privilege escalation. |
| `developer` | No sudo grant. | None through `/etc/sudoers` or the `sudo` group. | Must not receive `ALL`, `NOPASSWD: ALL`, package-manager, service-manager, editor, shell, or Tailscale administration permissions. | Docker-group membership remains root-equivalent: the account can control the Docker daemon and can therefore obtain host-root capability. “No sudo” is an audit and accidental-administration boundary, not an isolation boundary. |
| `sample-deploy` | One passwordless sudo command. | `sudo /usr/local/sbin/sample-staging-deploy staging-<short-sha>` only. | Never grant broad `ALL`, direct `docker`, `docker compose`, shell, package-manager, editor, or arbitrary `systemctl` commands. Do not add the account to the `docker` group. | The root-owned wrapper accepts only immutable hexadecimal staging tags, protects `.env.staging`, serializes releases, and avoids arbitrary command execution. |

Any sudoers entry must be written as a dedicated root-owned file under `/etc/sudoers.d/`, mode `0440`, and validated with `visudo -cf` before it is activated. Do not use wildcard command paths or writable wrapper locations.

## SSH desired state

| Variable | Value |
| --- | --- |
| `sample_staging_ssh_port` | `22` |
| `sample_staging_ssh_permit_root_login` | `no` |
| `sample_staging_ssh_password_authentication` | `no` |
| `sample_staging_ssh_pubkey_authentication` | `yes` |
| `sample_staging_ssh_allowed_users` | `ubuntu`, `developer`, `sample-deploy` |

Listen addresses, VM firewall policy, DNS, NTP, and reboot policy are intentionally deferred. OPNsense remains the primary network-enforcement owner; this reference does not authorize Ansible to change firewall policy.

## Docker and application paths

| Item | Desired value |
| --- | --- |
| Docker source | Docker CE from Docker's official apt repository. |
| Compose | Docker Compose plugin required; use the supported plugin packaged with Docker CE. |
| Application root | `/srv/sample-app` |
| Non-secret release state | `/srv/sample-app/.release-state` |
| Runtime environment file | `/srv/sample-app/.env.staging` |
| Fixed staging Compose file | `/srv/sample-app/docker-compose.staging.yml` |
| Constrained deployment wrapper | `/usr/local/sbin/sample-staging-deploy` |
| Deployment lock | `/run/lock/sample-staging-deploy.lock` |
| GHCR package-read token | Ignored controller source `secrets/sample-staging/ghcr-pull-token` (`0600`), copied to `/etc/sample-app/ghcr-pull-token` (`root:root`, `0600`) |
| Environment ownership/mode | `root:root`, `0600` |
| Persistent application data | Compose-managed named volumes, including `sample-staging-postgres-data`. |
| Application deployment owner | GitHub Actions, not Ansible. |

Ansible may install/configure Docker and establish host directories, but it must not deploy or restart `cloudflared`, `sample-app`, `postgres`, or migrations. This prevents conflict with the GitHub Actions release workflow.

## Temporary secret-file delivery

## Managed payload locations

The Ansible project has two distinct local payload trees:

| Tree | Git status | Purpose |
| --- | --- | --- |
| `ansible/infra-ops/files/` | Committed | Reviewed non-secret files copied to managed hosts. |
| `ansible/infra-ops/secrets/` | Ignored except `README.md` | Operator-supplied secret files copied with `no_log: true`. |

For the current staging baseline, the role copies the committed non-secret
`files/sample-staging/release-state` payload to `/srv/sample-app/.release-state`.
It copies the ignored local secret payload
`secrets/sample-staging/.env.staging` to `/srv/sample-app/.env.staging` as
`root:root` with mode `0600`.
It copies the ignored local GHCR package-read token
`secrets/sample-staging/ghcr-pull-token` to `/etc/sample-app/ghcr-pull-token` as
`root:root` with mode `0600`.

The ignored `secrets/sample-staging/access.yml` file stores the public-key
lists for the operator, developer, and deploy accounts. Create it by copying
the committed `files/sample-staging/access.yml.example` template, replacing
the placeholder values, and setting mode `0600`. The staging playbook loads it
automatically; normal playbook commands do not need `--extra-vars`.

Do not store `.env.staging`, credentials, private keys, passwords, tokens, or
generated host files beneath `files/`. Do not relocate runtime secrets to an
operator home-directory convention or provide the source path via environment
variables; the project-local ignored `secrets/` tree is the standard location.

- The source file is local, ignored, and never placed in inventory, group variables, documentation, terminal output, or Git history.
- The copy task must use `no_log: true`, `owner: root`, `group: root`, and `mode: '0600'`.
- `sample-deploy` must not read the file. CI invokes only the reviewed root-owned deployment wrapper with an immutable staging tag; the wrapper reads the protected file and host-local GHCR package-read token itself.
- Required secret names include `CLOUDFLARE_TUNNEL_TOKEN`, `POSTGRES_PASSWORD`, `DATABASE_URL`, `DIRECT_URL`, `AUTH_SECRET`, `SESSION_SECRET`, GHCR pull credentials if used, R2 credentials, Trigger.dev credentials, and enabled integration secrets.
- Rotate the file's contents immediately after suspected operator-workstation compromise, accidental disclosure, or unauthorized host access. Migrate to an external secret manager or encrypted secret workflow before this staging host carries sensitive data.

## Explicitly deferred ownership

Ansible currently does not install, enroll, update, or run `tailscale up`; it only may validate an already-enrolled node once a role is approved. Tailscale tags, auth keys, and tag changes remain outside this project.

Monitoring/Zabbix, host firewall rules, DNS resolvers, NTP sources, unattended upgrades, maintenance windows, reboot behavior, backup destinations, retention, encryption, and restore objectives are also deferred. Do not imply that this inventory configures them.
