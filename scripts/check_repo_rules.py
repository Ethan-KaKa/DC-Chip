#!/usr/bin/env python3
"""Check mechanical repository rules for DC-Chip.

The default mode checks tracked files as they appear in the working tree.
``--staged`` checks the complete Git index and is intended for pre-commit.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import posixpath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[1]

CHECK_EXTENSIONS = {
    ".sv", ".v", ".c", ".h", ".cpp", ".cc", ".S", ".s",
    ".py", ".sh", ".mk", ".ld", ".nxdc", ".json",
}
CHECK_EXACT_NAMES = {"Makefile", "Dconfig"}
DOC_RULE_EXEMPTIONS = {
    "BUILD_RULES.md",
    "GIT_RULES.md",
    "AGENTS.md",
    "AGENTS.local.example.md",
    "scripts/check_repo_rules.py",
    "scripts/test_repo_rules.py",
}
FORBIDDEN_PATH_PATTERN = re.compile(
    r"(?:/home/[a-zA-Z0-9_.-]+|/Users/[a-zA-Z0-9_.-]+)"
)
FORBIDDEN_TRACKED_NAMES = {"AGENTS.local.md", ".localset.md"}
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
TEMP_PREFIX = "docs/00-temp/"


@dataclass(frozen=True)
class RepositoryView:
    root: Path
    staged: bool
    tracked: tuple[str, ...]

    @classmethod
    def create(cls, root: Path, staged: bool) -> "RepositoryView":
        out = run_git(root, "ls-files", "-z")
        tracked = tuple(
            path for path in out.decode("utf-8", errors="replace").split("\0") if path
        )
        return cls(root=root, staged=staged, tracked=tracked)

    def read_bytes(self, rel_path: str) -> bytes | None:
        if self.staged:
            try:
                return run_git(self.root, "show", f":{rel_path}")
            except subprocess.CalledProcessError:
                return None
        path = self.root / rel_path
        if not path.is_file():
            return None
        try:
            return path.read_bytes()
        except OSError:
            return None

    def read_text(self, rel_path: str) -> str | None:
        content = self.read_bytes(rel_path)
        if content is None:
            return None
        return content.decode("utf-8", errors="replace")

    def target_exists(self, rel_path: str) -> bool:
        normalized = rel_path.rstrip("/")
        if not normalized:
            return True
        if self.staged:
            return normalized in self.tracked or any(
                path.startswith(normalized + "/") for path in self.tracked
            )
        return (self.root / normalized).exists()


def run_git(root: Path, *args: str) -> bytes:
    return subprocess.check_output(
        ["git", "-C", str(root), *args], stderr=subprocess.DEVNULL
    )


def is_private_file(rel_path: str) -> bool:
    name = PurePosixPath(rel_path).name
    return (
        name in FORBIDDEN_TRACKED_NAMES
        or (name.endswith(".local.md") and name != "AGENTS.local.example.md")
    )


def check_private_tracked_files(view: RepositoryView) -> list[str]:
    return [
        f"Private file tracked in Git: {path}"
        for path in view.tracked
        if is_private_file(path)
    ]


def check_temp_tracking(view: RepositoryView) -> list[str]:
    return [
        f"Temporary document tracked in Git: {path}"
        for path in view.tracked
        if path.startswith(TEMP_PREFIX) and path != TEMP_PREFIX + ".gitignore"
    ]


def check_hardcoded_paths(view: RepositoryView) -> list[str]:
    violations: list[str] = []
    for rel_path in view.tracked:
        if rel_path in DOC_RULE_EXEMPTIONS:
            continue
        path = PurePosixPath(rel_path)
        if path.suffix not in CHECK_EXTENSIONS and path.name not in CHECK_EXACT_NAMES:
            continue
        content = view.read_text(rel_path)
        if content is None:
            continue
        for line_no, line in enumerate(content.splitlines(), start=1):
            match = FORBIDDEN_PATH_PATTERN.search(line)
            if match and not ("Reference:" in line and path.suffix == ".sv"):
                violations.append(
                    f"{rel_path}:{line_no}: Hardcoded absolute host path found: "
                    f"{match.group(0)}"
                )
    return violations


def extract_link_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        return target[1:target.index(">")]
    return target.split(maxsplit=1)[0] if target else ""


def resolve_markdown_target(source: str, raw_target: str) -> str | None:
    target = unquote(extract_link_target(raw_target))
    if not target or target.startswith("#"):
        return None
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or parsed.path.startswith("/"):
        return None
    if not parsed.path:
        return None
    source_dir = posixpath.dirname(source)
    return posixpath.normpath(posixpath.join(source_dir, parsed.path)).rstrip("/")


def check_markdown_links(view: RepositoryView) -> list[str]:
    violations: list[str] = []
    for rel_path in view.tracked:
        if PurePosixPath(rel_path).suffix.lower() != ".md":
            continue
        content = view.read_text(rel_path)
        if content is None:
            continue
        for line_no, line in enumerate(content.splitlines(), start=1):
            for match in MARKDOWN_LINK_PATTERN.finditer(line):
                target = resolve_markdown_target(rel_path, match.group(1))
                if target is None:
                    continue
                if target == ".." or target.startswith("../"):
                    violations.append(
                        f"{rel_path}:{line_no}: Relative Markdown link escapes repository: "
                        f"{extract_link_target(match.group(1))}"
                    )
                elif target.startswith(TEMP_PREFIX.rstrip("/")):
                    violations.append(
                        f"{rel_path}:{line_no}: Formal Markdown links to temporary content: "
                        f"{extract_link_target(match.group(1))}"
                    )
                elif not view.target_exists(target):
                    violations.append(
                        f"{rel_path}:{line_no}: Broken relative Markdown link: "
                        f"{extract_link_target(match.group(1))}"
                    )
    return violations


def check_temp_references(view: RepositoryView) -> list[str]:
    violations: list[str] = []
    for rel_path in view.tracked:
        if rel_path.startswith(TEMP_PREFIX) or rel_path in DOC_RULE_EXEMPTIONS:
            continue
        path = PurePosixPath(rel_path)
        is_formal_doc = path.suffix.lower() == ".md"
        is_source = path.suffix in CHECK_EXTENSIONS or path.name in CHECK_EXACT_NAMES
        if not (is_formal_doc or is_source):
            continue
        content = view.read_text(rel_path)
        if content is None:
            continue
        for line_no, line in enumerate(content.splitlines(), start=1):
            if TEMP_PREFIX in line:
                violations.append(
                    f"{rel_path}:{line_no}: Tracked source or formal documentation "
                    f"references {TEMP_PREFIX}"
                )
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Check DC-Chip repository rules.")
    parser.add_argument("--staged", action="store_true", help="check the complete Git index")
    parser.add_argument(
        "--repo-root", type=Path, default=DEFAULT_REPO_ROOT,
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    root = args.repo_root.resolve()
    try:
        view = RepositoryView.create(root, args.staged)
    except (subprocess.SubprocessError, FileNotFoundError):
        print(f"error: cannot read Git index below {root}", file=sys.stderr)
        return 2

    violations: list[str] = []
    violations.extend(check_private_tracked_files(view))
    violations.extend(check_temp_tracking(view))
    violations.extend(check_hardcoded_paths(view))
    violations.extend(check_markdown_links(view))
    violations.extend(check_temp_references(view))

    if violations:
        print("Repository rule violation(s) detected:", file=sys.stderr)
        for violation in violations:
            print(f"  error: {violation}", file=sys.stderr)
        print(f"Total violations: {len(violations)}", file=sys.stderr)
        return 1

    view_name = "staged index" if args.staged else "tracked working tree"
    print(f"Repository rule check ({view_name}): PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
