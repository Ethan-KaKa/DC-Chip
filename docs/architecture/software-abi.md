# DC-Chip 软件 ABI 与运行时规范

- 版本：v1.0 (阶段 4)
- 状态：已正式冻结
- 日期：2026-09-11
- ISA 规范：`docs/isa/isa.md` v1.0
- 地址规范：`docs/architecture/memory-map.md` v0.2

---

## 1. 概述

本文档定义 DC-Chip 面向 RV32E 基础整数指令集（37 条标准指令，包括分支、跳转、算术逻辑、移位、半字及字节访存）的裸机软件应用二进制接口（ABI）、存储段布局、启动与终止协议，以及基于 Abstract Machine（AM）的 Turing Machine（TRM）运行时契约。

---

## 2. 寄存器分配与调用约定

本项目遵循 RISC-V 官方 RV32E 基础整数寄存器定义，仅支持 16 个通用寄存器（`x0`--`x15`），不支持任何特权 CSR 或 `x16`--`x31`。

| 寄存器 | ABI 名称 | 角色 / 用途 | 保存者规则 |
| --- | --- | --- | --- |
| `x0` | `zero` | 常数 0（硬件硬连线为 0） | 不适用 |
| `x1` | `ra` | 返回地址（Return Address） | Caller-saved |
| `x2` | `sp` | 栈指针（Stack Pointer，向下增长） | Callee-saved |
| `x3` | `gp` | 全局指针（Global Pointer） | Unallocatable |
| `x4` | `tp` | 线程指针（Thread Pointer） | Unallocatable |
| `x5` | `t0` | 临时寄存器 0 / 间接跳转中转 | Caller-saved |
| `x6` | `t1` | 临时寄存器 1 | Caller-saved |
| `x7` | `t2` | 临时寄存器 2 | Caller-saved |
| `x8` | `s0` / `fp` | 被保存寄存器 0 / 帧指针 | Callee-saved |
| `x9` | `s1` | 被保存寄存器 1 | Callee-saved |
| `x10` | `a0` | 函数第 1 参数 / 第 1 返回值 | Caller-saved |
| `x11` | `a1` | 函数第 2 参数 / 第 2 返回值 | Caller-saved |
| `x12` | `a2` | 函数第 3 参数 | Caller-saved |
| `x13` | `a3` | 函数第 4 参数 | Caller-saved |
| `x14` | `a4` | 函数第 5 参数 | Caller-saved |
| `x15` | `a5` | 函数第 6 参数 | Caller-saved |

编译器与汇编器参数必须统一指定 `-march=rv32e -mabi=ilp32e`。

---

## 3. Harvard 存储布局与链接段契约

配合硬件与仿真环境确立的 Harvard 访问隔离契约：
- **IROM**：基址 `0x0000_0000`，容量 64 KiB，仅供取指单元（IFU）读取与执行；
- **DRAM**：基址 `0x2000_0000`，容量 64 KiB，仅供数据访存单元（LSU）读写；
- **`tohost`**：私有写入端口 `0xffff_fff0`，仅供仿真器终止通知。

### 3.1 内存段分布表

```text
[IROM: 0x0000_0000 .. 0x0000_ffff] (64 KiB)
+-------------------------------------------------------+ 0x0000_ffff
|  .text (KEEP(*(.text._start)), KEEP(*(.text.entry))) |
+-------------------------------------------------------+ 0x0000_0000 (Reset PC)

[DRAM: 0x2000_0000 .. 0x2000_ffff] (64 KiB)
+-------------------------------------------------------+ 0x2001_0000
|  Stack (向下增长, _stack_top = 0x2001_0000, 4 KiB)    |
+-------------------------------------------------------+ 0x2000_f000 (_stack_bottom / _heap_end)
|  Heap (向上增长, Area heap = RANGE(_heap_start, end)) |
+-------------------------------------------------------+ _heap_start (16-byte aligned)
|  .bss (NOLOAD, zero-initialized)                      |
+-------------------------------------------------------+ _sbss
|  .data (initialized read-write globals)               |
+-------------------------------------------------------+ _sdata
|  .rodata (read-only constants)                        |
+-------------------------------------------------------+ 0x2000_0000 (_srodata)
```

### 3.2 链接器保护规则
1. 链接脚本丢弃 `.note.gnu.build-id`、`.comment` 与 `.eh_frame*`，保证 `_start` 严格定位于物理首地址 `0x0000_0000`；
2. 栈指针 `sp` 初始值固定为 `0x2001_0000`（DRAM 顶部）；
3. 栈与堆之间保留安全隔离区间，防范栈溢出破坏全局数据区。

---

## 4. 软件启动与 TRM 运行时契约

### 4.1 启动序列
1. 核心复位释放后，PC 处于 `0x0000_0000`；
2. 执行 `sw/am/src/start.S` 中的 `_start`：
   - 加载栈顶：`lui sp, %hi(_stack_top); addi sp, sp, %lo(_stack_top)`；
   - 清零帧指针：`addi s0, zero, 0`；
   - 转移至运行时初始化：`lui t0, %hi(_trm_init); addi t0, t0, %lo(_trm_init); jalr ra, 0(t0)`；
3. `_trm_init` 准备参数并调用 `main(const char *args)`；
4. `main` 返回后，返回值传递至 `halt(int code)`。

### 4.2 仿真终止契约 (`halt`)
程序通过向私有地址 `0xffff_fff0`（`tohost`）发起 32 位 `sw` 写入退出码：
- 写入值 `0`：表示程序自检成功（guest exit 0），仿真器以 exit code 0 退出；
- 写入非零值 `N`：表示程序自检失败（guest exit N），仿真器以 exit code 5 退出并打印退出码。

---

## 5. 镜像提取与交付格式

每一个在 AM 框架下编译的应用均生成四个产物：

| 产物扩展名 | 作用 | 提取方式 |
| --- | --- | --- |
| `.elf` | 包含符号与段信息的 ELF 可执行文件 | `riscv64-linux-gnu-gcc` 直接链接 |
| `.txt` | 反汇编文本转储，用于调试与指令集审计 | `riscv64-linux-gnu-objdump -d <app>.elf > <app>.txt` |
| `.inst.bin` | IROM 原始二进制镜像（仅提取 `.text`） | `objcopy -S -O binary -j .text <app>.elf <app>.inst.bin` |
| `.data.bin` | DRAM 原始二进制镜像（提取 `.rodata` 与 `.data`） | `objcopy -S -O binary -j .rodata* -j .data* -j .sdata* <app>.elf <app>.data.bin` |

---

## 6. RV32E 指令集硬性审计要求

阶段 4 起，任何软件镜像的汇编或编译输出必须通过 `scripts/check_isa_subset.py` 审计：

1. **允许的指令**：
   - 官方 RV32E 37 条标准基础整数指令：`lui, auipc, jal, jalr, beq, bne, blt, bge, bltu, bgeu, lb, lh, lw, lbu, lhu, sb, sh, sw, addi, slti, sltiu, xori, ori, andi, slli, srli, srai, add, sub, sll, slt, sltu, xor, srl, sra, or, and, fence`；
   - 常见安全别名：`nop, mv, not, neg, seqz, snez, sltz, sgtz, j, jr, ret, call` 等；
2. **严禁的指令**：
   - 严禁出现未实现扩展：乘除法 M（`mul*, div*, rem*`）、压缩指令 C、浮点 F/D、特权级 CSR（`csrr*`）等；
   - 严禁出现寄存器 `x16`--`x31`。
