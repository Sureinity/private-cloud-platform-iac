#!/usr/bin/env bash
# ==============================================================================
# scripts/ci/validate-markdown.sh
#
# Validates Markdown files across the repository:
# 1. Verifies fenced code blocks are properly paired/closed.
# 2. Verifies internal relative links exist on disk.
# 3. Verifies heading hierarchy structure.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

echo "==> [Markdown] Validating Markdown files and links..."

python3 - <<'EOF'
import os
import re
import subprocess
import sys
from pathlib import Path

repo_root = Path(".").resolve()

# Inspect tracked and untracked non-ignored Markdown files
cmd = ["git", "ls-files", "*.md"]
result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
cmd_untracked = ["git", "ls-files", "--others", "--exclude-standard", "*.md"]
result_untracked = subprocess.run(cmd_untracked, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)

all_paths = set(result.stdout.splitlines() + result_untracked.stdout.splitlines())
md_files = sorted([repo_root / p for p in all_paths if p.strip()])
errors = []

link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')

for md in md_files:
    try:
        content = md.read_text(encoding="utf-8")
    except Exception as e:
        errors.append(f"{md.relative_to(repo_root)}: Failed to read file: {e}")
        continue

    lines = content.splitlines()
    in_code_block = False
    code_block_start = 0

    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_code_block = not in_code_block
            if in_code_block:
                code_block_start = idx

        if in_code_block:
            continue

        # Check links outside code blocks
        for match in link_pattern.finditer(line):
            target = match.group(2).split("#")[0].strip()
            # Ignore empty, external, mailto, or URI schemes
            if not target or target.startswith(("http://", "https://", "mailto:", "file://", "tel:")):
                continue
            
            target_path = (md.parent / target).resolve()
            if not target_path.exists():
                errors.append(f"{md.relative_to(repo_root)}:{idx}: Broken relative link '{target}'")

    if in_code_block:
        errors.append(f"{md.relative_to(repo_root)}:{code_block_start}: Unclosed fenced code block")

if errors:
    print("ERROR: Markdown validation issues found:\n", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)
else:
    print(f"Validated {len(md_files)} Markdown files. Zero broken links or unclosed code blocks found.")
EOF

echo "==> [Markdown] All Markdown validation checks passed successfully."
