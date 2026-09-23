# Configure SampleApp staging with Ansible

Use this procedure to apply approved host configuration to `sample-staging-01`. It does not deploy the SampleApp application; GitHub Actions owns application releases.

Related: [Configure SampleApp production with Ansible](configure-sample-production-with-ansible.md), [SampleApp staging Ansible variables](../reference/sample-staging-ansible-variables.md), and [SampleApp production Ansible variables](../reference/sample-production-ansible-variables.md).

## Prerequisites

- Run from the designated operator/admin workstation, never from the staging VM.
- Use Ansible Core `2.16` or newer and install the `ansible.posix` collection used by the existing users role.
- Confirm `198.51.100.100` is the intended Tailnet address and the workstation can reach it.
- Record the VM SSH host key in the operator workstation's `~/.ssh/known_hosts` before running Ansible. Do not disable host-key checking.
- Keep the runtime secret source at `ansible/infra-ops/secrets/sample-staging/.env.staging`. This directory is ignored by Git; only its README is tracked.
- Confirm the source file is `0600`, contains no production secrets unless specifically approved, and is not copied into `ansible/infra-ops/files/`.
- Ensure the application checkout and `/srv/sample-app/docker-compose.staging.yml` exist before applying. The role does not clone or update the application checkout.
- Create `ansible/infra-ops/secrets/sample-staging/ghcr-pull-token` with a least-privilege GHCR package-read token and set it to `0600`. Ansible copies it with `no_log: true` to `/etc/sample-app/ghcr-pull-token` as `root:root` with mode `0600`. Do not place the token in GitHub Environment secrets, inventory, or this repository.
- Store non-secret files copied to hosts under `ansible/infra-ops/files/`. The staging release-state template is committed at `files/sample-staging/release-state`.
- Copy `ansible/infra-ops/files/sample-staging/access.yml.example` to `ansible/infra-ops/secrets/sample-staging/access.yml`, replace its public-key values, and set it to `0600`. The tracked inventory defaults are intentionally empty, and the playbook refuses to harden SSH without this file.

## Prepare the controller

```bash
cd ansible/infra-ops
ansible-galaxy collection install ansible.posix
ansible-inventory --graph
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100
```

The first interactive SSH validation confirms that the pinned host key works. Exit without changing the host.

## Inspect and dry-run

Use the staging limit for every command. Run syntax checks before check mode:

```bash
cd ansible/infra-ops
ansible-playbook playbooks/users.yml --syntax-check
ansible-playbook playbooks/users.yml --check --diff --limit sample_staging
```

Do not run the users role until UID/GID allocations for `ubuntu`, `developer`, and `sample-deploy` have been audited and added to the registry. Do not enable SSH hardening until a separate `ubuntu` session has been independently verified.

The staging baseline playbook is implemented. It manages users, SSH, Docker,
the protected runtime environment file, application directories, and
non-mutating Tailscale verification. Use the same sequence:

```bash
ansible-playbook playbooks/sample-app.yml --syntax-check
ansible-playbook playbooks/sample-app.yml --check --diff --limit sample_staging
```

## Apply approved host configuration

Apply only reviewed changes:

```bash
cd ansible/infra-ops
ansible-playbook playbooks/sample-app.yml --diff --limit sample_staging
```

The baseline may install Docker CE, the Docker Compose plugin, application directories, copy committed non-secret payloads, copy the ignored local `.env.staging` file using `no_log: true`, and install the root-owned constrained deployment wrapper. It must not log secret contents, commit the secret file, call `tailscale up`, change firewall/DNS/NTP/reboot policy, enroll monitoring, or deploy/restart the SampleApp Compose stack during Ansible application.

The baseline validates and copies both ignored runtime secret payloads: `.env.staging`
and `ghcr-pull-token`. A missing or incorrectly protected controller-side token
causes the playbook to stop before it changes the VM.

## Verify

Run only non-secret checks:

```bash
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100 'sudo sshd -t'
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100 'systemctl is-active docker'
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100 'docker --version && docker compose version'
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100 'sudo stat -c "%U:%G %a %n" /srv/sample-app/.env.staging'
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100 'sudo stat -c "%U:%G %a %n" /usr/local/sbin/sample-staging-deploy /etc/sample-app/ghcr-pull-token'
ssh -o StrictHostKeyChecking=yes ubuntu@198.51.100.100 'sudo -l -U sample-deploy'
```

Expected environment-file output is `root:root 600 /srv/sample-app/.env.staging`. Do not print or inspect its content through Ansible, SSH history, CI logs, or screen sharing.

Expected wrapper and GHCR-token output is `root:root 755 /usr/local/sbin/sample-staging-deploy` and `root:root 600 /etc/sample-app/ghcr-pull-token`. The deploy account must have only the exact wrapper command through sudo; it must not be in the `docker` or `sudo` group and must not read `/srv/sample-app/.env.staging`.

Once GitHub Actions deploys the stack, validate separately with the application repository's Compose commands and `https://sample-staging.novaryn.tech/api/health`.

## Rollback

Do not use a broad rollback playbook against the guest. Revert the smallest reviewed configuration change, preserving access first:

- If SSH access fails, use the PVE console or an already verified `ubuntu` session; do not remove the only working access path.
- If Docker installation causes a problem, stop and inspect package/service state before removal. Do not destroy Compose volumes.
- If the environment file was copied incorrectly, replace it from `secrets/sample-staging/.env.staging` and recheck ownership/mode without exposing its contents.
- If the wrapper fails, keep CI access intact, inspect the root-owned wrapper, fixed Compose file, release-state metadata, Docker service, and non-secret service status. Revoke and replace the host-side GHCR token if it may have leaked.
- If a secret may have leaked, revoke/rotate it at the source service before re-copying the replacement file.

## Deferred work

Tailscale enrollment and policy, VM firewall policy, DNS/NTP, monitoring, patch/reboot policy, backup configuration, and application deployments are separate decisions. Do not add them to this procedure without updating the related reference documents and the staging provisioning guide.

## GitHub Actions release and rollback

The GitHub Actions `staging` environment must use the `sample-deploy` SSH key,
a pinned `DEPLOY_KNOWN_HOSTS` value, and the dedicated staging Tailnet identity.
It calls only:

```bash
sudo /usr/local/sbin/sample-staging-deploy staging-<short-sha>
```

The wrapper validates the tag, obtains GHCR access from the root-only host
credential, updates `/srv/sample-app/.release-state`, validates the fixed Compose
configuration, and restarts the stack. It does not expose `.env.staging` to CI.

To roll back, select a known-good previously published immutable
`staging-<short-sha>` image tag and invoke the same wrapper from the approved
operator path. Do not edit `.env.staging`, run arbitrary Docker commands as
`sample-deploy`, or replace the Compose path during rollback.
