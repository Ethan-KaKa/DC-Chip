# DC-Chip RV32E 基础整数指令集手册

- 版本：v1.0 (阶段 4)
- 状态：已冻结；覆盖 RV32E 基础整数指令集（37 条标准指令）
- 更新日期：2026-09-11

## 1. 范围与兼容性

本文档是 DC-Chip 指令编码和体系结构语义的唯一规范源。阶段 4 正式实现官方
**RV32E 基础整数指令集（RV32E Base Integer Instruction Set, Version 2.0）**，
包含 37 条标准非特权指令与 16 个 32 位通用寄存器（`x0`--`x15`）。

通过本标准的完整实现，DC-Chip 支持 GNU/LLVM RISC-V 交叉工具链以标准
`-march=rv32e -mabi=ilp32e` 参数直接编译和运行标准 C 语言程序（含条件分支、
循环、排序、递归、结构体、字符串及长整数计算）。除本文精确列出的 37 条标准编码外，
其他标准扩展、特权指令、保留或自定义编码在本项目中一律按非法指令处理。

## 2. 体系结构状态

| 项目 | v1.0 定义 |
| --- | --- |
| `XLEN` | 32 bit |
| 指令宽度 | 32 bit，定长 |
| 指令对齐 | `IALIGN=32`，取指与跳转目标地址必须四字节对齐 |
| 通用寄存器 | `x0`--`x15`，每个 32 bit |
| PC | 32 bit、byte-addressed |
| 复位 PC | 默认 `0x00000000`；四字节对齐 |
| 复位寄存器值 | `x1`--`x15` 为 `0x00000000`；`x0` 恒为零 |
| 字节序 | 小端（Little-Endian） |
| 特权级、CSR | 无 |

`x0` 的读值始终为零，对 `x0` 的写入被忽略。写 `x0` 的指令仍须完成其他
规定行为（例如 `lw x0, 0(x1)` 仍会发起访存并可能触发对齐或访问故障）。

## 3. 指令格式与立即数

支持标准 RISC-V 六种基本指令格式：

```text
R: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
I: imm[11:0]                rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
S: imm[11:5]     rs2[24:20] rs1[19:15] funct3[14:12] imm[4:0] opcode[6:0]
B: imm[12|10:5]  rs2[24:20] rs1[19:15] funct3[14:12] imm[4:1|11] opcode[6:0]
U: imm[31:12]                                        rd[11:7] opcode[6:0]
J: imm[20|10:1|11|19:12]                             rd[11:7] opcode[6:0]
```

立即数符号扩展与生成规则：

```text
I-immediate = sext32(inst[31:20])
S-immediate = sext32({inst[31:25], inst[11:7]})
B-immediate = sext32({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0})
U-immediate = {inst[31:12], 12'b0}
J-immediate = sext32({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0})
```

对于移位立即数指令（`slli`, `srli`, `srai`），立即数采用 `shamt = inst[24:20]`（5位移位量），`inst[31:25]` 必须精确匹配功能码且 `inst[25] == 0`。

## 4. 编码总表 (37 条指令)

| 指令 | 格式 | `opcode` | `funct3` | `funct7` | 规范语法 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| `lui` | U | `0110111` | -- | -- | `lui rd, imm20` | 高 20 位立即数加载 |
| `auipc` | U | `0010111` | -- | -- | `auipc rd, imm20` | PC 加高 20 位立即数 |
| `jal` | J | `1101111` | -- | -- | `jal rd, imm21` | 跳转并链接 |
| `jalr` | I | `1100111` | `000` | -- | `jalr rd, imm12(rs1)` | 间接跳转并链接 |
| `beq` | B | `1100011` | `000` | -- | `beq rs1, rs2, label` | 相等跳转 |
| `bne` | B | `1100011` | `001` | -- | `bne rs1, rs2, label` | 不等跳转 |
| `blt` | B | `1100011` | `100` | -- | `blt rs1, rs2, label` | 有符号小于跳转 |
| `bge` | B | `1100011` | `101` | -- | `bge rs1, rs2, label` | 有符号大于等于跳转 |
| `bltu` | B | `1100011` | `110` | -- | `bltu rs1, rs2, label` | 无符号小于跳转 |
| `bgeu` | B | `1100011` | `111` | -- | `bgeu rs1, rs2, label` | 无符号大于等于跳转 |
| `lb` | I | `0000011` | `000` | -- | `lb rd, imm12(rs1)` | 字节加载（符号扩展） |
| `lh` | I | `0000011` | `001` | -- | `lh rd, imm12(rs1)` | 半字加载（符号扩展） |
| `lw` | I | `0000011` | `010` | -- | `lw rd, imm12(rs1)` | 字加载 |
| `lbu` | I | `0000011` | `100` | -- | `lbu rd, imm12(rs1)` | 字节加载（零扩展） |
| `lhu` | I | `0000011` | `101` | -- | `lhu rd, imm12(rs1)` | 半字加载（零扩展） |
| `sb` | S | `0100011` | `000` | -- | `sb rs2, imm12(rs1)` | 字节存储 |
| `sh` | S | `0100011` | `001` | -- | `sh rs2, imm12(rs1)` | 半字存储 |
| `sw` | S | `0100011` | `010` | -- | `sw rs2, imm12(rs1)` | 字存储 |
| `addi` | I | `0010011` | `000` | -- | `addi rd, rs1, imm12` | 立即数加法 |
| `slti` | I | `0010011` | `010` | -- | `slti rd, rs1, imm12` | 立即数有符号小于置位 |
| `sltiu` | I | `0010011` | `011` | -- | `sltiu rd, rs1, imm12` | 立即数无符号小于置位 |
| `xori` | I | `0010011` | `100` | -- | `xori rd, rs1, imm12` | 立即数异或 |
| `ori` | I | `0010011` | `110` | -- | `ori rd, rs1, imm12` | 立即数或 |
| `andi` | I | `0010011` | `111` | -- | `andi rd, rs1, imm12` | 立即数与 |
| `slli` | I | `0010011` | `001` | `0000000` | `slli rd, rs1, shamt` | 逻辑左移立即数 |
| `srli` | I | `0010011` | `101` | `0000000` | `srli rd, rs1, shamt` | 逻辑右移立即数 |
| `srai` | I | `0010011` | `101` | `0100000` | `srai rd, rs1, shamt` | 算术右移立即数 |
| `add` | R | `0110011` | `000` | `0000000` | `add rd, rs1, rs2` | 加法 |
| `sub` | R | `0110011` | `000` | `0100000` | `sub rd, rs1, rs2` | 减法 |
| `sll` | R | `0110011` | `001` | `0000000` | `sll rd, rs1, rs2` | 逻辑左移 |
| `slt` | R | `0110011` | `010` | `0000000` | `slt rd, rs1, rs2` | 有符号小于置位 |
| `sltu` | R | `0110011` | `011` | `0000000` | `sltu rd, rs1, rs2` | 无符号小于置位 |
| `xor` | R | `0110011` | `100` | `0000000` | `xor rd, rs1, rs2` | 异或 |
| `srl` | R | `0110011` | `101` | `0000000` | `srl rd, rs1, rs2` | 逻辑右移 |
| `sra` | R | `0110011` | `101` | `0100000` | `sra rd, rs1, rs2` | 算术右移 |
| `or` | R | `0110011` | `110` | `0000000` | `or rd, rs1, rs2` | 或 |
| `and` | R | `0110011` | `111` | `0000000` | `and rd, rs1, rs2` | 与 |
| `fence`| I | `0001111` | `000` | -- | `fence` | 存储屏障（单核NOP提交） |

## 5. 寄存器合法性与非法指令判定

RV32E 仅支持 `x0`--`x15`。指令实际使用的每个寄存器字段若编码为 `x16`--`x31`（即操作数字段最高位 bit 4 为 1），该指令非法：
- R 型：检查 `rd`, `rs1`, `rs2`
- I 型（算术/load/jalr）：检查 `rd`, `rs1`
- S 型：检查 `rs1`, `rs2`
- B 型：检查 `rs1`, `rs2`（不检查 `rd` 字段）
- U 型 / J 型：检查 `rd`（不检查 `rs1`/`rs2` 字段位）
- `fence`：不检查寄存器

任何不在此 37 条指令范围内的编码或使用越界寄存器的指令，均产生粘滞的 `FAULT_ILLEGAL_INSTRUCTION`。

## 6. 对齐与访存契约

1. **指令对齐 (`IALIGN=32`)**：
   - 顺序取指、`jal`、`jalr` 以及条件分支成立时，目标地址低 2 位必须为 `2'b00`；
   - 若跳转目标 `target[1:0] != 2'b00`，触发 `FAULT_INSTRUCTION_MISALIGNED`，不提交指令、不修改 PC 与寄存器。
2. **数据访存对齐**：
   - `lw`, `sw`：要求 `addr[1:0] == 2'b00`（4 字节对齐）；
   - `lh`, `lhu`, `sh`：要求 `addr[0] == 1'b0`（2 字节对齐）；
   - `lb`, `lbu`, `sb`：允许任意单字节地址；
   - 对齐违规触发 `FAULT_LOAD_MISALIGNED` 或 `FAULT_STORE_MISALIGNED`。

## 7. 规范依据

- [RISC-V Unprivileged ISA: RV32E Base Integer Instruction Set, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32e.html)
- [RISC-V Unprivileged ISA: RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
