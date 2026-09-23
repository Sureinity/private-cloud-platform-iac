# SeaweedFS TLS Architecture and Security Boundaries

This document details the architectural rationale, security boundaries, and tradeoffs for implementing TLS encryption on the SeaweedFS S3 state backend.

## The mental model

Terraform remote state contains raw infrastructure metadata, IP topologies, resource identifiers, and frequently sensitive secrets (e.g. database connection strings, generated passwords, API keys). Transmitting state over unencrypted HTTP exposes this data to packet capture, MITM tampering, and unauthorized inspection on local network segments.

```text
┌───────────────────────────────┐
│     Terraform / AWS CLI       │
└───────────────┬───────────────┘
                │ TLS v1.3 / HTTPS (Port :8334)
                │ Hostname: seaweedfs.example.invalid
                ▼
┌─────────────────────────────────────────────────────────────┐
│  Guest VM 151: seaweedfs-state (192.0.2.51)                 │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Native SeaweedFS Daemon (weed server)               │   │
│   │                                                     │   │
│   │  ┌───────────────────────────────────────────────┐  │   │
│   │  │ S3 Gateway HTTPS Listener (:8334)             │  │   │
│   │  │ - TLS Handshake & Termination                 │  │   │
│   │  │ - SigV4 Signature Verification                │  │   │
│   │  │ - IAM Authentication (/etc/seaweedfs/s3.json) │  │   │
│   │  └───────────────────────┬───────────────────────┘  │   │
│   │                          │ Internal IPC             │   │
│   │                          ▼                          │   │
│   │  ┌───────────────────────────────────────────────┐  │   │
│   │  │ Filer Engine (:8888, LevelDB2 Metadata)       │  │   │
│   │  └───────────────────────┬───────────────────────┘  │   │
│   │                          │ gRPC / Chunk Storage     │   │
│   │                          ▼                          │   │
│   │  ┌───────────────────────────────────────────────┐  │   │
│   │  │ Master (:9333) & Volume (:8080)               │  │   │
│   │  └───────────────────────────────────────────────┘  │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Sealed Certificates (/etc/seaweedfs/tls/)           │   │
│   │ - s3.crt (0644, root:seaweedfs)                     │   │
│   │ - s3.key (0600, seaweedfs:seaweedfs)                │   │
│   │ Synchronized via Certbot DNS-01 Renewal Hook        │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

> **The Key Insight:**
> In SeaweedFS, the S3 Gateway is the primary untrusted boundary where external clients interface with the cluster. By terminating TLS directly within the native daemon, we secure all external data transfers without adding reverse proxy process overhead to the resource-constrained 1 GB VM.

---

## Architectural decisions & tradeoffs

### 1. Native TLS vs. Reverse Proxy (Caddy / Nginx)

| Factor | Native SeaweedFS TLS | Reverse Proxy (Caddy / Nginx) |
|---|---|---|
| **Resource overhead** | **Zero additional RAM**; single Go binary | +60–120 MB RAM; runs secondary daemon |
| **Failure domains** | **Single systemd unit** (`seaweedfs.service`) | Two systemd units; failure in proxy breaks S3 |
| **AWS SigV4 compatibility** | Native `-s3.externalUrl` configuration | Requires strict header forwarding (`Host`, `x-amz-*`) |
| **ACME automation** | Managed via standard `certbot` + post-hook | Caddy automates ACME natively; Nginx requires certbot |
| **Systemd sandboxing** | Direct `/etc/seaweedfs/tls` read isolation | Proxy requires separate user/socket permissions |

**Decision:** We chose **Native SeaweedFS TLS**. VM 151 is rightsized with 1,024 MB RAM (idle footprint ~80–120 MB for SeaweedFS, ~250–350 MB for Ubuntu 26.04). Avoiding a reverse proxy preserves host RAM and eliminates redundant network hops on the guest loopback.

---

### 2. ACME DNS-01 vs. HTTP-01 Validation

- **The Problem with HTTP-01:** VM 151 sits on an isolated internal VLAN (`192.0.2.51/24`, `vmbr1`) behind OPNsense. It has no public IP address and port 80 is not exposed to the public internet. HTTP-01 ACME challenges would require inbound WAN port forwarding, conflicting with home-lab security policy.
- **The DNS-01 Solution:** Let's Encrypt validates domain ownership by creating temporary `_acme-challenge.seaweedfs.example.invalid` TXT records via the Cloudflare DNS API. This operates entirely via outbound HTTPS API requests from the guest VM, requiring zero inbound WAN exposure.

---

### 3. S3 SigV4 and `-s3.externalUrl`

The Amazon S3 Signature Version 4 algorithm incorporates the request host header into the cryptographic canonical request string. When clients connect to `https://seaweedfs.example.invalid:8334`, SeaweedFS must validate the signed signature against that exact hostname and port.

Providing `-s3.externalUrl=https://seaweedfs.example.invalid:8334` informs the S3 gateway of its advertised public identity, ensuring signature verification succeeds for AWS CLI, Boto3, and the Terraform S3 backend.

---

### 4. Dual-Stack Migration vs. Immediate Cutover

Changing the S3 protocol from HTTP to HTTPS creates operational disruption if client automation is not synchronized. We adopt a **two-phase transition model**:

1. **Phase 1 (Dual-Stack):**
   - SeaweedFS listens on both `:8333` (HTTP) and `:8334` (HTTPS).
   - Existing unencrypted clients continue functioning.
   - Operators qualify HTTPS connectivity, test certificate trust, and update Terraform backend configurations.
2. **Phase 2 (HTTPS-Only Hardening):**
   - `-s3.port` is set to `0`.
   - Plaintext HTTP is completely disabled; only encrypted connections on `:8334` (or `:8333` / `:443`) are accepted.

---

### 5. Least-Privilege Certificate Lifecycle & Sandboxing

Let's Encrypt stores private keys in `/etc/letsencrypt/live/`, which is restricted to `root:root` (mode `0700`/`0750`). Because SeaweedFS runs under the unprivileged system account `seaweedfs:seaweedfs` with `ProtectSystem=strict`, it cannot read certificates directly from Let's Encrypt archives without relaxing filesystem permissions.

**The Solution:**
- An automated Certbot post-renewal hook (`/etc/letsencrypt/renewal-hooks/post/seaweedfs-reload.sh`) executes on every successful issuance or renewal.
- The hook copies `fullchain.pem` and `privkey.pem` into `/etc/seaweedfs/tls/`, enforcing:
  - Certificate: Mode `0644`, owned by `root:seaweedfs`.
  - Private Key: Mode `0600`, owned by `seaweedfs:seaweedfs`.
- The systemd unit sandbox is augmented with `ReadOnlyPaths={{ seaweedfs_tls_dir }}`, permitting the daemon to read its keys while keeping all other host filesystems strictly protected.
