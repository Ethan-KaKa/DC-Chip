.section .text._start
.globl _start
_start:
    # Set up DRAM base pointer: x1 = 0x20000000
    lui   x1, 0x20000

    # Load 32-bit test constant from DRAM[0]: expected 100 (0x64)
    lw    x2, 0(x1)

    # Compute: x3 = x2 + 42 = 142 (0x8e)
    addi  x3, x2, 42

    # Store result into DRAM[4]
    sw    x3, 4(x1)

    # Load byte from DRAM[8]: expected 0x55
    lbu   x4, 8(x1)

    # Store byte into DRAM[9]
    sb    x4, 9(x1)

    # Verify byte read back: x5 = 0x55
    lbu   x5, 9(x1)

    # Compute final sum: x6 = x3 + x5 = 142 + 85 = 227 (0xe3)
    add   x6, x3, x5

    # Exit simulation via tohost: write 0 to 0xfffffff0
    addi  x8, x0, -16
    sw    x0, 0(x8)

.section .data
.word 100
.word 0
.byte 0x55
.byte 0xaa
.byte 0x00
.byte 0x00
