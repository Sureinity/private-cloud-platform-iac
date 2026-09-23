#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-workflows.sh
#
# Validates GitHub Actions workflow definitions:
# 1. Syntax, expression, and action verification via `actionlint`.
# 2. Workflow security audit via `zizmor`.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

WORKFLOWS_DIR=".github/workflows"

if [[ ! -d "${WORKFLOWS_DIR}" ]] || [[ -z "$(ls -A "${WORKFLOWS_DIR}" 2>/dev/null)" ]]; then
  echo "==> [Workflows] No workflows found in ${WORKFLOWS_DIR}. Skipping."
  exit 0
fi

echo "==> [Workflows] Validating workflows in ${WORKFLOWS_DIR}..."

if command -v actionlint >/dev/null 2>&1; then
  echo "==> [Workflows] Running actionlint..."
  actionlint
else
  echo "WARN: actionlint is not installed. Skipping actionlint static check." >&2
fi

if command -v zizmor >/dev/null 2>&1; then
  echo "==> [Workflows] Running zizmor security analysis..."
  zizmor "${WORKFLOWS_DIR}"
else
  echo "WARN: zizmor is not installed. Skipping zizmor security analysis." >&2
fi

echo "==> [Workflows] All workflow checks completed successfully."
