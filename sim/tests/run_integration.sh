#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && ${2:-} != --batch ) ]]; then
  printf 'usage: %s <simulator> [--batch]\n' "$0" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
simulator=$1
inject_batch=${2:-}
if [[ $simulator != /* ]]; then
  simulator="$repo_root/$simulator"
fi
if [[ ! -x $simulator ]]; then
  printf 'error: simulator is not executable: %s\n' "$simulator" >&2
  exit 1
fi

run_simulator() {
  if [[ ${1:-} == --help || -z $inject_batch ]]; then
    "$simulator" "$@"
  else
    "$simulator" --batch "$@"
  fi
}

fixture_dir=${TEST_FIXTURE_DIR:-"$repo_root/build/test-fixtures"}
mkdir -p -- "$fixture_dir"

expect_exit() {
  local name=$1
  local expected=$2
  shift 2

  local log="$fixture_dir/$name.log"
  local actual
  if "$@" >"$log" 2>&1; then
    actual=0
  else
    actual=$?
  fi

  if [[ $actual -ne $expected ]]; then
    printf 'integration: FAIL %s expected exit %s, got %s\n' \
      "$name" "$expected" "$actual" >&2
    sed -n '1,160p' "$log" >&2
    exit 1
  fi
  printf 'integration: PASS %s (exit %s)\n' "$name" "$actual"
}

expect_output() {
  local name=$1
  local expected=$2
  local log="$fixture_dir/$name.log"
  local expected_log="$fixture_dir/$name.expected.log"

  printf '%s\n' "$expected" >"$expected_log"
  if ! cmp -s -- "$expected_log" "$log"; then
    printf 'integration: FAIL %s output mismatch\n' "$name" >&2
    printf '%s\n' 'expected:' >&2
    sed -n '1,160p' "$expected_log" >&2
    printf '%s\n' 'actual:' >&2
    sed -n '1,160p' "$log" >&2
    exit 1
  fi
  printf 'integration: PASS %s output\n' "$name"
}

riscv_gcc=${RISCV_GCC:-riscv64-linux-gnu-gcc}
riscv_objcopy=${RISCV_OBJCOPY:-riscv64-linux-gnu-objcopy}

"$riscv_gcc" -march=rv32e -mabi=ilp32e -nostdlib -Wl,-T,"$script_dir/link.ld" \
  "$script_dir/bin_smoke.S" -o "$fixture_dir/bin_smoke.elf"
"$riscv_objcopy" -S -O binary -j .text "$fixture_dir/bin_smoke.elf" "$fixture_dir/bin_smoke.inst.bin"
"$riscv_objcopy" -S -O binary -j .data "$fixture_dir/bin_smoke.elf" "$fixture_dir/bin_smoke.data.bin"

"$riscv_gcc" -march=rv32e -mabi=ilp32e -nostdlib -Wl,-T,"$script_dir/link.ld" \
  "$script_dir/cross_fetch.S" -o "$fixture_dir/cross_fetch.elf"
"$riscv_objcopy" -S -O binary -j .text "$fixture_dir/cross_fetch.elf" "$fixture_dir/cross_fetch.inst.bin"

"$riscv_gcc" -march=rv32e -mabi=ilp32e -nostdlib -Wl,-T,"$script_dir/link.ld" \
  "$script_dir/cross_load.S" -o "$fixture_dir/cross_load.elf"
"$riscv_objcopy" -S -O binary -j .text "$fixture_dir/cross_load.elf" "$fixture_dir/cross_load.inst.bin"

"$riscv_gcc" -march=rv32e -mabi=ilp32e -nostdlib -Wl,-T,"$script_dir/link.ld" \
  "$script_dir/cross_store.S" -o "$fixture_dir/cross_store.elf"
"$riscv_objcopy" -S -O binary -j .text "$fixture_dir/cross_store.elf" "$fixture_dir/cross_store.inst.bin"

python3 -c 'import sys; sys.stdout.buffer.write(b"\x00" * 65537)' > "$fixture_dir/bin_too_large.bin"

too_many_image="$fixture_dir/too_many.hex"
missing_image="$fixture_dir/does-not-exist.hex"
rm -f -- "$missing_image"
python3 -c 'print("00000000\n" * 16385, end="")' >"$too_many_image"

expect_exit help 0 \
  run_simulator --help

expect_exit isa_smoke 0 \
  run_simulator --image "$script_dir/isa_smoke.hex" \
  --expect x1=0x00000002 --expect x8=0x00000005 --expect pc=0x00000034
expect_output isa_smoke \
  'summary commits=13 cycles=23 pc=0x00000034 x0=0x00000000 x1=0x00000002 x2=0x00000002 x3=0x00000004 x4=0x20000000 x5=0x00000004 x6=0x00000001 x7=0x00000001 x8=0x00000005 x9=0xfffffff0 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000'

expect_exit jump_loop 0 \
  run_simulator --image "$script_dir/jump_loop.hex" --steps 5 \
  --expect x1=0x00000003 --expect pc=0x00000008

expect_exit single_step_trace 0 \
  run_simulator --image "$script_dir/isa_smoke.hex" --steps 1 --trace
expect_output single_step_trace \
  $'cycle=1 commit=1 pc=0x00000000 inst=0x00200093 x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\nsummary commits=1 cycles=1 pc=0x00000004 x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000'

expect_exit jump_loop_trace 0 \
  run_simulator --image "$script_dir/jump_loop.hex" --steps 5 --trace
expect_output jump_loop_trace \
  $'cycle=1 commit=1 pc=0x00000000 inst=0x00100093 x0=0x00000000 x1=0x00000001 x2=0x00000000 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\ncycle=2 commit=2 pc=0x00000004 inst=0x00108093 x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\ncycle=3 commit=3 pc=0x00000008 inst=0x00400113 x0=0x00000000 x1=0x00000002 x2=0x00000004 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\ncycle=4 commit=4 pc=0x0000000c inst=0x00010067 x0=0x00000000 x1=0x00000002 x2=0x00000004 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\ncycle=5 commit=5 pc=0x00000004 inst=0x00108093 x0=0x00000000 x1=0x00000003 x2=0x00000004 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\nsummary commits=5 cycles=5 pc=0x00000008 x0=0x00000000 x1=0x00000003 x2=0x00000004 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000'

expect_exit illegal_reserved 2 \
  run_simulator --image "$script_dir/illegal_reserved.hex" --steps 1
expect_output illegal_reserved \
  'error: illegal instruction at pc=0x00000000 inst=0x80000000'

expect_exit illegal_noncanonical 2 \
  run_simulator --image "$script_dir/illegal_noncanonical.hex" --steps 1
expect_output illegal_noncanonical \
  'error: illegal instruction at pc=0x00000000 inst=0x00100813'

expect_exit fault_load_misalign 2 \
  run_simulator --image "$script_dir/fault_load_misalign.hex"
expect_output fault_load_misalign \
  'error: load address misaligned at pc=0x00000004 inst=0x0010a103'

expect_exit fault_store_misalign 2 \
  run_simulator --image "$script_dir/fault_store_misalign.hex"
expect_output fault_store_misalign \
  'error: store address misaligned at pc=0x00000004 inst=0x0000a123'

expect_exit fault_jalr_misalign 2 \
  run_simulator --image "$script_dir/fault_jalr_misalign.hex"
expect_output fault_jalr_misalign \
  'error: instruction address misaligned at pc=0x00000004 inst=0x00008067'

expect_exit guest_fail 5 \
  run_simulator --image "$script_dir/guest_fail.hex"
expect_output guest_fail \
  $'summary commits=4 cycles=6 pc=0x00000010 x0=0x00000000 x1=0xfffffff0 x2=0x0000002a x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\nerror: guest exit code: 42'

expect_exit missing_image 1 \
  run_simulator --image "$missing_image"

expect_exit empty_image 1 \
  run_simulator --image "$script_dir/empty.hex"

expect_exit malformed_image 1 \
  run_simulator --image "$script_dir/malformed.hex"

expect_exit too_wide_image 1 \
  run_simulator --image "$script_dir/too_wide.hex"

expect_exit too_many_words 1 \
  run_simulator --image "$too_many_image"

expect_exit timeout 3 \
  run_simulator --image "$script_dir/jump_loop.hex" --steps 5 \
  --max-cycles 2
expect_output timeout \
  'error: timeout after 2 cycles and 2 commits'

expect_exit state_mismatch 4 \
  run_simulator --image "$script_dir/isa_smoke.hex" --steps 1 \
  --expect x1=0
expect_output state_mismatch \
  $'summary commits=1 cycles=1 pc=0x00000004 x0=0x00000000 x1=0x00000002 x2=0x00000000 x3=0x00000000 x4=0x00000000 x5=0x00000000 x6=0x00000000 x7=0x00000000 x8=0x00000000 x9=0x00000000 x10=0x00000000 x11=0x00000000 x12=0x00000000 x13=0x00000000 x14=0x00000000 x15=0x00000000\nerror: x1 expected 0x00000000 but got 0x00000002'

expect_exit duplicate_expectation 1 \
  run_simulator --image "$script_dir/isa_smoke.hex" \
  --expect x1=2 --expect x1=2

expect_exit unknown_argument 1 \
  run_simulator --image "$script_dir/isa_smoke.hex" --unknown

expect_exit missing_argument_value 1 \
  run_simulator --image "$script_dir/isa_smoke.hex" --steps

expect_exit missing_required_image 1 \
  run_simulator --steps 1

expect_exit bin_smoke_dual 0 \
  run_simulator --image-inst "$fixture_dir/bin_smoke.inst.bin" \
  --image-data "$fixture_dir/bin_smoke.data.bin" \
  --expect x2=100 --expect x3=142 --expect x5=85 --expect x6=227

expect_exit bin_smoke_single 0 \
  run_simulator --image "$fixture_dir/bin_smoke.inst.bin" \
  --expect x2=0 --expect x3=42

expect_exit bin_cross_fetch_fault 2 \
  run_simulator --image "$fixture_dir/cross_fetch.inst.bin"
expect_output bin_cross_fetch_fault \
  'error: instruction access fault at pc=0x20000000'

expect_exit bin_cross_load_fault 2 \
  run_simulator --image "$fixture_dir/cross_load.inst.bin"
expect_output bin_cross_load_fault \
  'error: load access fault at pc=0x00000004 inst=0x0000a103'

expect_exit bin_cross_store_fault 2 \
  run_simulator --image "$fixture_dir/cross_store.inst.bin"
expect_output bin_cross_store_fault \
  'error: store access fault at pc=0x00000004 inst=0x0010a023'

expect_exit bin_missing_data_image 1 \
  run_simulator --image "$fixture_dir/bin_smoke.inst.bin" \
  --image-data "$fixture_dir/does_not_exist.bin"

expect_exit bin_too_large 1 \
  run_simulator --image "$fixture_dir/bin_too_large.bin"

expect_exit bin_format_explicit 0 \
  run_simulator --format bin --image "$fixture_dir/bin_smoke.inst.bin" \
  --image-data "$fixture_dir/bin_smoke.data.bin" \
  --expect x2=100

expect_exit bin_format_invalid 1 \
  run_simulator --format bogus --image "$fixture_dir/bin_smoke.inst.bin"

expect_exit conflicting_images 1 \
  run_simulator --image "$fixture_dir/bin_smoke.inst.bin" \
  --image-inst "$fixture_dir/bin_smoke.inst.bin"

printf 'run_integration: PASS (%s cases)\n' 32
