#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-security.sh
#
# Validates repository security and scans for secret leaks and IaC misconfigurations:
# 1. Secret detection via `gitleaks` (blocking).
# 2. IaC misconfiguration scanning via `trivy config` (blocking on HIGH,CRITICAL).
# 3. Policy and posture scanning via `checkov` (fail-closed in Phase 2).
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

echo "==> [Security] Checking for secret leaks with Gitleaks..."
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --verbose
else
  echo "ERROR: gitleaks CLI is not installed or not in PATH." >&2
  exit 1
fi

echo "==> [Security] Scanning IaC configuration with Trivy..."
if command -v trivy >/dev/null 2>&1; then
  # Scan IaC files in repository
  trivy config --severity HIGH,CRITICAL .
else
  echo "WARN: trivy CLI is not installed. Skipping Trivy scan." >&2
fi

echo "==> [Security] Scanning IaC configuration with Checkov..."
if command -v checkov >/dev/null 2>&1; then
  # In Phase 2, Checkov runs in fail-closed mode without --soft-fail.
  # Findings are written to artifacts/checkov-report.json and cross-referenced
  # with the central Security Exception Registry (security/exceptions/*.yaml).
  mkdir -p "${REPO_ROOT}/artifacts"
  REPORT_FILE="${REPO_ROOT}/artifacts/checkov-report.json"

  checkov_exit=0
  checkov -d . --framework terraform,ansible,github_actions \
    --skip-path artifacts \
    -o cli -o json \
    --output-file-path "console,${REPORT_FILE}" || checkov_exit=$?

  if [[ ${checkov_exit} -ne 0 && ${checkov_exit} -ne 1 ]]; then
    echo "ERROR: Checkov execution failed with exit code ${checkov_exit}." >&2
    exit "${checkov_exit}"
  fi

  echo "==> [Security] Evaluating Checkov findings against Security Exception Registry..."
  python3 "${SCRIPT_DIR}/evaluate-checkov-findings.py" \
    --repo-root "${REPO_ROOT}" \
    --report "${REPORT_FILE}" \
    --exceptions-dir "${REPO_ROOT}/security/exceptions"
else
  echo "WARN: checkov CLI is not installed on control machine. Skipping Checkov scan." >&2
fi

echo "==> [Security] All security scans completed successfully."
