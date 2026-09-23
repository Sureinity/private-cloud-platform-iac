# AGENTS.md

Durable instructions for agents working in this repository. Keep this file practical, current, and focused on behavior that should apply across sessions.

## Scope and precedence

- This file applies to the whole repository unless a more specific `AGENTS.md` or `AGENTS.override.md` exists in a subdirectory.
- More specific instructions closer to the changed files take precedence.
- If a task conflicts with these instructions, follow the user's explicit request only when it is safe and call out the conflict.
- Update this file when repeated agent mistakes reveal a durable project rule.

## Project summary

This repository manages a home Proxmox VE environment before and during VM provisioning. Treat it as infrastructure-as-code for a real host, not as a disposable lab.

Primary technologies:

- Terraform: Proxmox VE resources, host networking, bridges, images, storage-backed VM definitions, and environment composition.
- Ansible: guest or host operating-system configuration, post-provisioning setup, hardening, service configuration, and day-2 operations.
- Bash: read-only inspection, operator utilities, and small idempotent operational helpers.

## Repository map

Current and expected layout:

```text
AGENTS.md                 Agent instructions for this repository
artifacts/                Local artifacts and generated inspection output (ignored)
configs/                  Local device and appliance configuration exports (ignored)
scripts/                  Host inspection and operator helper scripts
secrets/                  Local Ansible secrets and operator payloads (ignored)
zabbix/                   Zabbix-related notes and roadmap
terraform/bootstrap/      Standalone bootstrap Terraform roots (e.g. seaweedfs)
terraform/live/           Environment-specific Terraform composition (e.g. onprem-pve)
terraform/modules/        Reusable Terraform modules
docs/tutorials/           Learning-oriented walkthroughs
docs/how-to/              Task-oriented operating procedures
docs/reference/           Facts, inputs, outputs, command, and API reference
docs/explanation/         Rationale, architecture, tradeoffs, and design notes
ansible/                  Independent Ansible projects, inventories, roles, and playbooks
```

If a directory does not exist yet, create it only when the change needs it.

## Standard agent workflow

For every change:

1. Inspect relevant files, existing conventions, and `git status --short` before editing.
2. Keep the change as small and coherent as the request allows.
3. Prefer explicit, reviewable infrastructure definitions over implicit host mutation.
4. Add or update documentation using the Diataxis guidance below.
5. Run relevant static checks before committing.
6. Review the diff for secrets, generated files, unsafe host operations, and accidental broad changes.
7. Record major or minor details and decisions made during the conversation in `docs/` when they affect future operation, provisioning, architecture, safety, or maintenance.
8. Use `$git-commit-message` with action signal `commit` and create a commit.
9. In the final response, report what changed, checks run, the commit hash, and any manual follow-up.

Do not leave intentional edits uncommitted unless the user explicitly says not to commit or committing would include unsafe material that cannot be separated.

## Done definition

A task is done when all applicable items are true:

- The requested behavior or artifact is implemented.
- Related documentation is updated in the correct Diataxis category or closest existing documentation location.
- Static checks pass, or any failures are clearly explained as pre-existing, external, or out of scope.
- The Git commit contains only intended files.
- The final response includes enough detail for an operator to review or continue safely.

## Documentation: Diataxis required

Every meaningful change must include documentation appropriate to the Diataxis framework. Standards and conventions may evolve, but every page must stay easy to navigate, easy to scan, and useful to an operator.

Use these categories:

- Tutorials: learning-oriented, step-by-step material for a safe first path.
- How-to guides: task-oriented procedures for a specific operational outcome.
- Reference: information-oriented facts, variables, inputs, outputs, commands, module behavior, and configuration meaning.
- Explanation: understanding-oriented rationale, architecture, security reasoning, tradeoffs, and design decisions.

Documentation expectations:

- Record meaningful details and decisions from the user conversation when they affect future operation, provisioning, architecture, safety, or maintenance.
- Use descriptive headings, short sections, lists, and fenced command blocks.
- Include prerequisites, assumptions, affected systems, validation steps, and rollback notes when relevant.
- Do not artificially shorten content when important operational details should be captured.
- Cross-link related pages when it improves navigation.
- Never document real secrets, private keys, passwords, token values, or sensitive host details.
- For Terraform changes, document variable intent, safe defaults, expected plan impact, and operational risks.
- For Ansible changes, document target hosts, inventory variables, idempotency expectations, and verification commands.
- For scripts, document purpose, safety profile, required privileges, output expectations, and whether the script is read-only or mutating.

If a change is purely internal and does not justify a new documentation page, update the closest README, reference page, module note, script header, or this file.

## Static checks

Run checks that match the changed files. Prefer configured project commands when they exist.

General checks before commit:

```bash
git status --short
git diff --check
```

Terraform checks:

```bash
terraform fmt -check -recursive
terraform validate
```

Run Terraform commands from the relevant root, usually `terraform/live/onprem-pve/` for environment composition, `terraform/bootstrap/<target>/` for bootstrap roots, or a module directory for module-only checks. Use `terraform plan` for infrastructure behavior changes when credentials and state are available. Do not apply unless the user explicitly requests mutation. If using `-target`, state that the plan is intentionally partial.

Ansible checks:

```bash
ansible-lint
ansible-playbook --syntax-check <playbook.yml>
```

If `ansible-lint` is unavailable, run available syntax checks and report the missing tool. It is recommended but not strictly required if unavailable on the control machine.

Shell script checks:

```bash
bash -n <script>
shellcheck <script>
```

If `shellcheck` is unavailable, run `bash -n` and report the missing tool. It is recommended but not strictly required if unavailable on the control machine.

Markdown checks:

- Use configured Markdown formatters or linters when present.
- If none are present, manually verify heading hierarchy, fenced code blocks, links, and readability.

Do not ignore check failures. Fix in-scope failures. Report failures that are external, pre-existing, or unsafe to fix during the task.

## Commit rules

Use `$git-commit-message` for every commit.

Commit process:

1. Inspect the actual diff.
2. Stage only intended files.
3. Use action signal `commit` unless the user requested `draft_only` or `amend`.
4. Use the generated message with `git commit -F <message-file>`.
5. Report the resulting commit hash.

Default message style unless a nested instruction says otherwise:

```text
type(scope): concise imperative subject

- direct change in repo-relative file or area
- direct change in repo-relative file or area
```

Use conventional types such as `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `chore`, or `perf`.

## Branch naming conventions

Branches must follow the `<prefix>/<description>` naming pattern:

- Format: Use lowercase alphanumeric characters and hyphens (`kebab-case`) after the prefix.
- Structure: `<prefix>/<short-description>`

Standard prefixes:

- `feat/*`: New features, modules, or capabilities (e.g. `feat/pve-storage-pool`, `feat/cloud-init-template`)
- `fix/*`: Bug fixes or defect corrections (e.g. `fix/terraform-provider-lock`, `fix/bridge-vlan-id`)
- `refactor/*`: Code or configuration restructuring without behavioral changes (e.g. `refactor/ansible-roles`, `refactor/vm-module-outputs`)
- `docs/*`: Documentation additions, revisions, or updates (e.g. `docs/diataxis-guides`, `docs/branch-naming`)
- `chore/*`: Maintenance tasks, tool configurations, or dependency bumps (e.g. `chore/update-linters`, `chore/pin-tflint-rules`)
- `release/*`: Release candidate or version tagging branches (e.g. `release/v1.2.0`)
- `hotfix/*`: Urgent operational, infrastructure, or production fixes (e.g. `hotfix/restore-host-gateway`)

## Terraform conventions

- Keep reusable logic in `terraform/modules/`.
- Keep bootstrap definitions in `terraform/bootstrap/<target>/`.
- Keep environment-specific composition and values in `terraform/live/<environment>/` (e.g. `terraform/live/onprem-pve/`).
- Prefer explicit variables with clear names over hardcoded infrastructure values.
- Keep examples synchronized with real variables, but never put real secrets in examples.
- When changing `terraform/live/onprem-pve/terraform.tfvars.example`, mirror all applicable non-secret values into the real ignored `terraform/live/onprem-pve/terraform.tfvars` in the same turn so examples and active local inputs do not drift.
- Preserve real secrets only in ignored local files; use placeholders in examples.
- Treat PVE networking, gateways, firewalls, storage, and boot order as high-risk changes.
- Plan before applying infrastructure changes.
- For Terraform infrastructure changes requested by the user, run `terraform plan`, review the intended actions, then apply in the same turn when the plan is safe and matches the request. Do not apply when the plan includes unrelated destructive changes, unexpected replacements, network-risky host changes, secrets exposure, or ambiguous scope; stop and explain instead.
- Distinguish install ISO media from importable VM disk images.
- Do not commit `.terraform/`, state files, plan files, crash logs, local overrides, downloaded images, or generated host logs.

## Ansible conventions

- Prefer idempotent tasks and handlers.
- Use roles for reusable configuration and playbooks for orchestration.
- Keep inventories and variables free of plaintext secrets unless encrypted with Ansible Vault or another approved secret mechanism.
- Document required variables and supported target operating systems.
- Include verification commands or validation tasks where practical.

## Dependency and version pinning conventions

To achieve determinism and immutability across local execution and CI supply-chain pipelines:

- When packages, collections, providers, plugins, tools, or dependencies are appended or updated, always specify exact pinned versions rather than floating ranges or unpinned definitions.
- For Terraform: pin exact Terraform CLI and provider versions in environment live roots (e.g. `required_version = "= 1.10.5"`, `version = "= 0.109.0"` in `terraform/live/onprem-pve/versions.tf`), and maintain multi-platform provider lockfiles (`.terraform.lock.hcl` targeting `linux_amd64`, `linux_arm64`, and `darwin_arm64`).
- For Ansible: pin exact versions for all Galaxy collections and roles in `requirements.yml` (e.g. `version: "2.1.0"`).
- For Python tooling: pin exact package versions in `requirements.txt` using `==` (e.g. `ansible-lint==26.8.0`, `checkov==3.3.17`, `yamllint==1.38.0`).
- For linters and scanners: pin exact plugin versions in `.tflint.hcl` and CLI binary versions across `scripts/ci/versions.env` and `.tool-versions`.
- Record any new or updated dependency versions in `docs/reference/supply-chain-tool-versions.md`.

## Proxmox VE safety rules

- Assume the PVE host may be remote and network-sensitive.
- Prefer read-only inspection before provisioning or reconfiguring virtualized objects.
- Do not reboot the host, restart networking, destroy resources, recreate guests, or stop services unless explicitly requested.
- Call out permission requirements for Proxmox API operations before applying changes.
- For bridge, gateway, firewall, and storage changes, document risk and rollback considerations.
- Keep host-specific credentials and sensitive topology details out of Git.

## Secrets and generated files

Never commit:

- Proxmox API tokens, ticket cookies, passwords, SSH private keys, cloud-init passwords, or Vault secrets.
- Terraform state, backups, plans, provider caches, crash logs, or override files.
- Downloaded ISOs, decompressed installers, VM disks, backups, large logs, or generated inspection output.

If sensitive material is found in the working tree, stop before committing it, update ignore rules when appropriate, and recommend rotation if a secret may have been exposed.

## Response style

Final responses should be concise but complete:

- State the change made.
- Identify the documentation updated and its Diataxis role.
- List checks run and results.
- Include the commit hash.
- Note manual follow-up for the PVE host when applicable.
