# UID and GID allocation policy

## Purpose

This policy defines how numeric user IDs and group IDs are allocated, recorded, and retired across the hosts managed by `ansible/infra-ops/`. It exists because numeric identity, unlike account names, is preserved by archive tools, backup restores, and network filesystems. An unplanned UID becomes permanent the moment a file is written with it.

Unlike the Zabbix tag policy, this policy is enforced in code. The `users` role asserts conformance before it mutates any host, and a violation fails the run. See [Enforcement](#enforcement).

## Scope

This policy applies to Linux `/etc/passwd` and `/etc/group` identity on hosts defined in `ansible/infra-ops/inventory/hosts.yml`, including:

- Human operator accounts
- Service and automation accounts
- Per-user primary groups
- Shared groups used for cross-host data ownership

This policy does not apply to:

- Proxmox VE realm identities managed by `pveum`, including PAM realm users, PVE realm users, roles, ACLs, groups, and API tokens. A PVE realm user is not a Linux account and has no UID. On the Proxmox host, the Linux accounts are in scope and the PVE identities are not.
- Zabbix frontend users, OPNsense local accounts, and any other application-level identity store.
- The `ansible/infra-ops/` inventory. This project distributes keys and should not create accounts or allocate numeric identity that contradicts this policy.

Account names describe who or what an identity belongs to. Numeric identity describes what the kernel and the filesystem enforce. This policy governs the numbers.

## Governance model

Use the registry at `ansible/infra-ops/inventory/group_vars/all/uid_registry.yml` as the source of truth for numeric identity.

- Every managed account must have a registry entry before the `users` role creates it.
- Allocate the lowest free number in the correct range.
- Record the allocation in the registry in the same change that introduces the account.
- Review the registry when adding a host, adding shared storage, or offboarding an account.
- Audit live hosts against the registry at least quarterly, and after any manual account creation.

Exceptions are allowed, but each exception should have:

- The account or group affected
- The reason the number falls outside its range
- The owner responsible for follow-up
- A review date
- The intended remediation or acceptance decision

Pre-existing accounts discovered by an audit are recorded as exceptions rather than renumbered. See [Immutability and retirement](#immutability-and-retirement).

## Allocation ranges

| Range | Class | Purpose |
| --- | --- | --- |
| `0-999` | System | Reserved for distribution packages and `useradd -r`. This project does not allocate here. |
| `1000-1099` | Cloud image | Reserved for accounts created by cloud images and `cloud-init`, such as `ubuntu` at 1000. This project does not allocate here. |
| `1100-1999` | Buffer | Unallocated headroom between image-owned and project-owned identity. |
| `2000-2999` | Human | Operator accounts belonging to a person. |
| `3000-3999` | Service | Automation and application accounts, including `ansible`. |
| `4000-4999` | Shared group | Group IDs only, for cross-host data ownership. No user account occupies this range. |
| `5000-99999` | Reserved | Unallocated. Available for a future class if one is documented first. |
| `100000` and above | Container | Reserved for `subuid` and `subgid` user namespace mappings. This project does not allocate real accounts here. |

Each boundary prevents a specific failure:

- The cloud image range is reserved because every guest is built from a cloud image that already owns UID 1000. Allocating a managed account at 1000 collides with the image default on some hosts and not others, depending on which accounts the image created.
- Human and service accounts are separated because `rsync -a`, `vzdump`, and Proxmox Backup Server restores preserve numeric ownership, not names. When a numeric identity crosses hosts, the separation ensures it resolves to the same class of account rather than handing a person's files to a daemon.
- Shared group IDs are pinned because NFS, CIFS, and Docker bind mounts match on the numeric GID. A package-created group such as `docker` receives a different GID on each host depending on package install order, so it cannot carry shared-storage ownership.
- The container range is reserved because `/etc/subuid` maps container users starting at 100000 in blocks of 65536 by default. A real account allocated inside that space collides with a container's mapped root.

## Registry

The registry file is authoritative. The tables in this document describe the ranges and rules; they do not list allocations. Read the registry for current allocations:

```text
ansible/infra-ops/inventory/group_vars/all/uid_registry.yml
```

The registry carries numbers. The `users` role variable `managed_users` carries account shape, such as shell, supplementary groups, and sudo. The role joins the two and asserts that every managed account resolves to a registry entry.

Registry shape:

```yaml
uid_registry:
  ansible:
    uid: 3000
    gid: 3000
    class: service
    description: Ansible automation account.

gid_registry:
  shared-data:
    gid: 4000
    description: Cross-host shared data ownership.
```

Recognized `class` values are `human`, `service`, and `preexisting`. The `preexisting` class marks an account discovered by audit that predates this policy and falls outside its range; it is exempt from range conformance and must carry a `description` explaining the exemption.

Do not record passwords, password hashes, private keys, or authorized key material in the registry.

## Group policy

- Every managed account receives a per-user primary group whose GID equals the account UID. This matches default Debian and Ubuntu behavior and keeps both halves of numeric ownership stable across hosts.
- Shared groups are allocated from the shared group range and pinned in `gid_registry`. Use a shared group for any data that more than one account or more than one host must access.
- The `docker` group is created by the Docker package in the system range. This project manages membership in it and does not manage or pin its GID. The `docker` GID differs per host and must not be used for shared-storage ownership.
- The administrative group is `sudo` on Debian-family hosts, which includes Ubuntu guests and Proxmox VE, and `wheel` on RedHat-family hosts. The `users` role selects it from `ansible_os_family` through the `users_sudo_group` variable. Its GID is distribution-owned and is not pinned.

## Immutability and retirement

A UID or GID that exists on a live host must never be changed.

Changing a number does not rewrite the ownership already recorded against it. Files on other hosts, inside backup archives, on network shares, and in container volumes continue to carry the old number. The account keeps working while an expanding set of files becomes owned by a number that no account claims. The failure is silent and grows over time.

When an account is retired:

- Mark its registry entry `retired: true` and keep the entry. Do not delete it.
- Remove the account from `managed_users`.
- Never reissue the number to a different account.

A number is burned permanently. A backup taken before retirement still contains files owned by that number, so restoring it after the number is reissued transfers the retired account's data to whichever account now holds it. Each class provides one thousand numbers, so there is no allocation pressure that would justify recycling.

If an audit finds an account whose number falls outside its range, record it in the registry with `class: preexisting` and document the exemption. Do not renumber the live account.

## Enforcement

The `users` role runs these checks as a guard prelude before any host mutation. All are hard failures.

| Check | Fails when |
| --- | --- |
| Registry presence | `uid_registry` is undefined or empty. |
| Registry completeness | A `managed_users` entry has no matching registry key. |
| Range conformance | An allocation falls outside the range for its declared class and is not marked `preexisting`. |
| Duplicate UID | Two registry entries resolve to the same UID. |
| Duplicate GID | Two registry entries or shared groups resolve to the same GID. |
| Connection account protection | The account named by `ansible_user` is declared absent, or its UID would change. |
| Retirement consistency | An entry marked `retired: true` also appears in `managed_users` as present. |

Checks fail the run rather than emitting a warning. Warnings scroll past in playbook output and do not prevent the mutation that follows, and the failure modes described above are not recoverable by rerunning the role.

## Naming rules

- Use lowercase account and group names.
- Use `kebab-case` for multi-word shared group names, such as `shared-data`.
- Registry keys must match the literal account or group name on the host.
- Do not create two names for the same identity.
- Keep the account name stable once files exist that it owns, even though the number is what the filesystem enforces.

## Operational ordering

The `users` role must run before the `ssh` role on any host.

The `ssh` role disables password authentication and root login. Applying it before a managed account exists with a working key leaves the host unreachable. On the Proxmox host, where Ansible connects as `root`, root login must remain enabled until an independent session as the new administrative account has been verified by an operator.

## Review checklist

Use this checklist before relying on the registry for shared storage, backups, or restores:

- Every managed account has a registry entry.
- Every allocation falls inside its class range, or is documented as an exception.
- No number appears twice in the registry.
- Live host state matches the registry, confirmed by audit.
- Retired numbers remain in the registry and are not reissued.
- Shared storage ownership uses a pinned shared group, not `docker` or a per-host group.
- The account Ansible connects as is present in the registry and is not marked for removal.
- The `users` role is ordered before the `ssh` role in any playbook that runs both.

## Related pages

- [Manage UID and GID allocations](../how-to/manage-uid-allocations.md) for allocation, audit, and offboarding procedures.
- [UID collision failure modes](../explanation/uid-collision-failure-modes.md) for the reasoning behind pinned numeric identity.
