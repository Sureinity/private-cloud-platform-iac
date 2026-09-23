# USB-backed VM storage tradeoffs

Why the PVE host carries a USB-attached `usb-ssd` datastore, what that costs,
and which workloads may use it.

Facts about the datastore are in
[`../reference/usb-ssd-datastore.md`](../reference/usb-ssd-datastore.md).

## Decision

An external SSD in a USB enclosure was onboarded on 2026-08-19 as a PVE `dir`
datastore named `usb-ssd`, holding guest images only, and it is approved for
real production guest disks on this host, not only scratch or lab guests.

## Why it exists

The host is a Lenovo ThinkCentre M720q with a single 256 GB internal SATA SSD.
That disk carries the PVE system, `local`, and the `local-lvm` thin pool of about
140.9 GiB. Sizing guidance had already capped the initial provisioned guest-disk
budget at roughly 100 to 115 GB, and `local-lvm` was 15.70% consumed with only a
handful of guests defined.

The chassis has no free internal drive bay that can be used without opening and
reconfiguring the unit. USB was the only expansion path available without new
hardware. The external SSD adds about 439 GiB, which is more than three times the
internal thin pool.

## Why production use is accepted

Treating `usb-ssd` as production-eligible is a deliberate tradeoff, not an
oversight. The reasoning:

- Capacity is the binding constraint on this host. Restricting 439 GiB to scratch
  workloads would leave the actual limitation unaddressed.
- The host has no storage redundancy of any kind. The internal SSD is a single
  point of failure already, so USB attachment does not introduce a new class of
  risk so much as add a second instance of an existing one.
- This is a private cloud. Guest availability requirements are lower than the language
  "production" implies elsewhere; the term here means real, persistent workloads
  rather than a service with an uptime commitment.

The consequence is that backup discipline matters more than it did before, and
the mitigations below are not optional.

## Failure modes this introduces

USB is a weaker storage transport than SATA. The realistic failure modes:

- **Bus resets and link drops.** A USB device can be reset by the controller or
  the enclosure firmware. If that happens while a guest is writing, the guest sees
  I/O errors and its filesystem may be left inconsistent.
- **UAS quirks.** Some enclosure chipsets misbehave under the UAS driver, causing
  timeouts under sustained load. If instability appears, check `dmesg` for reset
  or timeout messages before suspecting the SSD itself.
- **Accidental physical disconnection.** The cable and enclosure are external and
  can be knocked loose. Any running guest with disks on the datastore is affected
  immediately.
- **No SMART passthrough on many bridges.** USB-SATA bridges frequently do not
  expose SMART attributes, so wear and reallocated-sector trends may be invisible.
  `smartctl -d sat` is worth attempting, but it is not guaranteed to work.
- **Slow enumeration at boot.** A USB disk may not be ready when local mounts are
  processed.

## Mitigations already applied

Two flags carry most of the safety weight.

### `--is_mountpoint yes` on the storage definition

Without this flag, PVE treats `/mnt/pve/usb-ssd` as an ordinary directory. If the
SSD is unmounted, that path still exists as an empty directory on the root
filesystem, and PVE will happily create new guest images inside it. The result is
guest disks silently written to the 68 GiB root filesystem, filling it and
appearing to succeed until the host runs out of space.

With `is_mountpoint` set, PVE verifies that the path is an actual mountpoint
before using the storage, and marks the storage inactive when the SSD is absent.
Guest disk creation fails loudly instead of corrupting the host's capacity
assumptions.

### `nofail` in `/etc/fstab`

Without `nofail`, systemd treats the mount as required for boot. A disconnected,
failed, or slow-to-enumerate USB SSD then leaves the host waiting on a device that
will never appear, dropping to an emergency shell. On a headless PVE host, that
requires physical console access to recover, and PVE management is reachable only
after boot completes.

`nofail` degrades that outcome from "host does not boot" to "storage is inactive
and guests using it fail to start", which is recoverable remotely.

### UUID-based mounting

USB enumeration order is not stable. The disk that is `/dev/sdb` today may be
`/dev/sdc` after a reboot or a re-plug, and on a host with additional removable
media, a device-node-based fstab entry can mount the wrong disk. The entry uses
the filesystem UUID, and the filesystem also carries the `PVE_USB_SSD` label as a
human-readable cross-check.

## Directory storage versus LVM thin

Every other guest on this host uses `local-lvm`, an LVM thin pool. `usb-ssd` is
`dir` storage, which behaves differently in ways that matter when placing or
migrating guests:

| Aspect | `local-lvm` (lvmthin) | `usb-ssd` (dir) |
|---|---|---|
| Disk representation | thin logical volumes | files in `images/<vmid>/` |
| Thin provisioning | native to the pool | only with `qcow2` format |
| Snapshots | LVM thin snapshots | `qcow2` internal snapshots |
| `raw` format | not applicable | possible, but loses snapshots and thin behavior |
| Free-space reporting | pool-level, overcommit visible | filesystem-level |

Use `qcow2` on `usb-ssd` unless there is a specific reason not to; `raw` on
directory storage gives up both snapshots and thin provisioning.

`dir` storage was chosen over putting LVM on the SSD because it keeps the failure
mode simple. A directory datastore that vanishes leaves an inactive storage and
unreadable image files. An LVM physical volume that vanishes involves the host's
LVM subsystem in the failure, which is a worse thing to debug over a USB link that
may be resetting.

## Placement guidance

Given production eligibility, the sensible split is by failure sensitivity rather
than by "real versus lab":

- **Keep on `local-lvm`:** OPNsense (VMID 100). The router is the path through
  which PVE management is reached; it must not depend on a removable disk. Any
  guest that must be running for the host to be administered belongs on internal
  storage.
- **Suitable for `usb-ssd`:** application and service guests such as the n8n
  server, Zabbix components, managed clients, and larger or disk-heavy workloads
  that would otherwise not fit the internal budget.
- **Consider carefully:** anything with a `on_boot = true` startup dependency
  ordering ahead of other guests, since an inactive datastore delays or fails that
  start.

Whatever the placement, guests on `usb-ssd` need a backup destination that is not
`usb-ssd`.

## Monitoring requirement

A removable datastore that can silently become inactive is exactly the condition
that must alert rather than be discovered later. The needed checks:

- `/mnt/pve/usb-ssd` is mounted.
- Free space on the datastore.
- Kernel USB reset or I/O error messages naming the device.

This is tracked in ``../../zabbix/ROADMAP.md`` under
capacity planning and is not yet implemented.

## Management boundary

The datastore is created and changed by hand on the host, not by Terraform. The
`bpg/proxmox` provider has no directory-storage resource, and host partitioning
and `/etc/fstab` are outside Terraform's scope in this repository. This means
`terraform/live/onprem-pve/` under-reports host storage; see
[`../reference/usb-ssd-datastore.md`](../reference/usb-ssd-datastore.md).

## Related pages

- [Attach a USB SSD as a PVE directory datastore](../how-to/attach-usb-ssd-datastore-to-pve.md)
- [USB SSD datastore reference](../reference/usb-ssd-datastore.md)
- [PVE sizing guidelines](../reference/pve-sizing-guidelines.md)
