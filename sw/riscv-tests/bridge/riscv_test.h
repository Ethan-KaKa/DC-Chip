// DC-Chip RV32E physical single-core bridge for riscv-tests-am sources.
// It deliberately shadows vendor env/p/riscv_test.h through the first
// include directory, preserving the vendor scalar test bodies unchanged.
#ifndef DC_CHIP_RISCV_TEST_H
#define DC_CHIP_RISCV_TEST_H

#define RVTEST_RV64U .macro init; .endm
#define RVTEST_RV32U .macro init; .endm

#define RVTEST_CODE_BEGIN \
  .section .text.init; \
  .align 2; \
  .globl main; \
main:

// halt is supplied by sw/am/src/start.S and writes a0 to DC-Chip tohost.
#define RVTEST_PASS li a0, 0; j halt
#define TESTNUM x10
#define RVTEST_FAIL j halt

// The vendor uses an illegal unimp marker after an unconditional terminal
// jump.  Keep dead code RV32E-auditable instead.
#define RVTEST_CODE_END j halt

#define RVTEST_DATA_BEGIN .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:
#define EXTRA_DATA

#endif
