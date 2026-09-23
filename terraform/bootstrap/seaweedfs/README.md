# SeaweedFS Bootstrap Terraform Root

This directory contains the standalone Terraform root for provisioning the SeaweedFS VM on Proxmox VE. It provisions the VM and persistent disks only; guest service configuration is intentionally handled later.

> [!WARNING]
> **Subject to Data Storage Revamp:**
> The current storage topology (100 GiB virtual disk on `usb-ssd`) is an interim bootstrap implementation. An architectural revamp is planned to initialize a dedicated node for the SeaweedFS Volume server, decoupling persistent object storage from the hypervisor VM lifecycle.

## Operating rules

1. **Local state only:** Keep this root's state local or in an encrypted off-host backup. Never configure it to use the SeaweedFS backend it provisions.
2. **Verify allocation first:** Confirm the VMID and IPv4 address are unused before planning. The example values are placeholders and must be replaced with the approved allocation.
3. **No service configuration:** Terraform does not install or configure SeaweedFS, TLS, ACME, S3 credentials, backups, or firewall policy yet.
4. **Private network:** The VM attaches to `vmbr1` with the OPNsense LAN gateway. Do not expose the VM or Proxmox API publicly.
5. **Provider trust:** Keep Proxmox TLS verification enabled. Set `proxmox_insecure = true` only for a temporary, explicitly reviewed bootstrap exception.
6. **Deletion protection enforced:** VM protection (`seaweedfs_protection = true`) is enabled by default to prevent accidental `terraform destroy` or hypervisor-level removal of the VM and its attached 100 GiB data disk.

## Provisioned shape

- Direct reference to pre-existing Ubuntu cloud image (`local:import/ubuntu-26.04-server-cloudimg-amd64.qcow2`) via `import_image_file_id`, bypassing redundant WAN downloads and PVE download task collisions.
- VM name `seaweedfs-state` by default.
- 2 vCPU and 1 GiB (1024 MB) RAM by default.
- UEFI firmware, QEMU guest agent, boot-on-host-start, startup order `50`.
- Boot disk on `local-lvm` (20 GiB) and separate 100 GiB SeaweedFS data disk on `usb-ssd` by default.
- One firewall-enabled VirtIO NIC on `vmbr1`.
- Static cloud-init IPv4 configuration supplied through variables.

## Safe workflow

Run from this directory:

```bash
qm list
pct list
pvesm status
ip -br addr
ip route

terraform init
terraform fmt -check
terraform validate
terraform plan -out seaweedfs.tfplan
terraform show seaweedfs.tfplan
```

Apply only after confirming the plan contains the intended SeaweedFS VM, boot disk, EFI disk, cloud-init disk, and data disk (1 to add). Do not use this root to migrate the live On-Premises PVE state or configure the S3 backend.

## Later work

A separate guest-configuration change will install SeaweedFS, configure the S3 endpoint, issue `seaweedfs.example.invalid` certificates through the approved ACME DNS-01 process, configure backups, and qualify locking and recovery before any Terraform state migration.
