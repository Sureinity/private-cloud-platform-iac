# Terraform operations reference

Reference rules for running Terraform in this repository.

## Terraform roots

This repository maintains two distinct classes of Terraform roots:

| Root | Type | State backend | Purpose | Reference |
|---|---|---|---|---|
| `terraform/live/onprem-pve/` | Live environment | SeaweedFS S3 | Primary host composition (bridges, router, services, VMs) | ``../how-to/provisioning-allocation-plan.md`` |
| `terraform/bootstrap/seaweedfs/` | Standalone bootstrap | Local only | Provisions the SeaweedFS VM shell and persistent storage for S3 remote state | ``seaweedfs-bootstrap-allocation.md`` |

## Default workflow

For user-requested Terraform infrastructure changes, use this sequence from the relevant Terraform root, normally `terraform/live/onprem-pve/` (or `terraform/bootstrap/<target>/` for bootstrap roots):

```bash
# Backend initialization (for terraform/live/onprem-pve/ with SeaweedFS S3 backend)
terraform init -backend-config=backend.tfvars

terraform fmt -check -recursive
terraform validate
terraform plan -out=<safe-plan-name>
terraform apply <safe-plan-name>
rm -f <safe-plan-name>
terraform plan -detailed-exitcode
```

The final `plan -detailed-exitcode` should report no changes after a successful apply.

## Apply policy

The standing project decision is to apply safe, requested Terraform changes in the same turn after reviewing the plan.

Do not apply automatically when the plan contains any of the following:

- unrelated destructive actions
- unexpected VM, disk, image, bridge, gateway, or firewall replacement
- broad host networking changes that could affect Proxmox access
- changes outside the user's requested scope
- secret exposure or generated artifacts that would be committed
- ambiguous intent where a safer choice requires user confirmation

When any stop condition appears, leave the plan unapplied, explain the risk, and ask for confirmation or a narrower change.

## Commit policy

After the apply and validation checks pass, commit only intended source and documentation changes. Never commit Terraform state, plans, provider caches, ignored tfvars, downloaded images, or generated logs.

## Out-of-band host resources

Terraform is not a complete inventory of this host. Some resources are created and
changed manually and are absent from Terraform state.

| Resource | Managed by | Recorded in |
|---|---|---|
| `usb-ssd` directory datastore | `pvesm` on the PVE host | [`usb-ssd-datastore.md`](usb-ssd-datastore.md) |
| Host partitioning, filesystems, `/etc/fstab` | manual host operations | [`usb-ssd-datastore.md`](usb-ssd-datastore.md) |
| `vmbr0` DHCP client stanza | ``../../scripts/configure-pve-vmbr0-dhcp.sh`` | ``../explanation/temporary-pve-vmbr0-dhcp.md`` |

The `bpg/proxmox` provider has no resource type for Proxmox directory storage
definitions, so `usb-ssd` cannot be brought under Terraform management as things
stand. When auditing datastores, run `pvesm status` on the host in addition to
reading `terraform/live/onprem-pve/`.

Terraform can still target these datastores. `usb-ssd` is a valid value for the
`*_disk_datastore_id`, `*_efi_disk_datastore_id`, and `*_cloud_init_datastore_id`
inputs, and Terraform will fail the plan if the storage is inactive at the time.

## Reusable module catalog

Reusable logic lives under `terraform/modules/`:

| Module | Source path | Status | Description |
|---|---|---|---|
| `bridges` | `terraform/modules/bridges/` | Active | Configures Linux network bridges (`vmbr0`, `vmbr1`, `vmbrsync`) on the PVE host. |
| `images` | `terraform/modules/images/` | Active | Downloads and imports cloud images into Proxmox storage. |
| `proxmox_vm` | `terraform/modules/proxmox_vm/` | Active | Composes QEMU VM instances with disks, network interfaces, and cloud-init metadata. Decouples guest agent IP polling via `wait_for_ip.disabled = true` and standardizes SCSI Cloud-Init (`scsi2`). See [`../explanation/proxmox-cloud-init-and-guest-agent-lifecycle.md`](../explanation/proxmox-cloud-init-and-guest-agent-lifecycle.md) and [`../how-to/troubleshoot-vm-cloud-init-and-networking.md`](../how-to/troubleshoot-vm-cloud-init-and-networking.md). |
| `usb_resource_mapping` | `terraform/modules/usb_resource_mapping/` | Catalog / uninstantiated | Manages cluster USB hardware mappings (`proxmox_hardware_mapping_usb`) for VM passthrough. Retained for future USB hardware integration. |
