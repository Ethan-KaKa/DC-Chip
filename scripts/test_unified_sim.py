#!/usr/bin/env python3
"""Exercise the all-feature single Vsim_top build with runtime disables."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_SCRIPT = REPO_ROOT / "scripts" / "config.py"
IMAGE = REPO_ROOT / "sim" / "tests" / "isa_smoke.hex"


class TestFailure(Exception):
    pass


def require(condition: bool, message: str, result=None) -> None:
    if condition:
        return
    if result is not None:
        message += f"\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    raise TestFailure(message)


def run(command: list[str], *, input_text: str | None = None,
        environment: dict[str, str] | None = None):
    env = os.environ.copy()
    env["CCACHE_DISABLE"] = "1"
    if environment:
        env.update(environment)
    return subprocess.run(
        command, cwd=REPO_ROOT, env=env, input=input_text, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def run_tests(args: argparse.Namespace) -> None:
    root = Path(args.fixture_root).resolve()
    require(root.name == "unified-sim" and root.parent.name == "test-fixtures",
            "fixture root must end in test-fixtures/unified-sim")
    shutil.rmtree(root, ignore_errors=True)
    build_dir = root / "build"
    config = root / ".config"
    configured = run([
        args.python, str(CONFIG_SCRIPT), "--config", str(config),
        "--output-dir", str(build_dir / "config"), "set",
        "DC_SIM_SDB=y", "DC_SIM_WAVE=y", "DC_SIM_NVBOARD=y",
        "DC_SIM_DIFFTEST=y",
    ])
    require(configured.returncode == 0, "all-on configuration failed", configured)
    built = run([
        args.make, "--no-print-directory", f"BUILD_DIR={build_dir}",
        f"CONFIG_FILE={config}", "sim-build",
    ])
    require(built.returncode == 0, "all-on unified simulator build failed", built)

    simulator = build_dir / "verilator" / "Vsim_top"
    require(simulator.is_file(), "unified Vsim_top is missing")
    require(not (build_dir / "nvboard-sim").exists(),
            "legacy build/nvboard-sim was created")
    require((build_dir / "tools" / "nvboard" / "nvboard.a").is_file(),
            "NVBoard archive was not isolated under build/tools")

    wave = build_dir / "dump.vcd"
    all_on = run(
        [str(simulator), "--image", str(IMAGE)], input_text="c\n",
        environment={"SDL_VIDEODRIVER": "dummy"},
    )
    require(all_on.returncode == 0, "all-on interactive execution failed", all_on)
    require("(dc-sdb) stopped: program exit (code 0)" in all_on.stdout,
            "all-on execution did not enter SDB", all_on)
    require("difftest mismatch" not in all_on.stderr,
            "all-on SDB execution failed difftest", all_on)
    require(wave.is_file(), "all-on execution did not create a VCD")

    wave.unlink()
    sdb_off = run([
        str(simulator), "--image", str(IMAGE), "--sdb-off",
    ], environment={"SDL_VIDEODRIVER": "dummy"})
    require(sdb_off.returncode == 0, "SDB-off-only execution failed", sdb_off)
    require("(dc-sdb)" not in sdb_off.stdout and "summary commits=13" in sdb_off.stdout,
            "SDB-off-only did not select automatic execution", sdb_off)
    require(wave.is_file(), "SDB-off-only unexpectedly disabled WAVE")

    wave.unlink()
    nvboard_off_only = run([
        str(simulator), "--image", str(IMAGE), "--nvboard-off",
    ], input_text="c\n", environment={"SDL_VIDEODRIVER": "invalid-driver"})
    require(nvboard_off_only.returncode == 0,
            "NVBoard-off-only execution failed", nvboard_off_only)
    require("(dc-sdb) stopped: program exit" in nvboard_off_only.stdout,
            "NVBoard-off-only unexpectedly disabled SDB", nvboard_off_only)
    require(wave.is_file(), "NVBoard-off-only unexpectedly disabled WAVE")

    wave.unlink()
    wave_off_only = run([
        str(simulator), "--image", str(IMAGE), "--wave-off",
    ], input_text="c\n", environment={"SDL_VIDEODRIVER": "dummy"})
    require(wave_off_only.returncode == 0,
            "WAVE-off-only execution failed", wave_off_only)
    require("(dc-sdb) stopped: program exit" in wave_off_only.stdout,
            "WAVE-off-only unexpectedly disabled SDB", wave_off_only)
    require(not wave.exists(), "WAVE-off-only created a VCD")

    quit_dispatch = run([
        str(simulator), "--image", str(IMAGE), "--nvboard-off",
        "--wave-off", "--test-dispatch",
    ], input_text="q\n", environment={"SDL_VIDEODRIVER": "invalid-driver"})
    require(quit_dispatch.returncode == 6,
            "SDB q did not stop the software-test dispatcher", quit_dispatch)
    require("summary" not in quit_dispatch.stdout,
            "SDB q emitted an automatic PASS summary", quit_dispatch)

    batch = run([
        str(simulator), "--image", str(IMAGE), "--sdb-off",
        "--nvboard-off", "--wave-off",
    ], input_text="q\n", environment={"SDL_VIDEODRIVER": "invalid-driver"})
    require(batch.returncode == 0, "all runtime disables failed", batch)
    require("(dc-sdb)" not in batch.stdout and "summary commits=13" in batch.stdout,
            "SDB-off did not select automatic execution", batch)
    require(not wave.exists(), "WAVE-off created a VCD")
    require("difftest mismatch" not in batch.stderr,
            "runtime disables incorrectly disabled difftest", batch)

    print("test_unified_sim: PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-root", required=True)
    parser.add_argument("--make", default="make")
    parser.add_argument("--python", default="python3")
    args = parser.parse_args()
    try:
        run_tests(args)
    except (OSError, TestFailure) as error:
        print(f"test_unified_sim: FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
