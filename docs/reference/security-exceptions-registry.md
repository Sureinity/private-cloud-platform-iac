# Security Exceptions Registry Reference

This reference documents the schema, lifecycle rules, and validation harness for the central Security Exception Registry in `security/exceptions/`.

## Purpose

The Security Exception Registry provides an auditable, fail-closed mechanism to track known security scanner findings (Checkov, Trivy, TFLint, Gitleaks, Zizmor) that cannot be immediately remediated.

In accordance with pipeline design principles:
- **Exceptions are debt:** Every accepted finding must have a declared owner, technical rationale, narrow file scope, and hard expiration date.
- **Fail closed:** An expired, malformed, duplicate, or wildcard exception causes immediate CI failure.
- **Zero ambient waivers:** Global scanner disablement or broad rule exclusions (`*`, `.`, broad directories) are strictly prohibited.

## Directory layout

```text
security/exceptions/
├── schema.json                    # JSON Schema definition (Draft 2020-12)
└── seaweedfs-bootstrap-http.yaml  # Concrete exception definition(s)
```

## Schema definition

Each exception is defined as a YAML document conforming to [`security/exceptions/schema.json`](../../security/exceptions/schema.json).

### Field reference

| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `schema_version` | String | Yes | Must be exactly `"1.0.0"`. |
| `id` | String | Yes | Scanner rule or vulnerability ID (e.g. `CKV2_ANSIBLE_1`, `CVE-2026-1234`). |
| `tool` | String | Yes | Scanner enum: `checkov`, `trivy`, `tflint`, `gitleaks`, `zizmor`, `other`. |
| `severity` | String | Yes | Severity level: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFORMATIONAL`. |
| `owner` | String | Yes | Responsible maintainer handle (e.g. `@Sureinity`). Min length: 3. |
| `approved_by` | String | Yes | Authorizing maintainer handle. Min length: 3. |
| `created_at` | String | Yes | Date created in `YYYY-MM-DD` format. |
| `expires_at` | String | Yes | Hard expiration date in `YYYY-MM-DD` format. Must be strictly in the future. |
| `path` | String | Yes | Repo-relative path to affected file. Wildcards (`*`, `.`, `/`) are forbidden. Target file must exist. |
| `resource` | String | No | Specific task name, block identifier, or stanza within the file. |
| `rationale` | String | Yes | Detailed technical justification. Min length: 20 characters. |
| `remediation_ticket` | String | No | Tracking milestone, issue, or roadmap phase that will resolve the debt. |

### Example exception definition

```yaml
schema_version: "1.0.0"
id: "CKV2_ANSIBLE_1"
tool: "checkov"
severity: "MEDIUM"
owner: "@Sureinity"
approved_by: "@Sureinity"
created_at: "2026-09-21"
expires_at: "2026-12-31"
path: "ansible/infra-ops/roles/seaweedfs/tasks/verify.yml"
resource: "tasks.ansible.builtin.uri"
rationale: >-
  SeaweedFS cluster master status and S3 gateway endpoints currently operate over HTTP
  on the private isolated subnet (192.0.2.51) during Phase 1-2 bootstrap. TLS certificate
  termination for S3 and master APIs is scheduled for delivery in Phase 3.
remediation_ticket: "Phase 3 SeaweedFS State Qualification and TLS Hardening"
```

## Validation rules

The registry is validated by [`scripts/ci/validate-exceptions.py`](../../scripts/ci/validate-exceptions.py) and wrapped by [`scripts/ci/validate-exceptions.sh`](../../scripts/ci/validate-exceptions.sh):

1. **Schema conformity:** Validates presence, formatting, enums, and string length requirements.
2. **Expiration check:** `expires_at` is evaluated in UTC against today's date. If `expires_at <= today`, the script exits with code 1.
3. **Scope validation:**
   - Path cannot be empty, `.`, `/`, `*`, `**`, or contain wildcard wildcards.
   - Path must resolve to an existing file in the repository (prevents orphaned exceptions).
4. **Deduplication:** Composite key `(tool, id, path, resource)` must be unique across all YAML files.
5. **Fixture test verification:** Runs unit tests in `tests/ci/test_validate_exceptions.py` and `tests/ci/test_evaluate_checkov_findings.py` to prove that invalid, expired, or unapproved findings fail as expected.

## Checkov findings evaluation workflow

In Phase 2, Checkov runs in fail-closed posture without `--soft-fail`:

1. Checkov writes detailed JSON findings to `artifacts/checkov-report.json`.
2. [`scripts/ci/evaluate-checkov-findings.py`](../../scripts/ci/evaluate-checkov-findings.py) parses `failed_checks` across all scanned frameworks (`terraform`, `ansible`, `github_actions`).
3. For each finding:
   - Matches `(tool="checkov", id=check_id, path=repo_file_path)`.
   - If `resource` is defined in the exception, matches the specific task or resource.
   - Evaluates whether the exception has expired (`expires_at <= today`). Expired exceptions cannot waive findings.
4. If any unapproved or expired finding is discovered, the evaluator prints the exact finding, file location, and Prisma Cloud guideline, and exits with code 1.
5. If all findings are covered by valid, unexpired exceptions, the evaluator prints approval evidence and exits with code 0.

## Validation commands

To audit the exception registry locally:

```bash
./scripts/ci/validate-exceptions.sh
```

## Maintenance lifecycle

- **Monthly review:** Maintainers review active exceptions to assess remediation progress.
- **Early closure:** When a vulnerability or finding is remediated, delete the corresponding YAML file from `security/exceptions/`.
- **Extension policy:** An expiring exception may be extended only with updated rationale and an active tracking ticket.
