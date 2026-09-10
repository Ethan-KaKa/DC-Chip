#!/usr/bin/env python3
"""Self-checking tests for scripts/config.py and its generated files."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_SCRIPT = REPO_ROOT / "scripts" / "config.py"
VENDOR_DIR = REPO_ROOT / "tools" / "kconfiglib"
SYMBOLS = ("DC_SIM_SDB", "DC_SIM_WAVE")


class TestFailure(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise TestFailure(message)


def run(
    command: list[str],
    *,
    cwd: Path = REPO_ROOT,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["CCACHE_DISABLE"] = "1"
    return subprocess.run(
        command,
        cwd=cwd,
        input=input_text,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def config_command(
    config_path: Path, output_dir: Path, command: str, *arguments: str
) -> list[str]:
    return [
        sys.executable,
        str(CONFIG_SCRIPT),
        "--config",
        str(config_path),
        "--output-dir",
        str(output_dir),
        command,
        *arguments,
    ]


def expect_success(result: subprocess.CompletedProcess[str], context: str) -> None:
    require(
        result.returncode == 0,
        f"{context}: exit {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
    )


def expect_failure(result: subprocess.CompletedProcess[str], context: str) -> None:
    require(result.returncode != 0, f"{context}: unexpectedly succeeded")
    require(bool(result.stderr.strip()), f"{context}: missing stderr diagnostic")


def file_snapshot(paths: list[Path]) -> dict[Path, bytes | None]:
    return {path: path.read_bytes() if path.is_file() else None for path in paths}


def expected_show(sdb: bool, wave: bool) -> str:
    return (
        f"CONFIG_DC_SIM_SDB={'y' if sdb else 'n'}\n"
        f"CONFIG_DC_SIM_WAVE={'y' if wave else 'n'}\n"
    )


def verify_generated(output_dir: Path, sdb: bool, wave: bool) -> None:
    auto_conf = (output_dir / "auto.conf").read_text(encoding="utf-8")
    header = (output_dir / "config.h").read_text(encoding="utf-8")
    require(
        f"CONFIG_DC_SIM_SDB={'y' if sdb else 'n'}\n" in auto_conf,
        "auto.conf has the wrong SDB value",
    )
    require(
        f"CONFIG_DC_SIM_WAVE={'y' if wave else 'n'}\n" in auto_conf,
        "auto.conf has the wrong WAVE value",
    )
    for name, enabled in zip(SYMBOLS, (sdb, wave)):
        definition = f"#define CONFIG_{name} 1"
        require(
            (definition in header) == enabled,
            f"config.h has the wrong enabled-macro state for {name}",
        )


def compile_header(cxx: str, output_dir: Path, sdb: bool, wave: bool) -> None:
    checks: list[str] = []
    for name, enabled in zip(SYMBOLS, (sdb, wave)):
        if enabled:
            checks.extend(
                [
                    f"#ifndef CONFIG_{name}",
                    f'#error "CONFIG_{name} must be defined"',
                    "#endif",
                    f"#if CONFIG_{name} != 1",
                    f'#error "CONFIG_{name} must equal 1"',
                    "#endif",
                ]
            )
        else:
            checks.extend(
                [
                    f"#ifdef CONFIG_{name}",
                    f'#error "CONFIG_{name} must be absent"',
                    "#endif",
                ]
            )
    source = "\n".join(checks + ["int main() { return 0; }", ""])
    result = run(
        [
            cxx,
            "-std=c++17",
            f"-I{output_dir}",
            "-include",
            str(output_dir / "config.h"),
            "-x",
            "c++",
            "-fsyntax-only",
            "-",
        ],
        input_text=source,
    )
    expect_success(result, f"C++ header check for SDB={sdb}, WAVE={wave}")


def run_tests(fixture_root: Path, cxx: str) -> None:
    shutil.rmtree(fixture_root, ignore_errors=True)
    config_path = fixture_root / ".config"
    output_dir = fixture_root / "generated"
    tracked_paths = [config_path, output_dir / "auto.conf", output_dir / "config.h"]

    missing_show = run(config_command(config_path, output_dir, "show"))
    expect_success(missing_show, "show without a configuration")
    require(missing_show.stdout == expected_show(False, False), "wrong default show output")
    require(not config_path.exists(), "show created the missing configuration")
    require(not output_dir.exists(), "show created the output directory")

    default_result = run(config_command(config_path, output_dir, "default"))
    expect_success(default_result, "default")
    require(all(path.is_file() for path in tracked_paths), "default omitted an output file")
    verify_generated(output_dir, False, False)

    sdb_result = run(
        config_command(config_path, output_dir, "set", "DC_SIM_SDB=y")
    )
    expect_success(sdb_result, "set SDB")
    shown = run(config_command(config_path, output_dir, "show"))
    expect_success(shown, "show after setting SDB")
    require(shown.stdout == expected_show(True, False), "setting SDB changed another option")

    both_result = run(
        config_command(
            config_path,
            output_dir,
            "set",
            "DC_SIM_SDB=y",
            "DC_SIM_WAVE=y",
        )
    )
    expect_success(both_result, "set both options")
    verify_generated(output_dir, True, True)

    disabled_result = run(
        config_command(
            config_path,
            output_dir,
            "set",
            "DC_SIM_SDB=n",
            "DC_SIM_WAVE=n",
        )
    )
    expect_success(disabled_result, "disable both options")
    verify_generated(output_dir, False, False)

    baseline = file_snapshot(tracked_paths)
    invalid_sets = (
        ("unknown symbol", "DC_UNKNOWN=y"),
        ("CONFIG_ prefix", "CONFIG_DC_SIM_SDB=y"),
        ("invalid value", "DC_SIM_SDB=Y"),
        ("missing equals", "DC_SIM_SDB"),
    )
    for context, assignment in invalid_sets:
        result = run(config_command(config_path, output_dir, "set", assignment))
        expect_failure(result, context)
        require(file_snapshot(tracked_paths) == baseline, f"{context} modified files")

    duplicate = run(
        config_command(
            config_path,
            output_dir,
            "set",
            "DC_SIM_SDB=y",
            "DC_SIM_SDB=n",
        )
    )
    expect_failure(duplicate, "duplicate symbol")
    require(file_snapshot(tracked_paths) == baseline, "duplicate setting modified files")

    mixed_invalid = run(
        config_command(
            config_path,
            output_dir,
            "set",
            "DC_SIM_SDB=y",
            "DC_UNKNOWN=y",
        )
    )
    expect_failure(mixed_invalid, "mixed valid and invalid settings")
    require(
        file_snapshot(tracked_paths) == baseline,
        "mixed valid and invalid settings partially modified files",
    )

    old_time_ns = 946684800_000_000_000
    generated_paths = [output_dir / "auto.conf", output_dir / "config.h"]
    for path in generated_paths:
        os.utime(path, ns=(old_time_ns, old_time_ns))
    before_times = {path: path.stat().st_mtime_ns for path in generated_paths}
    sync_result = run(config_command(config_path, output_dir, "sync"))
    expect_success(sync_result, "idempotent sync")
    after_times = {path: path.stat().st_mtime_ns for path in generated_paths}
    require(before_times == after_times, "idempotent sync changed generated mtimes")

    alternate_root = fixture_root.parent / "config-alternate"
    shutil.rmtree(alternate_root, ignore_errors=True)
    alternate_config = alternate_root / ".config"
    alternate_output = alternate_root / "generated"
    primary_before = file_snapshot(tracked_paths)
    alternate = run(
        config_command(
            alternate_config,
            alternate_output,
            "set",
            "DC_SIM_WAVE=y",
        ),
        cwd=fixture_root,
    )
    expect_success(alternate, "alternate paths")
    verify_generated(alternate_output, False, True)
    require(file_snapshot(tracked_paths) == primary_before, "alternate paths crossed over")

    bad_config_path = fixture_root / "config-is-a-directory"
    bad_config_path.mkdir()
    file_error = run(config_command(bad_config_path, output_dir, "show"))
    expect_failure(file_error, "configuration file error")

    import_environment = os.environ.copy()
    import_result = subprocess.run(
        [
            sys.executable,
            "-c",
            "import curses, menuconfig; print('imports: PASS')",
        ],
        cwd=fixture_root,
        env={**import_environment, "PYTHONPATH": str(VENDOR_DIR)},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    expect_success(import_result, "vendored menuconfig and curses imports")

    for sdb, wave in ((False, False), (True, False), (False, True), (True, True)):
        matrix = run(
            config_command(
                config_path,
                output_dir,
                "set",
                f"DC_SIM_SDB={'y' if sdb else 'n'}",
                f"DC_SIM_WAVE={'y' if wave else 'n'}",
            )
        )
        expect_success(matrix, f"configuration matrix SDB={sdb}, WAVE={wave}")
        matrix_show = run(config_command(config_path, output_dir, "show"))
        expect_success(matrix_show, "matrix show")
        require(matrix_show.stdout == expected_show(sdb, wave), "wrong matrix values")
        verify_generated(output_dir, sdb, wave)
        compile_header(cxx, output_dir, sdb, wave)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-root", type=Path, required=True)
    parser.add_argument("--cxx", default="c++")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        run_tests(args.fixture_root.resolve(), args.cxx)
    except (OSError, TestFailure) as error:
        print(f"test_config: FAIL: {error}", file=sys.stderr)
        return 1
    print("test_config: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
