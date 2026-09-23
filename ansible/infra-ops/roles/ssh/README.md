# SSH Role

This Ansible role configures the OpenSSH server (`sshd`) on target hosts to enforce secure access policies. It is designed to be idempotent and safe to run across the `onprem-pve` infrastructure.

## Scope and Intent

The primary objective of this role is to harden SSH access by:
- Disabling root login.
- Disabling password authentication (forcing key-based authentication).
- Managing authorized keys for administrative users.
- Ensuring the SSH service is enabled and running.

## Reference

### Target Hosts
This role can be applied to both Proxmox VE hosts and guest VMs (Debian/Ubuntu/AlmaLinux/etc.).

### Role Variables

Variables should be defined in `defaults/main.yml` and can be overridden in `inventory/group_vars` or `inventory/host_vars`.

| Variable | Default | Description |
|---|---|---|
| `ssh_port` | `22` | The port on which the SSH server listens. |
| `ssh_permit_root_login` | `no` | Whether root can log in using SSH. |
| `ssh_password_authentication` | `no` | Whether password authentication is allowed. |
| `ssh_pubkey_authentication` | `yes` | Whether public key authentication is allowed. |
| `ssh_allowed_users` | `[]` | List of users allowed to connect via SSH. |

### Verification Commands

After the playbook runs, you can verify the configuration using:

```bash
# Check SSH daemon syntax
sshd -t

# Check SSH service status
systemctl status sshd
```

## How-to Guides

### Developing and Modifying this Role

1. **Adding new SSH configuration options**: Update `defaults/main.yml` with the new variable and a safe default. Then, add the configuration line to the `sshd_config` template or task (e.g., using `ansible.builtin.lineinfile` or a `template`).
2. **Testing Changes**: Run the playbook with `--check --diff` before applying changes to live hosts to verify the `sshd_config` modifications.
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/configure_ssh.yml --check --diff
   ```

### Idempotency Expectations

This role must be fully idempotent. Running it multiple times on the same host should not result in changes after the first successful run. Ensure that any `lineinfile` or `template` tasks accurately reflect the desired state without adding duplicate entries.

## Explanation

We enforce key-based authentication and disable root login to minimize the risk of brute-force attacks and unauthorized access. Hardening the SSH configuration is the first line of defense for both the Proxmox hosts and the guest VMs in the environment.
