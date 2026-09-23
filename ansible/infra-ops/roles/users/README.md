# Users Role

This Ansible role manages user accounts, their SSH public keys, and sudo privileges on target hosts. It ensures that required administrative and service accounts are present and configured correctly across the `onprem-pve` infrastructure, with numeric identity pinned from a central registry.

## Scope and Intent

The primary objective of this role is to:
- Create, modify, or remove user accounts with pinned UIDs and GIDs.
- Distribute authorized SSH public keys to the corresponding users.
- Configure `sudo` access where appropriate.
- Enforce the repository UID and GID allocation policy before mutating any host.

This role is the only supported path for creating accounts in this project. Numeric identity comes from `inventory/group_vars/all/uid_registry.yml`, never from `useradd` defaults.

Related documentation:
- [UID and GID allocation policy](../../../../docs/reference/uid-gid-allocation-policy.md) for ranges and rules.
- [Manage UID and GID allocations](../../../../docs/how-to/manage-uid-allocations.md) for allocation, audit, and offboarding.
- [UID collision failure modes](../../../../docs/explanation/uid-collision-failure-modes.md) for the reasoning.

## Reference

### Target Hosts

This role can be applied to both Proxmox VE hosts and guest VMs (Debian/Ubuntu/AlmaLinux/etc.).

### Ordering constraint

This role must run before the `ssh` role on any host.

The `ssh` role disables password authentication and root login. If it applies before this role has created a working account with a valid key, the host becomes unreachable. On `pve`, where Ansible connects as `root`, root login must stay enabled until an operator has verified an independent session as the managed administrative account. Do not create that account and disable root login in the same run.

### Role Variables

Variables should be defined in `defaults/main.yml` and can be overridden in `inventory/group_vars` or `inventory/host_vars`.

| Variable | Default | Description |
|---|---|---|
| `managed_users` | one `ansible` entry | List of dictionaries defining account shape. Carries no numbers. |
| `users_sudo_group` | `sudo`, or `wheel` on RedHat | Group that grants sudo privileges, selected from `ansible_os_family`. |
| `users_manage_authorized_keys` | `true` | Whether the role manages `authorized_keys` for managed accounts. |
| `users_manage_sudo` | `true` | Whether the role manages group membership and `/etc/sudoers.d` entries. |
| `users_authorized_keys_exclusive` | `false` | Whether to remove keys not declared here. Audit existing keys before enabling. |
| `users_uid_range_human` | `[2000, 2999]` | Allowed UID range for `class: human`. |
| `users_uid_range_service` | `[3000, 3999]` | Allowed UID range for `class: service`. |
| `users_gid_range_shared` | `[4000, 4999]` | Allowed GID range for shared groups. |
| `uid_registry` | `{}` | Numeric identity, supplied by `inventory/group_vars/all/uid_registry.yml`. |
| `gid_registry` | `{}` | Shared group IDs, supplied by the same file. |

### `managed_users` entry keys

| Key | Default | Description |
|---|---|---|
| `name` | required | Account name. Must match a `uid_registry` key. |
| `state` | `present` | `present` or `absent`. |
| `shell` | `/bin/bash` | Login shell. |
| `home` | `/home/<name>` | Home directory. |
| `groups` | `[]` | Supplementary groups, appended. |
| `sudo` | `false` | Whether to grant sudo through `users_sudo_group`. |
| `sudo_nopasswd` | `false` | Whether the sudoers entry is `NOPASSWD`. |
| `authorized_keys` | `[]` | List of public key strings. |

### Enforcement

The role runs a guard prelude before any mutation. Every check is a hard failure.

| Check | Fails when |
|---|---|
| Registry presence | `uid_registry` is empty or undefined. |
| Duplicate UID | Two registry entries resolve to the same UID. |
| Duplicate GID | Two entries across both registries resolve to the same GID. |
| Registry completeness | A `managed_users` entry has no complete registry entry. |
| Range conformance | An allocation falls outside its class range, or `gid` does not equal `uid`. |
| Shared group range | A `gid_registry` entry falls outside the shared range. |
| Retirement consistency | An entry marked `retired: true` is declared present. |
| Connection account protection | The account named by `ansible_user` is declared absent. |
| Live UID immutability | An existing account's UID on the host differs from the registry. |

The last two prevent lockout and ownership loss respectively. Neither is recoverable by rerunning the role.

### Verification Commands

After the playbook runs, you can verify the configuration using:

```bash
# Check account identity, including pinned uid and gid
id <username>

# Confirm the numbers match the registry
getent passwd <username>
getent group <username>

# Verify sudo privileges
sudo -l -U <username>

# Check authorized keys
cat ~<username>/.ssh/authorized_keys
```

## How-to Guides

### Developing and Modifying this Role

1. **Adding new users**: Allocate the number in `inventory/group_vars/all/uid_registry.yml` first, then declare the shape in `managed_users`.

   ```yaml
   # inventory/group_vars/all/uid_registry.yml
   uid_registry:
     admin:
       uid: 2001
       gid: 2001
       class: human
       description: Operator account.
   ```

   ```yaml
   # managed_users entry
   managed_users:
     - name: admin
       state: present
       groups: []
       sudo: true
       authorized_keys:
         - "ssh-ed25519 AAAAC3NzaC1l... user@machine"
   ```

   The role fails if the registry entry is missing, so the two cannot drift apart silently.

2. **Testing Changes**: Run with `--check --diff` before applying to live hosts.

   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff --limit <host>
   ```

3. **Testing the guards**: Temporarily set a registry UID to 1000 and confirm the run fails at the range assert rather than colliding with the cloud image account.

### Idempotency Expectations

This role must be fully idempotent. Running it multiple times on the same host should not result in changes after the first successful run. Account names, pinned UIDs and GIDs, group membership, `authorized_keys`, and sudoers entries must match the defined state exactly.

Accounts declared `absent` are removed with `remove: false`, so home directories survive. Identify and reassign owned files before offboarding; see the how-to guide.

## Explanation

Managing users centrally via Ansible ensures that authentication and authorization are consistent across the entire infrastructure. It eliminates configuration drift and allows for immediate revocation of access by removing a user from the variables list and re-running the playbook.

Numeric identity is pinned separately from account shape because the filesystem enforces numbers, not names. `rsync -a`, `vzdump`, Proxmox Backup Server restores, NFS, and Docker bind mounts all preserve the UID and discard the name. An account that receives a different number on each host produces ownership that silently changes meaning whenever data crosses a host boundary. Splitting the registry from `managed_users` lets the role assert that every account resolves to one deliberate, recorded number before it touches a host.
