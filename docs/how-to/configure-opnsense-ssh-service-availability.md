# Configure OPNsense SSH Service Availability Across Reboots

This guide provides the operational procedure to resolve SSH unavailability after an OPNsense VM reboot, explaining how to properly configure OpenSSH socket bindings and preserve firewall-level access control over Tailscale.

## Problem Context and Symptoms

When running OPNsense as a virtual machine (such as VM ID 100 on Proxmox VE) with the Tailscale plugin (`os-tailscale`) or other dynamic/overlay interfaces, operators may encounter the following behavior:

1. **Unreachable after reboot:** Upon system boot, OpenSSH fails to accept connections, even though SSH is marked as enabled in the configuration.
2. **Manual workaround required:** To restore SSH connectivity, an operator must log in to the Web GUI, navigate to **System > Settings > Administration**, uncheck **Enable Secure Shell**, click **Save**, re-check **Enable Secure Shell**, and click **Save** again.
3. **Root cause (Socket binding race condition):**
   - Restricting **Listen Interfaces** to a specific virtual or overlay interface (such as `opt2` / `tailscale0`) instructs OPNsense to write explicit `ListenAddress <IP>` statements into `/usr/local/etc/ssh/sshd_config`.
   - At system boot, the base FreeBSD `rc` subsystem starts OpenSSH before the userspace `tailscaled` daemon connects to the tailnet and assigns the `100.x.y.z` overlay IP.
   - FreeBSD returns `EADDRNOTAVAIL` ("Cannot assign requested address") when a socket tries to bind to an unassigned IP. OpenSSH treats this as fatal and terminates immediately.
   - Toggling the service in the Web GUI succeeds only because `tailscale0` is already up and addressed by the time an operator accesses the GUI.

```text
Boot-Time Race Condition (Failure):
--------------------------------------------------------------------------------
1. FreeBSD Kernel & Physical NICs boot (vtnet0, vtnet1)
2. OpenSSH daemon starts early
   ├── Reads sshd_config: ListenAddress <Tailscale_100.x.y.z>
   └── tailscale0 not plumbed yet -> bind() fails -> sshd exits (DEAD)
3. Later in boot: os-tailscale starts tailscaled
   └── tailscale0 gets IP 100.x.y.z (sshd remains dead; no auto-restart)
--------------------------------------------------------------------------------

Target Architecture (Persistent & Secure):
--------------------------------------------------------------------------------
1. OpenSSH Listen Interfaces set to "All (recommended)"
   └── sshd binds to wildcard (0.0.0.0:22 / [::]:22) at boot (SUCCEEDS)
2. Firewall Packet Filter (pf) enforces access control
   ├── TSC (opt2) Rule: Pass TCP -> This Firewall:22 (SSH)
   ├── WAN Rule: Default Deny (Blocks unsolicited port 22)
   └── LAN Rule: Anti-Lockout or explicit policy
--------------------------------------------------------------------------------
```

---

## Architectural Decision

To ensure high service availability across reboots without compromising perimeter security:

1. **Service Binding:** Set OpenSSH **Listen Interfaces** to **All (recommended)**. This allows `sshd` to bind to `INADDR_ANY` (`0.0.0.0` / `[::]`) during early boot, completely decoupling daemon initialization from overlay network readiness.
2. **Access Control Boundary:** Enforce network access restrictions at the firewall packet filter layer rather than the application socket layer.
3. **Preserved Firewall Rule:** Retain the dedicated inbound pass rule on the Tailscale interface (`TSC` / `opt2`) targeting port 22 (`(self)`). All untrusted interfaces (e.g., WAN) continue to block incoming port 22 traffic via default deny.

---

## Prerequisites

- Access to the OPNsense Web GUI via LAN (`192.0.2.1`), an existing VPN, or the Proxmox VE virtual console (`qm vncproxy 100` / noVNC).
- An existing and active firewall rule permitting inbound TCP port 22 on the Tailscale interface (`TSC`).
- Administrative credentials for OPNsense.

---

## Procedure

### Step 1: Set Listen Interfaces to All

1. Log into the OPNsense Web GUI.
2. Navigate to **System > Settings > Administration**.
3. Scroll down to the **Secure Shell** section.
4. Verify **Enable Secure Shell** is checked.
5. In the **Listen Interfaces** multi-select field, deselect all specific interfaces (e.g., deselect `opt2` / `TSC`) so that **All (recommended)** is active.
   - If no specific interfaces are selected, OPNsense automatically defaults to listening on all interfaces.
6. Scroll to the bottom of the page and click **Save**.

### Step 2: Verify the Preserved Tailscale Firewall Rule

Confirm that the packet filter rule allowing SSH over Tailscale remains in place:

1. Navigate to **Firewall > Rules > TSC** (or the descriptive interface label assigned to `tailscale0`).
2. Verify that an active rule exists matching the following criteria:
   - **Action:** `Pass`
   - **Interface:** `TSC`
   - **Direction:** `in`
   - **Address Family:** `IPv4+IPv6`
   - **Protocol:** `TCP`
   - **Source:** `any` (or restricted to authorized tailnet management client IPs)
   - **Destination:** `(self)` (or `This Firewall`)
   - **Destination Port Range:** `22 (SSH)`
   - **Description:** `Allow SSH on Tailscale`
3. Ensure no blocking or rejecting rules precede this rule on the `TSC` tab.

### Step 3: Verify WAN and External Isolation

1. Navigate to **Firewall > Rules > WAN**.
2. Confirm that there are no rules passing destination port 22 from external sources. The default deny rule will automatically discard unsolicited inbound attempts from the WAN.

---

## Verification and Validation

### 1. In-Service Socket Check

Log in to the OPNsense shell (via console or an active session) and check socket listeners:

```bash
sockstat -4 -l -p 22
```

**Expected output:**
```text
USER     COMMAND    PID   FD PROTO  LOCAL ADDRESS         FOREIGN ADDRESS
root     sshd       ...   ... tcp4   *:22                  *:*
```
*(The `*:22` address confirms that `sshd` is bound to all IPv4 interfaces rather than a specific single IP).*

Check service status via `configctl`:

```bash
configctl openssh status
```

**Expected output:**
```text
openssh is running
```

### 2. Tailscale Inbound Access Check

From an operator workstation connected to the tailnet:

```bash
ssh -v <admin_user>@opnsense-home.<tailnet-name>.ts.net
```

The SSH banner and authentication prompt should appear immediately.

### 3. Reboot Persistence Test

Perform a scheduled test reboot of the OPNsense VM from Proxmox VE:

```bash
qm reboot 100
```

Wait approximately 30–60 seconds for the VM to complete its boot sequence and for `os-tailscale` to reconnect to the tailnet. Without opening the Web GUI or toggling any settings, attempt the SSH connection again from the tailnet workstation:

```bash
ssh <admin_user>@opnsense-home.<tailnet-name>.ts.net
```

The connection must succeed without requiring any service disable/enable toggle.

---

## Troubleshooting and Failure Modes

| Symptom | Probable Cause | Corrective Action |
|---|---|---|
| `ssh: connect to host ... port 22: Connection refused` immediately after boot | `sshd` failed to start or crashed on boot. | Connect via Proxmox console, run `tail -n 50 /var/log/system.log`, and verify `configctl openssh status`. |
| `ssh: connect to host ... port 22: Operation timed out` | Packet filter (pf) is dropping packets on `tailscale0`. | Check **Firewall > Log Files > Live View** for blocked port 22 packets on interface `TSC`. Ensure the `Pass` rule exists on `TSC`. |
| `Permission denied (publickey,password)` | Daemon is reachable, but user authentication failed. | Verify user is a member of the authorized SSH group (`admins`) and that root login / password auth settings match configuration under **System > Settings > Administration**. |
| Client IP temporarily blocked | Exceeded login failure thresholds into the `sshlockout` table. | Run `pfctl -t sshlockout -T show` in the console. Flush with `pfctl -t sshlockout -T flush` if locked out. |

---

## Rollback Procedure

If it is necessary to revert to binding OpenSSH strictly to specific interfaces:

1. In the Web GUI, navigate to **System > Settings > Administration**.
2. Under **Secure Shell > Listen Interfaces**, reselect the specific interface (e.g., `TSC` or `LAN`).
3. Click **Save**.
4. *Note:* If bound to `TSC` (`tailscale0`), be aware that the boot-time race condition will return unless an `/usr/local/etc/rc.syshook.d/start/` script is deployed to restart `sshd` once `tailscale0` obtains an IP address.
