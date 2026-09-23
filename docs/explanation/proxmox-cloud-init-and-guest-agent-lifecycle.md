# Proxmox Cloud-Init and Guest Agent Lifecycle

This document explains the technical mechanisms, failure modes, and architectural decisions governing QEMU Guest Agent synchronization and Cloud-Init drive bus attachments in Proxmox VE under Terraform.

## Overview and Mental Model

Provisioning virtual machines with Terraform on Proxmox VE involves two decoupled execution planes:

1. **Hypervisor Plane (Host / PVE API):** Terraform requests VM creation, disk allocations, network bridges, and triggers VM start via the Proxmox API (`/api2/json`).
2. **Guest Operating System Plane (Guest OS):** The VM boots UEFI firmware, starts the Linux kernel, executes `cloud-init` via systemd, and configures guest networking, users, and daemons.

```text
+-------------------------------------------------------------------------+
| HYPERVISOR CONTROL PLANE (Proxmox VE + bpg/proxmox provider)             |
|                                                                         |
| 1. Create VM Shell  -->  2. Attach Disks  -->  3. Start QEMU Process     |
+------------------------------------------------------+------------------+
                                                       | (powers on)
                                                       v
+-------------------------------------------------------------------------+
| GUEST OPERATING SYSTEM PLANE (Ubuntu Cloud Image)                       |
|                                                                         |
| 4. OVMF UEFI Boot  -->  5. Probe Bus (SCSI vs IDE)  --> 6. Cloud-Init   |
|                                                                         |
|                                               [DataSourceNoCloud]       |
|                                                        |                |
|                                             +----------+----------+     |
|                                             |                     |     |
|                                         (Found)               (Missing) |
|                                             v                     v     |
|                                     Apply Static IP          Fall back  |
|                                     (192.0.2.51/24)          to DHCP    |
+-------------------------------------------------------------------------+
```

When Terraform attempts to synchronize with the guest's runtime state before the guest has finished configuring itself, or when the hypervisor attaches virtual hardware using a bus incompatible with modern guest firmware, provisioning hangs or silent configuration fallbacks occur.

---

## 1. QEMU Guest Agent Synchronization Hang

### The Problem

During `terraform apply`, Proxmox host tasks (`VM Create`, `VM/CT Resize`, `VM Start`) succeed within seconds. However, Terraform remains in `Still creating...` for up to 15 minutes before failing with a guest agent timeout error.

### Root Cause Mechanism

In the `bpg/proxmox` provider (v0.109+), defining:

```hcl
agent {
  enabled = true
}
```

enables the QEMU guest agent virtio-serial socket in the Proxmox VM configuration. By default, the provider also sets `wait_for_ip.disabled = false`. 

This causes Terraform to enter an active polling loop against the Proxmox API (`/api2/json/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces`), waiting for the in-guest agent daemon to report active IP addresses before considering resource creation complete.

Generic Ubuntu cloud images (`ubuntu-*-server-cloudimg-amd64.qcow2`) do not include or enable the `qemu-guest-agent` daemon out of the box. Because the agent never starts, the hypervisor never receives agent telemetry, and Terraform blocks until its 15-minute polling timeout expires.

### The Decision: Decouple Agent Readiness from Provisioning

Two design choices were evaluated:

| Option | Implementation | Tradeoff | Decision |
|---|---|---|---|
| **A. Disable Agent in Terraform** | `agent { enabled = false }` | Bypasses the hang, but removes the virtio-serial socket hardware from the VM. Enabling it later requires stopping the VM and reconfiguring hardware. | **Rejected** |
| **B. Decouple IP Polling** | `agent { enabled = true; wait_for_ip { disabled = true } }` | Leaves the virtio-serial socket enabled in PVE hardware for future telemetry, while instructing Terraform to mark creation complete immediately upon VM power-on. | **Accepted** |

### Implementation in `proxmox_vm` Module

In [`terraform/modules/proxmox_vm/main.tf`](file:///home/operator/Coding/DevOps/projects/onprem-pve/terraform/modules/proxmox_vm/main.tf):

```hcl
agent {
  enabled = var.agent_enabled
  wait_for_ip {
    disabled = true
  }
}
```

This guarantees day-1 Terraform applies succeed instantly. Once day-2 tooling (such as Ansible) installs and starts `qemu-guest-agent`, Proxmox automatically detects the running agent without needing VM hardware reconfiguration or guest reboots.

---

## 2. Cloud-Init DHCP Fallback under Q35 and UEFI (OVMF)

### The Problem

A VM boots up, but instead of applying the static IP configured in Terraform (`192.0.2.51/24`), it broadcasts a DHCP request on `vmbr1` and leases a dynamic IP (`192.0.2.101`) from OPNsense.

### Root Cause Mechanism: Bus Topology Mismatch

Modern VMs in this repository standardize on:
- `machine = "q35"` (modern PCIe chipset emulation)
- `bios = "ovmf"` (UEFI firmware)

The Q35 chipset does not feature a native legacy IDE controller. When a Cloud-Init drive is attached using `interface = "ide2"`, QEMU emulates an IDE device over legacy PIO compatibility ports.

Under OVMF UEFI firmware and modern Linux kernels:
1. UEFI bootloaders and early kernel initialization prioritize PCIe and VirtIO buses.
2. Cloud-init's `ds-identify` probe scans for a `NoCloud` volume (`CIDATA` label).
3. Because the emulated IDE device on `ide2` is not reliably surfaced or mounted before the datasource identification timeout, cloud-init concludes no datasource exists (`DataSourceNone`).
4. Ubuntu's default fallback networking takes precedence: Netplan issues DHCP requests across all available ethernet interfaces (`dhcp4: true`).
5. OPNsense's DHCP server responds on `vmbr1` and leases an address from its dynamic pool.

```text
Q35 Emulation Bus:
+---------------------------------------------------------------+
| PCIe / VirtIO SCSI Controller (virtio-scsi-single)             |
|   scsi0 -> OS Root Disk (20 GB NVMe/SATA backing) [Detected]   |
|   scsi1 -> Data Disk (100 GB USB-SSD backing)     [Detected]   |
|   scsi2 -> Cloud-Init ISO (NoCloud CIDATA)        [Detected]   |
+---------------------------------------------------------------+
| Legacy PIO Controller                                         |
|   ide2  -> Cloud-Init ISO [Unreliable / Ignored under OVMF]   |
+---------------------------------------------------------------+
```

### The Decision: Standardize Cloud-Init on SCSI (`scsi2`)

Cloud-init configuration drives must match the primary storage controller topology of the guest.

By setting `cloud_init_interface = "scsi2"`, the Cloud-Init ISO attaches directly to the `virtio-scsi-single` bus alongside the OS root disk (`scsi0`) and secondary data disks (`scsi1`).

- VirtIO SCSI drivers load deterministically in the initramfs.
- Cloud-init detects the `CIDATA` filesystem instantaneously on boot.
- Netplan renders `/etc/netplan/50-cloud-init.yaml` with the configured static IP and default gateway before network targets come online.

---

## Summary of Standards

| Property | Standard Value | Rationale |
|---|---|---|
| `agent.enabled` | `true` (or `false` for isolated sandboxes) | Provisions the virtio-serial hardware socket for future monitoring. |
| `agent.wait_for_ip.disabled` | `true` | Prevents apply deadlocks when guest agents are not pre-baked into images. |
| `cloud_init_interface` | `scsi2` | Ensures deterministic discovery under Q35 + UEFI (OVMF). |
| Storage controller | `virtio-scsi-single` | Provides per-disk queues, IO threads, and TRIM/discard support. |
