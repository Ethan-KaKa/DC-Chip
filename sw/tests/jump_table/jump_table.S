.section .text
.globl main
.type main, @function

main:
    # Initialize accumulator x11 = 0
    addi  x11, zero, 0

    # Load base address of jump table in DRAM
    lui   x12, %hi(jump_targets)
    addi  x12, x12, %lo(jump_targets)

step_0:
    # Jump to first step via jump table
    lw    t0, 0(x12)
    jalr  zero, 0(t0)

step_1:
    # Iteration 1: add 10
    addi  x11, x11, 10
    lw    t0, 4(x12)
    jalr  zero, 0(t0)

step_2:
    # Iteration 2: add 20
    addi  x11, x11, 20
    lw    t0, 8(x12)
    jalr  zero, 0(t0)

step_3:
    # Iteration 3: add 12 (sum = 42)
    addi  x11, x11, 12

    # Check sum == 42: compute x11 - 42, return in a0
    addi  a0, x11, -42
    jalr  zero, 0(ra)

.size main, . - main

.section .data
.align 2
jump_targets:
    .word step_1
    .word step_2
    .word step_3
