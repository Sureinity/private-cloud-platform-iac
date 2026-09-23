#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-all.sh
#
# Master validation orchestrator for the Home PVE repository.
# Executes all local CI parity checks in sequence:
# 1. Repository hygiene and forbidden files (validate-hygiene.sh)
# 2. Terraform format, validate, and tflint (validate-terraform.sh)
# 3. Ansible lint and syntax checks (validate-ansible.sh)
# 4. Shell syntax and shellcheck (validate-shell.sh)
# 5. Markdown formatting and link validity (validate-markdown.sh)
# 6. Gitleaks, Trivy, and Checkov security scans (validate-security.sh)
# 7. Workflow security and actionlint (validate-workflows.sh)
# 8. CycloneDX SBOM and evidence manifest validation (validate-evidence.sh)
# 9. Security exception registry validation (validate-exceptions.sh)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

echo "======================================================================"
echo "Starting Home PVE Local CI Parity Validation"
echo "======================================================================"

"${SCRIPT_DIR}/validate-hygiene.sh"
echo ""

"${SCRIPT_DIR}/validate-terraform.sh"
echo ""

"${SCRIPT_DIR}/validate-ansible.sh"
echo ""

"${SCRIPT_DIR}/validate-shell.sh"
echo ""

"${SCRIPT_DIR}/validate-markdown.sh"
echo ""

"${SCRIPT_DIR}/validate-security.sh"
echo ""

"${SCRIPT_DIR}/validate-workflows.sh"
echo ""

"${SCRIPT_DIR}/validate-evidence.sh"
echo ""

"${SCRIPT_DIR}/validate-exceptions.sh"
echo ""

echo "======================================================================"
echo "SUCCESS: All repository validation checks passed cleanly."
echo "======================================================================"
