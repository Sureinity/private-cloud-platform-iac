# Infrastructure supply-chain security pipeline

## Status

- **State:** Proposed
- **Decision date:** 2026-09-04
- **Intended operator:** Private Cloud Platform repository owner and infrastructure operator
- **Initial CI platform:** GitHub Actions in a private repository
- **Initial runner model:** GitHub-hosted runners only
- **Related roadmap item:** Priority 1 in the [platform engineering project roadmap](platform-engineering-project-roadmap.md)

## Purpose

This project establishes a controlled path from an infrastructure change in Git
to validated, reviewable, and auditable Terraform execution. It protects the
repository against accidental defects, committed secrets, compromised CI
dependencies, unsafe infrastructure definitions, state corruption, plan
tampering, and overprivileged automation.

The pipeline begins with non-mutating validation and introduces live Proxmox
access only after its state, identity, network, recovery, and approval controls
have been tested independently. CI must fail closed: inability to validate an
identity, retrieve authoritative state, acquire a state lock, verify a plan, or
classify a risky action is a reason not to apply.

This design uses supply-chain maturity concepts such as dependency pinning,
software bills of materials (SBOMs), provenance, immutable inputs, and
verifiable evidence. It does not claim a particular SLSA level until the
corresponding requirements are implemented and evidenced.

## Problem

The repository has Terraform, Ansible, shell, YAML, templates, and Markdown,
but it does not yet have a continuous control plane that applies the same
checks to every proposed change. Validation currently depends on an operator
remembering and correctly running local commands. Terraform also uses local
state and local runtime inputs, so it cannot safely support an immutable,
reviewable CI plan and apply flow.

The principal failure modes are:

- malformed Terraform, Ansible, shell, YAML, or documentation merging unnoticed
- a token, key, state file, plan, appliance export, or local payload entering Git
- a compromised or mutable GitHub Action gaining excessive permissions
- known unsafe IaC patterns being added without an explicit exception
- unreviewed code receiving access to the home network or Proxmox API
- concurrent Terraform processes corrupting or racing state
- a different commit or plan being applied from the one an operator reviewed
- Terraform state becoming unavailable with the PVE host that it describes
- CI applying destructive, network-sensitive, storage-sensitive, or replacement actions

## Intended outcomes

The project is complete when:

1. Every pull request receives deterministic, named checks for all tracked
   infrastructure and documentation formats.
2. Pull-request code cannot access repository deployment secrets, the tailnet,
   SeaweedFS state, the Proxmox API, or plan decryption keys.
3. New secrets and high-impact security regressions fail before merge with an
   actionable message.
4. Existing accepted findings are represented by owned, justified, expiring
   exceptions rather than unbounded scanner ignores.
5. Terraform state is remotely stored, locked, versioned, encrypted in transit,
   backed up off-host, and proven recoverable.
6. A trusted operator can create an immutable plan for the current protected
   `main` commit and later apply exactly that plan after verifying its digest.
7. Normal CI apply rejects deletion, replacement, host networking, firewall,
   gateway, storage, and other declared high-risk changes.
8. The pipeline emits a sanitized evidence record containing the commit,
   versions, checks, plan classification, actor, and result without publishing
   secrets, raw state, or raw Terraform plan JSON.

## Scope

### Included

- GitHub Actions workflow and branch-protection design
- local and CI-equivalent static validation
- repository hygiene and secret scanning
- Terraform, Ansible, shell, YAML, Markdown, and GitHub Actions validation
- dependency pinning and automated dependency updates
- IaC security scanning and a starter policy-as-code control set
- SBOM and evidence-manifest generation
- SeaweedFS S3-compatible Terraform state, locking, versioning, and recovery
- Tailscale workload identity federation for trusted GitHub-hosted jobs
- separately authorized Terraform plan and apply jobs
- risk classification, plan encryption, integrity verification, and audit evidence
- documentation for operation, exceptions, credential rotation, and recovery

### Excluded from the initial implementation

- CI execution of Ansible against guests
- CI access from pull-request jobs to any private infrastructure
- automatic Terraform apply after merge
- unattended drift remediation
- destruction or replacement of PVE resources from the normal apply workflow
- CI changes to PVE bridges, gateways, host networking, firewall policy, or storage
- provisioning the SeaweedFS VM from the Terraform state stored by that VM
- public exposure of SeaweedFS or the Proxmox API
- mandatory paid GitHub Advanced Security features
- a claim of strong artifact provenance for artifacts that are not yet built by this repository

The golden-image project should consume the reusable SBOM, signing, and
provenance interfaces established here when the repository begins producing VM
images or other deployable artifacts.

## Design principles

- **Untrusted first:** Treat pull-request content and its dependency changes as
  untrusted input.
- **No ambient authority:** A job receives only the permissions and credentials
  required for its specific stage.
- **Immutable handoff:** Apply consumes an encrypted saved plan tied to one
  protected commit, not a newly generated approximation.
- **Fail closed:** Missing evidence, unknown actions, stale inputs, lock failure,
  or network failure blocks mutation.
- **Separate detection from mutation:** Validation and planning are safe to run
  more broadly than apply.
- **No self-hosting dependency loop:** The main state backend must be recoverable
  without the main Terraform state.
- **Local parity:** CI calls version-pinned repository commands that operators can
  run locally.
- **Evidence without leakage:** Logs and artifacts contain enough information to
  review an operation but not enough to recover credentials or sensitive state.
- **Exceptions are debt:** Every exception has an owner, rationale, narrow scope,
  and expiry.

## Threat model

### Protected assets

- Proxmox API authority and guest lifecycle control
- Terraform state and its sensitive values
- SeaweedFS state objects, lock objects, and access credentials
- Tailscale identity and ACL policy
- cloud-init passwords and SSH material
- GitHub deployment secrets and plan-decryption keys
- trusted workflow definitions, policy definitions, and dependency lockfiles
- plan artifacts and evidence identifying what was approved

### Threat actors and events

- an accidental contributor mistake
- malicious code introduced through a pull request
- a compromised third-party GitHub Action or downloaded tool
- a dependency update that changes behavior unexpectedly
- a repository maintainer account used outside the intended workflow
- stale or tampered plan reuse
- concurrent plan/apply processes
- loss or compromise of the SeaweedFS VM
- transient loss of Tailscale, SeaweedFS, or PVE connectivity during execution

### Required mitigations

| Threat | Primary controls |
| --- | --- |
| Pull-request code requests credentials | GitHub-hosted untrusted jobs, read-only permissions, no secrets, no Tailscale, no `pull_request_target` execution |
| Action tag is retargeted | Third-party Actions pinned to reviewed full commit SHAs; automated updates arrive as reviewed pull requests |
| Secret is committed | Gitleaks, forbidden-file checks, immediate block, incident response and credential rotation |
| Scanner finding is silently ignored | Central exception registry with owner, path, rationale, approval, and expiration validation |
| State is concurrently modified | Terraform S3 lockfile enabled and tested against SeaweedFS; shared concurrency group for live operations |
| Plan artifact is viewed or modified | Client-side encryption before upload, short retention, SHA-256 verification, trusted provenance metadata |
| Different code is applied | Current protected `main` SHA verification, successful required checks, lockfile digest verification, saved-plan apply |
| Apply gains excessive PVE authority | Distinct plan and apply tokens, documented privilege matrix, short-lived network identity, restricted workflow environment |
| Backend fails with PVE | SeaweedFS bootstrap independence, versioning, encrypted off-host backup, isolated restoration exercises |
| Dangerous plan reaches CI apply | Plan JSON risk classifier; hard rejection of destructive and sensitive resource classes |

## Trust architecture

### Untrusted validation boundary

Pull requests and ordinary pushes execute only static checks on GitHub-hosted
ephemeral runners. The workflow uses no PVE, S3, Tailscale, cloud-init, SSH, or
plan-encryption secrets. Its default `GITHUB_TOKEN` permission is `contents: read`; any additional read permission
(such as `pull-requests: read` for Gitleaks commit scanning on pull requests) is scoped strictly
to the specific job that requires it. All repository checkouts explicitly set `persist-credentials: false`
to eliminate runner credential persistence into `.git/config` and prevent token exposure via artifact uploads.

The pipeline must not run contributor-controlled commands under
`pull_request_target`, check out untrusted code into a privileged job, or pass
untrusted artifact content to a trusted workflow without validation.

### Trusted plan boundary

The plan workflow is manually dispatched for an exact commit. Before receiving
network or backend credentials, it verifies that:

- the commit exists in this repository
- the commit is the current protected `main` head
- all required validation checks succeeded for that commit
- the workflow definition comes from the protected branch
- the actor has repository write or administrative authority

The runner joins Tailscale as an ephemeral `tag:github-plan` node through GitHub
workload identity federation. The Tailscale policy permits only the SeaweedFS S3
endpoint and PVE API endpoint needed by Terraform. It does not permit SSH,
guest administration, unrelated tailnet services, or broad subnet access.

The job receives a read-oriented PVE token and state credentials specific to
planning. The PVE provider's exact read permissions must be determined through
an API audit before rollout; failure due to a missing read permission must not
be solved by assigning an administrator token.

### Trusted apply boundary

Apply is a second manual workflow, not an automatic continuation after merge.
It receives:

- plan workflow run ID
- commit SHA
- expected encrypted-plan digest
- exact typed confirmation containing the commit and digest

The apply workflow verifies the producer workflow, producer conclusion, actor,
commit, current `main` head, required checks, Terraform version, provider
lockfile digest, artifact age, artifact checksum, plan checksum after decryption,
and current state compatibility. It rejects artifacts older than 24 hours.

The runner joins as `tag:github-apply` and receives a separate PVE write token.
The repository owner is the initial solo approver. GitHub environment reviewer
controls may be added when available, but the design does not depend on a
second person or paid-only feature.

## Workflow model

### Pull-request validation workflow

Use path-aware jobs while keeping check names stable for branch protection.
Documentation-only changes may skip expensive infrastructure scanners only when
the named check still reports success and explains the skip.

Required checks are:

| Check | Required behavior |
| --- | --- |
| Repository hygiene | Run `git diff --check`; reject tracked states, plans, appliance exports, media, private keys, local payloads, and generated artifacts |
| Terraform format | Run `terraform fmt -check -recursive` |
| Terraform validate | Initialize with `-backend=false` and validate `terraform/live/onprem-pve/`, bootstrap roots, plus every reusable module |
| Terraform lint | Run TFLint with pinned plugins and configuration |
| IaC security | Run Trivy configuration scanning and Checkov with repository policy and exception handling |
| Ansible lint | Run YAML checks and `ansible-lint` against the Ansible project |
| Ansible syntax | Parse inventory and syntax-check every playbook without contacting guests |
| Shell | Run `bash -n` and ShellCheck for tracked scripts; validate shell-bearing templates where reliable |
| Markdown | Check headings, fenced blocks, trailing whitespace, and internal links |
| Secrets | Run Gitleaks on the proposed change and relevant history; do not baseline real secrets |
| Workflow security | Run actionlint and zizmor; enforce full-SHA pins, explicit permissions, timeouts, and safe triggers |
| Policy tests | Run positive and negative fixtures for every repository-specific policy |
| Evidence | Generate a source/tool SBOM and manifest containing commit and tool-version digests |

Every job must set a timeout, use a least-privilege permissions block, avoid
printing environments or command tracing around secrets, and clean sensitive
workspace files in an `always()` cleanup step.

### Scheduled security workflow

Run weekly and on manual request:

- full-history secret scan
- full repository Trivy and Checkov scans
- dependency freshness checks
- OpenSSF Scorecard review where supported
- exception-expiry report
- SBOM regeneration and comparison
- action and tool pin freshness report

Scheduled work reports newly discovered upstream findings against the current
protected branch. It does not access PVE or apply changes.

### Trusted Terraform plan workflow

The workflow sequence is:

1. Validate dispatch inputs, actor authority, and current `main` SHA.
2. Confirm all required checks succeeded for the SHA.
3. Check out the exact SHA and verify no tracked runtime artifacts exist.
4. Install the repository-pinned Terraform and helper tool versions using
   verified checksums or pinned container digests.
5. Join Tailscale with the plan identity and test only the required endpoints.
6. Generate backend configuration without embedding credentials.
7. Provide Terraform inputs through individual `TF_VAR_*` variables and secrets.
8. Run format, initialization, validation, and lock acquisition.
9. Generate a saved plan without `-target`.
10. Convert the plan to JSON only in the private runner workspace.
11. Extract a sanitized action summary and classify risk without uploading raw JSON.
12. Reject unclassifiable, destructive, replacement, network, firewall, gateway,
    storage, or otherwise forbidden actions.
13. Encrypt the binary plan with a repository-controlled public key.
14. Create plan and evidence manifests with SHA-256 digests.
15. Scan summaries and manifests for accidental secret disclosure.
16. Upload only encrypted plan material and sanitized evidence with 24-hour retention.
17. Remove raw plan, raw JSON, generated variables, backend files containing
    runtime settings, and transient credentials before job completion.

A no-change plan remains valid evidence but does not require an apply workflow.

### Trusted Terraform apply workflow

The workflow sequence is:

1. Validate actor, workflow run ID, commit SHA, digest, and typed confirmation.
2. Confirm the plan producer was the trusted plan workflow and completed successfully.
3. Confirm the planned commit remains the current protected `main` head.
4. Confirm the artifact is no older than 24 hours and has not already been applied.
5. Re-run repository validation and compare tool/provider lock digests.
6. Join Tailscale using the apply identity.
7. Acquire the same non-cancelling `terraform-live` concurrency group.
8. Download the encrypted artifact and verify its outer digest.
9. Decrypt it using the apply environment's private key and verify its inner digest.
10. Recheck the stored risk classification and reject any forbidden action.
11. Apply the exact saved plan without `-auto-approve` being exposed as a general operator interface.
12. Run a post-apply `terraform plan -detailed-exitcode` using the same inputs.
13. Require exit code zero; otherwise report residual drift without performing remediation.
14. Record a sanitized result manifest and mark the plan identifier as consumed.
15. Remove decrypted plans, generated variables, and credentials in an unconditional cleanup step.

GitHub Actions concurrency must use one non-cancelling group for every operation
that can lock or modify the live state. A newer workflow must wait rather than
cancel an operation that may already be communicating with PVE.

## Repository tooling contract

### Local parity

Place orchestration under a dedicated `scripts/ci/` area or an equivalently
clear repository task interface. GitHub workflows should call these scripts
rather than reproduce large command sequences in YAML.

Provide commands for:

- fast validation
- full validation
- Terraform-only validation
- Ansible-only validation
- shell validation
- documentation validation
- security scanning
- policy tests
- evidence and SBOM generation

Scripts must be non-mutating, deterministic, shell-safe, and runnable from any
working directory. They may create ignored temporary files but must clean them
and never change tracked files.

### Version management

Pin:

- the Terraform CLI to a tested release supporting S3 lockfiles
- TFLint and each TFLint plugin
- Trivy, Checkov, Gitleaks, actionlint, zizmor, ShellCheck, Markdown tooling,
  Ansible, and SBOM tooling
- GitHub Actions to full commit SHAs
- container images to immutable digests when containers are used

Record checksums for downloaded release assets. Dependabot should manage GitHub
Actions and Terraform dependencies. Other tool upgrades should arrive through a
reviewed update process that records the old version, new version, release
notes, changed findings, and rollback method.

### Scanner responsibilities

- **Gitleaks:** credential and private-key detection
- **TFLint:** Terraform correctness and provider-aware linting
- **Trivy:** broad IaC configuration and repository scanning
- **Checkov:** complementary Terraform, Ansible, and GitHub Actions policy checks
- **actionlint:** GitHub Actions syntax and expression validation
- **zizmor:** GitHub Actions security analysis
- **ShellCheck:** shell correctness and portability risks
- **ansible-lint:** Ansible syntax, safety, and idempotency conventions
- **Conftest/OPA:** repository-specific infrastructure and workflow policy
- **SBOM tool:** SPDX JSON or CycloneDX JSON inventory of detectable source and tool dependencies

Do not add `tfsec` as another mandatory scanner because its Terraform coverage
overlaps the selected Trivy configuration scanner. Avoid adding multiple secret
scanners unless a documented gap justifies the operational noise.

## Policy-as-code contract

### Initial mandatory policies

- No tracked Terraform state, saved plans, crash logs, downloaded VM media,
  appliance exports, private keys, vault-password files, or secret payloads.
- Terraform provider sources and constraints must be explicit.
- The provider dependency lockfile must be present and must change only when the
  provider selection changes intentionally.
- CI cannot disable TLS verification for PVE, Tailscale, or SeaweedFS.
- Backend credentials cannot appear in Terraform source, backend files, command
  arguments, logs, or artifacts.
- Terraform variables carrying credentials or passwords must be marked sensitive.
- GitHub Actions require explicit permissions, timeouts, immutable action pins,
  and approved triggers.
- Privileged jobs cannot check out or execute pull-request-controlled code.
- Normal CI apply cannot process deletion, replacement, PVE bridge, host network,
  gateway, firewall, storage, or unknown resource classes.
- Suppressions cannot be inline unless the scanner requires it and the inline
  reference points to the central approved exception.

### Exception schema

Maintain one machine-readable exception registry. Each entry must include:

```yaml
id: SEC-EXAMPLE-001
rule: scanner-or-policy-rule-id
paths:
  - repository/relative/path
owner: operator-identity
rationale: Why the finding is currently acceptable
approved_on: YYYY-MM-DD
expires_on: YYYY-MM-DD
remediation: Concrete removal condition or follow-up work
```

Validation must reject duplicate IDs, missing fields, wildcard repository
scope, dates in the past, and exceptions longer than the configured maximum
period. The initial maximum is 90 days. Secret findings, state files, private
keys, and unsafe privileged pull-request execution cannot receive exceptions.

## Terraform state architecture

### Bootstrap boundary

The SeaweedFS VM is an out-of-band prerequisite. It must not be managed by the
same Terraform state it stores. Its VM definition, disks, credentials,
networking, backup, and recovery procedure remain separately managed until a
future bootstrap-state design is approved.

This prevents a circular dependency in which recovery of the state backend
requires the unavailable state stored inside it.

### Backend requirements

Use one dedicated bucket and object prefix for the On-Premises PVE live state. Require:

- valid TLS with hostname verification
- no public bucket or anonymous S3 access
- a dedicated state credential with the minimum object and listing permissions
- Terraform S3 `use_lockfile = true`
- bucket/object version retention sufficient to recover accidental overwrite or deletion
- durable SeaweedFS storage and monitored capacity
- audit logging for authentication and state-object operations
- encrypted off-host backup outside the PVE host
- documented endpoint, bucket, key, region placeholder, path-style behavior,
  and S3 compatibility flags without committed credentials

Terraform backend credentials must be supplied through standard environment
variables. Do not pass credentials in backend source, a checked-in backend
configuration, or `-backend-config` command arguments that may be captured in
shell history or Terraform working data.

### Compatibility qualification

Before state migration, test SeaweedFS with the exact Terraform version and
backend settings:

1. Initialize an isolated disposable state key.
2. Write and read a test state.
3. Start two operations and prove the second cannot acquire the `.tflock` object.
4. Interrupt a lock holder and document safe lock recovery.
5. Create multiple state versions and restore a selected previous version.
6. Delete a test object and recover it from retained versions or backup.
7. Verify TLS from a clean GitHub-hosted runner over Tailscale.
8. Verify the plan credential cannot perform write operations outside its prefix.
9. Verify audit records identify the credential and object operation.

If lock exclusion, version recovery, TLS, or least-privilege access fails, do not
migrate the authoritative state and keep CI plan/apply disabled.

### State migration procedure

The later implementation how-to must require:

1. Stop all Terraform processes and announce an exclusive maintenance window.
2. Record the local state's lineage, serial, checksum, and resource addresses.
3. Create two encrypted backups, including one outside the PVE host.
4. Validate the destination bucket and lock behavior again.
5. Configure the partial S3 backend without credentials in source.
6. Run `terraform init -migrate-state` from the trusted operator machine.
7. Pull the remote state and compare lineage, serial, checksum, and resources.
8. Run a refresh plan and investigate any unexpected difference.
9. Run a trusted CI plan and compare it with the local result.
10. Retain the encrypted pre-migration backup until at least one successful
    restore exercise and two normal Terraform changes have completed.

Do not delete or overwrite the local backup as part of automated cleanup.

### Backup and recovery

Back up state versions and the SeaweedFS metadata needed to locate and restore
them to encrypted storage outside the PVE host. Keep credential recovery
material in an approved password manager, not beside the backup.

Perform a quarterly isolated restore test that proves an operator can:

- provision or access a replacement S3-compatible endpoint
- restore the selected state version
- initialize Terraform against the recovery endpoint
- verify lineage, serial, and resource inventory
- generate a read-only plan without applying it
- return to the primary backend without creating split-brain state

## Terraform input contract

The current configuration loads the cloud-init password from a local file. To
support both safe local operation and GitHub Actions, add:

- nullable sensitive `cloud_init_password` for CI secret injection
- nullable `cloud_init_password_file` for local operator use
- validation requiring exactly one source
- one local effective password value consumed by VM modules

Retain the local-file workflow by default unless changing that default can be
done without breaking current ignored local inputs. CI must set the direct
password and disable the file source explicitly.

Supply the PVE API token, cloud-init password, SeaweedFS access key, SeaweedFS
secret key, and plan-decryption key as separate GitHub environment secrets.
Supply non-secret environment overrides as individual GitHub variables mapped
to `TF_VAR_*`. Do not place the active `terraform.tfvars`, host topology, or a
structured bundle of secrets into Git.

## Plan evidence and artifact format

### Encrypted plan bundle

The plan job uploads only:

- encrypted Terraform binary plan
- sanitized plan summary
- plan-risk report
- plan metadata manifest
- validation evidence manifest
- source/tool SBOM

The private decryption key is available only to the apply environment. The
corresponding public encryption key may be committed. Use an authenticated
encryption tool with a pinned version and verified binary provenance.

### Metadata manifest

Record at least:

- repository and workflow identity
- plan workflow run ID and actor
- commit SHA and protected branch
- plan creation and expiration timestamps
- Terraform version
- provider lockfile SHA-256
- policy/configuration digests
- backend bucket and key identifiers without credentials
- state lineage and serial before planning
- encrypted-plan SHA-256 and decrypted-plan SHA-256
- counts and addresses grouped by action class
- risk classification and the policy version that produced it
- validation check conclusions

The apply result adds the apply workflow run, actor, completion time, result,
and post-apply plan exit code. It must not include raw variable values, state,
provider responses, or raw plan JSON.

### Retention

- Encrypted saved plans expire after 24 hours.
- Sanitized validation and apply evidence follows a documented audit-retention
  period; begin with 90 days unless repository storage limits require less.
- Raw plan JSON, generated variable files, and decrypted plans are workspace-only
  and are removed in unconditional cleanup.
- SBOMs and tool manifests may be retained longer because they should not
  contain host credentials or Terraform values; scan them before upload.

## Risk classification and apply policy

Parse Terraform plan JSON locally and classify every resource action.
Classification code must be covered by fixtures for each Terraform action form,
including `create`, `update`, `delete`, `delete/create`, `create/delete`,
`read`, `no-op`, and unknown values.

### Allowed after manual approval

- no-op plans
- additive resources within approved resource types
- non-destructive updates that do not change a declared sensitive attribute or
  resource class

### Blocked from normal CI apply

- any delete or replacement
- PVE bridge or host networking changes
- gateways, routing, or firewall changes
- datastore, disk, EFI disk, cloud-init disk, or storage relocation changes
- resource imports, state moves not already committed and validated, or unknown actions
- broad VM lifecycle changes whose safety cannot be classified
- targeted plans using `-target`
- plans created from anything other than current protected `main`

A blocked plan may still produce sanitized evidence. Execution must return to
the local operator procedure with explicit rollback and console-recovery review.
Do not add a generic `allow_destructive` bypass to the initial workflow.

## Credentials and permissions

Maintain separate credentials for:

| Credential | Available to | Intended authority |
| --- | --- | --- |
| GitHub validation token | Untrusted checks | Read repository; narrowly scoped reporting if required |
| Tailscale plan identity | Trusted plan | Reach only PVE API and SeaweedFS endpoints |
| Tailscale apply identity | Trusted apply | Reach only PVE API and SeaweedFS endpoints |
| SeaweedFS plan credential | Trusted plan | Read state plus only the writes required for the tested lock protocol |
| SeaweedFS apply credential | Trusted apply | Read/write state and lock objects within one prefix |
| PVE plan token | Trusted plan | Provider-required read operations only |
| PVE apply token | Trusted apply | Minimum resource permissions for allowed creates and updates |
| Plan public key | Trusted plan and repository | Encrypt plan bundle only |
| Plan private key | Apply environment only | Decrypt approved plan bundle |

Document every required PVE privilege discovered during testing. Do not use the
root account, a full administrator token, a personal SSH key, or a reusable
Tailscale auth key to make automation convenient.

Rotate CI credentials after suspected exposure, operator change, permission
redesign, or a documented maximum age. Rotation must include a no-op plan test
before old credentials are revoked.

## Enforcement strategy

### Immediate blockers

Enable from the first protected pull request:

- formatting and syntax failures
- repository hygiene failures
- secret and private-key findings
- tracked state, plan, appliance export, or local payload findings
- unsafe privileged workflow patterns
- missing or mutable GitHub Action pins
- missing required workflow permissions or timeouts
- failed policy tests

### Phased security enforcement

1. Run Trivy, Checkov, TFLint, and other scanners in report mode to create the
   initial baseline.
2. Validate each finding; remediate obvious errors and false-positive causes.
3. Record only accepted pre-existing findings in the exception registry.
4. Block all new critical and high findings.
5. Report medium and low findings without blocking during the first rollout.
6. Review medium findings after operational noise is understood and promote
   appropriate rule classes to blocking.
7. Fail every expired exception and review the registry monthly.

Do not make a scan pass by excluding whole directories, disabling broad rule
families, or accepting an unreviewed generated baseline.

## Delivery phases

### Phase 0: Inventory and baseline

- Inventory repository file types, Terraform roots, modules, playbooks, scripts,
  templates, lockfiles, ignored sensitive classes, and local command requirements.
- Finalize the threat model and protected asset list.
- Select and pin the initial tool versions (recorded in [supply-chain-tool-versions.md](../reference/supply-chain-tool-versions.md)).
- Run scanners without changing branch protection.
- Remove any real secret exposure before continuing.
- Create the exception schema and policy fixtures.

**Exit evidence:** scanner baseline, tool manifest, threat model, and no known
tracked credentials.

### Phase 1: Deterministic merge gates

- Add local CI scripts and GitHub-hosted validation workflow.
- Add formatting, syntax, shell, Markdown, repository-hygiene, secret, workflow,
  and policy-test checks.
- Configure protected `main` rules and `CODEOWNERS` for workflows, policies,
  backend configuration, dependency locks, and privileged scripts.
- Add Dependabot for GitHub Actions, Terraform, and Python tooling with a 7-day cooldown policy.

**Exit evidence:** representative invalid fixtures fail their named checks and a
clean pull request cannot merge until every required check succeeds.

### Phase 2: Security, dependency, and evidence gates

- Add TFLint, Trivy, Checkov, scheduled scans, SBOMs, and evidence manifests.
- Establish the reviewed expiring baseline via central exception registry (`security/exceptions/`).
- Block new critical and high findings.
- Validate action/tool update and rollback procedures.

**Exit evidence:** new high-impact findings fail, accepted debt remains visible,
and expired exceptions fail automatically.

### Phase 3: SeaweedFS state qualification and migration

- Provision SeaweedFS independently.
- Configure TLS, bucket policy, credentials, versioning, monitoring, and off-host backup.
- Complete S3 lock and recovery qualification.
- Migrate state under an exclusive maintenance window.
- Perform an isolated restore exercise.

**Exit evidence:** verified lock exclusion, remote state equivalence, recovered
state plan, and encrypted off-host backup.

### Phase 4: Trusted plan

- Configure Tailscale workload identities, tags, and ACLs.
- Create separate plan and apply PVE tokens and state credentials.
- Implement the immutable plan workflow, risk classifier, encryption, and evidence.
- Run several representative plans while apply remains disabled.

**Exit evidence:** stable plans, no secrets in artifacts or logs, correct risk
classification, and proven denial of pull-request access.

### Phase 5: Restricted apply

- Implement the second manually dispatched apply workflow.
- Enforce current-main, artifact age, digest, actor, check, state, and
  classification validation.
- Exercise no-op and safe additive changes.
- Verify post-apply convergence and consumed-plan tracking.

**Exit evidence:** an authorized operator applies exactly one reviewed saved
plan and receives a zero-change verification plan afterward.

### Phase 6: Operations and improvement

- Finalize operator how-to and control reference pages.
- Add credential rotation, backend outage, lock recovery, and incident procedures.
- Schedule quarterly state restore tests and control reviews.
- Integrate future golden-image artifacts with SBOM, signing, and provenance.

**Exit evidence:** another authorized operator can follow the documentation
without needing undocumented repository knowledge.

## Test plan

### Static and fixture tests

Add isolated fixtures that prove:

- malformed Terraform fails format or validation
- invalid Ansible YAML and playbooks fail lint or syntax checks
- invalid shell fails `bash -n` or ShellCheck
- broken Markdown links or heading hierarchy fail
- an example token, private key, state, plan, and appliance export each fail
- an unpinned or overprivileged workflow action fails
- each starter policy has at least one allowed and rejected case
- expired, duplicate, wildcard, and malformed exceptions fail
- plan-risk classification handles every Terraform action representation

Fixtures must contain unmistakably fake credentials that cannot be confused
with active values and that are allow-listed only inside the fixture-test
harness.

### Trust-boundary tests

Prove that:

- pull-request jobs do not receive secrets or an OIDC identity accepted by the
  trusted Tailscale policy
- plan identity cannot reach SSH or unrelated tailnet destinations
- apply identity cannot access S3 objects outside its state prefix
- plan PVE credentials cannot perform an apply operation
- apply PVE credentials cannot perform unrelated administrative operations
- privileged workflows reject non-`main`, stale, fork, tag, and arbitrary-ref commits

### State tests

Prove that:

- two concurrent Terraform operations cannot hold the state lock
- an interrupted operation has a documented and audited recovery procedure
- an older version can be restored without losing lineage
- an off-host backup can seed an isolated replacement backend
- PVE, SeaweedFS, or Tailscale loss blocks operation without silently creating a new state

### Plan and apply tests

Prove that:

- changed encrypted content fails the outer digest
- changed decrypted content fails the inner digest
- wrong run ID, SHA, confirmation, actor, or workflow producer fails
- an artifact older than 24 hours fails
- an advanced `main` branch invalidates the old plan
- a provider lockfile or policy change invalidates the plan
- changed state causes Terraform to reject the saved plan
- delete, replace, network, firewall, storage, targeted, and unknown plans cannot apply
- a safe additive plan applies once and cannot be replayed
- the post-apply plan returns no changes

### Operational exercises

- Rotate each credential class and complete a no-op plan.
- Restore state into an isolated endpoint and generate a read-only plan.
- Simulate an expired exception and verify notification and enforcement.
- Simulate scanner unavailability and verify the pipeline fails closed.
- Review evidence to reconstruct who planned, who applied, what commit was used,
  and what changed without opening raw state.

## Monitoring and incident response

Monitor:

- workflow success, duration, cancellation, and queue time
- repeated validation and policy failures
- expiring exceptions and stale dependencies
- SeaweedFS capacity, availability, S3 errors, lock age, and backup status
- Tailscale authentication failures and unexpected tagged nodes
- PVE API authentication failures and unexpected token use
- plan artifacts approaching expiry without application
- post-apply drift or incomplete convergence

On suspected credential or plan compromise:

1. Disable plan and apply workflows or their environments.
2. Revoke affected PVE, SeaweedFS, GitHub, and Tailscale authority.
3. Preserve sanitized workflow and API audit evidence.
4. Invalidate pending plan artifacts and rotate the plan encryption key when relevant.
5. Inspect state versions and PVE audit history for unexpected mutation.
6. Restore state only after verifying lineage and actual infrastructure state.
7. Complete a no-op trusted plan before re-enabling apply.

A secret detected in Git requires rotation even if the commit is later removed.
History rewriting is a containment step, not a substitute for rotation.

## Rollback and failure handling

### Validation rollout rollback

If scanner noise prevents useful development, temporarily return only the
specific newly introduced rule to advisory mode. Keep deterministic checks,
secret detection, forbidden-file checks, workflow security, and existing
previously enforced rules blocking. Record the regression, owner, and expiry.

### State migration rollback

If migration validation fails before any CI apply:

- stop all Terraform operations
- preserve both local and remote copies
- compare lineage and serial before selecting authority
- restore the verified pre-migration local state as authoritative only through
  the documented backend migration procedure
- disable CI plan/apply until lock and recovery testing passes again

Never copy state files opportunistically between backends while another
Terraform process may be active.

### Apply failure

An interrupted or partially failed Terraform apply does not trigger automatic
rollback. Preserve evidence, inspect PVE and state, run a refresh plan, and
choose an explicit forward repair or resource-specific recovery procedure.
Never restart PVE networking, destroy guests, or recreate storage as a generic
pipeline rollback.

## Documentation deliverables

Implementation must add or update:

- this explanation document for architecture and decisions
- a how-to guide for local validation, pull-request handling, trusted planning,
  approved apply, credential rotation, and common failures
- a reference page for required checks, workflow inputs, tool versions,
  environment variables/secrets, Tailscale tags, backend fields, policy rules,
  exceptions, evidence schema, and PVE privileges
- the Terraform operations reference for remote state and CI boundaries
- the platform roadmap when project status or sequencing changes

Do not document real endpoint addresses, bucket credentials, API token values,
private topology beyond what is already approved for Git, or plan-decryption
material.

## Acceptance checklist

- [ ] Protected `main` requires all named validation checks.
- [ ] Untrusted workflows have no private-network or deployment credentials.
- [ ] Every external action and downloaded tool is immutable and verified.
- [ ] Secret, state, plan, appliance-export, and private-key tests block merging.
- [x] New critical/high IaC findings block; accepted findings expire automatically.
- [ ] SeaweedFS locking, versioning, TLS, least privilege, and recovery are proven.
- [ ] Authoritative state has an encrypted off-host tested backup.
- [ ] Plan and apply use different identities and PVE credentials.
- [ ] Apply verifies current `main`, required checks, plan age, and both digests.
- [ ] Destructive and sensitive infrastructure classes cannot use normal CI apply.
- [ ] Post-apply Terraform verification reports no changes.
- [ ] Logs and uploaded artifacts contain no raw state, raw plan JSON, or secrets.
- [ ] Rotation, lock recovery, backend restoration, and apply failure are documented.

## Assumptions and recorded decisions

- The repository will be private on GitHub.
- GitHub-hosted runners are the only initial runner type.
- Enforcement is phased rather than strict for all historical findings on day one.
- The repository owner is the initial solo manual apply approver.
- The normal workflow never applies automatically after merge.
- Tailscale workload identity federation is the trusted network path.
- SeaweedFS supplies the S3-compatible Terraform backend from an independently
  provisioned VM.
- SeaweedFS compatibility is tested rather than assumed.
- State has an encrypted off-host recovery copy.
- Paid GitHub Advanced Security features are optional enhancements, not prerequisites.
- High-risk PVE changes retain a separate local operator review and recovery path.

## Related documentation

- [Platform engineering project roadmap](platform-engineering-project-roadmap.md)
- [Terraform operations reference](../reference/terraform-operations.md)
- [Infrastructure Ansible operations](../how-to/infrastructure-ansible-operations.md)
- [OPNsense HA Tailguard design](opnsense-ha-tailguard-design.md)
