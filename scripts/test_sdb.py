#!/usr/bin/env python3
"""Self-checking integration tests for the configurable simulator debugger."""

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
TEST_IMAGES = REPO_ROOT / "sim" / "tests"


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
        input=input_text,
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


def expect_exact(
    result: subprocess.CompletedProcess[str],
    context: str,
    *,
    returncode: int,
    stdout: str,
    stderr: str = "",
) -> None:
    require(result.returncode == returncode, f"{context}: wrong exit code")
    require(
        result.stdout == stdout,
        f"{context}: stdout mismatch\nexpected:\n{stdout!r}\nactual:\n{result.stdout!r}",
    )
    require(
        result.stderr == stderr,
        f"{context}: stderr mismatch\nexpected:\n{stderr!r}\nactual:\n{result.stderr!r}",
    )


def configure(
    config_path: Path, output_dir: Path, sdb: bool, wave: bool,
    difftest: bool = False,
) -> None:
    result = run(
        [
            sys.executable,
            str(CONFIG_SCRIPT),
            "--config",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "set",
            f"DC_SIM_SDB={'y' if sdb else 'n'}",
            f"DC_SIM_WAVE={'y' if wave else 'n'}",
            "DC_SIM_NVBOARD=n",
            f"DC_SIM_DIFFTEST={'y' if difftest else 'n'}",
        ]
    )
    expect_success(result, f"configure SDB={sdb}, WAVE={wave}")


def make_command(
    args: argparse.Namespace,
    build_dir: Path,
    config_path: Path,
    *targets: str,
    variables: tuple[str, ...] = (),
) -> list[str]:
    return [
        *shlex.split(args.make),
        "--no-print-directory",
        f"BUILD_DIR={build_dir}",
        f"CONFIG_FILE={config_path}",
        f"VERILATOR={args.verilator}",
        f"IVERILOG={args.iverilog}",
        f"VVP={args.vvp}",
        f"CXX={args.cxx}",
        f"PYTHON={args.python}",
        *variables,
        *targets,
    ]


def make_targets(
    args: argparse.Namespace,
    build_dir: Path,
    config_path: Path,
    *targets: str,
) -> None:
    result = run(make_command(args, build_dir, config_path, *targets))
    expect_success(result, f"make {' '.join(targets)} in {build_dir}")


def cli(
    simulator: Path,
    image: str,
    *,
    commands: str = "",
    arguments: tuple[str, ...] = (),
    cwd: Path = REPO_ROOT,
) -> subprocess.CompletedProcess[str]:
    return run(
        [str(simulator), "--image", str(TEST_IMAGES / image), *arguments],
        cwd=cwd,
        input_text=commands,
    )


def state(
    pc: str,
    inst: str,
    assembly: str,
    registers: tuple[str, ...],
    cycles: int,
    commits: int,
    time: int,
) -> str:
    register_text = " ".join(f"x{index}={value}" for index, value in enumerate(registers))
    return (
        f'state pc={pc} inst={inst} asm="{assembly}" {register_text} '
        f"cycles={cycles} commits={commits} time={time}\n"
    )


def verify_sdb_off(
    args: argparse.Namespace, root: Path
) -> tuple[Path, Path, Path]:
    build_dir = root / "build"
    config_path = root / ".config"
    configure(config_path, build_dir / "config", False, False)
    make_targets(args, build_dir, config_path, "sim-build")
    simulator = build_dir / "verilator" / "Vsim_top"

    generated_make = (build_dir / "verilator" / "Vsim_top.mk").read_text(
        encoding="utf-8"
    )
    for object_name in ("sdb.o", "disasm.o"):
        require(
            object_name not in generated_make,
            f"SDB-off generated makefile links {object_name}",
        )
        require(
            not (build_dir / "verilator" / object_name).exists(),
            f"SDB-off build created {object_name}",
        )
    base_arguments = ("--steps", "1")
    default = cli(
        simulator,
        "isa_smoke.hex",
        commands="q\n",
        arguments=base_arguments,
    )
    explicit = cli(
        simulator,
        "isa_smoke.hex",
        commands="q\n",
        arguments=(*base_arguments, "--sdb-off"),
    )
    expect_success(default, "SDB-off default batch")
    expect_success(explicit, "SDB-off explicit runtime disable")
    require(default.stdout == explicit.stdout, "--sdb-off changed SDB-off stdout")
    require(default.stderr == explicit.stderr, "--sdb-off changed SDB-off stderr")
    expected_summary = (
        "summary commits=1 cycles=1 pc=0x00000004 "
        "x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 "
        "x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 "
        "x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 "
        "x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\n"
    )
    require(
        default.stdout == expected_summary,
        "SDB-off batch output changed",
    )
    return build_dir, config_path, simulator


def verify_help_and_quit(simulator: Path) -> None:
    help_lines = (
        "help                 Show this help\n"
        "q                    Quit the debugger\n"
        "c                    Continue execution\n"
        "si [N]               Step N committed instructions (default 1)\n"
        "sc [N]               Step N cycles (default 1)\n"
        "b <pc>               Set an execution-before breakpoint\n"
        "d <id>               Delete a breakpoint\n"
        "info r               Show registers and current instruction\n"
        "info b               Show breakpoints\n"
    )
    result = cli(simulator, "jump_loop.hex", commands="help\nq\n")
    expect_exact(
        result,
        "SDB help and q",
        returncode=0,
        stdout=f"(dc-sdb) {help_lines}(dc-sdb) ",
    )
    eof = cli(simulator, "jump_loop.hex")
    expect_exact(eof, "SDB EOF", returncode=0, stdout="(dc-sdb) ")


def verify_state_and_steps(simulator: Path) -> None:
    reset_state = state(
        "0x00000000",
        "0x00100093",
        "addi x1, x0, 1",
        ("0x00000000",) * 16,
        0,
        0,
        4,
    )
    after_one = state(
        "0x00000004",
        "0x00108093",
        "addi x1, x1, 1",
        ("0x00000000", "0x00000001") + ("0x00000000",) * 14,
        1,
        1,
        6,
    )
    after_three = state(
        "0x0000000c",
        "0x00010067",
        "jalr x0, 0(x2)",
        ("0x00000000", "0x00000002", "0x00000004") + ("0x00000000",) * 13,
        3,
        3,
        10,
    )
    after_five = state(
        "0x00000008",
        "0x00400113",
        "addi x2, x0, 4",
        ("0x00000000", "0x00000003", "0x00000004") + ("0x00000000",) * 13,
        5,
        5,
        14,
    )
    result = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--max-cycles", "10"),
        commands="info r\nsi\nsc 2\nsi 2\nq\n",
    )
    expected = (
        f"(dc-sdb) {reset_state}"
        "(dc-sdb) stopped: commits complete\n"
        'commit pc=0x00000000 inst=0x00100093 asm="addi x1, x0, 1"\n'
        f"{after_one}"
        "(dc-sdb) stopped: cycles complete\n"
        'commit pc=0x00000008 inst=0x00400113 asm="addi x2, x0, 4"\n'
        f"{after_three}"
        "(dc-sdb) stopped: commits complete\n"
        'commit pc=0x00000004 inst=0x00108093 asm="addi x1, x1, 1"\n'
        f"{after_five}"
        "(dc-sdb) "
    )
    expect_exact(result, "SDB state and step commands", returncode=0, stdout=expected)


def verify_breakpoints(simulator: Path) -> None:
    result = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--max-cycles", "10"),
        commands=(
            "info b\nb 4\nb 0X04\nb 8\nd 1\nb 4\ninfo b\nd 99\n"
            "c\nsc\nc\nc\nq\n"
        ),
    )
    require(result.returncode == 0, "breakpoint scenario failed")
    expected_fragments = (
        "(dc-sdb) no breakpoints\n",
        "breakpoint id=1 set at pc=0x00000004\n",
        "breakpoint id=1 already set at pc=0x00000004\n",
        "breakpoint id=2 set at pc=0x00000008\n",
        "breakpoint id=1 deleted\n",
        "breakpoint id=3 set at pc=0x00000004\n",
        "breakpoint id=2 pc=0x00000008\nbreakpoint id=3 pc=0x00000004\n",
        "stopped: breakpoint id=3\n",
        "stopped: cycles complete\n",
        "stopped: breakpoint id=2\n",
        "stopped: breakpoint id=3\n",
    )
    for fragment in expected_fragments:
        require(fragment in result.stdout, f"missing breakpoint output {fragment!r}")
    require(
        result.stdout.count("stopped: breakpoint id=3\n") == 2,
        "self-loop breakpoint was not hit again after its instruction committed",
    )
    require(
        result.stderr == "error: breakpoint id=99 not found\n",
        "missing-breakpoint diagnostic changed",
    )


def verify_command_errors(simulator: Path) -> None:
    commands = (
        "unknown arg\nhelp extra\nq extra\nc extra\nsi 1 2\nsc 1 2\n"
        "b\nb 1 2\nd\nd 1 2\ninfo\ninfo r extra\ninfo x\ninfo wave\n"
        "wave off\nsi 0\nsi -1\nsi 18446744073709551616\nsi 0x\n"
        "d 0\nd -1\nd 18446744073709551616\n"
        "b -1\nb 0x\nb 0xgg\nb 1\nb 4294967296\ninfo b\nq\n"
    )
    result = cli(simulator, "jump_loop.hex", commands=commands)
    require(result.returncode == 0, "command-error scenario did not reach q")
    expected_errors = (
        "error: unknown command 'unknown'\n"
        "error: usage: help\n"
        "error: usage: q\n"
        "error: usage: c\n"
        "error: usage: si [N]\n"
        "error: usage: sc [N]\n"
        "error: usage: b <pc>\n"
        "error: usage: b <pc>\n"
        "error: usage: d <id>\n"
        "error: usage: d <id>\n"
        "error: usage: info r|b\n"
        "error: usage: info r|b\n"
        "error: unknown info target 'x'\n"
        "error: unknown info target 'wave'\n"
        "error: unknown command 'wave'\n"
        "error: invalid positive step count '0'\n"
        "error: invalid positive step count '-1'\n"
        "error: invalid positive step count '18446744073709551616'\n"
        "error: invalid positive step count '0x'\n"
        "error: invalid positive breakpoint id '0'\n"
        "error: invalid positive breakpoint id '-1'\n"
        "error: invalid positive breakpoint id '18446744073709551616'\n"
        "error: invalid pc '-1'\n"
        "error: invalid pc '0x'\n"
        "error: invalid pc '0xgg'\n"
        "error: pc '1' is not 4-byte aligned\n"
        "error: pc '4294967296' is outside 0..0xffffffff\n"
    )
    require(result.stderr == expected_errors, "SDB command diagnostics changed")
    require("no breakpoints\n" in result.stdout, "failed commands partially set a breakpoint")


def verify_terminal_stops(simulator: Path) -> None:
    illegal = cli(simulator, "illegal_reserved.hex", commands="c\n")
    illegal_state = state(
        "0x00000000",
        "0x80000000",
        ".word 0x80000000",
        ("0x00000000",) * 16,
        1,
        0,
        6,
    )
    expect_exact(
        illegal,
        "SDB illegal stop",
        returncode=2,
        stdout=f"(dc-sdb) stopped: illegal instruction\n{illegal_state}",
        stderr="error: illegal instruction at pc=0x00000000 inst=0x80000000\n",
    )

    guest_fail = cli(simulator, "guest_fail.hex", commands="c\n")
    require(guest_fail.returncode == 5, "SDB guest fail exit code changed")
    require(
        "(dc-sdb) stopped: program exit (code 42)\n" in guest_fail.stdout,
        "SDB guest fail stop text changed",
    )
    require(
        guest_fail.stderr == "error: guest exit code: 42\n",
        "SDB guest fail diagnostic changed",
    )

    timeout = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--max-cycles", "2"),
        commands="c\n",
    )
    require(timeout.returncode == 3, "SDB timeout exit code changed")
    require("(dc-sdb) stopped: timeout\n" in timeout.stdout, "missing timeout stop")
    require(
        timeout.stderr == "error: timeout after 2 cycles and 2 commits\n",
        "SDB timeout diagnostic changed",
    )


def verify_cli_modes(
    args: argparse.Namespace,
    build_dir: Path,
    config_path: Path,
    simulator: Path,
) -> None:
    integration = run(
        ["bash", str(INTEGRATION_SCRIPT), str(simulator)],
        environment={"TEST_FIXTURE_DIR": str(build_dir / "integration")},
    )
    expect_success(integration, "SDB-on 32-case batch integration")
    require(
        "run_integration: PASS (32 cases)" in integration.stdout,
        "SDB-on batch integration omitted cases",
    )
    batch_with_stdin = cli(
        simulator,
        "isa_smoke.hex",
        commands="q\n",
        arguments=("--steps", "1", "--sdb-off", "--nvboard-off"),
    )
    expected_step1_summary = (
        "summary commits=1 cycles=1 pc=0x00000004 "
        "x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 "
        "x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 "
        "x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 "
        "x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\n"
    )
    require(
        batch_with_stdin.stdout == expected_step1_summary,
        "SDB-on --sdb-off read debugger commands from stdin",
    )

    conflicts = (
        (
            ("--expect", "x1=0", "--trace", "--steps", "1"),
            "error: option --steps requires --sdb-off when SDB is enabled\n",
        ),
        (("--trace",), "error: option --trace requires --sdb-off when SDB is enabled\n"),
        (
            ("--expect", "x1=0"),
            "error: option --expect requires --sdb-off when SDB is enabled\n",
        ),
    )
    for arguments, expected_error in conflicts:
        result = cli(simulator, "isa_smoke.hex", arguments=arguments)
        expect_exact(
            result,
            f"interactive conflict {arguments}",
            returncode=1,
            stdout="",
            stderr=expected_error,
        )

    duplicate_disable = cli(
        simulator,
        "isa_smoke.hex",
        arguments=("--sdb-off", "--sdb-off"),
    )
    require(duplicate_disable.returncode == 1, "duplicate --sdb-off was accepted")
    require(
        duplicate_disable.stderr.startswith("error: duplicate option --sdb-off\n"),
        "duplicate --sdb-off diagnostic changed",
    )


def verify_sdb_only(
    args: argparse.Namespace, root: Path
) -> tuple[Path, Path, Path]:
    build_dir = root / "build"
    config_path = root / ".config"
    configure(config_path, build_dir / "config", True, False, difftest=True)
    make_targets(args, build_dir, config_path, "sim-build")
    simulator = build_dir / "verilator" / "Vsim_top"
    for object_name in ("sdb.o", "disasm.o"):
        require(
            (build_dir / "verilator" / object_name).is_file(),
            f"SDB-on omitted {object_name}",
        )
    generated_make = (build_dir / "verilator" / "Vsim_top.mk").read_text(encoding="utf-8")
    require("difftest.o" in generated_make, "SDB test did not compile the difftest monitor")
    verify_help_and_quit(simulator)
    verify_state_and_steps(simulator)
    verify_breakpoints(simulator)
    verify_command_errors(simulator)
    verify_terminal_stops(simulator)
    verify_cli_modes(args, build_dir, config_path, simulator)
    return build_dir, config_path, simulator


def vcd_timestamps(path: Path) -> set[int]:
    contents = path.read_text(encoding="utf-8")
    return {
        int(match.group(1))
        for match in re.finditer(r"^#([0-9]+)$", contents, re.MULTILINE)
    }


def verify_sdb_wave(args: argparse.Namespace, root: Path) -> None:
    build_dir = root / "build"
    config_path = root / ".config"
    configure(config_path, build_dir / "config", True, True)
    make_targets(args, build_dir, config_path, "sim-build")
    simulator = build_dir / "verilator" / "Vsim_top"
    wave_path = build_dir / "dump.vcd"
    pre_model_cases = (
        (0, [str(simulator), "--help"]),
        (
            1,
            [
                str(simulator),
                "--image",
                str(TEST_IMAGES / "isa_smoke.hex"),
                "--steps",
                "1",
            ],
        ),
        (1, [str(simulator), "--image", str(root / "missing.hex")]),
    )
    for expected_exit, command in pre_model_cases:
        wave_path.unlink(missing_ok=True)
        failure = run(command, cwd=root)
        require(
            failure.returncode == expected_exit,
            f"pre-model case returned {failure.returncode}, expected {expected_exit}",
        )
        require(not wave_path.exists(), "pre-model SDB+WAVE failure created a VCD")

    delayed = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--wave-off", "--max-cycles", "10"),
        commands="info wave\nsc\nwave on\nsc\nq\n",
        cwd=root,
    )
    expect_success(delayed, "SDB delayed wave enable")
    require(wave_path.is_file(), "SDB wave on did not lazily create the VCD")
    require(
        f"wave=off path={wave_path.resolve()} time=4\n" in delayed.stdout,
        "--wave-off did not reach SDB with recording disabled",
    )
    wave_path.unlink()

    commands = (
        "info wave\nwave off\nwave off\nwave invalid\ninfo wave\nsc 2\ninfo wave\n"
        "wave on\nwave on\nsc\ninfo wave\nq\n"
    )
    result = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--max-cycles", "10"),
        commands=commands,
        cwd=root,
    )
    expect_success(result, "SDB+WAVE command sequence")
    require(
        result.stderr == "error: usage: wave on|off\n",
        "invalid wave command diagnostic changed",
    )
    absolute_wave = str(wave_path.resolve())
    required_lines = (
        f"wave=on path={absolute_wave} time=4\n",
        f"wave=off path={absolute_wave} time=4\n",
        f"wave=off path={absolute_wave} time=8\n",
        f"wave=on path={absolute_wave} time=8\n",
        f"wave=on path={absolute_wave} time=10\n",
    )
    for line in required_lines:
        require(line in result.stdout, f"missing waveform status {line!r}")
    require(
        result.stdout.count(f"wave=off path={absolute_wave} time=4\n") == 3,
        "repeated or invalid wave off changed state",
    )
    require(
        result.stdout.count(f"wave=on path={absolute_wave} time=8\n") == 2,
        "repeated wave on was not idempotent",
    )
    toggled_state = [line for line in result.stdout.splitlines() if "state pc=" in line][-1]

    reference = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--max-cycles", "10"),
        commands="sc 3\nq\n",
        cwd=root,
    )
    expect_success(reference, "SDB+WAVE reference execution")
    reference_state = [line for line in reference.stdout.splitlines() if "state pc=" in line][-1]
    require(toggled_state == reference_state, "wave toggles changed architectural state")

    toggled = cli(
        simulator,
        "jump_loop.hex",
        arguments=("--max-cycles", "10"),
        commands=commands,
        cwd=root,
    )
    expect_success(toggled, "SDB+WAVE retained-file execution")
    timestamps = vcd_timestamps(wave_path)
    require({0, 1, 2, 3, 4, 9, 10}.issubset(timestamps), "VCD timestamps missing")
    require(
        not {5, 6, 7, 8}.intersection(timestamps),
        "VCD contains timestamps while SDB paused recording",
    )
    require(
        list(build_dir.rglob("*.vcd")) == [wave_path],
        "SDB waveform commands created a second VCD",
    )

    help_result = cli(simulator, "jump_loop.hex", commands="help\nq\n", cwd=root)
    expect_success(help_result, "SDB+WAVE help")
    for command in ("info wave", "wave on", "wave off"):
        require(command in help_result.stdout, f"SDB+WAVE help omitted {command}")


def run_tests(args: argparse.Namespace) -> None:
    fixture_root = Path(args.fixture_root).resolve()
    require(
        fixture_root.name == "sdb" and fixture_root.parent.name == "test-fixtures",
        "fixture root must end in test-fixtures/sdb",
    )
    shutil.rmtree(fixture_root, ignore_errors=True)
    verify_sdb_off(args, fixture_root / "off")
    verify_sdb_only(args, fixture_root / "on")
    verify_sdb_wave(args, fixture_root / "wave")
    print("test_sdb: PASS")


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
        print(f"test_sdb: FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
