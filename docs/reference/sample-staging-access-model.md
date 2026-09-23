# SampleApp staging access model

This reference defines the current access boundary for `sample-staging-01`. It complements the provisioning design in [Provision an isolated SampleApp staging VM](../how-to/provision-developer-isolated-staging-vm.md).

## Tailnet boundary

The VM is reached over Tailscale at `198.51.100.100`. It is currently tagged `tag:sample-app-hosts`; the existing provisioning guide records the tag owner and current ACL state as of August 22, 2026.

- Human developers use individual Tailnet identities and must satisfy MFA and device-approval requirements.
- GitHub Actions uses a short-lived Tailnet identity for deployment access; it must not reuse a developer identity.
- Neither the developer nor CI identity may administer the Tailnet, change tags, rotate auth keys, advertise subnet routes, use an exit node, access PVE/OPNsense, or reach unrelated Tailnet devices.
- Tailscale enrollment, `tailscale up` flags, version policy, Tailscale SSH, tag changes, and auth-key rotation are out of scope for Ansible at this stage.

## Local account and SSH model

SSH is key-only and restricted with `AllowUsers` to `ubuntu`, `developer`, and `sample-deploy`. Root login and password authentication are disabled when the SSH hardening role is introduced and an independent `ubuntu` recovery session is verified.

- **`ubuntu`** is the bootstrap/operator account used by the designated operator workstation.
- **`developer`** is the human account and has Docker-group membership. Docker access is root-equivalent on the VM and is accepted only because this is a dedicated, segmented staging guest.
- **`sample-deploy`** is reserved for GitHub Actions. It must be distinct from `developer` and should receive only a reviewed constrained deployment command, not broad sudo or direct access to runtime secrets.
- SSH public keys are owned by their respective human/operator or GitHub Environment deployment identity. Keys are supplied outside tracked Ansible variables.

The operator workstation pins the VM's expected SSH host key in `known_hosts`. Host-key verification must stay enabled; do not use per-run host-key discovery.

### Sudo privileges

| Account | Sudo policy | Technical boundary |
| --- | --- | --- |
| `ubuntu` | Full administrative `NOPASSWD` sudo for approved staging automation. | It is the recovery and Ansible `become` account. The designated controller authenticates with its pinned operator key and needs non-interactive escalation for this key-only playbook. Keep the scope limited to this dedicated staging VM and review the exception when its automation model changes. |
| `developer` | Receives no sudo access. | The account must not be in the `sudo` group or receive a sudoers rule. Its Docker membership is nevertheless root-equivalent, so this policy prevents routine/accidental administration but does not contain a hostile developer account. |
| `sample-deploy` | Receives no sudo access at bootstrap. | It must not join `sudo` or `docker`. A later reviewed sudoers rule may allow only one root-owned, non-writable deployment wrapper by absolute path; it must not authorize arbitrary Docker, shell, package, editor, or service-management commands. |

Every future sudoers file must be root-owned with mode `0440` under `/etc/sudoers.d/` and pass `visudo -cf` validation before activation. Never use wildcard command rules or a wrapper path writable by `developer` or `sample-deploy`.

## Onboarding and review

1. Confirm the person has an approved individual Tailnet identity, MFA, and device approval.
2. Review the requested local account and SSH public key out of band.
3. Reconcile the account's UID/GID in the On-Premises PVE registry before creating it.
4. Add the key and account through the users role, then verify key-only login from the approved device.
5. For `developer`, explicitly record acceptance of Docker's root-equivalent risk.

Review Tailnet membership, SSH keys, developer Docker access, GitHub Environment deploy keys, and deployment permissions every quarter. Rotate SSH keys at least annually and immediately after device loss, suspected compromise, or personnel change.

## Offboarding and emergency revocation

For ordinary offboarding, remove the SSH key and local account access first, then revoke Tailnet group/device access and GitHub Environment permissions. Remove Docker access with the account; do not leave abandoned group membership.

For an emergency, immediately disable/remove the affected Tailnet identity or CI credential, lock the affected local account, revoke GitHub deployment authorization, and rotate any secrets that may have been reachable from the account or operator workstation. Investigate GitHub, Tailnet, SSH, and Docker activity before restoring access.

## Deferred controls

OPNsense is the primary network-enforcement owner. VM-local firewall controls, DNS/NTP, monitoring, backup design, and patch/reboot policy have not been approved for Ansible management and must not be inferred from this access model.

## GitHub Actions deployment boundary

`sample-deploy` is a non-interactive GitHub Actions SSH identity. It must not
have direct access to `/srv/sample-app`, `.env.staging`, the host-side GHCR token,
or Docker's Unix socket. Those permissions would expose runtime secrets or make
the CI account root-equivalent on the VM.

The only deployment privilege is the exact command below, authorized through a
root-owned mode-`0440` sudoers file validated with `visudo -cf`:

```text
sudo /usr/local/sbin/sample-staging-deploy staging-<immutable-short-sha>
```

The root-owned wrapper accepts only lower-case hexadecimal immutable staging
tags (`staging-` followed by 7 to 64 hexadecimal characters). It uses a lock to
serialize releases, writes only non-secret release metadata to
`/srv/sample-app/.release-state`, validates the fixed
`/srv/sample-app/docker-compose.staging.yml` configuration, pulls `sample-app`,
and starts the fixed staging stack. It does not accept a caller-selected path,
Compose file, environment file, registry, service, or arbitrary command.

The operator stores the GHCR package-read token in the ignored controller-side
file `ansible/infra-ops/secrets/sample-staging/ghcr-pull-token`, mode
`0600`. Ansible copies it with `no_log: true` to
`/etc/sample-app/ghcr-pull-token` as `root:root` with mode `0600`. Do not send it
through GitHub Actions, place it in Ansible inventory, commit it, or print it
in logs. GitHub Actions passes only the reviewed immutable image tag.

For emergency revocation, remove the GitHub Environment deploy key or disable
`sample-deploy`, revoke the Tailscale CI identity, and remove the sudoers file
if necessary. To restore the previous release, invoke the same wrapper with a
previously published immutable `staging-<short-sha>` tag.
