#!/usr/bin/env python3
"""Isolated regression tests for scripts/check_repo_rules.py."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile

REPO_ROOT = Path(__file__).resolve().parents[1]
CHECKER = REPO_ROOT / "scripts" / "check_repo_rules.py"


def run(*args: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [*args], cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=check,
    )


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def git_add_all(root: Path) -> None:
    run("git", "add", "--all", cwd=root)


def check_rules(root: Path, *, staged: bool = False) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(CHECKER), "--repo-root", str(root)]
    if staged:
        args.append("--staged")
    return run(*args, cwd=root, check=False)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="dc-chip-repo-rules-") as tmp:
        root = Path(tmp)
        run("git", "init", "-q", cwd=root)
        write(root / "docs/00-temp/.gitignore", "*\n!.gitignore\n")
        write(root / "docs/guide.md", "[local](target.md#part)\n[web](https://example.com/a)\n[#](#part)\n")
        write(root / "docs/target.md", "# Part\n")
        git_add_all(root)

        result = check_rules(root, staged=True)
        require(result.returncode == 0, f"valid links rejected: {result.stderr}")

        write(root / "docs/guide.md", "[missing](renamed.md)\n")
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 1 and "Broken relative Markdown link" in result.stderr,
                "broken link was not rejected")

        write(root / "docs/guide.md", "[target](target.md)\n")
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 0, "repaired link did not pass")

        run("git", "mv", "docs/target.md", "docs/renamed.md", cwd=root)
        result = check_rules(root, staged=True)
        require(result.returncode == 1 and "Broken relative Markdown link" in result.stderr,
                "staged rename with stale link was not rejected")

        write(root / "docs/guide.md", "[renamed](renamed.md)\n")
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 0, "updated rename link did not pass")

        (root / "docs/renamed.md").unlink()
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 1 and "Broken relative Markdown link" in result.stderr,
                "staged deletion with stale link was not rejected")

        write(root / "docs/renamed.md", "# Renamed\n")
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 0, "restored deleted target did not pass")

        write(root / "docs/guide.md", "temporary path: docs/00-temp/note.md\n")
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 1 and "references docs/00-temp/" in result.stderr,
                "temporary-content reference was not rejected")

        write(root / "docs/guide.md", "[renamed](renamed.md)\n")
        write(root / "docs/00-temp/note.md", "draft\n")
        run("git", "add", "-f", "docs/00-temp/note.md", cwd=root)
        git_add_all(root)
        result = check_rules(root, staged=True)
        require(result.returncode == 1 and "Temporary document tracked" in result.stderr,
                "tracked temporary document was not rejected")

    print("test_repo_rules: PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"test_repo_rules: FAIL: {error}", file=sys.stderr)
        sys.exit(1)
