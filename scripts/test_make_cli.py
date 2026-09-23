#!/usr/bin/env python3
"""Self-check the public Make command contract without running regressions."""

import argparse
import os
import subprocess
import sys


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NVBOARD_FIXTURE_ROOT = os.path.join(REPO_ROOT, "build", "test-fixtures", "make-cli-nvboard")
NVBOARD_FIXTURE_BUILD_DIR = os.path.join(NVBOARD_FIXTURE_ROOT, "build")
NVBOARD_FIXTURE_CONFIG = os.path.join(NVBOARD_FIXTURE_ROOT, ".config")
NVBOARD_INVALID_ROOT = os.path.join(REPO_ROOT, "build", "test-fixtures", "make-cli-nvboard-invalid")
NVBOARD_COMPAT_PATCH = os.path.join(REPO_ROOT, "tools", "nvboard-dc-compat.patch")


def run(make_command, *args, env=None):
    command = [make_command, "--no-print-directory", "ALL=", *args]
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )


def run_nvboard_dry_run(make_command, *args, env=None):
    return run(
        make_command,
        f"BUILD_DIR={NVBOARD_FIXTURE_BUILD_DIR}",
        f"CONFIG_FILE={NVBOARD_FIXTURE_CONFIG}",
        "CONFIG_DC_SIM_NVBOARD=y",
        "-B",
        "-n",
        "sim-build",
        *args,
        env=env,
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
    require("make sw riscv-tests list" in suite_list.stdout, "test index omits riscv-tests discovery")
    require("make sw demo list" in suite_list.stdout, "test index omits demo discovery")

    unified_build = run(args.make, "-B", "-n", "sim-build")
    require(unified_build.returncode == 0, "unified sim-build dry-run failed", unified_build.stdout)
    require(
        "config.h" in unified_build.stdout and "headless_config.h" not in unified_build.stdout,
        "sim-build does not use the current unified configuration",
        unified_build.stdout,
    )

    with open(NVBOARD_COMPAT_PATCH, encoding="utf-8") as patch_file:
        nvboard_patch = patch_file.read()
    with open(os.path.join(REPO_ROOT, "rtl", "soc", "soc_periph_subsystem.sv"), encoding="utf-8") as rtl_file:
        soc_top = rtl_file.read()
    require(
        "divisor(432)" in nvboard_patch and ".BAUD_DIV(432)" in soc_top,
        "NVBoard UART sampling divisor no longer matches the SoC BAUD_DIV",
    )
    require(
        not any(
            line.startswith("+") and "getenv(\"NVBOARD_HOME\")" in line
            for line in nvboard_patch.splitlines()
        )
        and "DC_NVBOARD_HOME" in nvboard_patch,
        "NVBoard compatibility patch still reads generic NVBOARD_HOME",
    )

    legacy_nvboard_home = run_nvboard_dry_run(
        args.make, "NVBOARD_HOME=legacy-nvboard"
    )
    require(
        legacy_nvboard_home.returncode == 0,
        "sim-build dry-run with legacy NVBOARD_HOME failed",
        legacy_nvboard_home.stdout,
    )

    legacy_nvboard_env = os.environ.copy()
    legacy_nvboard_env["NVBOARD_HOME"] = "legacy-nvboard-from-env"
    legacy_nvboard_env_output = run_nvboard_dry_run(args.make, env=legacy_nvboard_env)
    require(
        legacy_nvboard_env_output.returncode == 0,
        "sim-build dry-run inherited NVBOARD_HOME from the environment",
        legacy_nvboard_env_output.stdout,
    )
    require(
        "legacy-nvboard-from-env" not in legacy_nvboard_env_output.stdout,
        "environment NVBOARD_HOME overrides the pinned submodule",
        legacy_nvboard_env_output.stdout,
    )
    require(
        "legacy-nvboard" not in legacy_nvboard_home.stdout
        and "tools/nvboard/usr/include" in legacy_nvboard_home.stdout,
        "legacy NVBOARD_HOME overrides the pinned submodule",
        legacy_nvboard_home.stdout,
    )

    explicit_nvboard_home = run_nvboard_dry_run(
        args.make, "DC_NVBOARD_HOME=explicit-nvboard"
    )
    require(
        explicit_nvboard_home.returncode == 0,
        "sim-build dry-run with DC_NVBOARD_HOME failed",
        explicit_nvboard_home.stdout,
    )
    require(
        "explicit-nvboard/usr/include" in explicit_nvboard_home.stdout,
        "DC_NVBOARD_HOME does not override the NVBoard source path",
        explicit_nvboard_home.stdout,
    )
    require(
        "nvboard-dc-compat.patch" in legacy_nvboard_home.stdout
        and "dc-nvboard-uart-432-v3" in legacy_nvboard_home.stdout
        and "-DDC_NVBOARD_HOME" in legacy_nvboard_home.stdout,
        "NVBoard compatibility patch or build stamp is absent from sim-build",
        explicit_nvboard_home.stdout,
    )

    incompatible_nvboard_home = run(
        args.make,
        f"BUILD_DIR={os.path.join(NVBOARD_INVALID_ROOT, 'build')}",
        f"CONFIG_FILE={os.path.join(NVBOARD_INVALID_ROOT, '.config')}",
        "CONFIG_DC_SIM_NVBOARD=y",
        "DC_NVBOARD_HOME=not-a-compatible-nvboard",
        "sim-build",
    )
    require(
        incompatible_nvboard_home.returncode != 0
        and "not a compatible NVBoard source tree" in incompatible_nvboard_home.stdout,
        "incompatible DC_NVBOARD_HOME does not fail with a clear diagnostic",
        incompatible_nvboard_home.stdout,
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

    riscv_batch = run(args.make, "CLI_CHECK_ONLY=1", "sw", "riscv-tests", "batch")
    require(riscv_batch.returncode == 0, "riscv-tests batch syntax/dry-run failed", riscv_batch.stdout)

    unknown_riscv = run(args.make, "-n", "sw", "riscv-tests", "ALL=does-not-exist")
    require(unknown_riscv.returncode != 0, "unknown riscv-tests ALL filter succeeded")

    legacy_targets = (
        "lint", "lint-isa", "lint-comb", "lint-mem",
        "test-unit", "test-sw", "test-config", "test-isa", "test-alu",
        "test-decoder", "test-execute", "test-lsu", "test-regfile", "test-core",
        "test-led", "test-uart",
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
