#!/usr/bin/env python3
"""Run AM-built riscv-tests-am images with DC-Chip's normal verdict path."""
import argparse
import os
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--test-dir", required=True)
    parser.add_argument("--max-cycles", type=int, required=True)
    parser.add_argument("--sdb-off", action="store_true")
    parser.add_argument("--nvboard-off", action="store_true")
    parser.add_argument("--wave-off", action="store_true")
    parser.add_argument("tests", nargs="+")
    args = parser.parse_args()
    simulator = os.path.abspath(args.simulator)
    if not os.path.isfile(simulator) or not os.access(simulator, os.X_OK):
        parser.error(f"simulator binary not found or not executable: {simulator}")
    runtime = ["--test-dispatch", "--max-cycles", str(args.max_cycles)]
    runtime.extend(f"--{name}-off" for name, enabled in (
        ("sdb", args.sdb_off), ("nvboard", args.nvboard_off),
        ("wave", args.wave_off)) if enabled)
    passed = 0
    for name in args.tests:
        root = os.path.join(os.path.abspath(args.test_dir), name)
        inst = os.path.join(root, f"{name}.inst.bin")
        data = os.path.join(root, f"{name}.data.bin")
        if not os.path.isfile(inst):
            print(f"riscv_test: FAIL {name}: missing instruction image: {inst}", file=sys.stderr)
            return 1
        cmd = [simulator, "--image-inst", inst]
        if os.path.isfile(data) and os.path.getsize(data):
            cmd += ["--image-data", data]
        result = subprocess.run([*cmd, *runtime], capture_output=True, text=True)
        if result.returncode:
            print(f"riscv_test: FAIL {name}: simulator exit {result.returncode}", file=sys.stderr)
            if result.stdout:
                print(result.stdout, file=sys.stderr, end="")
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            return result.returncode
        print(f"riscv_test: PASS {name}")
        passed += 1
    print(f"riscv_test: ALL PASSED ({passed}/{len(args.tests)})")


if __name__ == "__main__":
    main()
