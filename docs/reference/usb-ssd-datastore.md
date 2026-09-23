# USB SSD datastore reference

Facts for the `usb-ssd` Proxmox VE directory datastore on node `pve`.

Onboarded manually on 2026-08-19. The procedure is in
[`../how-to/attach-usb-ssd-datastore-to-pve.md`](../how-to/attach-usb-ssd-datastore-to-pve.md);
the design reasoning is in
[`../explanation/usb-backed-vm-storage-tradeoffs.md`](../explanation/usb-backed-vm-storage-tradeoffs.md).

## Storage definition

| Property | Value |
|---|---|
| Storage ID | `usb-ssd` |
| PVE storage type | `dir` |
| Node | `pve` |
| Path | `/mnt/pve/usb-ssd/` |
| Content types | `images` only |
| `is_mountpoint` | `yes` |
| Shared | no, single-node local storage |

Content types deliberately exclude `iso`, `vztmpl`, `backup`, and `snippets`.
ISOs and cloud images continue to use `local`. Do not add content types without
recording the change here.

## Block device

| Property | Value |
|---|---|
| Device node at onboarding | `/dev/sdb1` |
| Attachment | external SSD in a USB enclosure |
| Partition table | GPT |
| Partition layout | single primary partition, `1MiB` to `100%` |
| Filesystem | ext4 |
| Filesystem label | `PVE_USB_SSD` |
| Filesystem UUID | `7e0a350d-b358-4b26-b2b0-e46c7915f2b5` |

The device node is not stable. Identify the disk by label or UUID, never by
`/dev/sdX`.

## Mount configuration

Active `/etc/fstab` entry on the PVE host:

```text
UUID=7e0a350d-b358-4b26-b2b0-e46c7915f2b5 /mnt/pve/usb-ssd ext4 defaults,nofail 0 2
```

`nofail` is mandatory. Without it, a disconnected or slow-to-enumerate USB SSD
blocks host boot, which requires physical console access to recover.

## Capacity

Observed on 2026-08-19, immediately after creation:

| Storage | Type | Total | Available | Used |
|---|---|---:|---:|---:|
| `local` | `dir` | ~67.6 GiB | ~55.8 GiB | 12.38% |
| `local-lvm` | `lvmthin` | ~140.9 GiB | ~118.8 GiB | 15.70% |
| `usb-ssd` | `dir` | ~439.0 GiB | ~416.7 GiB | 0.00% |

This roughly quadruples available guest-image capacity on the host. Update
[`pve-sizing-guidelines.md`](pve-sizing-guidelines.md) disk budgets when guest
placement on `usb-ssd` begins in earnest.

## Terraform usage

`usb-ssd` is a valid value for the datastore inputs consumed by
`terraform/modules/proxmox_vm`, alongside `local-lvm`:

```hcl
<vm>_disk_datastore_id       = "usb-ssd"
<vm>_efi_disk_datastore_id   = "usb-ssd"
<vm>_cloud_init_datastore_id = "usb-ssd"
```

Because the datastore has `content images` only, all three disk classes above are
supported. Note that `dir` storage produces file-backed disks rather than LVM thin
volumes, which changes snapshot and provisioning behavior; see the explanation
page before moving an existing VM.

No VM in `terraform/live/onprem-pve/main.tf` currently targets `usb-ssd`. All active guests
remain on `local-lvm`.

## Management boundary

The `usb-ssd` datastore is managed **out of band** and is not represented in
Terraform state.

The `bpg/proxmox` provider used in this repository has no resource for Proxmox
directory storage definitions, and Terraform does not manage host partitioning,
filesystems, or `/etc/fstab`. Consequently `terraform/live/onprem-pve/` is not a complete
inventory of host storage. Anyone auditing datastores must also inspect the host
with `pvesm status`.

Changes to this datastore are made with `pvesm` on the host and recorded on this
page. See [`terraform-operations.md`](terraform-operations.md).

## Validation commands

```bash
lsblk -f
findmnt /mnt/pve/usb-ssd
pvesm status
pvesm list usb-ssd
```

## Related pages

- [Attach a USB SSD as a PVE directory datastore](../how-to/attach-usb-ssd-datastore-to-pve.md)
- [USB-backed VM storage tradeoffs](../explanation/usb-backed-vm-storage-tradeoffs.md)
- [PVE sizing guidelines](pve-sizing-guidelines.md)
- [Terraform operations reference](terraform-operations.md)
