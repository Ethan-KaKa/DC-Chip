.section .text._start
.globl _start
_start:
    lui   x1, 0x20000
    jalr  x0, 0(x1)
