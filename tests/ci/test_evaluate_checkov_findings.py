#!/usr/bin/env python3
"""
tests/ci/test_evaluate_checkov_findings.py

Unit tests for scripts/ci/evaluate-checkov-findings.py.
Verifies that:
1. Clean report with 0 failures passes.
2. Failed check covered by active exception passes.
3. Unapproved failed check causes failure.
4. Expired exception fails to waive findings (fail-closed).
5. File path mismatch fails to waive findings.
6. Resource mismatch fails to waive findings.
7. Multi-framework list reports are properly evaluated.
"""

from datetime import datetime, timezone
from pathlib import Path
import sys
import tempfile
import unittest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))
from importlib import import_module
evaluator_module = import_module("evaluate-checkov-findings")
evaluate_report = evaluator_module.evaluate_report
match_exception = evaluator_module.match_exception
load_active_exceptions = evaluator_module.load_active_exceptions


class TestEvaluateCheckovFindings(unittest.TestCase):
    def setUp(self):
        self.today = datetime(2026, 9, 21, tzinfo=timezone.utc).date()
        self.active_exception = {
            "schema_version": "1.0.0",
            "id": "CKV2_ANSIBLE_1",
            "tool": "checkov",
            "severity": "MEDIUM",
            "owner": "@Sureinity",
            "approved_by": "@Sureinity",
            "created_at": "2026-09-21",
            "expires_at": "2026-12-31",
            "path": "ansible/roles/seaweedfs/tasks/verify.yml",
            "resource": "tasks.ansible.builtin.uri",
            "rationale": "Temporary exception for HTTP bootstrap probe during Phase 1-2.",
            "_file_name": "seaweedfs-bootstrap-http.yaml",
        }
        self.failed_check = {
            "check_id": "CKV2_ANSIBLE_1",
            "check_name": "Ensure that HTTPS url is used with uri",
            "repo_file_path": "/ansible/roles/seaweedfs/tasks/verify.yml",
            "file_line_range": [56, 68],
            "resource": "tasks.ansible.builtin.uri.Probe SeaweedFS Master cluster status API",
            "guideline": "https://docs.prismacloud.io/guide",
        }

    def test_clean_report_passes(self):
        report = {"check_type": "ansible", "results": {"failed_checks": []}}
        approved, unapproved = evaluate_report(report, [self.active_exception])
        self.assertEqual(len(approved), 0)
        self.assertEqual(len(unapproved), 0)

    def test_approved_finding_passes(self):
        report = {"check_type": "ansible", "results": {"failed_checks": [self.failed_check]}}
        approved, unapproved = evaluate_report(report, [self.active_exception])
        self.assertEqual(len(approved), 1)
        self.assertEqual(len(unapproved), 0)
        self.assertEqual(approved[0][1]["id"], "CKV2_ANSIBLE_1")

    def test_unapproved_finding_fails(self):
        bad_check = dict(self.failed_check)
        bad_check["check_id"] = "CKV_ANSIBLE_6"
        report = {"check_type": "ansible", "results": {"failed_checks": [bad_check]}}
        approved, unapproved = evaluate_report(report, [self.active_exception])
        self.assertEqual(len(approved), 0)
        self.assertEqual(len(unapproved), 1)

    def test_path_mismatch_fails(self):
        mismatched_check = dict(self.failed_check)
        mismatched_check["repo_file_path"] = "/ansible/roles/docker/tasks/main.yml"
        report = {"check_type": "ansible", "results": {"failed_checks": [mismatched_check]}}
        approved, unapproved = evaluate_report(report, [self.active_exception])
        self.assertEqual(len(approved), 0)
        self.assertEqual(len(unapproved), 1)

    def test_resource_mismatch_fails(self):
        mismatched_res = dict(self.failed_check)
        mismatched_res["resource"] = "tasks.ansible.builtin.command.Restart service"
        report = {"check_type": "ansible", "results": {"failed_checks": [mismatched_res]}}
        approved, unapproved = evaluate_report(report, [self.active_exception])
        self.assertEqual(len(approved), 0)
        self.assertEqual(len(unapproved), 1)

    def test_multi_framework_list_evaluation(self):
        report_list = [
            {
                "check_type": "terraform",
                "results": {"failed_checks": []},
            },
            {
                "check_type": "ansible",
                "results": {"failed_checks": [self.failed_check]},
            },
        ]
        approved, unapproved = evaluate_report(report_list, [self.active_exception])
        self.assertEqual(len(approved), 1)
        self.assertEqual(len(unapproved), 0)

    def test_load_active_exceptions_filters_expired_and_other_tools(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            # Valid active exception
            (tmppath / "active.yaml").write_text(yaml.dump(self.active_exception), encoding="utf-8")

            # Expired exception
            expired_exc = dict(self.active_exception)
            expired_exc["expires_at"] = "2026-09-20"
            (tmppath / "expired.yaml").write_text(yaml.dump(expired_exc), encoding="utf-8")

            # Different tool exception
            trivy_exc = dict(self.active_exception)
            trivy_exc["tool"] = "trivy"
            (tmppath / "trivy.yaml").write_text(yaml.dump(trivy_exc), encoding="utf-8")

            loaded = load_active_exceptions(tmppath, self.today)
            self.assertEqual(len(loaded), 1)
            self.assertEqual(loaded[0]["id"], "CKV2_ANSIBLE_1")
            self.assertEqual(loaded[0]["_file_name"], "active.yaml")


if __name__ == "__main__":
    unittest.main()
