# On-Premises PVE platform engineering project roadmap

## Purpose

This document is the long-term project reference for evolving this On-Premises PVE
private cloud into a modern platform-engineering environment. It describes the
platform capabilities already represented in repository infrastructure-as-code
(IaC), the important gaps between the current state and a mature internal
platform, and a curated set of implementation projects.

This is an **explanation** document. It records the rationale and sequencing
for future work; it is not authorization to change the Proxmox host, OPNsense,
or any guest. Each selected project must receive its own design, how-to guide,
risk review, and Terraform/Ansible implementation plan before it is applied.

## Current baseline

The repository already supports a useful VM-first platform foundation:


| Capability               | Current repository implementation                                                                                                              | Platform value                                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Virtualization lifecycle | Reusable `terraform/modules/proxmox_vm` module composes OPNsense, Zabbix, n8n, SampleApp staging, and managed-client VMs from `terraform/live/onprem-pve/`. | Repeatable VM definitions, cloud-init input, lifecycle flags, boot order, resource sizing, and PVE tags.          |
| Networking               | Terraform composes `vmbr0`, the OPNsense LAN bridge, and an isolated OPNsense sync bridge. OPNsense is modeled as a three-NIC router VM.       | Network segmentation, routed management, firewall experimentation, and an eventual high-availability edge design. |
| Guest configuration      | `ansible/infra-ops/` contains roles for users, SSH, Docker, Zabbix Agent 2, local-secret loading, and the SampleApp host baseline.            | Idempotent baseline configuration and safer day-two guest operations.                                             |
| Identity and access      | Ansible uses a UID/GID registry, account lifecycle checks, SSH key allow-lists, and SSH hardening.                                             | Consistent identity allocation and lower risk of account or shared-storage ownership collisions.                  |
| Monitoring               | Zabbix VM definitions, Zabbix Agent 2 role, tag policy, and an implementation roadmap are present.                                             | A workable starting point for infrastructure and guest health monitoring.                                         |
| Application hosts        | Dedicated n8n and SampleApp staging/production host definitions plus Docker Compose readiness exist.                                             | Real consumers of the platform and a path toward application delivery automation.                                 |
| Images and storage       | Terraform imports cloud images; USB resource mapping and USB SSD storage guidance are documented.                                              | A foundation for image lifecycle, capacity, backup, and storage-resilience work.                                  |
| Operations documentation | The repository uses tutorials, how-to guides, reference pages, and explanation documents.                                                      | Reproducible operations and a place to capture future architectural decisions.                                    |


### Current operating constraints

The platform should evolve without bypassing existing safety boundaries:

- Proxmox VE is a real, network-sensitive host. Network, firewall, gateway,
storage, boot order, and guest lifecycle changes need reviewed plans and
explicit rollback steps.
- The current environment is single-host and VM-centric. Designs that claim
high availability must distinguish application-level resilience from true
host-failure resilience.
- Secrets, cloud-init passwords, API tokens, private keys, state files, plans,
appliance exports, and downloaded VM media must remain outside Git.
- Existing Ansible deliberately does **not** manage application deployment,
OPNsense firewall policy, DNS, NTP, Tailnet enrollment, backups, reboots, or
monitoring for SampleApp hosts without an approved role and runbook.
- The ignored, untracked OPNsense export in the repository root must not be
committed. Appliance exports may contain credentials, certificates, private
topology, and configuration secrets; store such material under ignored
`configs/` or an approved encrypted backup location.

## Platform maturity gaps

The highest-value gaps between the current baseline and a modern internal
platform are:

1. No continuous IaC validation, security scanning, or policy gate is visible.
2. Cloud images are downloaded/imported but not yet built, hardened, tested,
 versioned, signed, or promoted as golden images.
3. Terraform state strategy, change-review automation, and drift detection are
 not represented as platform capabilities.
4. Secret handling is local-file based rather than centralized, short-lived,
 audited, and automatically rotated.
5. Zabbix establishes monitoring, but centralized logs, distributed traces,
 OpenTelemetry instrumentation, service-level objectives (SLOs), and
 error-budget alerting are not yet established.
6. Backup, restore verification, disaster-recovery objectives, and recurring
 recovery drills are not yet encoded as a platform service.
7. Network policy is pivotal to the lab but is not yet fully declarative and
 continuously tested as network-as-code.
8. There is no Kubernetes, GitOps, service catalog, self-service workflow, or
 multi-tenant developer experience yet.

## Project catalog

The following projects are intentionally ambitious. They are ordered broadly
from foundational controls toward higher-level developer platform capabilities;
the numeric priority is a suggested learning and dependency order, not a fixed
commitment.


| Priority | Project                                             | Outcome                                                                                                                                   | Key skills                                                                                     | Dependencies and scope notes                                                                                                    |
| --------: | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 1        | Infrastructure supply-chain security pipeline       | CI validates Terraform, Ansible, shell, Markdown, secrets, dependencies, and IaC policy before merge.                                     | CI/CD, Trivy, Checkov, tfsec, `ansible-lint`, ShellCheck, SBOMs, provenance.                   | Start with non-mutating checks and protected branches. Do not let CI apply PVE changes initially.                               |
| 2        | Platform landing zone for On-Premises PVE                  | A standard workload contract defines VM classes, tags, sizing, network placement, access, image, monitoring, backup class, and ownership. | Terraform module design, metadata models, conventions, architecture decision records.          | Generalize existing `proxmox_vm` composition without hiding high-risk settings.                                                 |
| 3        | Proxmox golden-image factory                        | Packer-built, hardened, tested, versioned Ubuntu/Debian images replace ad hoc cloud-image consumption where appropriate.                  | Packer, cloud-init, image testing, CIS-style hardening, SBOMs, signing.                        | Keep imported images separate from ISO installer media; test in isolated VMs before promotion.                                  |
| 4        | IaC state, change review, and drift platform        | Remote state, locked change workflow, scheduled read-only plans, drift reports, and approved remediation process.                         | Terraform/OpenTofu state design, review workflows, drift triage, auditability.                 | Do not expose state or provider credentials; use plans only after verifying safe scope.                                         |
| 5        | Policy-as-code for PVE and guest standards          | Machine-enforced rules prevent unsafe definitions and missing operating metadata.                                                         | OPA/Rego, Conftest, risk classification, reusable policy tests.                                | Examples: required tags; defined owner; no plaintext secrets; network/firewall changes require risk metadata.                   |
| 6        | Backup, disaster recovery, and restore verification | Encrypted backup schedules, RPO/RTO classes, documented restore procedures, and scheduled isolated restore tests.                         | Proxmox Backup Server, retention design, encryption, recovery testing, incident procedures.    | Prioritize restore evidence over backup-job success; account for USB SSD limitations and off-host copies.                       |
| 7        | Observability platform                              | Metrics, logs, traces, dashboards, alert routing, and host/application telemetry complement existing Zabbix.                              | Prometheus, Grafana, Loki, Tempo, OpenTelemetry, alert engineering.                            | Retain Zabbix where it is useful; introduce components incrementally to control storage and operational overhead.               |
| 8        | SLO and error-budget engineering                    | Service ownership, SLIs, SLOs, burn-rate alerts, and reliability reviews guide operational decisions.                                     | Reliability engineering, service catalog design, dashboard and alert tuning.                   | Begin with OPNsense connectivity, PVE availability, Zabbix, n8n, and SampleApp staging.                                           |
| 9        | Secrets-management and private-PKI platform         | Centrally managed secrets, workload identity, short-lived credentials, and automated certificate lifecycle.                               | Vault or OpenBao, PKI, OIDC/AppRole, ACME, secret rotation, Ansible/Terraform integration.     | Migrate one low-risk workload first; never bulk-migrate secrets without a rollback and recovery plan.                           |
| 10       | Zero-trust access plane                             | Identity-aware access replaces broad long-lived SSH access and improves operator auditability.                                            | Tailscale/Headscale, OIDC, SSH certificates, access review, device posture.                    | Align with current key-only SSH policy; do not change Tailnet policy without a dedicated design.                                |
| 11       | Network-as-code for OPNsense                        | Firewall aliases, rules, NAT, DHCP/DNS, VLANs, and change validation become declarative and reviewable.                                   | OPNsense API automation, Terraform provider patterns, network design, test and rollback plans. | High risk: stage on isolated networks; retain console access and tested rollback before production policy changes.              |
| 12       | OPNsense HA and resilient edge                      | A tested paired-firewall design uses the existing sync-network concept for failover and state synchronization.                            | CARP, pfsync, routing, gateway failover, failure testing.                                      | This improves edge resilience but cannot make a single physical PVE host resilient to host failure.                             |
| 13       | GitOps Kubernetes platform on Proxmox               | Kubernetes clusters are provisioned on PVE and workloads reconcile from Git.                                                              | Kubernetes, Cilium, Gateway API, Argo CD or Flux, Helm, Kustomize, RBAC.                       | Provision separate control-plane/worker VM classes; start non-HA if hardware capacity is limited.                               |
| 14       | Service mesh and progressive delivery lab           | Canary and blue/green releases use traffic shifting, health analysis, and automated rollback.                                             | Argo Rollouts/Flagger, service mesh or eBPF networking, release engineering.                   | Build only after Kubernetes, metrics, and an application workload are stable.                                                   |
| 15       | Internal developer platform and self-service API    | Developers request standardized environments and services without editing raw infrastructure definitions.                                 | Backstage, templates, Crossplane or Terraform automation, RBAC, approval flows.                | Model existing SampleApp staging as the first platform consumer and golden path.                                                  |
| 16       | Ephemeral preview-environment platform              | Pull requests create short-lived isolated application environments with automatic cleanup.                                                | CI/CD, dynamic provisioning, ingress, environment lifecycle, quotas, secrets injection.        | Use TTL cleanup, spend/capacity safeguards, and namespace/VM network isolation.                                                 |
| 17       | Platform CI runner fleet                            | Short-lived isolated build runners are provisioned and retired automatically.                                                             | GitHub Actions/GitLab Runner, VM snapshots, runner isolation, caching, credential control.     | Place runners in segmented networks and prevent access to PVE credentials by default.                                           |
| 18       | Event-driven infrastructure operations              | Monitoring and platform events create audited, human-approved operational workflows.                                                      | n8n, webhooks, ChatOps, runbook automation, event enrichment.                                  | Start with notifications, evidence collection, and approval requests; avoid unattended destructive remediation.                 |
| 19       | Configuration drift detection and reconciliation    | Scheduled checks compare live PVE/guest state to declared desired state and guide safe correction.                                        | Terraform plans, Ansible check mode, compliance reporting, reconciliation design.              | Separate detection from mutation; retain operator review for network and lifecycle drift.                                       |
| 20       | FinOps and capacity-engineering dashboard           | Resource budgets, growth forecasts, allocation reports, and rightsizing recommendations become visible.                                   | Capacity modeling, PromQL, cost/showback models, forecasting.                                  | Use existing sizing and allocation documentation as the initial source of truth.                                                |
| 21       | Software catalog and architecture knowledge graph   | Services, VMs, owners, dependencies, runbooks, SLOs, and recovery classes are discoverable.                                               | Backstage catalog, metadata governance, ADRs, CMDB concepts.                                   | Generate selected facts from Terraform/Ansible rather than maintaining all facts manually.                                      |
| 22       | Multi-tenant sandbox platform                       | Independent project environments receive boundaries, quotas, expiry, network isolation, and access control.                               | Multi-tenancy, RBAC, quotas, isolation, lifecycle automation.                                  | Start with logical isolation; do not promise strong security tenancy without a formal threat model.                             |
| 23       | Security operations and detection-engineering lab   | Central security telemetry and detections cover PVE, OPNsense, Linux, SSH, Docker, and Kubernetes.                                        | Wazuh, OpenSearch, Sigma, Falco, auditd, incident investigation.                               | Define retention, privacy, and disk budgets before ingesting broad logs.                                                        |
| 24       | Chaos engineering and game-day lab                  | Controlled faults validate recovery, observability, and operational runbooks.                                                             | Fault injection, resilience testing, incident command, postmortems.                            | Use isolated workloads first; never inject failures into PVE networking or firewall paths without an explicit safe test window. |
| 25       | Platform scorecard and maturity model               | A measurable view of delivery, security, reliability, observability, and developer experience guides investment.                          | DORA metrics, maturity models, scorecard design, engineering governance.                       | Maintain as a lightweight decision tool, not a compliance exercise.                                                             |


## Recommended delivery sequence

The following sequence builds reusable safety and operability before developer
self-service:

1. Build the **infrastructure supply-chain security pipeline**.
2. Define the **On-Premises PVE platform landing zone** and workload metadata contract.
3. Deliver the **golden-image factory** and the **state/change/drift platform**.
4. Implement **backup, recovery, and restore verification** before expanding
 the number of critical workloads.
5. Build the **observability platform**, then establish initial **SLOs**.
6. Add a **secrets-management and private-PKI platform** and a **zero-trust
 access plane**.
7. Design and validate **network-as-code**; optionally pursue OPNsense HA only
 after hardware, power, and physical topology make the resilience claim real.
8. Provision a **GitOps Kubernetes platform on Proxmox**.
9. Build the **internal developer platform**, then add preview environments,
 runner fleets, and multi-tenant sandbox capabilities.
10. Use event-driven operations, detection engineering, chaos experiments, and
  the platform scorecard as continuous-improvement loops.

## How to choose the next project

Choose a project based on the platform constraint you want to solve, not only
the technology you want to learn:


| If the main problem is...                   | Start with...                                        | Proof of completion                                                                  |
| ------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Unsafe or inconsistent changes              | Supply-chain pipeline and policy-as-code             | Unsafe IaC changes fail before merge with actionable messages.                       |
| Slow or inconsistent VM delivery            | Landing zone and golden-image factory                | A documented VM class is provisioned predictably from a tested image.                |
| Weak recovery confidence                    | Backup/DR restore verification                       | A representative workload is restored in isolation within the declared RTO.          |
| Poor operational visibility                 | Observability and SLOs                               | Operators can diagnose an injected guest/service failure from telemetry and alerts.  |
| Long-lived credentials or unmanaged secrets | Secrets/PKI and zero trust                           | A workload receives renewable secrets or certificates without committing them.       |
| Manual developer environment setup          | Kubernetes, GitOps, then internal developer platform | A developer requests an approved environment through a catalog/template.             |
| Risky network changes                       | Network-as-code                                      | A staged firewall/network policy change is reviewed, tested, and rolled back safely. |


## Standard project-definition template

Before implementation, create a project page under the appropriate Diataxis
location and include:

1. **Problem and intended platform user** — Who has friction and why the
 platform should own the solution.
2. **Scope and non-goals** — Explicitly state what remains operator-managed.
3. **Architecture and trust boundaries** — Include network paths, identities,
 secret flows, state, and external dependencies.
4. **IaC and configuration contract** — Define Terraform inputs/outputs,
 Ansible inventory/variables, ownership tags, and lifecycle metadata.
5. **Security and failure analysis** — Identify blast radius, approvals,
 rollback, recovery, and logging requirements.
6. **Validation plan** — Include static checks, plan/check-mode commands,
 functional tests, and success evidence.
7. **Operational runbook** — Include deployment, routine operation,
 troubleshooting, rollback, and restore procedures.
8. **Documentation placement** — Add how-to and reference pages for operators;
 preserve design reasoning in an explanation page.

## Related repository documentation

- [Infrastructure supply-chain security pipeline](infrastructure-supply-chain-security-pipeline.md)
defines the Priority 1 trust model, validation gates, remote-state prerequisites,
and restricted Terraform plan/apply workflow.
- [Terraform operations](../reference/terraform-operations.md) documents safe
plan/apply expectations and Terraform workflow.
- [PVE sizing guidelines](../reference/pve-sizing-guidelines.md) provides the
current resource-allocation basis for new workloads.
- `REF-089 sandbox topology`
documents the isolated OPNsense sync-network context.
- [OPNsense HA Tailguard design](opnsense-ha-tailguard-design.md) is the
existing resilience design reference for paired-firewall exploration.
- `Zabbix VM monitoring roadmap` remains the detailed
monitoring-learning plan and should be reconciled with any broader
observability implementation.
- [Infrastructure Ansible operations](../how-to/infrastructure-ansible-operations.md)
documents safe execution of the current guest-configuration project.

## Recommended Sequence

  For the strongest “modern platform engineering” learning path, build these in order:

1. Infrastructure Supply-Chain Security Pipeline
2. Proxmox Golden Image Factory
3. Backup/DR and Restore Verification Platform
4. Observability Platform
5. GitOps Kubernetes Platform on Proxmox
6. Internal Developer Platform / Self-Service Environment API
7. Ephemeral Preview Environments
8. Policy-as-Code and Multi-Tenant Sandbox Platform

## Review cadence

Review this roadmap after every completed platform project and at least twice
a year. Update priorities using real constraints: host capacity, storage health,
backup restore evidence, reliability incidents, service demand, security
findings, and the value of new self-service capabilities. Do not expand the
platform merely to add tools; retire or avoid components that do not improve a
documented operator or developer outcome.
