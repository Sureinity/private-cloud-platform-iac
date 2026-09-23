# Troubleshoot VM Cloud-Init and Networking

Use this procedure to diagnose and resolve common bootstrap failures on Proxmox VE VMs, including Terraform apply timeouts, Cloud-Init datasource failures, unexpected DHCP lease assignments, and aborted state locks.

## Symptoms Quick Reference

| Symptom | Primary Cause | Immediate Fix |
|---|---|---|
| `terraform apply` hangs at `Still creating...` | Provider waiting for QEMU Guest Agent IP report. | Set `wait_for_ip { disabled = true }` in module. |
| VM receives dynamic IP (e.g. `.101`) instead of static IP (e.g. `.51`) | Cloud-Init drive on `ide2` failed to mount under Q35/OVMF; guest fell back to DHCP. | Change drive bus to `scsi2` in Terraform and run `cloud-init clean && reboot`. |
| `Error acquiring the state lock` | Previous apply was killed while polling the API. | Verify process termination and release lock. |

---

## Procedure 1: Diagnose In-Guest Network & Cloud-Init State

Log into the guest VM via the Proxmox VE console (noVNC / xterm.js) or via SSH using the leased DHCP IP.

### Step 1: Check active IP addressing

Verify which addresses are bound to the network interfaces:

```bash
ip -brief address show
```

- **Dual IP symptom:** If both the static IP (`192.0.2.51/24`) and dynamic IP (`192.0.2.101/24`) appear, multiple Netplan configuration files exist or DHCP client services remain active alongside static stanzas.
- **DHCP only symptom:** If only `192.0.2.101/24` appears, Cloud-Init did not apply network configuration.

### Step 2: Check Cloud-Init datasource status

Inspect whether Cloud-Init found the virtual CD-ROM drive:

```bash
cloud-init status
cat /run/cloud-init/result.json
```

Look at the `datasource` key:
- **Expected:** `DataSourceNoCloud [seed=/dev/sr0][dsmode=net]`
- **Failure:** `DataSourceNone` (indicates the drive bus was not probed or unreadable).

### Step 3: Inspect rendered Netplan files

Check what network configuration was written to disk:

```bash
ls -la /etc/netplan/
cat /etc/netplan/*.yaml
```

If `/etc/netplan/50-cloud-init.yaml` is missing, Cloud-Init never reached the network configuration stage.

---

## Procedure 2: Remediate and Apply Static IP to Guest

Once the Terraform configuration has been updated to use `cloud_init_interface = "scsi2"` and applied:

1. In the guest VM console, reset the Cloud-Init machine state:
   ```bash
   sudo cloud-init clean --logs
   ```
2. Reboot the guest so UEFI firmware and the kernel mount the SCSI drive:
   ```bash
   sudo reboot
   ```
3. After reboot, verify that the static IP is bound and the gateway is reachable:
   ```bash
   ip -brief address show
   ip route show
   ping -c 2 192.0.2.1
   ```

---

## Procedure 3: Recovering from an Aborted Terraform Apply

If a `terraform apply` command was interrupted (Ctrl+C) while waiting for the guest agent:

### Step 1: Verify no orphaned Terraform processes are running

```bash
ps aux | grep terraform
```

If an orphaned process is holding the local lock, terminate it cleanly before proceeding.

### Step 2: Clear stale state locks (if applicable)

If `.terraform.tfstate.lock.info` persists after process termination:

```bash
# In the affected root (e.g. terraform/bootstrap/seaweedfs)
terraform force-unlock <LOCK-ID>
```

### Step 3: Reconcile state with existing Proxmox VM

If Proxmox successfully created the VM in hardware (e.g. VMID `151`) but Terraform aborted before committing it to `terraform.tfstate`:

```bash
terraform plan
```

If Terraform attempts to create the VM again and Proxmox errors with `VM 151 already exists`, import the existing hypervisor object:

```bash
terraform import module.seaweedfs_vm.proxmox_virtual_environment_vm.vm pve/151
```

Once imported, run `terraform plan` to verify the state matches disk and hypervisor definitions.
