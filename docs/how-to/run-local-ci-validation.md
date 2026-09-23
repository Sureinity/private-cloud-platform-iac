# How to run local CI validation checks

This guide describes how to run repository CI validation checks on your local machine using the scripts in `scripts/ci/`. These scripts provide 100% command parity with the GitHub Actions [`.github/workflows/validate.yml`](../../.github/workflows/validate.yml) pipeline.

## Prerequisites

Ensure you have installed the pinned tool versions listed in [`scripts/ci/versions.env`](../../scripts/ci/versions.env) and [`.tool-versions`](../../.tool-versions):

- **Terraform:** `1.10.5`
- **TFLint:** `0.64.0`
- **ShellCheck:** `0.11.0`
- **Gitleaks:** `8.30.0`
- **Trivy:** `0.74.0`
- **Python 3:** with dependencies installed via `pip install -r requirements.txt` (`ansible-lint==26.8.0`, `checkov==3.3.17`, `yamllint==1.38.0`)
- **Ansible:** `ansible-playbook` and required collections (`ansible-galaxy collection install -r ansible/infra-ops/requirements.yml`)

## Running the full validation suite

To run all checks across all languages and scanners in one pass:

```bash
./scripts/ci/validate-all.sh
```

A clean pass outputs:
```text
======================================================================
SUCCESS: All repository validation checks passed cleanly.
======================================================================
```

## Running individual validation checks

You can run targeted scripts during iterative development:

### 1. Repository hygiene and forbidden files

Checks for trailing whitespace, unresolved merge conflicts, and ensures no sensitive or temporary artifacts (state, plans, private keys, secrets, appliance backups) are tracked in git:

```bash
./scripts/ci/validate-hygiene.sh
```

### 2. Terraform formatting, validation, and linting

Verifies code formatting across all files, initializes all roots (`terraform/live/onprem-pve`, `terraform/bootstrap/seaweedfs`) and modules with `-backend=false`, and runs `tflint`:

```bash
./scripts/ci/validate-terraform.sh
```

*Note: If `tflint` reports warnings (e.g. unused variable declarations), they are printed as informational items; only errors block execution.*

### 3. Ansible linting and syntax verification

Validates Ansible playbooks, roles, inventory, and syntax against the inventory without contacting remote hosts:

```bash
./scripts/ci/validate-ansible.sh
```

*Note: YAML structure is validated using `.yamllint.yml` (enforcing strict duplicate key prevention while permitting 160-character lines for Jinja2 templates and URLs). Best-practice and safety checks are driven by `.ansible-lint` targeting the `basic` profile with Galaxy publishing rules skipped for in-house roles.*

### 4. Shell script static analysis

Runs `bash -n` and `shellcheck` across all shell scripts in `scripts/`:

```bash
./scripts/ci/validate-shell.sh
```

### 5. Markdown syntax and broken link checking

Verifies that all tracked Markdown files have closed code blocks, valid heading hierarchies, and zero broken relative links:

```bash
./scripts/ci/validate-markdown.sh
```

### 6. Secret scanning and IaC security checks

Executes `gitleaks` to detect committed credentials, `trivy config` to detect infrastructure misconfigurations, and `checkov` in fail-closed posture cross-referenced against approved, unexpired waivers in the central Security Exception Registry (`security/exceptions/`):

```bash
./scripts/ci/validate-security.sh
```

### 7. GitHub Actions workflow validation

Runs `actionlint` and `zizmor` on `.github/workflows/`:

```bash
./scripts/ci/validate-workflows.sh
```

### 8. CycloneDX SBOM and supply-chain evidence validation

Generates a CycloneDX JSON Software Bill of Materials (`artifacts/sbom.cdx.json`) and an evidence manifest (`artifacts/evidence-manifest.json`) indexing all Python libraries, Ansible collections, Terraform providers, service binaries, CI CLI tools, and GitHub Actions dependencies:

```bash
./scripts/ci/validate-evidence.sh
```

### 9. Security exception registry validation

Validates the central security exception registry (`security/exceptions/`) against its JSON schema, verifies that no registered exceptions have expired, ensures no broad wildcards or root paths are used, and runs test fixtures to verify rejection of malformed or expired debt:

```bash
./scripts/ci/validate-exceptions.sh
```

## Troubleshooting failures

### Whitespace or conflict marker error
Run `git diff --check` to locate the exact file and line number, remove the trailing whitespace or conflict markers, and re-run `./scripts/ci/validate-hygiene.sh`.

### Tracked forbidden file error
If git reports a forbidden file (e.g. `terraform.tfvars` or `crash.log`), remove it from the index without deleting the local file:
```bash
git rm --cached <path-to-file>
```

### Terraform formatting error
Format all Terraform files recursively:
```bash
terraform fmt -recursive
```

### Markdown broken link
Inspect the output from `./scripts/ci/validate-markdown.sh` to see the referencing file and line number. Verify the target relative path exists and update the link target.

### Checkov unapproved finding failure
When `./scripts/ci/validate-security.sh` fails due to unapproved Checkov findings:
1. Review the unapproved findings printed by `evaluate-checkov-findings.py` (includes rule ID, file, and line range).
2. If remediable, update the IaC code (Terraform, Ansible, or GitHub Actions) to eliminate the violation.
3. If remediation must be deferred (e.g. temporary bootstrap HTTP probe prior to TLS enablement), author a new exception in `security/exceptions/<name>.yaml` with an assigned owner, clear technical rationale, narrow file path, and a future `expires_at` date (refer to [Security Exceptions Registry Reference](../reference/security-exceptions-registry.md)).
4. Re-run `./scripts/ci/validate-exceptions.sh` and `./scripts/ci/validate-security.sh` to verify approval.

## Related documentation

- [Infrastructure supply-chain security pipeline](../explanation/infrastructure-supply-chain-security-pipeline.md)
- [Supply-chain tool and dependency version reference](../reference/supply-chain-tool-versions.md)
- [Terraform operations reference](../reference/terraform-operations.md)
