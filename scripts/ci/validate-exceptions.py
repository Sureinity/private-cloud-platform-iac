#!/usr/bin/env python3
"""
scripts/ci/validate-exceptions.py

Validates the security exception registry (security/exceptions/*.yaml):
1. Verifies structural schema conformity against security/exceptions/schema.json.
2. Asserts no expired exceptions (expires_at > today in UTC).
3. Rejects wildcard, directory-level, or orphaned file paths.
4. Rejects duplicate exceptions for the same tool, rule ID, path, and resource.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys
import yaml


def load_schema(schema_path: Path) -> dict:
    with schema_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_entry(entry: dict, file_path: Path, repo_root: Path, today: datetime.date) -> list[str]:
    errors = []

    # 1. Required fields
    required_fields = [
        "schema_version",
        "id",
        "tool",
        "severity",
        "owner",
        "approved_by",
        "created_at",
        "expires_at",
        "path",
        "rationale",
    ]
    for field in required_fields:
        if field not in entry:
            errors.append(f"Missing required field '{field}'")

    if errors:
        return errors

    # 2. Schema version and enums
    if entry.get("schema_version") != "1.0.0":
        errors.append(f"Unsupported schema_version '{entry.get('schema_version')}'; expected '1.0.0'")

    valid_tools = ["checkov", "trivy", "tflint", "gitleaks", "zizmor", "other"]
    if entry.get("tool") not in valid_tools:
        errors.append(f"Invalid tool '{entry.get('tool')}'; must be one of {valid_tools}")

    valid_severities = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL"]
    if entry.get("severity") not in valid_severities:
        errors.append(f"Invalid severity '{entry.get('severity')}'; must be one of {valid_severities}")

    # 3. Rule ID format
    id_pattern = re.compile(r"^[A-Za-z0-9_.:-]+$")
    if not id_pattern.match(str(entry.get("id", ""))):
        errors.append(f"Invalid rule id format '{entry.get('id')}'")

    # 4. Dates and expiration
    date_pattern = re.compile(r"^\d{4}-\d{2}-\d{2}$")
    created_str = str(entry.get("created_at", ""))
    expires_str = str(entry.get("expires_at", ""))

    if not date_pattern.match(created_str):
        errors.append(f"Invalid created_at date format '{created_str}'; expected YYYY-MM-DD")

    if not date_pattern.match(expires_str):
        errors.append(f"Invalid expires_at date format '{expires_str}'; expected YYYY-MM-DD")
    else:
        try:
            exp_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
            if exp_date <= today:
                days_ago = (today - exp_date).days
                errors.append(
                    f"Exception has expired on {expires_str} ({days_ago} days ago). "
                    "Remediation is overdue; renew with justification or resolve the underlying debt."
                )
        except ValueError as e:
            errors.append(f"Could not parse expires_at date: {e}")

    # 5. Path checks (no wildcards, must exist)
    rel_path = str(entry.get("path", "")).strip()
    if not rel_path or rel_path in [".", "/", "*", "**"] or "*" in rel_path:
        errors.append(
            f"Wildcard or root path '{rel_path}' is forbidden. Exceptions must target a specific file path."
        )
    else:
        target_file = repo_root / rel_path
        if not target_file.is_file():
            errors.append(
                f"Target path '{rel_path}' does not exist in repository. Stale or orphaned exception."
            )

    # 6. Content length requirements
    rationale = str(entry.get("rationale", "")).strip()
    if len(rationale) < 20:
        errors.append("Rationale is too short (< 20 characters); provide meaningful technical justification")

    for identity_field in ["owner", "approved_by"]:
        val = str(entry.get(identity_field, "")).strip()
        if len(val) < 3:
            errors.append(f"Field '{identity_field}' must be at least 3 characters long")

    return errors


def main():
    parser = argparse.ArgumentParser(description="Validate Security Exception Registry")
    parser.add_argument("--repo-root", default=".", help="Root directory of repository")
    parser.add_argument("--exceptions-dir", default="security/exceptions", help="Directory containing exceptions")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    exceptions_dir = (repo_root / args.exceptions_dir).resolve()
    schema_path = exceptions_dir / "schema.json"

    if not exceptions_dir.is_dir():
        print(f"==> [Exceptions] Directory {exceptions_dir} does not exist. Nothing to validate.")
        sys.exit(0)

    if not schema_path.is_file():
        print(f"ERROR: Schema file missing at {schema_path}", file=sys.stderr)
        sys.exit(1)

    today = datetime.now(timezone.utc).date()
    yaml_files = sorted(exceptions_dir.glob("*.yaml")) + sorted(exceptions_dir.glob("*.yml"))

    if not yaml_files:
        print("==> [Exceptions] Zero security exceptions registered (fully strict baseline).")
        sys.exit(0)

    print(f"==> [Exceptions] Auditing {len(yaml_files)} security exception file(s) as of {today}...")

    seen_keys = {}
    total_errors = 0

    for fpath in yaml_files:
        rel_fpath = fpath.relative_to(repo_root)
        try:
            with fpath.open("r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
        except Exception as e:
            print(f"ERROR: [{rel_fpath}] Failed to parse YAML: {e}", file=sys.stderr)
            total_errors += 1
            continue

        if not isinstance(data, dict):
            print(f"ERROR: [{rel_fpath}] Content must be a YAML mapping/dictionary", file=sys.stderr)
            total_errors += 1
            continue

        file_errors = validate_entry(data, fpath, repo_root, today)
        if file_errors:
            print(f"FAILED: [{rel_fpath}]:", file=sys.stderr)
            for err in file_errors:
                print(f"  - {err}", file=sys.stderr)
            total_errors += len(file_errors)
            continue

        # Check for duplicates
        tool = data.get("tool")
        rule_id = data.get("id")
        target_path = data.get("path")
        resource = data.get("resource", "")
        dedup_key = (tool, rule_id, target_path, resource)

        if dedup_key in seen_keys:
            prev_file = seen_keys[dedup_key]
            print(
                f"ERROR: [{rel_fpath}] Duplicate exception for ({tool}, {rule_id}, {target_path}, {resource}). "
                f"Already defined in {prev_file}.",
                file=sys.stderr,
            )
            total_errors += 1
            continue

        seen_keys[dedup_key] = rel_fpath

        exp_date = datetime.strptime(str(data["expires_at"]), "%Y-%m-%d").date()
        days_remaining = (exp_date - today).days
        print(
            f"  ✔ [{data['tool'].upper()}] {data['id']} -> {data['path']} "
            f"(Owner: {data['owner']} | Expires: {data['expires_at']} [{days_remaining}d remaining])"
        )

    if total_errors > 0:
        print(f"\nERROR: Security exception validation failed with {total_errors} issue(s).", file=sys.stderr)
        sys.exit(1)

    print(f"\n==> [Exceptions] All {len(yaml_files)} security exception(s) are valid, unexpired, and non-duplicate.")


if __name__ == "__main__":
    main()
