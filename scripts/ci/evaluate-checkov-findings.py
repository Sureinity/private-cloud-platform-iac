#!/usr/bin/env python3
"""
scripts/ci/evaluate-checkov-findings.py

Evaluates Checkov JSON report against the central Security Exception Registry
(security/exceptions/*.yaml):
1. Parses Checkov's JSON results across all scanned frameworks.
2. Cross-references failed checks against active, unexpired exceptions in security/exceptions/.
3. Enforces a fail-closed posture: any unapproved failed check exits with code 1.
4. Verifies expiration: expired exceptions cannot waive findings.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import yaml


def load_active_exceptions(exceptions_dir: Path, today: datetime.date) -> list[dict]:
    """Load all active, unexpired Checkov exceptions from the registry."""
    if not exceptions_dir.is_dir():
        return []

    exceptions = []
    yaml_files = sorted(exceptions_dir.glob("*.yaml")) + sorted(exceptions_dir.glob("*.yml"))

    for fpath in yaml_files:
        try:
            with fpath.open("r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
        except Exception:
            continue

        if not isinstance(data, dict):
            continue

        # Only consider checkov exceptions
        if data.get("tool") != "checkov":
            continue

        # Check expiration date
        expires_str = str(data.get("expires_at", ""))
        try:
            exp_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
            if exp_date <= today:
                # Expired exceptions cannot be used to waive findings
                print(
                    f"WARN: [Exceptions] Exception in {fpath.name} expired on {expires_str} and is inactive.",
                    file=sys.stderr,
                )
                continue
        except ValueError:
            continue

        data["_file_name"] = fpath.name
        exceptions.append(data)

    return exceptions


def normalize_path(path_str: str) -> str:
    """Normalize file path by stripping leading slashes and whitespace."""
    return path_str.strip().lstrip("/")


def match_exception(failed_check: dict, exceptions: list[dict]) -> dict | None:
    """
    Find an active exception matching the given failed check.
    Matches on:
    - check_id == exception.id
    - normalized repo_file_path == exception.path
    - resource matches exception.resource (exact, prefix, or omitted)
    """
    check_id = failed_check.get("check_id")
    file_path = failed_check.get("repo_file_path") or failed_check.get("file_path") or ""
    norm_file_path = normalize_path(file_path)
    check_resource = str(failed_check.get("resource", "")).strip()

    for exc in exceptions:
        if exc.get("id") != check_id:
            continue

        exc_path = normalize_path(str(exc.get("path", "")))
        if exc_path != norm_file_path:
            continue

        exc_resource = str(exc.get("resource", "")).strip()
        if exc_resource:
            # Match exact or prefix (e.g. tasks.ansible.builtin.uri matching tasks.ansible.builtin.uri.Task Name)
            if not (check_resource == exc_resource or check_resource.startswith(exc_resource)):
                continue

        return exc

    return None


def evaluate_report(
    report_data: dict | list, exceptions: list[dict]
) -> tuple[list[tuple[dict, dict]], list[dict]]:
    """
    Evaluate all failed checks against active exceptions.
    Returns (approved_list, unapproved_list).
    """
    reports = report_data if isinstance(report_data, list) else [report_data]

    all_failed_checks = []
    for r in reports:
        if not isinstance(r, dict):
            continue
        results = r.get("results")
        if isinstance(results, dict):
            failed = results.get("failed_checks", [])
            if isinstance(failed, list):
                all_failed_checks.extend(failed)

    approved = []
    unapproved = []

    for fc in all_failed_checks:
        exc = match_exception(fc, exceptions)
        if exc:
            approved.append((fc, exc))
        else:
            unapproved.append(fc)

    return approved, unapproved


def main():
    parser = argparse.ArgumentParser(description="Evaluate Checkov findings against Security Exception Registry")
    parser.add_argument("--repo-root", default=".", help="Root directory of repository")
    parser.add_argument("--report", default="artifacts/checkov-report.json", help="Path to Checkov JSON report")
    parser.add_argument("--exceptions-dir", default="security/exceptions", help="Directory containing exceptions")
    parser.add_argument("--today", default=None, help="Reference date YYYY-MM-DD for expiration checks (defaults to UTC today)")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    report_path = (repo_root / args.report).resolve() if not Path(args.report).is_absolute() else Path(args.report)
    exceptions_dir = (repo_root / args.exceptions_dir).resolve() if not Path(args.exceptions_dir).is_absolute() else Path(args.exceptions_dir)

    if args.today:
        today = datetime.strptime(args.today, "%Y-%m-%d").date()
    else:
        today = datetime.now(timezone.utc).date()

    if not report_path.is_file():
        print(f"ERROR: Checkov JSON report not found at {report_path}. Failing closed.", file=sys.stderr)
        sys.exit(1)

    try:
        with report_path.open("r", encoding="utf-8") as f:
            report_data = json.load(f)
    except Exception as e:
        print(f"ERROR: Failed to parse Checkov report {report_path}: {e}", file=sys.stderr)
        sys.exit(1)

    exceptions = load_active_exceptions(exceptions_dir, today)
    approved, unapproved = evaluate_report(report_data, exceptions)

    total_failures = len(approved) + len(unapproved)
    print(f"==> [Checkov Evaluator] Evaluated {total_failures} Checkov finding(s) as of {today}:")

    if approved:
        print(f"\n  [Approved Exceptions ({len(approved)})]:")
        for fc, exc in approved:
            cid = fc.get("check_id")
            fpath = normalize_path(fc.get("repo_file_path") or fc.get("file_path") or "")
            res = fc.get("resource", "")
            print(f"    ✔ {cid} on {fpath}")
            print(f"      Resource:  {res}")
            print(f"      Exception: security/exceptions/{exc.get('_file_name')} (Owner: {exc.get('owner')}, Expires: {exc.get('expires_at')})")
            print(f"      Rationale: {exc.get('rationale', '').strip()[:100]}...")

    if unapproved:
        print(f"\n  ❌ [Unapproved Violations ({len(unapproved)})]:", file=sys.stderr)
        for fc in unapproved:
            cid = fc.get("check_id")
            cname = fc.get("check_name")
            fpath = normalize_path(fc.get("repo_file_path") or fc.get("file_path") or "")
            res = fc.get("resource", "")
            lines = fc.get("file_line_range", [])
            guide = fc.get("guideline", "")
            print(f"    ❌ {cid}: {cname}", file=sys.stderr)
            print(f"       File:     {fpath}:{lines}", file=sys.stderr)
            print(f"       Resource: {res}", file=sys.stderr)
            if guide:
                print(f"       Guide:    {guide}", file=sys.stderr)

        print(
            f"\nERROR: Security gate rejected {len(unapproved)} unapproved Checkov finding(s). "
            "Remediate the underlying IaC configuration or register an approved, expiring exception "
            "in security/exceptions/.",
            file=sys.stderr,
        )
        sys.exit(1)

    if total_failures == 0:
        print("  ✔ No failed checks detected. IaC security posture is 100% clean.")
    else:
        print(f"\n==> [Checkov Evaluator] All {len(approved)} finding(s) are approved under active exceptions.")

    sys.exit(0)


if __name__ == "__main__":
    main()
