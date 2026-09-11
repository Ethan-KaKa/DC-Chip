.section .text._start, "ax"
.globl _start
.type _start, @function

_start:
    # 1. Initialize stack pointer sp (x2) to _stack_top in DRAM (0x20010000)
    lui   sp, %hi(_stack_top)
    addi  sp, sp, %lo(_stack_top)

    # 2. Clear frame pointer s0 (x8)
    addi  s0, zero, 0

    # 3. Call _trm_init via lui + addi + jalr
    lui   t0, %hi(_trm_init)
    addi  t0, t0, %lo(_trm_init)
    jalr  ra, 0(t0)

    # 4. If _trm_init returns, halt with exit code in a0 (or 0)
    lui   t0, %hi(halt)
    addi  t0, t0, %lo(halt)
    jalr  zero, 0(t0)

.size _start, . - _start

.section .text
.globl _trm_init
.type _trm_init, @function
_trm_init:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    sw    s0, 8(sp)

    # Call main(mainargs)
    lui   a0, %hi(mainargs)
    addi  a0, a0, %lo(mainargs)
    lui   t0, %hi(main)
    addi  t0, t0, %lo(main)
    jalr  ra, 0(t0)

    # Return value from main is in a0
    lw    s0, 8(sp)
    lw    ra, 12(sp)
    addi  sp, sp, 16

    # Call halt(a0)
    lui   t0, %hi(halt)
    addi  t0, t0, %lo(halt)
    jalr  zero, 0(t0)
.size _trm_init, . - _trm_init

.globl halt
.type halt, @function
halt:
    # Exit simulation via tohost (0xfffffff0): write exit code in a0
    sw    a0, -16(zero)
1:  jalr  zero, 0(ra)
.size halt, . - halt
