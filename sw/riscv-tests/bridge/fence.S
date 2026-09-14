// Local completion of the DC-Chip RV32E fence coverage.  riscv-tests-am's
// rv32ui collection provides fence_i only, which is intentionally unsupported.
.section .text.init, "ax"
.globl main
.type main, @function
main:
  fence rw, rw
  addi a0, zero, 0
  j halt
.size main, . - main
