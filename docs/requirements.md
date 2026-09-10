# DC-Chip 项目需求

- 版本：v0.1
- 状态：初版 CPU 实施基线
- 更新日期：2026-09-10
- ISA 规范：`docs/isa/isa.md` v0.1

## 1. 项目目标

DC-Chip 面向低功耗嵌入式控制与周期性传感任务，最终需要在 Zynq-7020 FPGA 的 PL 中形成可综合、可验证、可运行的软件硬件闭环。目标负载包括周期性采样、少量整数计算、阈值判断、状态控制和通信。

初版 CPU 里程碑只建立最小执行与仿真闭环。由于 ISA v0.1 尚无数据访存、条件分支、中断和睡眠指令，本里程碑不能独立完成最终传感任务，也不把示例算术程序等同于目标应用。

## 2. 最终课程交付

最终项目应提供：

1. ISA、微架构和存储映射规格；
2. CPU、片上存储、必要外设和 FPGA wrapper RTL；
3. 模块测试、程序测试和独立参考模型或差分测试；
4. 裸机运行时、测试程序和周期性传感演示；
5. 可复现的 Vivado 综合、实现、约束和上板流程；
6. 注明工具、阶段、约束和负载的面积、性能与功耗结果。

初版 CPU 里程碑只覆盖上述第 1 项的一部分、第 2 项中的 CPU 核心，以及第 3 项中的 behavioral simulation 基线。

## 3. 初版功能范围

### 3.1 必须实现

- 16 位定长自定义 ISA，不兼容 RISC-V 二进制；
- 4 个 16 位通用寄存器 `R0`–`R3`，全部可写；
- 8 位指令字地址 PC，复位值为 `0x00`；
- `MOVI`、`MOV`、`ADDI`、`ADD`、`SUB`、`AND`、`OR` 和 `JUMP`；
- opcode `0x8`–`0xF` 及已分配 opcode 的非规范字段检测；
- 同步高有效核心复位、单周期顺序执行和组合零等待取指接口；
- 合法提交 trace、寄存器调试总线和粘滞非法指令指示；
- Icarus 模块级自检与 Verilator 端到端自检入口。

所有软件可见行为均以 `docs/isa/isa.md` 为唯一规范源。

### 3.2 本里程碑不实现

- 数据存储器、load/store、MMIO 和外设；
- 条件分支、状态标志、调用/返回、`HALT`、异常入口、中断和睡眠/唤醒；
- 流水线、stall、flush、valid/ready、Cache 和通用片上总线；
- 汇编器、编译器、ELF、链接 ABI 和裸机运行时；
- NEMU difftest、NVBoard、Vivado 工程、XDC、bitstream 和真实 FPGA 验证。

## 4. 初版验收需求

| 编号 | 需求 | 验收方法 |
| --- | --- | --- |
| `F-01` | 8 条已分配指令符合 ISA v0.1 | decoder/core 定向测试与 ISA smoke 程序 |
| `F-02` | 8 个保留 opcode 均为非法 | decoder 测试与集成负向镜像 |
| `F-03` | 所有已规定的未使用字段非零编码均为非法 | decoder 测试与非规范编码镜像 |
| `F-04` | 非法指令不提交、不写寄存器、PC 保持，状态保持到复位 | core 自检 testbench |
| `F-05` | 连续合法指令在零等待接口下每个非复位周期提交一条 | core trace 检查 |
| `F-06` | 构建和测试失败返回非零且包含最小定位上下文 | Make 目标与集成 runner |
| `F-07` | 核心不依赖 DPI-C、文件操作、仿真终止或厂商原语 | lint 与代码审阅 |

## 5. 性能、资源与功耗

| 项目 | 初版目标 | 测量方法 |
| --- | --- | --- |
| 功能吞吐 | 零等待取指且无非法状态时，每周期提交 1 条指令 | behavioral simulation 按上升沿检查 `trace_valid` |
| 最高时钟频率 | `TODO`，需实际器件和时钟目标 | Vivado post-implementation timing summary，记录 part、speed grade、约束与路径 |
| LUT/FF/BRAM/DSP | `TODO`，不预设数值 | Vivado synthesis 与 implementation utilization report，分别报告层级和阶段 |
| 动态与静态功耗 | `TODO`，不预设节能比例 | Vivado post-implementation power report，记录时钟、环境、活动文件和测试负载 |
| 程序执行性能 | `TODO`，待 ISA 和软件负载可运行 | 记录程序版本、输入、提交指令数、周期数和时钟约束 |

未经相应测量只能报告“未验证”或 `TODO`，不能从 behavioral simulation 推断综合、时序、资源、功耗或板级结果。

## 6. 后续需求门槛

数据访存、MMIO、外设、睡眠/唤醒和 FPGA 引脚只有在 ISA、存储映射、微架构及板卡文档同步更新后才能实施。任何新机制必须说明目标负载收益、接口行为、失败模式和验证方法。
