# DC-Chip 初版 CPU 与仿真系统构思

- 状态：规划稿，尚未实现
- 更新日期：2026-09-10
- 对应 ISA：`docs/isa/isa.md` v0.1
- 详细代码计划：[`initial-code-implementation-plan.md`](initial-code-implementation-plan.md)

## 1. 目标与结论

初版以“尽快形成可执行、可观察、可自检的最小闭环”为目标，只实现一个单周期 CPU 核心和一个 Verilator 仿真系统：

```text
16-bit HEX image
       |
       v
C++ instruction memory
       |
       | DPI-C (simulation boundary only)
       v
SystemVerilog sim_top wrapper
       |
       | imem_addr / imem_rdata
       v
synthesizable single-cycle CPU core
       |
       v
commit trace / registers / illegal indication
```

核心结论如下：

- CPU 使用自定义 16 位定长 ISA，不是 RISC-V，也不兼容 RISC-V 二进制。
- 初版实现 `MOVI`、`MOV`、`ADDI`、`ADD`、`SUB`、`AND`、`OR`、`JUMP` 共 8 条指令；opcode `0x8`–`0xF` 保留。
- 数据通路和寄存器宽度为 16 bit，PC 为 8 bit 字地址，最多直接容纳 256 条指令。
- 每个非复位时钟周期最多完成且初版固定完成一条合法指令。
- CPU 核心不导入 DPI-C；DPI-C 放在仿真 wrapper 中，未来可将 wrapper 替换为 ROM、BRAM 或 SoC 取指接口。
- 初版不实现数据存储器、外设、流水线、difftest、调试器、软件工具链或 FPGA 顶层。

本文档位于临时目录，用于指导下一阶段落地。稳定接口和设计决策在实现前应归档到正式架构与验证文档，正式文档不得反向依赖本文件。

## 2. 本阶段边界

### 2.1 包含

- 16 位自定义 ISA 的单周期执行；
- PC、4 个通用寄存器、组合译码和组合 ALU；
- 零等待、组合返回的只读指令接口；
- Verilator 时钟、复位和运行循环；
- 16-bit HEX 程序加载；
- 指令提交 trace、最终寄存器检查、非法指令检测和超时；
- 覆盖全部 8 条指令的最小自检回归。

### 2.2 不包含

- load/store、数据 RAM 或 MMIO；
- 条件分支、调用/返回、状态标志；
- `HALT`、异常入口、中断和睡眠/唤醒；
- NEMU difftest 或其他 RISC-V 设施；
- 汇编器、编译器、链接脚本和 ELF 加载；
- NVBoard、Vivado、Xilinx IP、XDC 和真实 FPGA 验证；
- 面积、时序、性能和功耗结论。

这些能力只有在需求和正式规格确定后才能加入，不能借初版仿真之名提前固化。

## 3. CPU 核心构思

### 3.1 建议模块划分

初版代码落地时建议按功能建立以下模块，不创建无内容的目录或占位文件：

```text
rtl/core/
  cpu_core.sv       # PC、提交、模块连接和顶层接口
  decoder.sv        # 指令字段、控制信号和非法编码检查
  regfile.sv        # 4 x 16-bit 双读单写寄存器堆
  alu.sv            # MOV/ADD/SUB/AND/OR 组合运算
```

模块拆分用于单元测试和教学观察，不引入流水寄存器。若实现时发现拆分只会增加无意义连线，可将 `decoder` 或 `alu` 合入 `cpu_core`，但寄存器状态、译码语义和外部接口不得变化。

### 3.2 核心接口

建议 `cpu_core` 使用以下可综合接口：

| 方向 | 信号 | 宽度 | 含义 |
| --- | --- | --- | --- |
| input | `clk` | 1 | 时钟，上升沿提交 |
| input | `rst` | 1 | 同步高有效复位 |
| output | `imem_addr` | 8 | 当前取指字地址，等于执行态 PC |
| input | `imem_rdata` | 16 | 当前地址对应的组合指令字 |
| output | `trace_valid` | 1 | 本次上升沿提交了一条合法指令 |
| output | `trace_pc` | 8 | 最近一次合法提交指令的 PC |
| output | `trace_inst` | 16 | 最近一次合法提交的指令字 |
| output | `debug_regs` | 64 | `{R3,R2,R1,R0}`，供初版自检读取 |
| output | `illegal_inst` | 1 | 粘滞非法指令指示，复位清零 |

`debug_regs` 和 trace 端口只用于可见性，不参与执行控制。后续若采用标准化 trace 接口，应同步更新仿真器和验证文档，不能依赖不稳定的 Verilator 内部层次路径读取寄存器。

### 3.3 单周期数据流

一个正常执行周期包含：

1. `PC` 组合驱动 `imem_addr`；
2. 仿真 wrapper 组合返回 `imem_rdata`；
3. decoder 拆分 `opcode`、`rd`、`rs` 和 `imm8`，并检查未使用字段；
4. regfile 组合读出 `Rd` 与 `Rs` 当前值；
5. ALU 或 next-PC 逻辑生成写回值和下一 PC；
6. 上升沿写回目标寄存器、更新 PC，并寄存 trace 信息。

组合逻辑必须完整提供默认值，默认禁止寄存器写入。时序状态只在 `always_ff @(posedge clk)` 中使用非阻塞赋值更新。

### 3.4 复位与提交

- 当上升沿采样到 `rst=1` 时，PC、`R0`–`R3`、trace 输出和 `illegal_inst` 全部清零。
- `rst=0` 且指令合法时，执行指令、更新 PC，并令 `trace_valid=1`。
- `rst=0` 且指令非法时，不写寄存器、不更新 PC、令 `trace_valid=0`，并将 `illegal_inst` 置 1。
- `illegal_inst` 置位后核心保持 PC 和寄存器状态，直到复位；仿真器应立即把它判为失败。

初版没有 stall 或 valid/ready，因此 `imem_rdata` 必须在当前周期组合稳定。未来接入同步 ROM 或可背压总线时必须重新定义取指协议，不能在当前接口上暗加延迟假设。

### 3.5 关键组合路径

初版关键路径预计为：

```text
PC -> DPI wrapper/instruction word -> decode -> regfile read
   -> ALU/next-PC mux -> register or PC input
```

这只是结构判断，不是时序测量结果。DPI-C 只存在于 behavioral simulation，不能据此推断综合或 FPGA 时序。

## 4. 仿真系统构思

### 4.1 建议文件布局

```text
sim/verilator/
  sim_top.sv        # CPU 实例和 DPI-C 指令存储器适配
  main.cpp          # 参数解析、时钟、复位、运行与结果检查
  memory.cpp        # HEX 加载和 sim_imem_read
  memory.h
sim/tests/
  isa_smoke.hex     # 全部 8 条指令的顺序测试
Makefile            # make sim / make test / make lint
build/              # Verilator 生成物，不纳入版本管理
```

落地时只创建实际使用的文件，并在对应 `.gitignore` 中忽略 `build/`、波形和日志。

### 4.2 DPI-C 边界

`sim_top.sv` 导入一个只读函数：

```systemverilog
import "DPI-C" function int unsigned sim_imem_read(
  input int unsigned word_addr
);
```

wrapper 将零扩展后的 `imem_addr` 传给该函数，并把返回值低 16 位连接到 `imem_rdata`。DPI 声明、调用和仿真专用逻辑不得进入 `rtl/core/`。

C++ 侧对应接口为：

```cpp
extern "C" uint32_t sim_imem_read(uint32_t word_addr);
```

指令内存使用 `std::vector<uint16_t>`。越过已加载镜像范围的取指应打印地址并返回一个保留编码 `0x8000`，使核心产生 `illegal_inst`；测试不应把越界取指当作正常程序结束。

### 4.3 HEX 镜像格式

初版程序文件采用如下规则：

- 每个有效行恰好包含 4 个十六进制数字，大小写均可；
- 地址按有效指令行从 `0x00` 递增，空行和注释行不占地址；
- 行首、行尾空白可以忽略；
- `#` 后内容为注释；
- 镜像最多包含 256 条指令；
- 非法字符、超过 4 位、空数据项或超过容量必须在仿真开始前报错。

示例：

```text
0402  # MOVI R1, #0x02
1900  # MOV  R2, R1
7002  # JUMP #0x02
```

HEX 是初版仿真输入格式，不是最终可执行文件 ABI。将来增加 binary/ELF 时应保留 HEX 以支持小型定向测试。

### 4.4 驱动生命周期

C++ 主程序按以下顺序运行：

1. 解析参数并加载、校验 HEX；
2. 创建 Verilated context 和 `sim_top` 实例；
3. 令 `rst=1` 驱动两个完整周期；
4. 令 `rst=0`，从下一上升沿开始统计提交；
5. 每周期执行 `clock=0/eval` 和 `clock=1/eval`；
6. 上升沿后检查 `illegal_inst`、`trace_valid`、trace 内容和寄存器值；
7. 达到指定提交数后检查全部期望状态；
8. 输出摘要、释放对象并返回明确退出码。

波形不是初版通过条件。后续可选加入 `--wave <path>`，但默认关闭，避免每次回归生成大文件。

### 4.5 命令接口

计划中的统一入口为：

```bash
make sim IMG=<program.hex> STEPS=<retired-instructions> TRACE=1
make test
make lint
```

`STEPS` 未指定时默认等于镜像内有效指令数。因为 v0.1 没有 `HALT`，程序正常结束只由提交步数决定，不允许把保留 opcode 当作成功结束指令。

底层可执行文件建议支持：

```text
cpu_sim --image <file> [--steps <n>] [--trace]
        [--expect r0=<v>] ... [--expect r3=<v>]
        [--expect pc=<v>] [--max-cycles <n>]
```

建议退出码约定：

| 退出码 | 含义 |
| --- | --- |
| 0 | 达到提交步数且所有期望状态匹配 |
| 1 | 参数或镜像加载错误 |
| 2 | CPU 报告非法指令 |
| 3 | 达到最大周期数仍未完成 |
| 4 | 最终状态与期望不匹配 |

默认 `max-cycles` 可设为复位释放后 `STEPS + 4`；在当前无 stall 单周期核中，额外 4 周期足以暴露未提交问题。未来增加 stall 后必须按新协议重新确定超时，不能沿用该数字宣称性能。

### 4.6 Trace 输出

启用 `TRACE=1` 时，每次合法提交输出一行：

```text
cycle=<n> pc=0x00 inst=0x0402 r0=0x0000 r1=0x0002 r2=0x0000 r3=0x0000
```

默认回归只在失败时保留必要上下文。trace 的依据是核心显式提交端口，不通过固定的 Verilator 内部成员路径读取信号。

## 5. 验证构思

### 5.1 最小 smoke 程序

`isa_smoke.hex` 使用 `docs/isa/isa.md` 中的 8 条程序：

```text
0402
1900
2408
3600
4600
5600
6600
7008
```

执行 8 条后必须得到：

```text
R0=0x0000 R1=0x0002 R2=0x0002 R3=0x0000 PC=0x08
```

### 5.2 定向测试

在 smoke 测试之后按最小层级增加：

- reset：所有状态清零，复位周期不产生提交；
- regfile：4 个寄存器均可读写，包含 `R0`；
- immediate：`0x00`、`0x7F`、`0x80`、`0xFF` 均零扩展；
- arithmetic：`0xFFFF + 1 = 0x0000`，`0 - 1 = 0xFFFF`；
- logic：全零、全一和交替位模式；
- jump：从非零 PC 跳到低地址和 `0xFF`；
- PC wrap：地址 `0xFF` 的普通指令提交后 PC 变为 `0x00`；
- illegal：8 个保留 opcode 各至少一例，已分配指令的非零未使用字段各至少一例；
- loader：空文件、错误字符、过宽数据、超过 256 条和不存在文件；
- timeout：核心没有产生预期提交时返回非零。

所有测试必须自检并通过进程退出码报告结果。波形只能作为定位手段，不能代替断言。

### 5.3 后续验证升级

当 ISA 扩展或核心复杂度增加后，优先建立独立的轻量参考解释器，再逐条提交比较 PC 和寄存器状态。NEMU 当前实现的是 RISC-V，不应通过大范围 skip 迁就本项目 ISA。

## 6. 建议实施顺序

1. 先完成 `docs/requirements.md`、正式微架构、memory-map、验证和板卡文档的最小版本；未知项明确标 `TODO`。
2. 实现并单测 `alu.sv`、`regfile.sv` 和 `decoder.sv`。
3. 集成 `cpu_core.sv`，用纯 SystemVerilog testbench 验证复位和单条指令。
4. 实现 DPI wrapper、HEX loader 和最小 Verilator 驱动。
5. 接入 `isa_smoke.hex` 与定向回归，提供 `make lint`、`make sim`、`make test`。
6. 固化稳定接口到正式架构/验证文档，再考虑 load/store、分支或 FPGA 入口。

## 7. 风险与约束

- 当前组合 DPI 取指只适用于 behavioral simulation；它不是可综合存储器。
- 单周期组合路径会随指令和存储功能增加而变长，扩展前需重新评估是否继续单周期。
- 8 位 PC 限制程序为 256 个指令字；扩大 PC 会改变核心接口和 `JUMP` 的可达范围，必须先改规格。
- v0.1 没有条件分支、数据访存和 `HALT`，只能验证小型算术/逻辑与绝对跳转程序。
- 当前没有独立参考模型；初版正确性证据来自模块级断言、定向程序和最终架构状态检查。
- 本构思尚未经过 RTL 仿真、综合、实现或上板验证，不能据此给出频率、面积、性能或功耗数字。

## 8. 资料与借鉴边界

课程资料：

- `docs/sources/lab/lab2.pptx` 第 7–12 页：指令格式、PC、寄存器组和 ALU；
- `docs/sources/lab/lab3.pptx` 第 6–8 页：指令表和控制信号；
- `docs/sources/lab/lab4.pptx` 第 15–16 页：扩展方向、benchmark 和 memory BFM。

NPC 参考：

- 路径：`/home/kaka/ysyx-workbench/npc`；
- ysyx-workbench 提交：`77cceb3f3a21c4cc9251b6e0c43342340cd2d9ee`；
- 借鉴内容：Verilator 编译入口、C++ 时钟推进、镜像加载、trace 和退出状态的组织方法；
- 不采用内容：RV32IM 编码、双发射/ROB、SoC 地址、NEMU 语义、NVBoard、完整调试器和复杂配置系统。

后续若复制而非重新实现任何参考代码，必须先核查对应文件许可证并记录来源；当前构思没有复制外部源码。
