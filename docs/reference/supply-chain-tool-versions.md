# Supply-chain tool and dependency version reference

This reference documents the pinned tool versions, lockfiles, and environment manifests established in Phase 0 of the [infrastructure supply-chain security pipeline](../explanation/infrastructure-supply-chain-security-pipeline.md).

## Pinned components

### 1. Terraform core and provider lock

- **Configuration root:** `terraform/live/onprem-pve/versions.tf`
- **Dependency lockfile:** `terraform/live/onprem-pve/.terraform.lock.hcl`
- **Terraform core version:** `= 1.10.5`
- **`bpg/proxmox` provider version:** `= 0.109.0`
- **Target platforms:** `linux_amd64`, `linux_arm64`, `darwin_arm64`

- **Bootstrap configuration root:** `terraform/bootstrap/seaweedfs/versions.tf`
- **Bootstrap dependency lockfile:** `terraform/bootstrap/seaweedfs/.terraform.lock.hcl`
- **Bootstrap `bpg/proxmox` provider version:** `0.113.1` (`~> 0.108`)
- **Target platforms:** `linux_amd64`, `linux_arm64`, `darwin_arm64`

#### Provider lock update command

```bash
terraform -chdir=terraform/live/onprem-pve providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_arm64

terraform -chdir=terraform/bootstrap/seaweedfs providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_arm64
```

### 2. Ansible collection dependencies

- **File:** `ansible/infra-ops/requirements.yml`
- **Collection:** `ansible.posix`
- **Version:** `2.1.0`

#### Installation command

```bash
ansible-galaxy collection install -r ansible/infra-ops/requirements.yml
```

### 3. TFLint and ruleset plugins

- **File:** `.tflint.hcl`
- **Ruleset plugin:** `tflint-ruleset-terraform`
- **Version:** `0.15.0`
- **Source:** `github.com/terraform-linters/tflint-ruleset-terraform`

#### Initialization and execution

```bash
tflint --init
tflint --recursive
```

### 4. CI binaries and security scanners

- **Environment file:** `scripts/ci/versions.env`
- **Local manager manifest:** `.tool-versions`

| Variable | Version | Purpose |
|---|---|---|
| `TERRAFORM_VERSION` | `1.10.5` | Pinned CLI version supporting native S3 state locking |
| `TFLINT_VERSION` | `0.64.0` | Terraform linter engine |
| `GITLEAKS_VERSION` | `8.30.0` | Secret and private-key scanner |
| `TRIVY_VERSION` | `0.74.0` | IaC and vulnerability scanner |
| `SHELLCHECK_VERSION` | `0.11.0` | Shell script static analysis |
| `ACTIONLINT_VERSION` | `1.7.12` | GitHub Actions workflow linter |
| `ZIZMOR_VERSION` | `1.30.1` | GitHub Actions security audit scanner |

### 5. Python tooling

- **File:** `requirements.txt`

| Package | Version | Purpose |
|---|---|---|
| `ansible-lint` | `26.8.0` | Ansible best-practices and playbook linter |
| `checkov` | `3.3.17` | IaC security and compliance scanner |
| `yamllint` | `1.38.0` | YAML syntax and formatting validator |

#### Installation command

```bash
python3 -m pip install -r requirements.txt
```

### 6. GitHub Actions workflow dependencies

- **Workflow files:** `.github/workflows/validate.yml`, `.github/workflows/security-schedule.yml`

| Action | Pinned Commit SHA | Tag | Purpose |
|---|---|---|---|
| `actions/checkout` | `11bd71901bbe5b1630ceea73d27597364c9af683` | `v4.2.2` | Checkout git repository |
| `hashicorp/setup-terraform` | `b9cd54a3c349d3f38e8881555d616ced269862dd` | `v3.1.2` | Install pinned Terraform CLI |
| `terraform-linters/setup-tflint` | `90f302c255ef959cbfb4bd10581afecdb7ece3e6` | `v4.1.1` | Install pinned TFLint engine |
| `actions/setup-python` | `42375524e23c412d93fb67b49958b491fce71c38` | `v5.4.0` | Setup Python runtime for linters |
| `gitleaks/gitleaks-action` | `ff98106e4c7b2bc287b24eaf42907196329070c7` | `v2.3.9` | Run secret leak detection |
| `aquasecurity/setup-trivy` | `81e514348e19b6112ce2a7e3ecbafe19c1e1f567` | `v0.3.1` | Install and cache pinned Trivy binary |
| `eifinger/actionlint-action` | `1fc89649be682d16ec5cf65ea16e269eb88d3982` | `v1.10.2` | Lint GitHub Actions workflow syntax |
| `zizmorcore/zizmor-action` | `cc914d7f3750a2d13d75c7f184a1060aa0e9d482` | `v0.6.4` | Audit GitHub Actions workflow security |
| `actions/upload-artifact` | `4cec3d8aa04e39d1a68397de0c4cd6fb9dce8ec1` | `v4.6.1` | Upload supply-chain SBOM and evidence artifacts |

### 7. Pinned service binaries

- **Role:** `ansible/infra-ops/roles/seaweedfs/`
- **Component:** SeaweedFS (`weed`)
- **Version:** `4.47`
- **Build type:** `large_disk` (`linux_amd64_large_disk.tar.gz`)
- **SHA-256 Checksum:** `99cd686a0b40c00dfe443f8f8a4476c01e90cf3aa0cee1a58f289d6819dba63c`
- **Target destination:** `/usr/local/bin/weed`
- **Permissions:** `root:root` `0755`
- **CLI version signature:** `version <volume_size_limit> <version> <commit_sha> <os> <arch>` (e.g. `version 8000GB 4.47 <sha> linux amd64`). Note that SeaweedFS CLI does not output the `"SeaweedFS"` or `"seaweedfs.com"` brand token; version verification matches token 1 (volume size limit), token 2 (version), token 4 (OS), and token 5 (arch).

### 8. Supply-chain SBOM and evidence manifest tooling

- **Generator script:** `scripts/ci/generate-sbom.py`
- **Validation script:** `scripts/ci/validate-evidence.sh`
- **SBOM specification:** CycloneDX JSON 1.6 (`artifacts/sbom.cdx.json`)
- **Evidence schema:** `https://json-schema.org/draft/2020-12/schema` (`artifacts/evidence-manifest.json`)
- **Tracked layers:** Python dependencies, Ansible Galaxy collections, Terraform providers, service binaries, CI CLI tools, and GitHub Actions dependencies.

### 9. Security exception registry and Checkov evaluator tooling

- **Registry directory:** `security/exceptions/`
- **Schema specification:** `https://json-schema.org/draft/2020-12/schema` (`security/exceptions/schema.json`)
- **Exception validator script:** `scripts/ci/validate-exceptions.py` / `scripts/ci/validate-exceptions.sh`
- **Checkov evaluator script:** `scripts/ci/evaluate-checkov-findings.py`
- **Test fixtures:** `tests/ci/test_validate_exceptions.py`, `tests/ci/test_evaluate_checkov_findings.py`

## Validation commands and CI parity scripts

To verify local parity against the pinned versions and CI checks, use the dedicated orchestrators under `scripts/ci/`:

```bash
# Execute the complete validation suite across all components
./scripts/ci/validate-all.sh

# Or run individual validation checks:
./scripts/ci/validate-hygiene.sh
./scripts/ci/validate-terraform.sh
./scripts/ci/validate-ansible.sh
./scripts/ci/validate-shell.sh
./scripts/ci/validate-markdown.sh
./scripts/ci/validate-security.sh
./scripts/ci/validate-workflows.sh
./scripts/ci/validate-evidence.sh
./scripts/ci/validate-exceptions.sh
```

For operational details and troubleshooting instructions, see the how-to guide:
[How to run local CI validation checks](../how-to/run-local-ci-validation.md).
