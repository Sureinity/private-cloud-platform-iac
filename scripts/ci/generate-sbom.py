#!/usr/bin/env python3
# ==============================================================================
# scripts/ci/generate-sbom.py
#
# Generates CycloneDX JSON Software Bill of Materials (SBOM) and evidence manifest
# for the On-Premises PVE infrastructure supply chain.
#
# Catalogs:
# 1. Python tooling dependencies (requirements.txt)
# 2. Ansible Galaxy collections (ansible/infra-ops/requirements.yml)
# 3. Terraform core and provider dependencies (.terraform.lock.hcl)
# 4. Pinned service binaries (roles/seaweedfs/defaults/main.yml)
# 5. Pinned CI CLI scanners and tools (scripts/ci/versions.env)
# 6. Pinned GitHub Actions dependencies (.github/workflows/validate.yml)
# ==============================================================================

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid


def sha256_file(filepath: Path) -> str:
    """Computes SHA-256 checksum of a file."""
    h = hashlib.sha256()
    with filepath.open("rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def get_git_info(repo_root: Path) -> dict[str, str]:
    """Retrieves current Git commit and branch name."""
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=repo_root, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        commit = "unknown"

    try:
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"], cwd=repo_root, text=True, stderr=subprocess.DEVNULL
        ).strip()
        if not branch:
            branch = "HEAD"
    except Exception:
        branch = "unknown"

    return {"commit_sha": commit, "branch": branch}


def extract_python_packages(repo_root: Path) -> list[dict]:
    """Extracts Python dependencies from requirements.txt."""
    req_file = repo_root / "requirements.txt"
    components = []
    if not req_file.is_file():
        return components

    for line in req_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([a-zA-Z0-9_\-\.]+)(?:==([a-zA-Z0-9_\-\.]+))?", line)
        if m:
            name, version = m.group(1), m.group(2) or "unknown"
            components.append({
                "type": "library",
                "bom-ref": f"pkg:pypi/{name}@{version}",
                "name": name,
                "version": version,
                "purl": f"pkg:pypi/{name}@{version}",
                "scope": "required",
                "properties": [
                    {"name": "platform:ecosystem", "value": "pypi"},
                    {"name": "platform:source_file", "value": "requirements.txt"},
                ],
            })
    return sorted(components, key=lambda c: c["name"])


def extract_ansible_collections(repo_root: Path) -> list[dict]:
    """Extracts Ansible Galaxy collections from requirements.yml."""
    req_file = repo_root / "ansible/infra-ops/requirements.yml"
    components = []
    if not req_file.is_file():
        return components

    content = req_file.read_text(encoding="utf-8")
    for match in re.finditer(r"-\s*name:\s*([^\s]+)\s*\n\s*version:\s*\"?([^\s\"]+)\"?", content):
        name = match.group(1)
        version = match.group(2)
        components.append({
            "type": "library",
            "bom-ref": f"pkg:ansible/{name}@{version}",
            "name": name,
            "version": version,
            "purl": f"pkg:ansible/{name}@{version}",
            "scope": "required",
            "properties": [
                {"name": "platform:ecosystem", "value": "ansible"},
                {"name": "platform:source_file", "value": "ansible/infra-ops/requirements.yml"},
            ],
        })
    return sorted(components, key=lambda c: c["name"])


def extract_terraform_providers(repo_root: Path) -> list[dict]:
    """Extracts Terraform provider locks across live and bootstrap roots."""
    lockfiles = [
        ("terraform/live/onprem-pve/.terraform.lock.hcl", "live"),
        ("terraform/bootstrap/seaweedfs/.terraform.lock.hcl", "bootstrap"),
    ]
    components = []
    seen = set()

    for rel_path, context in lockfiles:
        lockfile = repo_root / rel_path
        if not lockfile.is_file():
            continue

        content = lockfile.read_text(encoding="utf-8")
        for match in re.finditer(r'provider\s+"([^"]+)"\s*\{(.*?)\}', content, re.DOTALL):
            provider_addr = match.group(1)
            block = match.group(2)
            v_match = re.search(r'version\s*=\s*"([^"]+)"', block)
            version = v_match.group(1) if v_match else "unknown"

            key = (provider_addr, version)
            if key in seen:
                continue
            seen.add(key)

            # Collect zh: (sha256) hashes from lockfile
            hashes = []
            for h in re.findall(r'"zh:([a-f0-9]{64})"', block):
                hashes.append({"alg": "SHA-256", "content": h})

            parts = provider_addr.split("/")
            group = parts[-2] if len(parts) >= 2 else "terraform"
            name = parts[-1]

            components.append({
                "type": "application",
                "bom-ref": f"pkg:terraform/{group}/{name}@{version}",
                "group": group,
                "name": name,
                "version": version,
                "purl": f"pkg:terraform/{group}/{name}@{version}",
                "hashes": hashes[:5],  # Include first 5 multi-platform hashes for concise validity
                "properties": [
                    {"name": "platform:ecosystem", "value": "terraform"},
                    {"name": "platform:provider_address", "value": provider_addr},
                    {"name": "platform:context", "value": context},
                    {"name": "platform:source_file", "value": rel_path},
                ],
            })
    return sorted(components, key=lambda c: c["name"])


def extract_service_binaries(repo_root: Path) -> list[dict]:
    """Extracts pinned guest / service binaries (e.g. SeaweedFS)."""
    defaults_file = repo_root / "ansible/infra-ops/roles/seaweedfs/defaults/main.yml"
    components = []
    if not defaults_file.is_file():
        return components

    content = defaults_file.read_text(encoding="utf-8")
    v_match = re.search(r'seaweedfs_version:\s*"([^"]+)"', content)
    c_match = re.search(r'seaweedfs_checksum:\s*"([^"]+)"', content)
    b_match = re.search(r'seaweedfs_build_type:\s*"([^"]+)"', content)
    a_match = re.search(r'seaweedfs_arch:\s*"([^"]+)"', content)

    if v_match:
        version = v_match.group(1)
        checksum = c_match.group(1) if c_match else ""
        build_type = b_match.group(1) if b_match else "standard"
        arch = a_match.group(1) if a_match else "amd64"

        components.append({
            "type": "application",
            "bom-ref": f"pkg:generic/seaweedfs@{version}",
            "name": "seaweedfs",
            "version": version,
            "purl": f"pkg:generic/seaweedfs@{version}",
            "hashes": [{"alg": "SHA-256", "content": checksum}] if checksum else [],
            "properties": [
                {"name": "platform:ecosystem", "value": "binary"},
                {"name": "platform:build_type", "value": build_type},
                {"name": "platform:arch", "value": arch},
                {"name": "platform:target_destination", "value": "/usr/local/bin/weed"},
                {"name": "platform:source_file", "value": "ansible/infra-ops/roles/seaweedfs/defaults/main.yml"},
            ],
        })
    return components


def extract_ci_tools(repo_root: Path) -> list[dict]:
    """Extracts pinned CLI scanners and tools from versions.env."""
    env_file = repo_root / "scripts/ci/versions.env"
    components = []
    if not env_file.is_file():
        return components

    content = env_file.read_text(encoding="utf-8")
    for k, v in re.findall(r'([A-Z_]+)="([^"]+)"', content):
        tool_name = k.replace("_VERSION", "").lower()
        components.append({
            "type": "application",
            "bom-ref": f"pkg:generic/{tool_name}@{v}",
            "name": tool_name,
            "version": v,
            "purl": f"pkg:generic/{tool_name}@{v}",
            "scope": "optional",
            "properties": [
                {"name": "platform:ecosystem", "value": "ci-tooling"},
                {"name": "platform:env_var", "value": k},
                {"name": "platform:source_file", "value": "scripts/ci/versions.env"},
            ],
        })
    return sorted(components, key=lambda c: c["name"])


def extract_github_actions(repo_root: Path) -> list[dict]:
    """Extracts pinned GitHub Actions dependencies from workflow files."""
    workflow_file = repo_root / ".github/workflows/validate.yml"
    components = []
    seen = set()
    if not workflow_file.is_file():
        return components

    content = workflow_file.read_text(encoding="utf-8")
    for action, sha, tag in re.findall(
        r"uses:\s*([^@\s]+)@([a-f0-9]{40})\s*(?:#\s*([^\s\n]+))?", content
    ):
        if (action, sha) in seen:
            continue
        seen.add((action, sha))

        version_label = tag if tag else sha[:7]
        components.append({
            "type": "application",
            "bom-ref": f"pkg:githubactions/{action}@{sha}",
            "name": action,
            "version": version_label,
            "purl": f"pkg:githubactions/{action}@{sha}",
            "hashes": [{"alg": "SHA-1", "content": sha}],
            "properties": [
                {"name": "platform:ecosystem", "value": "github-actions"},
                {"name": "platform:commit_sha", "value": sha},
                {"name": "platform:source_file", "value": ".github/workflows/validate.yml"},
            ],
        })
    return sorted(components, key=lambda c: c["name"])


def build_cyclonedx_sbom(repo_root: Path, components: list[dict], git_info: dict) -> dict:
    """Builds the CycloneDX 1.6 compliant SBOM dictionary."""
    now_iso = datetime.now(timezone.utc).isoformat()
    return {
        "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": now_iso,
            "tools": {
                "components": [
                    {
                        "type": "application",
                        "name": "platform-sbom-generator",
                        "version": "1.0.0",
                        "description": "Platform Supply-Chain Pipeline Evidence Generator",
                    }
                ]
            },
            "component": {
                "type": "application",
                "bom-ref": "pkg:generic/private-cloud-platform@main",
                "name": "onprem-pve",
                "version": git_info["commit_sha"][:8],
                "description": "Home Proxmox VE Infrastructure and Automation Platform",
                "properties": [
                    {"name": "platform:git_commit", "value": git_info["commit_sha"]},
                    {"name": "platform:git_branch", "value": git_info["branch"]},
                ],
            },
        },
        "components": components,
    }


def build_evidence_manifest(
    repo_root: Path,
    sbom_path: Path,
    counts: dict[str, int],
    git_info: dict,
) -> dict:
    """Builds the sanitized evidence manifest linking lockfiles, SBOM, and git state."""
    lockfiles_to_hash = [
        ("requirements.txt", "requirements.txt"),
        ("ansible_requirements", "ansible/infra-ops/requirements.yml"),
        ("terraform_live_lock", "terraform/live/onprem-pve/.terraform.lock.hcl"),
        ("terraform_bootstrap_lock", "terraform/bootstrap/seaweedfs/.terraform.lock.hcl"),
        ("tool_versions", "scripts/ci/versions.env"),
        ("seaweedfs_defaults", "ansible/infra-ops/roles/seaweedfs/defaults/main.yml"),
        ("validate_workflow", ".github/workflows/validate.yml"),
    ]

    lockfile_hashes = {}
    for key, rel_path in lockfiles_to_hash:
        p = repo_root / rel_path
        if p.is_file():
            lockfile_hashes[key] = {
                "path": rel_path,
                "sha256": sha256_file(p),
            }

    now_iso = datetime.now(timezone.utc).isoformat()
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "schema_version": "1.0.0",
        "generated_at": now_iso,
        "repository": {
            "name": "onprem-pve",
            "commit_sha": git_info["commit_sha"],
            "branch": git_info["branch"],
        },
        "lockfiles": lockfile_hashes,
        "artifacts": {
            "sbom": {
                "path": str(sbom_path.name),
                "format": "CycloneDX-1.6",
                "sha256": sha256_file(sbom_path),
                "component_counts": counts,
            }
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Generate SBOM and Evidence Manifest for On-Premises PVE")
    parser.add_argument("--repo-root", default=".", help="Root directory of git repository")
    parser.add_argument("--out-dir", default="artifacts", help="Output directory for generated files")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    git_info = get_git_info(repo_root)

    # Collect all component sets
    py_pkgs = extract_python_packages(repo_root)
    ans_colls = extract_ansible_collections(repo_root)
    tf_provs = extract_terraform_providers(repo_root)
    svc_bins = extract_service_binaries(repo_root)
    ci_tools = extract_ci_tools(repo_root)
    gh_actions = extract_github_actions(repo_root)

    all_components = py_pkgs + ans_colls + tf_provs + svc_bins + ci_tools + gh_actions

    counts = {
        "python_packages": len(py_pkgs),
        "ansible_collections": len(ans_colls),
        "terraform_providers": len(tf_provs),
        "service_binaries": len(svc_bins),
        "ci_tools": len(ci_tools),
        "github_actions": len(gh_actions),
        "total": len(all_components),
    }

    # 1. Write CycloneDX SBOM
    sbom_data = build_cyclonedx_sbom(repo_root, all_components, git_info)
    sbom_path = out_dir / "sbom.cdx.json"
    sbom_path.write_text(json.dumps(sbom_data, indent=2), encoding="utf-8")

    # 2. Write Evidence Manifest
    manifest_data = build_evidence_manifest(repo_root, sbom_path, counts, git_info)
    manifest_path = out_dir / "evidence-manifest.json"
    manifest_path.write_text(json.dumps(manifest_data, indent=2), encoding="utf-8")

    print(f"==> Generated CycloneDX SBOM: {sbom_path} ({counts['total']} components)")
    print(f"==> Generated Evidence Manifest: {manifest_path}")
    print(
        f"    [Breakdown] Python: {counts['python_packages']} | "
        f"Ansible: {counts['ansible_collections']} | "
        f"Terraform: {counts['terraform_providers']} | "
        f"Service Binaries: {counts['service_binaries']} | "
        f"CI Tools: {counts['ci_tools']} | "
        f"GitHub Actions: {counts['github_actions']}"
    )


if __name__ == "__main__":
    main()
