#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-exceptions.sh
#
# Validates the security exception registry (security/exceptions/):
# 1. Audits registered exceptions against schema, expiration, and scope rules.
# 2. Runs unit test fixtures to ensure expired, malformed, or wildcard exceptions fail.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

echo "==> [Exceptions] Validating security exception registry..."
python3 "${SCRIPT_DIR}/validate-exceptions.py" --repo-root "${REPO_ROOT}"

echo "==> [Exceptions] Running exception validation unit test fixtures..."
python3 -m unittest "${REPO_ROOT}/tests/ci/test_validate_exceptions.py"
python3 -m unittest "${REPO_ROOT}/tests/ci/test_evaluate_checkov_findings.py"

echo "==> [Exceptions] All exception validations and test fixtures passed successfully."
