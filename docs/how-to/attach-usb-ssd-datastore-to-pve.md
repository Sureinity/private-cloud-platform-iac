# Attach a USB SSD as a PVE directory datastore

Task-oriented procedure for preparing an external USB SSD and onboarding it to the
Home PVE host as the `usb-ssd` directory datastore.

This procedure was performed manually on 2026-08-19 against node `pve`. Rerun it
only when replacing the disk or rebuilding the host; the datastore already exists.
See [`../reference/usb-ssd-datastore.md`](../reference/usb-ssd-datastore.md) for
the resulting facts and
[`../explanation/usb-backed-vm-storage-tradeoffs.md`](../explanation/usb-backed-vm-storage-tradeoffs.md)
for the reasoning behind the safety flags.

## Prerequisites and assumptions

- Root shell on the PVE host, by console or SSH.
- An external SSD in a USB enclosure, already physically connected.
- The disk contains no data you need. Every step below is destructive.
- The target device is confirmed by `lsblk` before any command runs.

## Safety notes

- Wiping the wrong device destroys the host. `sda` on this host is the PVE system
  disk. Confirm the target device node on every run; USB enumeration order is not
  stable across reboots.
- Do not reboot the host until `mount -a` has been verified. A malformed
  `/etc/fstab` entry without `nofail` can block boot on a headless host.
- The mountpoint is `/mnt/pve/usb-ssd`. Never use a path under `/etc/pve`; that is
  the pmxcfs cluster filesystem and cannot host a block device mount.

## Procedure

### 1. Connect the enclosure and identify the device

Attach the SSD in its USB enclosure, then identify it:

```bash
lsblk -f
dmesg | tail -20
```

Record the device node. On this host it enumerated as `/dev/sdb`.

### 2. Wipe existing signatures

```bash
wipefs -a /dev/sdb
```

### 3. Create a GPT label and a single full-disk partition

```bash
parted --script /dev/sdb mklabel gpt
parted --script /dev/sdb mkpart primary ext4 1MiB 100%
```

The `1MiB` start offset keeps the partition aligned.

### 4. Create the filesystem with a stable label

```bash
mkfs.ext4 -F -L PVE_USB_SSD /dev/sdb1
```

### 5. Read the filesystem UUID

```bash
blkid /dev/sdb1
```

Use the `UUID=` value in the next step. Do not use `/dev/sdb1` in `/etc/fstab`;
USB device nodes are not stable across reboots.

### 6. Create the mountpoint and configure /etc/fstab

```bash
mkdir -p /mnt/pve/usb-ssd
```

Append one line to `/etc/fstab`, substituting the UUID from the previous step:

```text
UUID=7e0a350d-b358-4b26-b2b0-e46c7915f2b5 /mnt/pve/usb-ssd ext4 defaults,nofail 0 2
```

Field meanings:

| Field | Value | Reason |
|---|---|---|
| Source | `UUID=...` | stable across USB re-enumeration |
| Mountpoint | `/mnt/pve/usb-ssd` | PVE convention for directory storage |
| Options | `defaults,nofail` | `nofail` prevents a boot hang when the SSD is absent |
| Dump | `0` | not used |
| fsck pass | `2` | non-root filesystem, checked after root |

### 7. Reload systemd and test the mount before rebooting

```bash
systemctl daemon-reload
mount -a
findmnt /mnt/pve/usb-ssd
```

`mount -a` must succeed with no error before the host is rebooted.

### 8. Register the PVE directory storage

```bash
pvesm add dir usb-ssd \
  --path /mnt/pve/usb-ssd/ \
  --content images \
  --nodes pve \
  --is_mountpoint yes
```

`--is_mountpoint yes` is required. Without it, PVE writes guest images into the
host root filesystem whenever the SSD is not mounted.

## Validation

```bash
lsblk -f
findmnt /mnt/pve/usb-ssd
pvesm status
```

Expected results:

- `lsblk -f` shows `sdb1` with filesystem `ext4`, label `PVE_USB_SSD`, and
  mountpoint `/mnt/pve/usb-ssd`.
- `pvesm status` lists `usb-ssd` with type `dir` and status `active`.

Observed output from the 2026-08-19 run:

```text
sdb
└─sdb1  ext4  1.0  PVE_USB_SSD  7e0a350d-b358-4b26-b2b0-e46c7915f2b5  416.7G  0%  /mnt/pve/usb-ssd
```

```text
Name             Type     Status     Total (KiB)      Used (KiB) Available (KiB)        %
local             dir     active        70892712         8777760        58468080   12.38%
local-lvm     lvmthin     active       147714048        23191105       124522942   15.70%
usb-ssd           dir     active       460367724            2080       436906736    0.00%
```

## Rollback

Reverse the steps only after confirming no guest disks live on the datastore.

```bash
pvesm status
ls -la /mnt/pve/usb-ssd/images/ 2>/dev/null
```

If the datastore is empty:

```bash
pvesm remove usb-ssd
umount /mnt/pve/usb-ssd
```

Then remove the `/etc/fstab` line, run `systemctl daemon-reload`, and confirm with
`findmnt /mnt/pve/usb-ssd` returning nothing.

If guest disks exist, migrate them to `local-lvm` first with the PVE web UI disk
move action or `qm move-disk`, and only then remove the storage.

## Related pages

- [USB SSD datastore reference](../reference/usb-ssd-datastore.md)
- [USB-backed VM storage tradeoffs](../explanation/usb-backed-vm-storage-tradeoffs.md)
- [PVE sizing guidelines](../reference/pve-sizing-guidelines.md)
