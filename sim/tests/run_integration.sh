#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <simulator>\n' "$0" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
simulator=$1
if [[ $simulator != /* ]]; then
  simulator="$repo_root/$simulator"
fi
if [[ ! -x $simulator ]]; then
  printf 'error: simulator is not executable: %s\n' "$simulator" >&2
  exit 1
fi

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

too_many_image="$fixture_dir/too_many.hex"
missing_image="$fixture_dir/does-not-exist.hex"
rm -f -- "$missing_image"
for ((address = 0; address < 257; ++address)); do
  printf '0000\n'
done >"$too_many_image"

expect_exit help 0 \
  "$simulator" --help

expect_exit isa_smoke 0 \
  "$simulator" --image "$script_dir/isa_smoke.hex" --steps 8 \
  --expect r0=0x0000 --expect r1=0x0002 --expect r2=0x0002 \
  --expect r3=0x0000 --expect pc=0x08

expect_exit jump_loop 0 \
  "$simulator" --image "$script_dir/jump_loop.hex" --steps 5 \
  --expect r0=0x0000 --expect r1=0x0003 --expect r2=0x0000 \
  --expect r3=0x0000 --expect pc=0x01

expect_exit illegal_reserved 2 \
  "$simulator" --image "$script_dir/illegal_reserved.hex" --steps 1

expect_exit illegal_noncanonical 2 \
  "$simulator" --image "$script_dir/illegal_noncanonical.hex" --steps 1

expect_exit out_of_bounds 2 \
  "$simulator" --image "$script_dir/isa_smoke.hex" --steps 9

expect_exit missing_image 1 \
  "$simulator" --image "$missing_image"

expect_exit empty_image 1 \
  "$simulator" --image "$script_dir/empty.hex"

expect_exit malformed_image 1 \
  "$simulator" --image "$script_dir/malformed.hex"

expect_exit too_wide_image 1 \
  "$simulator" --image "$script_dir/too_wide.hex"

expect_exit too_many_words 1 \
  "$simulator" --image "$too_many_image"

expect_exit timeout 3 \
  "$simulator" --image "$script_dir/jump_loop.hex" --steps 5 \
  --max-cycles 2

expect_exit state_mismatch 4 \
  "$simulator" --image "$script_dir/isa_smoke.hex" --steps 8 \
  --expect r1=0

expect_exit duplicate_expectation 1 \
  "$simulator" --image "$script_dir/isa_smoke.hex" \
  --expect r1=2 --expect r1=2

expect_exit unknown_argument 1 \
  "$simulator" --image "$script_dir/isa_smoke.hex" --unknown

expect_exit missing_argument_value 1 \
  "$simulator" --image "$script_dir/isa_smoke.hex" --steps

expect_exit missing_required_image 1 \
  "$simulator" --steps 1

printf 'run_integration: PASS (%s cases)\n' 17
