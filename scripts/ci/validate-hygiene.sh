#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-hygiene.sh
#
# Validates repository hygiene:
# 1. Runs `git diff --check` for whitespace and conflict markers.
# 2. Ensures no forbidden sensitive or runtime artifacts are tracked in git
#    (e.g., state files, plans, private keys, secrets payloads, VM media).
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

echo "==> [Hygiene] Checking whitespace and git diff..."
git diff --check

echo "==> [Hygiene] Checking for forbidden tracked artifacts..."
FORBIDDEN_TRACKED=()

# Define forbidden file patterns
PATTERNS=(
  '*.tfstate'
  '*.tfstate.*'
  '*.tfplan'
  '*.tfplan.*'
  '*.plan'
  'plan.out'
  'crash.log'
  'crash.*.log'
  'terraform.tfvars'
  '*.auto.tfvars'
  '*.auto.tfvars.json'
  '*.pem'
  '*.key'
  'id_rsa'
  'id_ed25519'
  '*.iso'
  '*.img'
  '*.qcow2'
  '*.raw'
  '*.vmdk'
  'configs/*'
)

for pattern in "${PATTERNS[@]}"; do
  # Find any tracked files matching pattern
  while IFS= read -r file; do
    if [[ -n "${file}" ]]; then
      # Allow .example files
      if [[ "${file}" == *.example ]]; then
        continue
      fi
      FORBIDDEN_TRACKED+=("${file}")
    fi
  done < <(git ls-files "${pattern}" 2>/dev/null || true)
done

# Specifically check secrets directories (only README.md is permitted)
while IFS= read -r file; do
  if [[ -n "${file}" && "${file}" != */README.md ]]; then
    FORBIDDEN_TRACKED+=("${file}")
  fi
done < <(git ls-files '**/secrets/*' 'secrets/*' 2>/dev/null || true)

if [[ ${#FORBIDDEN_TRACKED[@]} -gt 0 ]]; then
  echo "ERROR: Forbidden sensitive or runtime files are tracked in git:" >&2
  for f in "${FORBIDDEN_TRACKED[@]}"; do
    echo "  - ${f}" >&2
  done
  exit 1
fi

echo "==> [Hygiene] All repository hygiene checks passed."
