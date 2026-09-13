#!/usr/bin/env python3
"""Self-check the public Make command contract without running regressions."""

import argparse
import os
import subprocess
import sys


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def run(make_command, *args):
    command = [make_command, "--no-print-directory", "ALL=", *args]
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def require(condition, message, output=""):
    if condition:
        return
    print(f"make_cli_test: FAIL: {message}", file=sys.stderr)
    if output:
        print(output, file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--make", default="make")
    args = parser.parse_args()

    default_help = run(args.make)
    explicit_help = run(args.make, "help")
    require(default_help.returncode == 0, "plain make failed", default_help.stdout)
    require(explicit_help.returncode == 0, "make help failed", explicit_help.stdout)
    require(default_help.stdout == explicit_help.stdout, "plain make and make help differ")
    require("make list" in explicit_help.stdout, "help does not point to make list")
    require("make testunit" not in explicit_help.stdout, "help leaks detailed test commands")

    suite_list = run(args.make, "list")
    require(suite_list.returncode == 0, "make list failed", suite_list.stdout)
    require(suite_list.stdout != explicit_help.stdout, "make help still aliases make list")
    require("make test" in suite_list.stdout, "test index omits the full regression entry")
    require("make testunit list" in suite_list.stdout, "test index omits unit discovery")
    require("make testinfra list" in suite_list.stdout, "test index omits infra discovery")
    require("make sw tests list" in suite_list.stdout, "test index omits software discovery")
    require("make sw demo list" in suite_list.stdout, "test index omits demo discovery")

    unified_build = run(args.make, "-B", "-n", "sim-build")
    require(unified_build.returncode == 0, "unified sim-build dry-run failed", unified_build.stdout)
    require(
        "config.h" in unified_build.stdout and "headless_config.h" not in unified_build.stdout,
        "sim-build does not use the current unified configuration",
        unified_build.stdout,
    )

    for command in (
        ("testunit", "list"),
        ("testinfra", "list"),
        ("sw", "tests", "list"),
        ("sw", "riscv-tests", "list"),
        ("sw", "tests", "sdboff"),
        ("sw", "tests", "nvboardoff", "waveoff", "sdboff"),
        ("sw", "tests", "waveoff", "sdboff", "nvboardoff"),
        ("sw", "tests", "batch"),
        ("sw", "demo", "list"),
        ("sw", "demo", "build"),
        ("sw", "demo", "run"),
    ):
        dry_run = ("CLI_CHECK_ONLY=1", *command) if len(command) > 2 and command[2] != "list" else command
        result = run(args.make, *dry_run)
        require(result.returncode == 0, f"valid command failed: make {' '.join(command)}", result.stdout)

    invalid_commands = (
        ("testunit", "typo"),
        ("sw", "tests", "typo"),
        ("help", "list"),
        ("batch",),
        ("sdboff",),
        ("sw", "tests", "sdboff", "sdboff"),
        ("sw", "tests", "batch", "waveoff"),
        ("sw", "tests", "list", "nvboardoff"),
        ("sw", "demo", "typo"),
    )
    for command in invalid_commands:
        result = run(args.make, *command)
        require(result.returncode != 0, f"invalid command succeeded: make {' '.join(command)}")
        require(">>> 开始执行" not in result.stdout, "invalid command started a test suite", result.stdout)

    unknown_filter = run(args.make, "testunit", "ALL=does-not-exist")
    require(unknown_filter.returncode != 0, "unknown ALL filter succeeded")
    require(">>> 开始执行" not in unknown_filter.stdout, "unknown filter started tests", unknown_filter.stdout)

    unknown_demo = run(args.make, "sw", "demo", "build", "ALL=does-not-exist")
    require(unknown_demo.returncode != 0, "unknown demo filter succeeded")

    unavailable = run(args.make, "sw", "riscv-tests", "batch")
    require(unavailable.returncode != 0, "unavailable riscv-tests suite reported success")

    legacy_targets = (
        "lint", "lint-isa", "lint-comb", "lint-mem",
        "test-unit", "test-sw", "test-config", "test-isa", "test-alu",
        "test-decoder", "test-regfile", "test-core", "test-led", "test-uart",
        "test-periph-interconnect", "test-cdc", "test-interconnect", "test-soc",
        "test-disasm", "test-memory", "test-reference", "test-simulation",
        "test-difftest", "test-integration", "test-wave", "test-sdb",
        "test-difftest-spike",
        "sim", "nvboard-build", "nvboard-run",
    )
    for target in legacy_targets:
        result = run(args.make, "-n", target)
        require(result.returncode != 0, f"legacy target is still public: {target}", result.stdout)

    conflict = run(args.make, "-n", "testunit", "batch", "ALL=alu")
    require(conflict.returncode != 0, "batch and ALL conflict was accepted")

    sw_batch_filter = run(
        args.make, "CLI_CHECK_ONLY=1", "sw", "tests", "batch", "ALL=uart_hello"
    )
    require(sw_batch_filter.returncode == 0, "sw tests batch rejected ALL filter")

    for variable in ("BATCH=1", "WAVE=0", "DIFFTEST=0"):
        result = run(args.make, "-n", "sw", "tests", variable)
        require(result.returncode != 0, f"legacy variable was accepted: {variable}")
        require(">>> 开始执行" not in result.stdout, "legacy variable started tests", result.stdout)

    list_all = run(args.make, "-n", "sw", "tests", "list", "ALL=uart_hello")
    require(list_all.returncode != 0, "list and ALL conflict was accepted")

    print("make_cli_test: PASS")


if __name__ == "__main__":
    main()
