#!/usr/bin/env python3
"""Static rule and path compliance checker for DC-Chip.

Enforces BUILD_RULES.md requirements:
1. No hardcoded host absolute paths (/home/, /Users/) in code, scripts, and build files.
2. No private local configuration files tracked in git.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]

# File patterns to check for absolute paths
CHECK_EXTENSIONS = {
    ".sv", ".v", ".c", ".h", ".cpp", ".cc", ".S", ".s",
    ".py", ".sh", ".mk", ".ld", ".nxdc", ".json"
}
CHECK_EXACT_NAMES = {"Makefile", "Dconfig"}

# Files allowed to mention path examples for documentation / rule checking purposes
DOC_RULE_EXEMPTIONS = {
    "BUILD_RULES.md",
    "GIT_RULES.md",
    "AGENTS.md",
    "AGENTS.local.example.md",
    "scripts/check_repo_rules.py",
}

# Regex matching forbidden absolute host paths
FORBIDDEN_PATH_PATTERN = re.compile(r"""(?:/home/[a-zA-Z0-9_\.\-]+|/Users/[a-zA-Z0-9_\.\-]+)""")

# Forbidden tracked private files
FORBIDDEN_TRACKED_NAMES = {"AGENTS.local.md", ".localset.md"}


def get_tracked_files() -> list[str]:
    """Retrieve all tracked files in the repository using git ls-files."""
    cmd = ["git", "-C", str(REPO_ROOT), "ls-files", "-z"]
    try:
        out = subprocess.check_output(cmd)
        return [p for p in out.decode("utf-8", errors="replace").split("\0") if p]
    except (subprocess.SubprocessError, FileNotFoundError) as e:
        print(f"warning: failed to run git ls-files: {e}", file=sys.stderr)
        # Fallback to filesystem traversal excluding .git and build
        tracked = []
        for p in REPO_ROOT.rglob("*"):
            rel = p.relative_to(REPO_ROOT).as_posix()
            if rel.startswith(".git/") or rel.startswith("build/") or rel.startswith(".gemini/"):
                continue
            if p.is_file():
                tracked.append(rel)
        return tracked


def check_private_tracked_files(tracked_files: list[str]) -> list[str]:
    """Ensure no private configuration files are tracked."""
    violations = []
    for f in tracked_files:
        path = Path(f)
        if path.name in FORBIDDEN_TRACKED_NAMES or path.name.endswith(".local.md"):
            if path.name != "AGENTS.local.example.md":
                violations.append(f"Private file tracked in Git: {f}")
    return violations


def check_hardcoded_paths(tracked_files: list[str]) -> list[str]:
    """Ensure no hardcoded absolute host paths appear in source/build files."""
    violations = []
    for rel_path in tracked_files:
        if rel_path in DOC_RULE_EXEMPTIONS:
            continue

        p = Path(rel_path)
        if p.suffix not in CHECK_EXTENSIONS and p.name not in CHECK_EXACT_NAMES:
            continue

        full_path = REPO_ROOT / rel_path
        if not full_path.is_file():
            continue

        try:
            content = full_path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            violations.append(f"Cannot read {rel_path}: {e}")
            continue

        for line_no, line in enumerate(content.splitlines(), start=1):
            match = FORBIDDEN_PATH_PATTERN.search(line)
            if match:
                # Check for comment markers explaining reference origins in sim_mem if any
                if "Reference:" in line and full_path.suffix == ".sv":
                    continue
                violations.append(
                    f"{rel_path}:{line_no}: Hardcoded absolute host path found: {match.group(0)}"
                )
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Check DC-Chip repository rule compliance.")
    parser.add_argument("--mode", choices=["all", "paths", "private"], default="all")
    args = parser.parse_args()

    tracked = get_tracked_files()
    violations: list[str] = []

    if args.mode in ("all", "private"):
        violations.extend(check_private_tracked_files(tracked))

    if args.mode in ("all", "paths"):
        violations.extend(check_hardcoded_paths(tracked))

    if violations:
        print("BUILD_RULES.md violation(s) detected:", file=sys.stderr)
        for v in violations:
            print(f"  error: {v}", file=sys.stderr)
        print(f"Total violations: {len(violations)}", file=sys.stderr)
        return 1

    print("Repository path and configuration compliance check: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
