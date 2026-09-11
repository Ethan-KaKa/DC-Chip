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
    command = [
        *shlex.split(args.make),
        "--no-print-directory",
        f"BUILD_DIR={build_dir}",
        f"CONFIG_FILE={config_path}",
        f"VERILATOR={args.verilator}",
        f"IVERILOG={args.iverilog}",
        f"VVP={args.vvp}",
        f"CXX={args.cxx}",
        f"PYTHON={args.python}",
        *targets,
    ]
    expect_success(run(command), f"make {' '.join(targets)} in {build_dir}")


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


def verify_reset_trace(contents: str) -> None:
    identifiers = []
    for line in contents.splitlines():
        fields = line.split()
        if len(fields) >= 6 and fields[0] == "$var" and fields[4] == "rst":
            identifiers.append(fields[3])
    require(bool(identifiers), "VCD header does not expose reset")

    current_time = 0
    reset_changes: list[tuple[int, str]] = []
    for line in contents.splitlines():
        if line.startswith("#") and line[1:].isdigit():
            current_time = int(line[1:])
        elif line and line[0] in "01xz" and line[1:] in identifiers:
            reset_changes.append((current_time, line[0]))
    require((0, "1") in reset_changes, "VCD does not start with reset asserted")
    require(
        any(time >= 5 and value == "0" for time, value in reset_changes),
        "VCD does not show reset deassertion before normal execution",
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
    make_targets(args, off_build, off_config, "sim-build", "test-simulation")
    verify_trace_mode(off_build, False)
    verify_wave_interface(args, off_build, False)
    require(not list(off_build.rglob("*.vcd")), "WAVE-off build created a VCD")

    on_root = fixture_root / "on"
    on_build = on_root / "build"
    on_config = on_root / ".config"
    configure(on_config, on_build / "config", True)
    make_targets(args, on_build, on_config, "sim-build", "test-simulation")
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
