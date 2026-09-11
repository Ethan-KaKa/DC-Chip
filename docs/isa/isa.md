# DC-Chip RV32E 过渡子集指令集手册

- 版本：v0.2
- 状态：阶段 1 规范基线；ISA 公共层与核心 RTL 已迁移，仿真器尚未迁移
- 更新日期：2026-09-11

## 1. 范围与兼容性

本文档是 DC-Chip 指令编码和体系结构语义的唯一规范源。v0.2 采用标准
RISC-V 32 位指令编码和 RV32E 的 16 个整数寄存器模型，但只实现
`add`、`addi`、`lui`、`lw`、`lbu`、`sw`、`sb`、`jalr` 八条指令。

因此，本 ISA 的准确名称是 **RV32E 过渡子集 v0.2**，不是完整 RV32E，不能
宣称能够运行普通 RV32E/RV32I ELF 或由通用 GCC 工具链任意生成的程序。除本
文精确列出的编码外，其他标准、保留或自定义编码在本项目中一律是非法指令。

截至本文日期，ISA package、decoder、32 位反汇编器、测试编码器、ALU、
regfile 和 CPU 核心已按本文迁移，并由 `make test-isa`、`make lint` 和
`make test-unit` 验证。Verilator wrapper/loader、Simulation、SDB 和程序测试
仍待步骤 2.4--2.5 迁移，因此尚无 v0.2 端到端执行闭环；旧 ISA 不提供长期
双模式开关，只由 Git 历史和迁移前验证记录保留。

本文中的“必须”表示后续实现与测试必须遵守；`TODO` 表示尚未决定，不得自行
补全为架构行为。

## 2. 体系结构状态

| 项目 | v0.2 定义 |
| --- | --- |
| `XLEN` | 32 bit |
| 指令宽度 | 32 bit，定长 |
| 指令对齐 | `IALIGN=32`，取指地址必须四字节对齐 |
| 通用寄存器 | `x0`--`x15`，每个 32 bit |
| PC | 32 bit、byte-addressed |
| 复位 PC | 默认 `0x00000000`；允许后续平台参数覆盖，但必须四字节对齐 |
| 复位寄存器值 | `x1`--`x15` 为 `0x00000000`；`x0` 恒为零 |
| 字节序 | 小端 |
| 特权级、CSR | 无 |

`x0` 的读值始终为零，对 `x0` 的写入被忽略。写 `x0` 的指令仍须完成其他
规定行为；例如 `lw x0, 0(x1)` 仍会发起访问并报告对齐或访问故障。

PC 和有效地址加法均保留结果低 32 位，即按模 `2^32` 回绕。正常顺序提交后
`pc <- pc + 4`。指令和多字节数据按小端顺序存放：最低地址对应最低有效字节。

## 3. 指令格式与立即数

v0.2 使用标准 RISC-V R、I、S、U 格式：

```text
R: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
I: imm[11:0]     rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
S: imm[11:5]     rs2[24:20] rs1[19:15] funct3[14:12] imm[4:0] opcode[6:0]
U: imm[31:12]                                        rd[11:7] opcode[6:0]
```

立即数构造如下：

```text
I-immediate = sext32(inst[31:20])
S-immediate = sext32({inst[31:25], inst[11:7]})
U-immediate = {inst[31:12], 12'b0}
```

I/S 立即数范围为 `-2048`--`2047`。汇编语法中的 `lui` 立即数写作 20 位字段，
执行值为该字段左移 12 位后的 32 位位模式。

## 4. 编码总表

| 指令 | 格式 | `opcode` | `funct3` | `funct7` | 规范语法 |
| --- | --- | --- | --- | --- | --- |
| `add` | R | `0110011` | `000` | `0000000` | `add rd, rs1, rs2` |
| `addi` | I | `0010011` | `000` | -- | `addi rd, rs1, imm12` |
| `lui` | U | `0110111` | -- | -- | `lui rd, imm20` |
| `lw` | I | `0000011` | `010` | -- | `lw rd, imm12(rs1)` |
| `lbu` | I | `0000011` | `100` | -- | `lbu rd, imm12(rs1)` |
| `sw` | S | `0100011` | `010` | -- | `sw rs2, imm12(rs1)` |
| `sb` | S | `0100011` | `000` | -- | `sb rs2, imm12(rs1)` |
| `jalr` | I | `1100111` | `000` | -- | `jalr rd, imm12(rs1)` |

表中 `--` 表示该位置属于立即数或其他已列字段，不是可忽略的功能码。编码必须
同时匹配对应格式、`opcode`、`funct3` 以及适用的 `funct7`。这八类编码没有
实现可随意忽略的未使用位；每一位都属于表中格式定义的字段。

## 5. 寄存器字段合法性

RV32E 只提供 `x0`--`x15`。指令实际使用的每个寄存器字段若编码为
`x16`--`x31`，该指令非法：

| 指令 | 必须检查的寄存器字段 |
| --- | --- |
| `add` | `rd`、`rs1`、`rs2` |
| `addi`、`lw`、`lbu`、`jalr` | `rd`、`rs1` |
| `sw`、`sb` | `rs1`、`rs2` |
| `lui` | `rd` |

只检查实际操作数字段。特别是 `lui` 的 `inst[31:12]` 全部属于立即数；即使
`inst[19:15]` 的位模式大于 15，也不得把它误判成 `rs1`。

## 6. 指令语义

以下伪代码中，`X[n]` 表示寄存器当前值，`M8[A]` 表示地址 `A` 的一个字节，
`M32[A]` 表示从四字节对齐地址 `A` 开始的小端 32 位值。`old_pc` 和所有源
寄存器都在本条指令写回前读取。

### 6.1 `add`

```text
encoding: 0000000 rs2 rs1 000 rd 0110011
effect:   X[rd] <- (X[rs1] + X[rs2]) mod 2^32
```

不产生算术溢出故障。示例：`add x3, x1, x2` 编码为 `0x002081b3`。

### 6.2 `addi`

```text
encoding: imm[11:0] rs1 000 rd 0010011
effect:   X[rd] <- (X[rs1] + sext32(imm12)) mod 2^32
```

不产生算术溢出故障。示例：`addi x3, x1, -1` 编码为 `0xfff08193`。

### 6.3 `lui`

```text
encoding: imm[31:12] rd 0110111
effect:   X[rd] <- {imm[31:12], 12'b0}
```

示例：`lui x3, 0x12345` 编码为 `0x123451b7`，结果为 `0x12345000`。

### 6.4 `lw`

```text
address:  A <- (X[rs1] + sext32(imm12)) mod 2^32
effect:   X[rd] <- M32[A]
```

`A` 必须四字节对齐，否则产生 `load address misaligned`。访问未映射、无读权限
或由存储系统返回错误时产生 `load access fault`。成功响应前不得写回或提交。
示例：`lw x3, 4(x1)` 编码为 `0x0040a183`。

### 6.5 `lbu`

```text
address:  A <- (X[rs1] + sext32(imm12)) mod 2^32
effect:   X[rd] <- zero_extend32(M8[A])
```

`lbu` 允许任意字节地址。访问失败产生 `load access fault`。示例：
`lbu x3, 1(x1)` 编码为 `0x0010c183`。

### 6.6 `sw`

```text
address:  A <- (X[rs1] + sext32(imm12)) mod 2^32
effect:   M32[A] <- X[rs2]
```

`A` 必须四字节对齐，否则产生 `store address misaligned`。访问未映射、无写权限
或由存储系统返回错误时产生 `store access fault`。只有成功响应才能使写入对
体系结构可见并提交；失败 store 不得产生部分或完整内存副作用。示例：
`sw x2, 4(x1)` 编码为 `0x0020a223`。

### 6.7 `sb`

```text
address:  A <- (X[rs1] + sext32(imm12)) mod 2^32
effect:   M8[A] <- X[rs2][7:0]
```

`sb` 允许任意字节地址，只写对应 byte lane；访问失败产生
`store access fault` 且不得产生内存副作用。示例：`sb x2, 1(x1)` 编码为
`0x002080a3`。

### 6.8 `jalr`

```text
base:     B <- old X[rs1]
sum:      S <- (B + sext32(imm12)) mod 2^32
target:   T <- S & 0xfffffffe
link:     L <- (old_pc + 4) mod 2^32
if T[1] == 1:
    raise instruction address misaligned
else:
    X[rd] <- L
    pc    <- T
```

必须先读取旧 `rs1`，因此 `rd == rs1` 时仍使用写回前的基址。清除 bit 0 后，
`IALIGN=32` 仍要求 bit 1 为零；若 bit 1 为一，故障归属于该 `jalr`，不写 link、
不更新 PC、不提交。示例：`jalr x5, 8(x1)` 编码为 `0x008082e7`。

## 7. 提交与故障语义

支持的故障类别固定为：

1. `illegal instruction`；
2. `instruction access fault`；
3. `instruction address misaligned`；
4. `load address misaligned`；
5. `load access fault`；
6. `store address misaligned`；
7. `store access fault`。

任一故障均为精确、粘滞的受控停机，而不是进入异常处理程序：故障指令不提交，
PC 保持为故障指令地址，不写任何通用寄存器；失败 store 不修改内存。核心记录
结构化 fault 并停止发起新请求，直到 reset 清除 fault。v0.2 不定义 trap vector、
异常原因 CSR 或返回指令。

数据地址对齐在发出数据请求前检查；不对齐访问不得发出请求。数据访问只有在
收到成功响应后提交，错误响应产生相应 access fault。取指错误产生
`instruction access fault`，不得把错误返回数据继续译码成另一类故障。

## 8. 非法指令

下列情况均产生 `illegal instruction`：

- 不是第 4 节八条指令之一的任何编码；
- 功能码不精确匹配，例如 `opcode=0110011` 但不是规定的 `add`；
- 任一实际使用的寄存器字段编码为 `x16`--`x31`。

不存在 v0.1 的“保留 opcode 可扩展”规则，也不接受未记录别名。新增指令必须
先更新本文，再同步修改 RTL、参考模型、编码/反汇编接口和定向测试。

## 9. 明确排除的能力

v0.2 不包含：

- RV32E/RV32I 的其余指令，包括条件分支、`jal`、比较、逻辑、移位、`fence`、
  `ecall` 和 `ebreak`；
- 压缩指令、乘除法、原子或浮点扩展；
- CSR、异常入口、中断、特权模式和睡眠/唤醒；
- 标准 ABI、ELF、链接布局或通用编译器支持。

八条指令足以建立 32 位计算、间接控制流和数据访存的硬件验证闭环，但因没有
条件分支，不能构成普通 C 程序所需的完整编译目标。

## 10. 规范依据

- [RISC-V Unprivileged ISA：RV32E/RV64E v2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32e.html)：
  采用 `x0`--`x15`，并把编码中实际指定 `x16`--`x31` 的情况视为保留；本项目
  进一步规定这些编码为非法。
- [RISC-V Unprivileged ISA：RV32I v2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)：
  采用 32 位格式、立即数、八条指令、`IALIGN=32`、`jalr` 和 load/store 的标准
  编码与基础语义。

本项目额外冻结小端执行环境、未对齐访问必定故障、结构化粘滞 fault 以及仅八条
指令合法。这些是 DC-Chip v0.2 的平台/子集约束，不代表完整 RV32E 的全部行为。
