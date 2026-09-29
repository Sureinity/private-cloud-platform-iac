# Ansible inventory variable ownership reference

This reference documents the ownership of all inventory variables across the repository. It maps each variable found in `ansible/infra-ops/inventory/` and `ansible/opnsense-ops/inventory/` to its authoritative owning role, playbook, or Ansible Core connection plugin.

Related:
- [SampleApp staging Ansible variables](sample-staging-ansible-variables.md)
- [SampleApp production Ansible variables](sample-production-ansible-variables.md)
- [UID/GID allocation policy](uid-gid-allocation-policy.md)
- [Infrastructure Ansible operations](../how-to/infrastructure-ansible-operations.md)

## Variable ownership principles

1. **Role scoping:** Variables configured in `inventory/group_vars/` or `inventory/hosts.yml` must clearly belong to a specific role, a dedicated operational playbook, or Ansible Core.
2. **Explicit demarcation:** When an inventory file configures multiple roles for a single host group (such as `sample_staging.yml` or `sample_production.yml`), variables are grouped into distinct, commented sections identified by `# Role: <role_path>`.
3. **Prefix conventions:** Where roles declare distinct prefixes (e.g., `seaweedfs_*`, `zabbix_*`, `docker_*`, `sample_app_*`, `ssh_*`), variable names reflect the owning role. Cross-cutting variables (e.g., `managed_users`) belong to the managing role (`roles/users`) and are documented as such.
4. **Ansible Core connection variables:** Built-in connection keys (`ansible_host`, `ansible_user`, `ansible_ssh_private_key_file`, `ansible_connection`) belong to Ansible Core (`ansible.builtin` connection plugins), not custom roles.

---

## Master inventory variable ownership matrix

| Variable name | Inventory definition location | Owning entity | Role defaults location | Purpose |
| --- | --- | --- | --- | --- |
| `ansible_host` | `inventory/hosts.yml` | Ansible Core (`ansible.builtin`) | N/A (Core) | Target host IP address or hostname for SSH / connection transport |
| `ansible_user` | `inventory/hosts.yml` | Ansible Core (`ansible.builtin`) | N/A (Core) | Remote login user account for SSH connection |
| `ansible_ssh_private_key_file` | `inventory/hosts.yml` | Ansible Core (`ansible.builtin`) | N/A (Core) | Path to SSH private key used for authentication |
| `ansible_connection` | `opnsense-ops/inventory/hosts.example.yml` | Ansible Core (`ansible.builtin`) | N/A (Core) | Transport plugin type (e.g. `local` for localhost execution) |
| `managed_users` | `group_vars/all/users.yml`, `group_vars/sample-app_*.yml` | `roles/users` | `roles/users/defaults/main.yml` | List of managed system user accounts, groups, shells, sudo privileges, and SSH keys |
| `uid_registry` | `group_vars/all/uid_registry.yml` | `roles/users` | `roles/users/defaults/main.yml` | Authoritative mapping of account names to static UID/GID numbers |
| `gid_registry` | `group_vars/all/uid_registry.yml` | `roles/users` | `roles/users/defaults/main.yml` | Mapping of shared group names to static GID allocations |
| `ssh_port` | `group_vars/all/ssh.yml`, `group_vars/sample-app_*.yml` | `roles/ssh` | `roles/ssh/defaults/main.yml` | SSH daemon listening port (default `22`) |
| `ssh_permit_root_login` | `group_vars/all/ssh.yml`, `group_vars/sample-app_*.yml` | `roles/ssh` | `roles/ssh/defaults/main.yml` | Hardening toggle for SSH root login (`"no"`) |
| `ssh_password_authentication` | `group_vars/all/ssh.yml`, `group_vars/sample-app_*.yml` | `roles/ssh` | `roles/ssh/defaults/main.yml` | Hardening toggle for password authentication (`"no"`) |
| `ssh_pubkey_authentication` | `group_vars/all/ssh.yml`, `group_vars/sample-app_*.yml` | `roles/ssh` | `roles/ssh/defaults/main.yml` | Hardening toggle for public key authentication (`"yes"`) |
| `ssh_allowed_users` | `group_vars/all/ssh.yml`, `group_vars/sample-app_*.yml` | `roles/ssh` | `roles/ssh/defaults/main.yml` | List of usernames permitted to log in via SSH |
| `ssh_known_hosts_file` | `group_vars/sample_staging.yml` | `roles/ssh` / Operator verification | N/A (Operator) | Path to known hosts verification file |
| `docker_source` | `group_vars/sample_staging.yml` | `roles/docker` | `roles/docker/defaults/main.yml` | Package source for Docker (`ubuntu` or `docker-ce`) |
| `docker_compose_plugin_required` | `group_vars/sample-app_*.yml` | `roles/docker` | `roles/docker/defaults/main.yml` | Assertion requirement for Docker Compose plugin |
| `docker_daemon_config` | `group_vars/sample_staging.yml` | `roles/docker` | `roles/docker/defaults/main.yml` | JSON configuration dictionary applied to `/etc/docker/daemon.json` |
| `seaweedfs_data_device` | `group_vars/seaweedfs_hosts.yml` | `roles/seaweedfs` | `roles/seaweedfs/defaults/main.yml` | Dedicated block storage device path (e.g. `/dev/sdb`) |
| `seaweedfs_data_mount_point` | `group_vars/seaweedfs_hosts.yml` | `roles/seaweedfs` | `roles/seaweedfs/defaults/main.yml` | Mount point path for SeaweedFS persistent storage (`/srv/seaweedfs`) |
| `seaweedfs_tls_enabled` | `group_vars/seaweedfs_hosts.yml` | `roles/seaweedfs` | `roles/seaweedfs/defaults/main.yml` | TLS enablement toggle for S3 API endpoints |
| `seaweedfs_s3_enable_http` | `group_vars/seaweedfs_hosts.yml` | `roles/seaweedfs` | `roles/seaweedfs/defaults/main.yml` | Plaintext HTTP S3 endpoint toggle (`false`) |
| `seaweedfs_s3_port_https` | `group_vars/seaweedfs_hosts.yml` | `roles/seaweedfs` | `roles/seaweedfs/defaults/main.yml` | HTTPS port for SeaweedFS S3 endpoint (`8334`) |
| `seaweedfs_endpoint_hostname` | `group_vars/seaweedfs_hosts.yml` | `roles/seaweedfs` | `roles/seaweedfs/defaults/main.yml` | FQDN for SeaweedFS S3 endpoint (`seaweedfs.example.invalid`) |
| `zabbix_server_address` | `group_vars/zabbix_agent2_hosts.yml` | `roles/zabbix_agent2` | `roles/zabbix_agent2/defaults/main.yml` | Central Zabbix server or proxy IP address |
| `zabbix_agent_hostname` | `group_vars/zabbix_agent2_hosts.yml` | `roles/zabbix_agent2` | `roles/zabbix_agent2/defaults/main.yml` | Monitored hostname string registered in Zabbix |
| `zabbix_agent2_enable_active_check` | `group_vars/zabbix_agent2_hosts.yml` | `roles/zabbix_agent2` | `roles/zabbix_agent2/defaults/main.yml` | Active check listener toggle (`true`) |
| `zabbix_agent2_enable_passive_check` | `group_vars/zabbix_agent2_hosts.yml` | `roles/zabbix_agent2` | `roles/zabbix_agent2/defaults/main.yml` | Passive check listener toggle (`false`) |
| `zabbix_agent2_supported_distributions` | `group_vars/zabbix_agent2_hosts.yml` | `roles/zabbix_agent2` | `roles/zabbix_agent2/defaults/main.yml` | Permitted Linux distributions for agent deployment |
| `sample_app_environment` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Target environment identifier (`sample-staging`, `sample-production`) |
| `sample_app_inventory_hostname` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Hostname identifier for the sample-app guest |
| `sample_app_accounts` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Account dictionary (`operator`, `developer`, `deploy`) |
| `sample_app_application_root` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Host filesystem directory for application assets (`/srv/sample-app`) |
| `sample_app_release_state_path` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Release marker file path on target host |
| `sample_app_env_file` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Target host environment variable file path |
| `sample_app_environment_owner` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | POSIX user owner for environment files (`root`) |
| `sample_app_environment_group` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | POSIX group owner for environment files (`root`) |
| `sample_app_environment_mode` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | POSIX permission mode for environment files (`0600`) |
| `sample_app_compose_file` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Target compose file location |
| `sample_app_deploy_wrapper_path` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Target executable path for the deploy script |
| `sample_app_deploy_sudoers_path` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Path for sudoers rule granting execution to deploy account |
| `sample_app_deployment_lock_path` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Concurrency lock file path |
| `sample_app_image_repository` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Target GHCR container image repository |
| `sample_app_deploy_image_tag_pattern` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Validation regex pattern for immutable deploy image tags |
| `sample_app_ghcr_username` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | GHCR credentials service username |
| `sample_app_ghcr_credentials_path` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Target host token file path (`/etc/sample-app/ghcr-pull-token`) |
| `sample_app_files_root` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Controller path to committed non-secret files tree |
| `sample_app_secrets_root` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Controller path to ignored secrets tree |
| `sample_app_release_state_source_path` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Controller source file for release-state |
| `sample_app_env_source_path` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Controller source path for `.env.*` payload |
| `sample_app_ghcr_credentials_source_path` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Controller source path for GHCR pull token |
| `sample_app_tailscale_hostname` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Expected Tailscale node hostname |
| `sample_app_tailscale_service_name` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Systemd service name for Tailscale (`tailscaled`) |
| `sample_app_tailscale_verify_command` | `group_vars/sample_staging.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Verification command executed to confirm node registration |
| `sample_app_verify_tailscale` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Assertion toggle to verify Tailscale enrollment |
| `sample_app_ansible_manages_*` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Boundary assertion flags (DNS, firewall, NTP, deployment, reboot) |
| `sample_app_monitoring_enabled` | `group_vars/sample-app_*.yml` | `roles/sample_app` | `roles/sample_app/defaults/main.yml` | Boundary assertion flag for Zabbix monitoring inclusion |
| `sample_app_*_ssh_public_keys` | `group_vars/sample-app_*.yml` | `roles/local_secrets` / `roles/users` | N/A (Secrets payload) | Public keys loaded via `local_secrets` and passed to `managed_users` |
| `opnsense_api_url` | `opnsense-ops/inventory/hosts.example.yml` | OPNsense Playbooks | N/A (Playbooks) | URL of the OPNsense REST API endpoint |
| `opnsense_validate_certs` | `opnsense-ops/inventory/hosts.example.yml` | OPNsense Playbooks | N/A (Playbooks) | TLS certificate validation toggle for OPNsense Web GUI API |
| `opnsense_api_key` | `opnsense-ops/inventory/group_vars/opnsense.yml` | OPNsense Playbooks | N/A (Playbooks) | API key credential for OPNsense operations |
| `opnsense_api_secret` | `opnsense-ops/inventory/group_vars/opnsense.yml` | OPNsense Playbooks | N/A (Playbooks) | API secret credential for OPNsense operations |
| `opnsense_backup_dir` | `opnsense-ops/inventory/group_vars/all.yml` | `playbooks/backup-config.yml` | N/A (Playbook) | Local target directory for exported OPNsense backup XMLs |
| `opnsense_api_timeout` | `opnsense-ops/inventory/group_vars/all.yml` | OPNsense Playbooks | N/A (Playbooks) | HTTP client timeout in seconds for OPNsense API calls |

---

## Detailed role breakdown

### `roles/users`
- **Location:** `ansible/infra-ops/roles/users/`
- **Purpose:** User account lifecycle, UID/GID allocation enforcement, sudo privilege configuration, and authorized SSH key provisioning.
- **Inventory sources:**
  - `ansible/infra-ops/inventory/group_vars/all/users.yml`: baseline `managed_users` (e.g. `ansible` automation account).
  - `ansible/infra-ops/inventory/group_vars/all/uid_registry.yml`: central `uid_registry` and `gid_registry`.
  - `ansible/infra-ops/inventory/group_vars/sample_staging.yml`: host-specific `managed_users` for staging accounts (`ubuntu`, `developer`, `sample-deploy`).
  - `ansible/infra-ops/inventory/group_vars/sample_production.yml`: host-specific `managed_users` for production accounts (`azureuser`, `developer`, `sample-deploy`).

### `roles/ssh`
- **Location:** `ansible/infra-ops/roles/ssh/`
- **Purpose:** SSH daemon configuration hardening (`sshd_config`) across all managed nodes.
- **Inventory sources:**
  - `ansible/infra-ops/inventory/group_vars/all/ssh.yml`: global baseline configuration (`ssh_port`, `ssh_permit_root_login`, `ssh_password_authentication`, `ssh_pubkey_authentication`, `ssh_allowed_users`).
  - `ansible/infra-ops/inventory/group_vars/sample_staging.yml`: environment-specific `ssh_allowed_users` and `ssh_known_hosts_file`.
  - `ansible/infra-ops/inventory/group_vars/sample_production.yml`: environment-specific `ssh_allowed_users`.

### `roles/docker`
- **Location:** `ansible/infra-ops/roles/docker/`
- **Purpose:** Docker engine, CLI, plugins, and daemon logging configuration.
- **Inventory sources:**
  - `ansible/infra-ops/inventory/group_vars/sample_staging.yml`: `docker_source`, `docker_compose_plugin_required`, `docker_daemon_config`.
  - `ansible/infra-ops/inventory/group_vars/sample_production.yml`: `docker_compose_plugin_required`.

### `roles/sample_app`
- **Location:** `ansible/infra-ops/roles/sample_app/`
- **Purpose:** SampleApp application host prerequisites, release directories, deployment wrappers, sudoers grants, and boundary assertions.
- **Inventory sources:**
  - `ansible/infra-ops/inventory/group_vars/sample_staging.yml`: staging-specific application paths, locks, wrapper configs, and boundary flags.
  - `ansible/infra-ops/inventory/group_vars/sample_production.yml`: production-specific application paths, locks, wrapper configs, and boundary flags.

### `roles/seaweedfs`
- **Location:** `ansible/infra-ops/roles/seaweedfs/`
- **Purpose:** SeaweedFS cluster service provisioning, persistent disk mounting, S3 endpoint configuration, and ACME TLS.
- **Inventory sources:**
  - `ansible/infra-ops/inventory/group_vars/seaweedfs_hosts.yml`: `seaweedfs_data_device`, `seaweedfs_data_mount_point`, `seaweedfs_tls_enabled`, `seaweedfs_s3_enable_http`, `seaweedfs_s3_port_https`, `seaweedfs_endpoint_hostname`.

### `roles/zabbix_agent2`
- **Location:** `ansible/infra-ops/roles/zabbix_agent2/`
- **Purpose:** Zabbix Agent 2 monitoring installation and active/passive agent configuration.
- **Inventory sources:**
  - `ansible/infra-ops/inventory/group_vars/zabbix_agent2_hosts.yml`: `zabbix_server_address`, `zabbix_agent_hostname`, `zabbix_agent2_enable_active_check`, `zabbix_agent2_enable_passive_check`, `zabbix_agent2_supported_distributions`.
