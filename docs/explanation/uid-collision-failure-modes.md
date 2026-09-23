# UID collision failure modes

A Linux filesystem does not store account names. It stores numbers. The name shown by `ls -l` is resolved at display time by looking the number up in `/etc/passwd` on whichever host is doing the lookup. When a file moves between hosts, the number travels with it and the name is resolved again against a different passwd database.

This page explains why that matters for this environment, and what breaks when numeric identity is left to chance. The [UID and GID allocation policy](../reference/uid-gid-allocation-policy.md) is the source of truth for the ranges, rules, and enforcement described here.

## Why numbers drift without a policy

`useradd` assigns the next free UID at or above the distribution minimum, which is 1000 on Debian and Ubuntu. The number an account receives therefore depends on how many accounts already exist on that host and in what order they were created.

Every guest in this environment is built from a cloud image, so `cloud-init` has already created an account at 1000 before any configuration management runs. A second account created on one host in January and on another host in March can easily receive different numbers, because the hosts did not have identical account histories in between.

Nothing warns about this. Each host is internally consistent and the names look correct on every host. The inconsistency only becomes visible when a number crosses a host boundary.

## What preserves numeric ownership

Several routine operations preserve the number and discard the name:

| Operation | Behavior |
| --- | --- |
| `rsync -a` | Preserves numeric UID and GID when run as root, unless `--numeric-ids` is explicitly negotiated with name mapping. |
| `tar -p` and archive extraction | Restores the numeric ownership recorded in the archive. |
| `vzdump` and Proxmox Backup Server restore | Restore the guest filesystem with its original numeric ownership intact. |
| NFS with `sys` security | Sends the raw UID and GID over the wire. The server matches on the number. |
| Docker bind mounts | The container sees the host's numeric ownership. Names inside the container are irrelevant to access control. |
| Container `subuid` mapping | Maps container UIDs into a host range starting at 100000 by default. |

In each case the receiving host resolves the number against its own passwd database. If the number means something different there, ownership silently changes meaning.

## The concrete failures

**Backup restore transfers ownership.** A guest is backed up, then restored onto a host where UID 1001 belongs to a different account than it did on the source. Every file the original account owned is now owned by the other account. The restore reports success. Nothing in the output indicates that ownership changed hands.

**Shared storage grants the wrong access.** A dataset is exported over NFS and mounted on two guests. The group that owns it has GID 998 on one host and 1001 on the other, because the group was created by a package on one and by hand on the other. Access works from one guest and fails from the other, or worse, succeeds for an unintended account that happens to hold the matching number.

**Bind mounts break between hosts.** A container writes data to a bind-mounted directory as UID 1000. The same compose file deployed to a second host writes as UID 1000 there too, but 1000 is a different account. Moving the data directory between hosts produces files the application cannot read.

**Renumbering orphans files.** An operator notices the inconsistency and changes an account's UID to match another host. The account continues to work, because the login path resolves by name. But every file the account already owned still carries the old number, on that host and inside every backup taken before the change. Those files are now owned by a number no account claims. The problem is invisible until something enumerates ownership.

The last case is why the policy prohibits changing a live UID rather than merely discouraging it. The repair is worse than the original inconsistency, because it converts a known mismatch into orphaned ownership spread across backups.

## Why retired numbers stay burned

Removing an account frees its number for reuse. Reusing it is unsafe for as long as any backup exists that predates the removal.

A restore from such a backup writes files owned by the retired number. If a new account now holds that number, it receives the retired account's data. This is the same failure as a cross-host restore, except that it happens on a single host and looks entirely legitimate.

Each class in the allocation table provides one thousand numbers. There is no allocation pressure in an environment of this size, so there is no benefit to recycling that would offset the risk.

## Why ranges rather than a sequence

Sequential allocation from a single starting point would prevent duplicates within the registry, but it carries no information. A number would say nothing about whether it belongs to a person, a daemon, or a shared dataset.

Separating classes into ranges means that when a number does cross hosts unexpectedly, it resolves to the same kind of account. A human UID colliding with another human UID is a permissions problem between two operators. A human UID colliding with a service UID hands a person's files to a daemon, or gives a daemon's data to a person. The range separation bounds the severity of a mistake that the policy cannot entirely prevent.

The cloud image range is reserved for the same reason in the other direction. The project does not control what a cloud image creates, so it does not allocate where a cloud image might.

## When to replace this approach

Ansible-managed local accounts work well while the account set is small and the operator set is essentially one person. The cost is that every account exists independently on every host, and every change requires a converging run across the fleet.

Replace this approach at roughly 15 to 20 hosts, or at the first non-operator human who needs access to a subset of hosts rather than all of them. Past either threshold, per-host convergence and key rotation cost more than a central directory, and the registry stops being a useful abstraction because it is tracking identity that should be resolved at authentication time instead.

Until then, the registry plus role assertions provide the property that matters: numeric identity is decided deliberately, recorded in one place, and verified before any host is modified.

## Validation checklist

- Numeric identity for a given account is identical on every host that carries it.
- No number appears twice in the registry.
- Shared storage ownership uses a pinned group ID from the shared range.
- No live account has been renumbered.
- Retired numbers remain recorded and unissued.

## Rollback

If a collision is discovered on a live host, do not renumber the account. Record the current state in the registry as an exception, identify the files affected by running `find / -xdev -uid <uid>`, and plan a deliberate migration through account replacement rather than a UID change. The procedures are in [Manage UID and GID allocations](../how-to/manage-uid-allocations.md).
