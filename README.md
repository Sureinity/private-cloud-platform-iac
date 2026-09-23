# Private Cloud Platform — Infrastructure as Code & Automation

[![CI Validation](https://github.com/Sureinity/private-cloud-platform-iac/actions/workflows/validate.yml/badge.svg)](https://github.com/Sureinity/private-cloud-platform-iac/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Security: Gitleaks](https://img.shields.io/badge/Security-Gitleaks-brightgreen.svg)](#security-and-supply-chain)
[![Security: Trivy](https://img.shields.io/badge/Security-Trivy-brightgreen.svg)](#security-and-supply-chain)
[![Security: Checkov](https://img.shields.io/badge/Security-Checkov-brightgreen.svg)](#security-and-supply-chain)

Production-grade Infrastructure as Code (IaC), guest configuration management, and automated supply-chain governance for a virtualized on-premises Proxmox VE environment.

---

## Architecture Overview

This platform manages virtualized compute, storage, isolated networking, and application delivery on Proxmox VE (PVE). Guest lifecycle is orchestrated declaratively with **Terraform**, post-provisioning and host operations are managed with **Ansible**, and supply-chain integrity is verified with a comprehensive multi-scanner CI pipeline.

```text
+-----------------------------------------------------------------------------------+
| Proxmox Virtual Environment (PVE) Host                                            |
|                                                                                   |
|  +--------------------+         +----------------------------------------------+  |
|  | Physical NIC (WAN) |         | Management & Isolated Guest Segment (vmbr1)  |  |
|  | (vmbr0)            |         | 192.0.2.0/24 (RFC 5737 Test Subnet)          |  |
|  +---------+----------+         +----------------------+-----------------------+  |
|            |                                           |                          |
|  +---------v-------------------------------------------v-----------------------+  |
|  | OPNsense Virtual Router & Firewall (Appliance ID 100)                       |  |
|  | - WAN Interface on vmbr0                                                   |  |
|  | - LAN Gateway (192.0.2.1) on vmbr1                                         |  |
|  | - WireGuard Admin Mesh / Isolated VLAN Segments                             |  |
|  +-----------------------------------------------------------------------------+  |
|            |                                                                      |
|  +---------v-------------------------------------------------------------------+  |
|  | Managed Infrastructure Guests (Attached to vmbr1 behind OPNsense)           |  |
|  |                                                                             |  |
|  |  +------------------------+  +------------------------+                     |  |
|  |  | SeaweedFS S3 Backend   |  | Zabbix Observability   |                     |  |
|  |  | ID 151 (192.0.2.51)     |  | Monolith ID 130        |                     |  |
|  |  | S3 State / Data Store  |  | Fleet Monitoring       |                     |  |
|  |  +------------------------+  +------------------------+                     |  |
|  |                                                                             |  |
|  |  +------------------------+  +------------------------+                     |  |
|  |  | Staging Application    |  | Monitored Linux Fleet  |                     |  |
|  |  | ID 142 (VLAN Isolated) |  | IDs 133-136            |                     |  |
|  |  | Docker / Cloud-Init    |  | Zabbix Agent 2 Clients |                     |  |
|  |  +------------------------+  +------------------------+                     |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## Key Capabilities

### 1. Declarative Infrastructure as Code (Terraform)
- **Reusable Modules**: Isolated, parameterized modules for Linux bridges (`terraform/modules/bridges`), Proxmox cloud-image provisioning (`terraform/modules/images`), VM definitions (`terraform/modules/proxmox_vm`), and USB passthrough mapping (`terraform/modules/usb_resource_mapping`).
- **Bootstrap Root**: Dedicated standalone bootstrap root (`terraform/bootstrap/seaweedfs`) provisioning an S3-compatible SeaweedFS object storage VM for remote state without circular dependencies.
- **Environment Composition**: Live environment root (`terraform/live/onprem-pve`) managing network bridges, guest VMs, boot order, and cloud-init credentials.
- **Provider Multi-Platform Locks**: Deterministic provider lockfiles (`.terraform.lock.hcl`) supporting `linux_amd64`, `linux_arm64`, and `darwin_arm64`.

### 2. Configuration Management & Fleet Operations (Ansible)
- **Modular Roles**: Reusable roles for Docker engine setup, SSH daemon hardening, system user creation, SeaweedFS S3 storage clustering, and Zabbix Agent 2 monitoring fleet rollout.
- **Deterministic UID/GID Allocation**: Central numeric identity registry (`inventory/group_vars/all/uid_registry.yml`) preventing privilege collisions across Linux guests.
- **Least-Privilege Deployments**: Role-tailored service accounts and restricted sudo wrappers for automated container deployments.

### 3. Supply-Chain Security & Local CI Parity
- **Static Multi-Scanner Pipeline**: Runs `gitleaks` (secret scanning), `trivy` (IaC misconfigurations), `checkov` (policy adherence), `tflint` (Terraform linter), `ansible-lint`, `shellcheck`, and `yamllint`.
- **Security Exception Registry**: Audited, schema-enforced exception catalog (`security/exceptions/`) with mandatory expiration dates and rationale.
- **CycloneDX SBOM & Evidence Manifest**: Automated Software Bill of Materials (SBOM) generation (`scripts/ci/generate-sbom.py`) cataloging lockfiles, dependencies, and SHA-256 integrity digests.

---

## Repository Map

```text
.github/workflows/          Static GitHub Actions CI pipelines
ansible/infra-ops/       Ansible orchestration root
  inventory/                Inventory group variables and example hosts
  playbooks/                Guest orchestration playbooks
  roles/                    Reusable configuration roles (docker, ssh, users, etc.)
docs/                       Diataxis documentation
  explanation/              Architecture, security model, and design records
  how-to/                   Task-oriented operational procedures
  reference/                Input variables, tool versions, and policies
scripts/ci/                 Local CI parity validation scripts and scanners
security/exceptions/        Audited security exception registry
terraform/
  bootstrap/seaweedfs/      Standalone S3 backend VM bootstrap root
  live/onprem-pve/          Environment-specific composition
  modules/                  Reusable Terraform modules (bridges, vm, images, usb)
tests/ci/                   Unit tests for CI evaluators and schemas
```

---

## Sanitization & Synthetic Data Notice

This repository is a curated, history-free public export of an operational on-premises environment. To protect operational security:
- **IP Addressing**: All host addresses, gateways, and subnets use official RFC 5737 (`192.0.2.0/24`, `198.51.100.0/24`) and RFC 3849 (`2001:db8::/32`) test ranges.
- **Domains**: All domain names use the reserved `.example.invalid` pseudo-TLD (RFC 2606 / RFC 6761).
- **Credentials & Keys**: All API tokens, passwords, and SSH keys have been replaced with invalid dummy placeholders.
- **Workloads**: Application payloads and private client references have been generalized into neutral architectural patterns.
- **No Live Access**: Defaults in this repository cannot target the live host or private environment.

For full architectural and security details, see [`docs/explanation/sanitized-architecture-and-security-model.md`](docs/explanation/sanitized-architecture-and-security-model.md).

---

## Local Validation Quickstart

To run the full suite of static security scans, linting, and formatting checks locally:

```bash
# 1. Install prerequisites (Python, Terraform, TFLint, Gitleaks, Checkov, Trivy)
pip install -r requirements.txt

# 2. Run master validation suite
./scripts/ci/validate-all.sh
```

---

## License

This project is licensed under the [MIT License](LICENSE).
