#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-shell.sh
#
# Validates all shell scripts across the repository:
# 1. Syntax check via `bash -n`.
# 2. Static analysis and portability checks via `shellcheck`.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

echo "==> [Shell] Discovering shell scripts..."
mapfile -t SHELL_SCRIPTS < <(find scripts -type f -name "*.sh" | sort)

if [[ ${#SHELL_SCRIPTS[@]} -eq 0 ]]; then
  echo "WARN: No shell scripts found in scripts/."
  exit 0
fi

echo "==> [Shell] Checking syntax with bash -n..."
for script in "${SHELL_SCRIPTS[@]}"; do
  echo "  -> bash -n ${script}"
  bash -n "${script}"
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> [Shell] Running ShellCheck (severity: warning)..."
  for script in "${SHELL_SCRIPTS[@]}"; do
    echo "  -> shellcheck ${script}"
    shellcheck --severity=warning "${script}"
  done
else
  echo "WARN: shellcheck is not installed. Skipping static analysis." >&2
fi

echo "==> [Shell] All shell script checks passed successfully."
