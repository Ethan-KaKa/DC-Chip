#!/usr/bin/env python3
"""
run_sw_tests.py

Automated test runner for DC-Chip AM software test suite.
Executes compiled software images on the Verilator simulator (Vsim_top)
and checks guest exit codes and architectural state.
"""

import argparse
import os
import re
import subprocess
import sys

TEST_CASES = [
    {
        "name": "trm_smoke",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {},
    },
    {
        "name": "trm_exit_code",
        "expected_sim_exit": 5,  # Simulator exits with 5 on non-zero guest exit
        "expected_guest_exit": 17,
        "expect_regs": {"x10": 17},
    },
    {
        "name": "calc_add",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "dram_access",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "heap_smoke",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "jump_table",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0, "x11": 42},
    },
    {
        "name": "cpu_dummy",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_add",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_sub_longlong",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_bit",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_bubble_sort",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_select_sort",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_fib",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_recursion",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_string",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_leap_year",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_if_else",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "cpu_load_store",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "led_marquee",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
    {
        "name": "uart_hello",
        "expected_sim_exit": 0,
        "expected_guest_exit": 0,
        "expect_regs": {"x10": 0},
    },
]

def parse_summary_line(line):
    regs = {}
    tokens = line.strip().split()
    for token in tokens:
        if "=" in token:
            k, v = token.split("=", 1)
            if k in ("commits", "cycles"):
                try:
                    regs[k] = int(v)
                except ValueError:
                    pass
            elif k.startswith("x"):
                try:
                    regs[k] = int(v, 16)
                except ValueError:
                    pass
    return regs

def run_test(simulator, test_dir, case, runtime_args, interactive):
    name = case["name"]
    inst_bin = os.path.join(test_dir, name, f"{name}.inst.bin")
    data_bin = os.path.join(test_dir, name, f"{name}.data.bin")

    if not os.path.isfile(inst_bin):
        return False, f"missing instruction image: {inst_bin}"

    cmd = [simulator, "--image-inst", inst_bin, "--test-dispatch", *runtime_args]
    if os.path.isfile(data_bin) and os.path.getsize(data_bin) > 0:
        cmd += ["--image-data", data_bin]

    if interactive:
        returncode = subprocess.run(cmd).returncode
        if returncode == 6:
            return None, "user quit"
        if returncode != case["expected_sim_exit"]:
            return False, (
                f"expected simulator exit {case['expected_sim_exit']}, got {returncode}"
            )
        return True, "interactive"

    res = subprocess.run(cmd, capture_output=True, text=True)

    if res.returncode != case["expected_sim_exit"]:
        return False, (
            f"expected simulator exit {case['expected_sim_exit']}, got {res.returncode}\n"
            f"stdout:\n{res.stdout}\nstderr:\n{res.stderr}"
        )

    # Check guest exit code from stderr if expected non-zero
    if case["expected_guest_exit"] != 0:
        match = re.search(r"guest exit code:\s*(\d+)", res.stderr)
        if not match:
            return False, f"expected guest exit code {case['expected_guest_exit']}, but none found in stderr:\n{res.stderr}"
        actual_code = int(match.group(1))
        if actual_code != case["expected_guest_exit"]:
            return False, f"expected guest exit code {case['expected_guest_exit']}, got {actual_code}"

    # Parse registers from summary
    regs = {}
    for line in res.stdout.splitlines():
        if line.startswith("summary"):
            regs = parse_summary_line(line)
            break

    for reg_name, exp_val in case["expect_regs"].items():
        if reg_name not in regs:
            return False, f"register {reg_name} not found in summary output: {res.stdout}"
        if regs[reg_name] != exp_val:
            return False, f"register {reg_name} expected {exp_val:#x} ({exp_val}), got {regs[reg_name]:#x} ({regs[reg_name]})"

    return True, f"commits={regs.get('commits', '?')} cycles={regs.get('cycles', '?')}"

def main():
    parser = argparse.ArgumentParser(description="Run DC-Chip AM software test suite")
    parser.add_argument("--simulator", default="build/verilator/Vsim_top", help="Path to Vsim_top binary")
    parser.add_argument("--test-dir", default="build/sw/tests", help="Path to built tests directory")
    parser.add_argument("--sdb-off", action="store_true")
    parser.add_argument("--nvboard-off", action="store_true")
    parser.add_argument("--wave-off", action="store_true")
    parser.add_argument("--interactive", action="store_true")
    parser.add_argument("tests", nargs="*", help="Optional specific tests to run")
    args = parser.parse_args()

    simulator = os.path.abspath(args.simulator)
    test_dir = os.path.abspath(args.test_dir)

    if not os.path.isfile(simulator) or not os.access(simulator, os.X_OK):
        print(f"error: simulator binary not found or not executable: {simulator}", file=sys.stderr)
        sys.exit(1)

    cases = TEST_CASES
    if args.tests:
        cases = [c for c in TEST_CASES if c["name"] in args.tests]

    all_passed = True
    runtime_args = [
        f"--{name}-off"
        for name, enabled in (
            ("sdb", args.sdb_off),
            ("nvboard", args.nvboard_off),
            ("wave", args.wave_off),
        )
        if enabled
    ]
    for case in cases:
        name = case["name"]
        ok, msg = run_test(simulator, test_dir, case, runtime_args, args.interactive)
        if ok is None:
            print(f"sw_test: STOP {name} ({msg})")
            sys.exit(6)
        if ok:
            print(f"sw_test: PASS {name} (guest exit {case['expected_guest_exit']}) [{msg}]")
        else:
            all_passed = False
            print(f"sw_test: FAIL {name}:\n  {msg}", file=sys.stderr)

    if not all_passed:
        sys.exit(1)
    print(f"sw_test: ALL PASSED ({len(cases)} test(s))")

if __name__ == "__main__":
    main()
