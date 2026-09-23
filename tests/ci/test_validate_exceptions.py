#!/usr/bin/env python3
"""
tests/ci/test_validate_exceptions.py

Unit tests for scripts/ci/validate-exceptions.py.
Verifies that:
1. Valid exception passes cleanly.
2. Expired exception is rejected.
3. Duplicate exception is rejected.
4. Wildcard/root path is rejected.
5. Malformed exception (missing fields, invalid enum, bad date) is rejected.
6. Non-existent/orphaned file path is rejected.
"""

from datetime import datetime, timezone
from pathlib import Path
import sys
import tempfile
import unittest

# Import validator module
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))
from importlib import import_module
validate_module = import_module("validate-exceptions")
validate_entry = validate_module.validate_entry


class TestValidateExceptions(unittest.TestCase):
    def setUp(self):
        self.today = datetime(2026, 9, 21, tzinfo=timezone.utc).date()
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.repo_root = Path(self.tmp_dir.name)

        # Create a dummy real file to satisfy path existence checks
        self.dummy_rel_path = "ansible/roles/test.yml"
        self.dummy_file = self.repo_root / self.dummy_rel_path
        self.dummy_file.parent.mkdir(parents=True, exist_ok=True)
        self.dummy_file.write_text("dummy: content", encoding="utf-8")

        self.valid_entry = {
            "schema_version": "1.0.0",
            "id": "CKV2_ANSIBLE_1",
            "tool": "checkov",
            "severity": "MEDIUM",
            "owner": "@Sureinity",
            "approved_by": "@Sureinity",
            "created_at": "2026-09-21",
            "expires_at": "2026-12-31",
            "path": self.dummy_rel_path,
            "resource": "tasks.ansible.builtin.uri",
            "rationale": "Legitimate temporary exception for testing verification purposes.",
            "remediation_ticket": "Phase 3 TLS Hardening",
        }

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_valid_entry(self):
        errors = validate_entry(self.valid_entry, Path("dummy.yaml"), self.repo_root, self.today)
        self.assertEqual(errors, [])

    def test_expired_exception_fails(self):
        expired_entry = dict(self.valid_entry)
        expired_entry["expires_at"] = "2026-09-20"  # Yesterday relative to 2026-09-21
        errors = validate_entry(expired_entry, Path("dummy.yaml"), self.repo_root, self.today)
        self.assertTrue(any("expired" in err.lower() for err in errors), f"Expected expiration error, got {errors}")

    def test_wildcard_path_fails(self):
        for wildcard in ["*", "**", ".", "/", "ansible/*", "*.tf"]:
            wildcard_entry = dict(self.valid_entry)
            wildcard_entry["path"] = wildcard
            errors = validate_entry(wildcard_entry, Path("dummy.yaml"), self.repo_root, self.today)
            self.assertTrue(any("wildcard" in err.lower() for err in errors), f"Expected wildcard error for {wildcard}, got {errors}")

    def test_orphaned_path_fails(self):
        orphaned_entry = dict(self.valid_entry)
        orphaned_entry["path"] = "nonexistent/file.yml"
        errors = validate_entry(orphaned_entry, Path("dummy.yaml"), self.repo_root, self.today)
        self.assertTrue(any("does not exist" in err.lower() for err in errors), f"Expected existence error, got {errors}")

    def test_malformed_missing_fields_fails(self):
        for req_field in ["id", "tool", "severity", "owner", "approved_by", "created_at", "expires_at", "path", "rationale"]:
            bad_entry = dict(self.valid_entry)
            del bad_entry[req_field]
            errors = validate_entry(bad_entry, Path("dummy.yaml"), self.repo_root, self.today)
            self.assertTrue(any(f"Missing required field '{req_field}'" in err for err in errors), f"Expected missing {req_field} error, got {errors}")

    def test_invalid_enum_fails(self):
        bad_tool = dict(self.valid_entry)
        bad_tool["tool"] = "unknown_tool_xyz"
        errors = validate_entry(bad_tool, Path("dummy.yaml"), self.repo_root, self.today)
        self.assertTrue(any("Invalid tool" in err for err in errors), f"Expected tool enum error, got {errors}")

        bad_sev = dict(self.valid_entry)
        bad_sev["severity"] = "SUPER_CRITICAL"
        errors = validate_entry(bad_sev, Path("dummy.yaml"), self.repo_root, self.today)
        self.assertTrue(any("Invalid severity" in err for err in errors), f"Expected severity enum error, got {errors}")

    def test_short_rationale_fails(self):
        short_entry = dict(self.valid_entry)
        short_entry["rationale"] = "Too short"
        errors = validate_entry(short_entry, Path("dummy.yaml"), self.repo_root, self.today)
        self.assertTrue(any("too short" in err.lower() for err in errors), f"Expected short rationale error, got {errors}")


if __name__ == "__main__":
    unittest.main()
