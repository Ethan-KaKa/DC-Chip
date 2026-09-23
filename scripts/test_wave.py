#!/usr/bin/env python3
"""Self-checking integration tests for build-time VCD waveform support."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_SCRIPT = REPO_ROOT / "scripts" / "config.py"
INTEGRATION_SCRIPT = REPO_ROOT / "sim" / "tests" / "run_integration.sh"
SMOKE_IMAGE = REPO_ROOT / "sim" / "tests" / "isa_smoke.hex"


class TestFailure(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise TestFailure(message)


def run(
    command: list[str],
    *,
    cwd: Path = REPO_ROOT,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["CCACHE_DISABLE"] = "1"
    if environment is not None:
        env.update(environment)
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def expect_success(result: subprocess.CompletedProcess[str], context: str) -> None:
    require(
        result.returncode == 0,
        f"{context}: exit {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
    )


def configure(config_path: Path, output_dir: Path, wave: bool) -> None:
    result = run(
        [
            sys.executable,
            str(CONFIG_SCRIPT),
            "--config",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "set",
            "DC_SIM_SDB=n",
            f"DC_SIM_WAVE={'y' if wave else 'n'}",
        ]
    )
    expect_success(result, f"configure WAVE={'y' if wave else 'n'}")


def make_targets(
    args: argparse.Namespace,
    build_dir: Path,
    config_path: Path,
    *targets: str,
) -> None:
    common = [
        *shlex.split(args.make),
        "--no-print-directory",
        f"BUILD_DIR={build_dir}",
        f"CONFIG_FILE={config_path}",
        f"VERILATOR={args.verilator}",
        f"IVERILOG={args.iverilog}",
        f"VVP={args.vvp}",
        f"CXX={args.cxx}",
        f"PYTHON={args.python}",
    ]
    for target in targets:
        expect_success(run([*common, target]), f"make {target} in {build_dir}")


def verify_trace_mode(build_dir: Path, enabled: bool) -> None:
    expected = "1" if enabled else "0"
    for relative in (
        Path("verilator/Vsim_top_classes.mk"),
        Path("verilator-test/Vsim_top_classes.mk"),
    ):
        contents = (build_dir / relative).read_text(encoding="utf-8")
        require(
            re.search(rf"^VM_TRACE = {expected}$", contents, re.MULTILINE)
            is not None,
            f"{relative} has the wrong VM_TRACE value",
        )
        require(
            re.search(rf"^VM_TRACE_VCD = {expected}$", contents, re.MULTILINE)
            is not None,
            f"{relative} has the wrong VM_TRACE_VCD value",
        )

    vcd_objects = [
        path
        for path in build_dir.rglob("*")
        if "verilated_vcd_c" in path.name
    ]
    require(
        bool(vcd_objects) == enabled,
        "VCD implementation artifacts do not match the configured trace mode",
    )


def verify_wave_interface(args: argparse.Namespace, build_dir: Path, enabled: bool) -> None:
    source = (
        '#include "simulation.h"\n'
        "bool probe(dc_sim::Simulation &simulation) {\n"
        "  return simulation.wave_enabled();\n"
        "}\n"
    )
    result = subprocess.run(
        [
            args.cxx,
            "-std=c++17",
            f"-I{REPO_ROOT / 'sim' / 'verilator'}",
            "-include",
            str(build_dir / "config" / "config.h"),
            "-x",
            "c++",
            "-fsyntax-only",
            "-",
        ],
        cwd=REPO_ROOT,
        env={**os.environ, "CCACHE_DISABLE": "1"},
        input=source,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        (result.returncode == 0) == enabled,
        "wave API compile-time visibility does not match CONFIG_DC_SIM_WAVE",
    )


def read_vcd(path: Path) -> tuple[str, set[int]]:
    require(path.is_file(), f"missing VCD file: {path}")
    contents = path.read_text(encoding="utf-8")
    for marker in ("$version", "$timescale", "$scope", "$enddefinitions $end"):
        require(marker in contents, f"VCD header is missing {marker}")
    timestamps = {
        int(match.group(1))
        for match in re.finditer(r"^#([0-9]+)$", contents, re.MULTILINE)
    }
    require(0 in timestamps, "VCD does not contain a time-zero dump")
    return contents, timestamps


def signal_changes(contents: str, signal_name: str) -> list[tuple[int, str]]:
    identifiers = set()
    for line in contents.splitlines():
        fields = line.split()
        if (
            len(fields) >= 6
            and fields[0] == "$var"
            and fields[4] == signal_name
        ):
            identifiers.add(fields[3])
    require(bool(identifiers), f"VCD header does not expose {signal_name}")

    current_time = 0
    changes: list[tuple[int, str]] = []
    for line in contents.splitlines():
        if line.startswith("#") and line[1:].isdigit():
            current_time = int(line[1:])
        elif line and line[0] in "01xz" and line[1:] in identifiers:
            changes.append((current_time, line[0]))
        elif line.startswith("b"):
            fields = line.split()
            if len(fields) == 2 and fields[1] in identifiers:
                changes.append((current_time, fields[0][1:]))
    return changes


def signal_value_at(
    contents: str, signal_name: str, timestamp: int
) -> str | None:
    value = None
    for change_time, change_value in signal_changes(contents, signal_name):
        if change_time > timestamp:
            break
        value = change_value
    return value


def binary_value_at(contents: str, signal_name: str, timestamp: int) -> int:
    value = signal_value_at(contents, signal_name, timestamp)
    require(value is not None, f"VCD has no value for {signal_name}")
    require(
        all(bit in "01" for bit in value),
        f"VCD {signal_name} is unknown at time {timestamp}",
    )
    return int(value, 2)


def verify_reset_trace(contents: str) -> None:
    reset_changes = signal_changes(contents, "rst")
    require((0, "1") in reset_changes, "VCD does not start with reset asserted")
    require(
        (4, "0") in reset_changes,
        "VCD does not record reset deassertion in the final reset low phase",
    )
    require(
        signal_value_at(contents, "clk", 4) == "0",
        "VCD reset deassertion is not recorded while the clock is low",
    )
    require(
        binary_value_at(contents, "pc_q", 4) == 0,
        "VCD advances the PC before the first post-reset execution edge",
    )
    require(
        signal_value_at(contents, "trace_valid", 4) == "0",
        "VCD reports a commit during reset release",
    )
    require(
        signal_value_at(contents, "clk", 5) == "1"
        and signal_value_at(contents, "trace_valid", 5) == "1"
        and binary_value_at(contents, "trace_pc", 5) == 0
        and binary_value_at(contents, "pc_q", 5) == 4,
        "VCD does not show the PC=0 commit on the first execution edge",
    )


def run_cli(
    simulator: Path, cwd: Path, *arguments: str
) -> subprocess.CompletedProcess[str]:
    return run([str(simulator), *arguments], cwd=cwd)


def verify_pre_model_failures(simulator: Path, cwd: Path, wave_path: Path) -> None:
    cases = (
        ("help", 0, ("--help",)),
        ("argument error", 1, ("--unknown",)),
        (
            "HEX load error",
            1,
            ("--image", str(cwd / "missing-image.hex")),
        ),
    )
    for context, expected_exit, arguments in cases:
        wave_path.unlink(missing_ok=True)
        result = run_cli(simulator, cwd, *arguments)
        require(
            result.returncode == expected_exit,
            f"{context} returned {result.returncode}, expected {expected_exit}",
        )
        require(not wave_path.exists(), f"{context} created a VCD before model creation")


def run_tests(args: argparse.Namespace) -> None:
    fixture_root = Path(args.fixture_root).resolve()
    require(
        fixture_root.name == "wave" and fixture_root.parent.name == "test-fixtures",
        "fixture root must end in test-fixtures/wave",
    )
    shutil.rmtree(fixture_root, ignore_errors=True)

    off_root = fixture_root / "off"
    off_build = off_root / "build"
    off_config = off_root / ".config"
    configure(off_config, off_build / "config", False)
    make_targets(args, off_build, off_config, "sim-build", "_test-infra-simulation")
    verify_trace_mode(off_build, False)
    verify_wave_interface(args, off_build, False)
    require(not list(off_build.rglob("*.vcd")), "WAVE-off build created a VCD")

    on_root = fixture_root / "on"
    on_build = on_root / "build"
    on_config = on_root / ".config"
    configure(on_config, on_build / "config", True)
    make_targets(args, on_build, on_config, "sim-build", "_test-infra-simulation")
    verify_trace_mode(on_build, True)
    verify_wave_interface(args, on_build, True)

    wave_path = on_build / "dump.vcd"
    paused_contents, paused_timestamps = read_vcd(wave_path)
    verify_reset_trace(paused_contents)
    require(
        set(range(0, 7)).issubset(paused_timestamps),
        "VCD is missing reset or first execution half-cycle timestamps",
    )
    require(
        {11, 12}.issubset(paused_timestamps),
        "VCD is missing timestamps after wave recording resumed",
    )
    require(
        not set(range(7, 11)).intersection(paused_timestamps),
        "VCD contains timestamps while wave recording was paused",
    )

    simulator = on_build / "verilator" / "Vsim_top"
    launch_dir = on_root / "launch-cwd"
    launch_dir.mkdir(parents=True)

    wave_path.unlink(missing_ok=True)
    disabled = run_cli(
        simulator,
        launch_dir,
        "--image",
        str(SMOKE_IMAGE),
        "--steps",
        "1",
        "--wave-off",
    )
    expect_success(disabled, "runtime WAVE-off execution")
    require(not wave_path.exists(), "--wave-off created a VCD")

    wave_path.write_text("sentinel content that must be truncated\n", encoding="utf-8")
    one_step = run_cli(
        simulator,
        launch_dir,
        "--image",
        str(SMOKE_IMAGE),
        "--steps",
        "1",
    )
    expect_success(one_step, "WAVE-on simulator launched from another directory")
    expected_one_step_summary = (
        "summary commits=1 cycles=1 pc=0x00000004 "
        "x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 "
        "x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 "
        "x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 "
        "x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\n"
    )
    require(
        one_step.stdout == expected_one_step_summary,
        "WAVE-on changed batch output",
    )
    cli_contents, cli_timestamps = read_vcd(wave_path)
    verify_reset_trace(cli_contents)
    require("sentinel content" not in cli_contents, "VCD was not truncated")
    require(
        set(range(0, 7)).issubset(cli_timestamps),
        "one-step VCD does not contain both phases of reset and execution",
    )
    require(
        sorted(fixture_root.rglob("*.vcd")) == [wave_path],
        "simulator created a VCD outside the configured build root",
    )

    verify_pre_model_failures(simulator, launch_dir, wave_path)

    integration_dir = on_root / "integration"
    integration = run(
        ["bash", str(INTEGRATION_SCRIPT), str(simulator)],
        cwd=launch_dir,
        environment={"TEST_FIXTURE_DIR": str(integration_dir)},
    )
    expect_success(integration, "32-case WAVE-on CLI integration regression")
    require(
        "run_integration: PASS (32 cases)" in integration.stdout,
        "WAVE-on integration regression did not report all 32 cases",
    )

    wave_path.unlink(missing_ok=True)
    wave_path.mkdir()
    open_failure = run_cli(
        simulator,
        launch_dir,
        "--image",
        str(SMOKE_IMAGE),
        "--steps",
        "1",
    )
    require(open_failure.returncode == 1, "unopenable VCD target did not return 1")
    expected_diagnostic = f"error: failed to open VCD waveform: {wave_path}"
    require(
        expected_diagnostic in open_failure.stderr,
        "unopenable VCD target diagnostic omitted the full target path",
    )
    shutil.rmtree(wave_path)

    print("test_wave: PASS")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-root", required=True)
    parser.add_argument("--make", default="make")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--cxx", default="c++")
    parser.add_argument("--python", default="python3")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    try:
        run_tests(parse_args(argv))
    except (OSError, TestFailure) as error:
        print(f"test_wave: FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
