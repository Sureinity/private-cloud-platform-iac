# Configure SampleApp production with Ansible

Use this procedure to apply approved host configuration to `sample-app-prod-01` (Azure production VM). It does not deploy the SampleApp application; GitHub Actions owns application releases.

## Prerequisites

- Run from the designated operator/admin workstation, never from the production VM.
- Use Ansible Core `2.16` or newer and install the `ansible.posix` collection used by the existing users role.
- Confirm `20.249.4.99` is reachable from the workstation.
- Ensure the Azure SSH private key is present at `ansible/infra-ops/secrets/sample-production/SampleApp_key948.pem` with permissions `0600`. This directory is ignored by Git; only its README is tracked.
- Record the VM SSH host key in the operator workstation's `~/.ssh/known_hosts` before running Ansible. Do not disable host-key checking.
- Keep the runtime secret source at `ansible/infra-ops/secrets/sample-production/.env.production`. Confirm the source file is mode `0600`.
- Ensure the application checkout and `/srv/sample-app/docker-compose.prod.yml` exist on the target host before applying. The role does not clone or update the application checkout.
- Create `ansible/infra-ops/secrets/sample-production/ghcr-pull-token` with a least-privilege GHCR package-read token and set it to `0600`. Ansible copies it with `no_log: true` to `/etc/sample-app/ghcr-pull-token` as `root:root` with mode `0600`.
- Non-secret files copied to hosts live under `ansible/infra-ops/files/`. The production release-state template is committed at `files/sample-production/release-state`.
- Place approved account public keys in `ansible/infra-ops/secrets/sample-production/access.yml` with mode `0600`. The tracked inventory defaults are intentionally empty, and the playbook refuses to harden SSH without this file.

## Prepare the controller

```bash
cd ansible/infra-ops
ansible-galaxy collection install -r requirements.yml
ansible-inventory --graph
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99
```

The first interactive SSH validation confirms that the host key and credentials work. Exit without changing the host.

## Inspect and dry-run

Use the production limit for every command. Run syntax checks before check mode:

```bash
cd ansible/infra-ops
ansible-playbook playbooks/sample-app.yml --syntax-check
ansible-playbook playbooks/sample-app.yml --check --diff --limit sample_production
```

Do not run the users role until UID/GID allocations have been audited and reconciled. Do not enable SSH hardening until a separate `azureuser` session has been independently verified.

The production baseline manages users, SSH, Docker, the protected runtime environment file, application directories, and release state.

## Apply approved host configuration

Apply only reviewed changes:

```bash
cd ansible/infra-ops
ansible-playbook playbooks/sample-app.yml --diff --limit sample_production
```

The baseline may install Docker CE, the Docker Compose plugin, create application directories, copy committed non-secret payloads (`release-state`), copy the ignored local `.env.production` file using `no_log: true`, and install the root-owned constrained deployment wrapper (`/usr/local/sbin/sample-app-prod-deploy`). It must not log secret contents, commit secret files, change firewall/DNS/NTP policy, enroll monitoring, or restart the SampleApp Compose stack during Ansible application.

The baseline validates and copies both ignored runtime secret payloads: `.env.production` and `ghcr-pull-token`. A missing or incorrectly protected controller-side token causes the playbook to stop before it changes the VM.

## Verify

Run only non-secret checks:

```bash
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99 'sudo sshd -t'
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99 'systemctl is-active docker'
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99 'docker --version && docker compose version'
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99 'sudo stat -c "%U:%G %a %n" /srv/sample-app/.env.production'
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99 'sudo stat -c "%U:%G %a %n" /usr/local/sbin/sample-app-prod-deploy /etc/sample-app/ghcr-pull-token'
ssh -i secrets/sample-production/SampleApp_key948.pem -o StrictHostKeyChecking=yes azureuser@20.249.4.99 'sudo -l -U sample-deploy'
```

Expected environment-file output is `root:root 600 /srv/sample-app/.env.production`. Do not print or inspect its content through Ansible, SSH history, CI logs, or screen sharing.

Expected wrapper and GHCR-token output is `root:root 755 /usr/local/sbin/sample-app-prod-deploy` and `root:root 600 /etc/sample-app/ghcr-pull-token`. The deploy account must have only the exact wrapper command through sudo; it must not be in the `docker` or `sudo` group and must not read `/srv/sample-app/.env.production`.

Once GitHub Actions deploys the stack, validate separately with the application repository's Compose commands and health endpoint.

## Rollback

Do not use a broad rollback playbook against the guest. Revert the smallest reviewed configuration change, preserving access first:

- If SSH access fails, use the cloud provider console or an already verified session; do not remove the only working access path.
- If Docker installation causes a problem, stop and inspect package/service state before removal. Do not destroy Compose volumes.
- If the environment file was copied incorrectly, replace it from `secrets/sample-production/.env.production` and recheck ownership/mode without exposing its contents.
- If the wrapper fails, keep CI access intact, inspect the root-owned wrapper, fixed Compose file, release-state metadata, Docker service, and non-secret service status. Revoke and replace the host-side GHCR token if it may have leaked.
- If a secret may have leaked, revoke/rotate it at the source service before re-copying the replacement file.

## Deferred work

VM firewall policy, DNS/NTP, monitoring enrollment, patch/reboot policy, backup configuration, and application deployments are separate decisions. Do not add them to this procedure without updating related reference documents.

## GitHub Actions release and rollback

The GitHub Actions `production` environment must use the `sample-deploy` SSH key, a pinned `DEPLOY_KNOWN_HOSTS` value, and calls only:

```bash
sudo /usr/local/sbin/sample-app-prod-deploy prod-<short-sha>
```

The wrapper validates the tag, obtains GHCR access from the root-only host credential, updates `/srv/sample-app/.release-state`, validates the fixed Compose configuration, and restarts the stack. It does not expose `.env.production` to CI.

To roll back, select a known-good previously published immutable `prod-<short-sha>` image tag and invoke the same wrapper from the approved operator path. Do not edit `.env.production`, run arbitrary Docker commands as `sample-deploy`, or replace the Compose path during rollback.
