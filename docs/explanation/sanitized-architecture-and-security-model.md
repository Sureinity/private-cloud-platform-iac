# Sanitized Architecture and Security Model

This document explains the security boundaries, sanitization policies, design decisions, and residual limitations of the public `private-cloud-platform-iac` repository.

---

## Purpose and Scope

`private-cloud-platform-iac` is an open reference architecture for on-premises virtualization and DevOps operations. It demonstrates production-grade Infrastructure as Code, automated configuration management, and supply-chain governance without exposing private network topology, real cryptographic material, or active management planes.

---

## Threat Model and Boundary Controls

```text
+------------------------------------+          +------------------------------------+
| Public Reference Repository        |          | Real Operational Environment       |
| (private-cloud-platform-iac)              |          | (private-repo)                     |
|                                    |          |                                    |
| - Synthetic RFC 5737 Subnets       |          | - Private Management Subnet        |
| - example.invalid Domains          |          | - Real Cloudflare & Internal DNS   |
| - Neutral Placeholder Credentials  |          | - Hardware USB Datastores          |
| - Static CI Security Parity        |  No Path | - Active Proxmox Management API    |
| - History-Free Curated Snapshot    | <======> | - Real SSH Keys & Ansible Vault    |
+------------------------------------+          +------------------------------------+
```

### 1. Network Boundary Isolation
- **Synthetic Addressing**: All example configurations, documentation, and playbooks use RFC 5737 reserved documentation ranges:
  - `192.0.2.0/24` (TEST-NET-1) for management and VM networks
  - `198.51.100.0/24` (TEST-NET-2) for external services and overlay networks
  - `203.0.113.0/24` (TEST-NET-3) for legacy gateway representations
  - `2001:db8::/32` for IPv6 documentation
- **Domain Names**: Domain references use `.example.invalid`, preventing DNS resolution and accidental traffic routing.
- **No Live Host Targets**: The repository contains no real IPs, MAC addresses, or interface identifiers from the operational host.

### 2. Identity and Credential Neutralization
- **Cryptographic Keys**: Real operator SSH public keys have been stripped and replaced with syntactically valid non-functional placeholder keys.
- **API Tokens**: Proxmox VE API tokens and S3 backend access keys are represented as abstract template strings (`root@pam!tf=<token-uuid>`).
- **No Private History**: This repository is initialized as an independent, single-commit snapshot. No prior git revisions, branch histories, or deleted commits are inherited from the private source repository.

### 3. Application and Workload Generalization
- **Client Disassociation**: Workloads, customer names, and internal ticket identifiers have been generalized into neutral reference applications (`sample-app`, `staging-server`, `REF-089`).
- **Engineering Patterns Preserved**: Core operational patterns—such as unprivileged container deployment accounts, root-owned deployment wrappers, immutable image tagging, and Docker group separation—are preserved in full architectural detail.

---

## Omissions and Residual Limitations

While this repository provides complete, runnable IaC definitions, certain elements are intentionally omitted:
1. **Live State Files (`terraform.tfstate`)**: Remote state files contain ephemeral resource IDs and runtime metadata. Operators must initialize their own state backend using `terraform/bootstrap/seaweedfs` or an external S3 provider.
2. **Private Secrets (`secrets/`)**: Production Ansible Vault passwords and token payloads are excluded. Operators must generate local credentials using the committed `.example` files.
3. **Hardware Storage Mappings**: Physical disk serials and host-specific volume UUIDs must be surveyed on the operator's physical node before provisioning.

---

## Hardening Recommendations for Operators

When deploying this architecture in your own environment:
1. **Management-Plane Isolation**: Bind the Proxmox web UI and API strictly to an isolated internal management bridge (`vmbr1`) behind a firewall appliance (e.g. OPNsense). Never expose port 8006 to WAN.
2. **Least-Privilege API Tokens**: Create a dedicated Proxmox API token with granular permissions (`VM.Allocate`, `VM.Config.*`, `Datastore.AllocateSpace`) rather than granting full `Administrator` privileges.
3. **Backend Transport Security**: Ensure SeaweedFS or S3 state backends enforce TLS termination before production state storage.
4. **Credential Rotation**: Implement automated secret scanning (e.g. Gitleaks) in local pre-commit hooks and CI pipelines to prevent accidental leakage.
