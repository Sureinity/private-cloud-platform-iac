# Manage UID and GID allocations

## Purpose

Use this guide to audit numeric identity on managed hosts, allocate a new UID or shared GID, and offboard an account without breaking backup restores or shared storage.

The source of truth for allowed ranges, immutability rules, and enforcement is [UID and GID allocation policy](../reference/uid-gid-allocation-policy.md). Current allocations live in `ansible/infra-ops/inventory/group_vars/all/uid_registry.yml`.

## Prerequisites

- Network reachability to the `192.0.2.0/24` management subnet. From outside that subnet the hosts sit behind OPNsense and require Tailscale or an equivalent path.
- A working Ansible control environment in `ansible/infra-ops/`.
- SSH access as the inventory `ansible_user` for each target host.
- For offboarding, confirmation that no running service depends on the account.

## Safety profile

Allocating a number is low risk. Applying it to a host is not.

Changing the UID of an account that already owns files is destructive to ownership and is prohibited by policy. Removing an account that Ansible connects as will lock the control node out of the host. Running the `ssh` role before the `users` role on a host that has no working key will lock every operator out of that host.

Run every command in this guide read-only or with `--check --diff` first. Do not put private keys, passwords, or password hashes in the registry.

## Audit existing UIDs and GIDs

Run from `ansible/infra-ops/`. These commands read host state and change nothing.

```bash
ansible all -i inventory/hosts.yml -m ansible.builtin.shell \
  -a "getent passwd | awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1, \$3, \$4}'" \
  -e ansible_become=false
```

```bash
ansible all -i inventory/hosts.yml -m ansible.builtin.shell \
  -a "getent group | awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1, \$3}'" \
  -e ansible_become=false
```

```bash
ansible all -i inventory/hosts.yml -m ansible.builtin.shell \
  -a "getent group docker || echo 'no docker group'" \
  -e ansible_become=false
```

```bash
ansible all -i inventory/hosts.yml -m ansible.builtin.shell \
  -a "cat /etc/subuid /etc/subgid 2>/dev/null || echo none" \
  -e ansible_become=false
```

Expect UID 1000 to be taken by the cloud image account on each Ubuntu guest, and expect the `docker` GID to differ between hosts. Both are normal and are the reason the policy reserves the cloud image range and does not pin the `docker` GID.

Compare the output against the registry. For each account present on a host but missing from the registry, decide whether to adopt it or remove it before continuing.

## Adopt a pre-existing account

When the audit finds an account that predates this policy:

1. Do not change its UID. The policy prohibits renumbering a live account.
2. Add it to `uid_registry.yml` with its current numbers.
3. Set `class: preexisting` if the numbers fall outside the range for its role.
4. Add a `description` explaining why the exemption exists.
5. Record the exception owner and review date in the change description.

## Allocate a new UID

1. Audit first. Do not allocate against a stale registry.
2. Choose the class: `human` for a person, `service` for automation.
3. Read `uid_registry.yml` and find the lowest free number in that class range, skipping any entry marked `retired: true`.
4. Add the entry, setting `gid` equal to `uid`:

   ```yaml
   uid_registry:
     example-operator:
       uid: 2001
       gid: 2001
       class: human
       description: Operator account for the example operator.
   ```

5. Add the matching shape entry to `managed_users` in `roles/users/defaults/main.yml`, or override it in group_vars for a host subset.
6. Run a syntax check and a dry run before applying:

   ```bash
   cd ansible/infra-ops
   ansible-playbook playbooks/site.yml --syntax-check
   ansible-playbook playbooks/site.yml --check --diff --limit <host>
   ```

7. Apply to one host first, verify, then widen the limit.

## Add a shared group

1. Choose the lowest free GID in the shared group range.
2. Add it to `gid_registry` with a description naming the data it owns:

   ```yaml
   gid_registry:
     shared-media:
       gid: 4001
       description: Ownership for the shared media dataset.
   ```

3. Add the group to the supplementary groups of each account that needs it.
4. Apply, then confirm the GID is identical on every host that mounts the shared storage.

Do not use the `docker` group for this. Its GID differs per host.

## Offboard an account

1. Confirm no service depends on the account.
2. Identify files it owns before removing it, so ownership can be reassigned deliberately:

   ```bash
   ansible <host> -i inventory/hosts.yml -m ansible.builtin.shell \
     -a "find / -xdev -uid <uid> -printf '%p\n' 2>/dev/null | head -50"
   ```

3. Reassign or archive those files.
4. Set the account `state: absent` in `managed_users` and apply.
5. Mark the registry entry retired. Do not delete it:

   ```yaml
   uid_registry:
     example-operator:
       uid: 2001
       gid: 2001
       class: human
       retired: true
       description: Retired on 2026-08-04. Number is burned and must not be reissued.
   ```

6. Confirm the entry no longer appears in `managed_users`. The role fails if a retired entry is still declared present.

The number stays burned permanently. A backup taken before offboarding still contains files owned by it, so reissuing the number would transfer the retired account's data to a new account on restore.

## Verify after a change

Run against each affected host:

```bash
id <username>
getent passwd <username>
getent group <username>
sudo -l -U <username>
```

Confirm that:

- The UID and GID match the registry exactly.
- The primary group GID equals the UID.
- Supplementary group membership is as intended.
- Sudo access matches what `managed_users` declares.

Re-run the audit commands and confirm live state matches the registry across all hosts.

## Verify before hardening SSH

The `users` role must run before the `ssh` role. Before allowing SSH hardening to apply to a host:

1. Open a new SSH session as the managed account from a second terminal.
2. Confirm key-based authentication succeeds without a password.
3. Confirm `sudo` works in that session.
4. Keep the original session open until all three succeed.

On the Proxmox host, where Ansible connects as `root`, complete this verification before `sshd_permit_root_login` is set to false. Do not create the administrative account and disable root login in the same run.

## Rollback

If an account was created with the wrong number:

1. Do not change the UID in place if the account has written files.
2. Remove the account, reassign any files it owns, allocate a new number, and recreate it.
3. Mark the incorrect number retired in the registry.

If a change locked out SSH access:

1. Use the Proxmox VE console for a guest, or physical or out-of-band access for the Proxmox host.
2. Re-enable password authentication or repair the `authorized_keys` file locally.
3. Confirm access, then correct the inventory or registry that produced the failure.
4. Record what allowed the ordering violation so the role's guard checks can be extended.
