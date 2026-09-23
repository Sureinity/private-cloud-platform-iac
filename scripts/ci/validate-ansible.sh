#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-ansible.sh
#
# Validates Ansible configuration, inventory, and playbooks:
# 1. YAML syntax and format validation via `yamllint` (if installed).
# 2. Best-practice and safety checks via `ansible-lint` (if installed).
# 3. Playbook syntax check via `ansible-playbook --syntax-check`.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

ANSIBLE_DIR="ansible/infra-ops"
ANSIBLE_CFG="${ANSIBLE_DIR}/ansible.cfg"
INVENTORY="${ANSIBLE_DIR}/inventory/hosts.yml"
if [[ ! -f "${INVENTORY}" && -f "${ANSIBLE_DIR}/inventory/hosts.example.yml" ]]; then
  INVENTORY="${ANSIBLE_DIR}/inventory/hosts.example.yml"
fi

if command -v yamllint >/dev/null 2>&1; then
  echo "==> [Ansible] Running yamllint on Ansible YAML files..."
  yamllint -c "${REPO_ROOT}/.yamllint.yml" "${ANSIBLE_DIR}"
else
  echo "WARN: yamllint is not installed. Skipping YAML linting." >&2
fi

if command -v ansible-lint >/dev/null 2>&1; then
  echo "==> [Ansible] Running ansible-lint..."
  ANSIBLE_CONFIG="${ANSIBLE_CFG}" ansible-lint -c "${REPO_ROOT}/.ansible-lint" "${ANSIBLE_DIR}"
else
  echo "WARN: ansible-lint is not installed on control machine. Skipping ansible-lint." >&2
fi

if command -v ansible-playbook >/dev/null 2>&1; then
  echo "==> [Ansible] Checking playbook syntax with ansible-playbook..."
  for playbook in "${ANSIBLE_DIR}"/playbooks/*.yml; do
    if [[ -f "${playbook}" ]]; then
      echo "  -> Checking syntax for ${playbook}"
      ANSIBLE_CONFIG="${ANSIBLE_CFG}" ansible-playbook -i "${INVENTORY}" --syntax-check "${playbook}"
    fi
  done
else
  echo "ERROR: ansible-playbook CLI is not installed or not in PATH." >&2
  exit 1
fi

echo "==> [Ansible] All Ansible checks completed successfully."
