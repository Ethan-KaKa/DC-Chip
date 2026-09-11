# DC-Chip 项目需求

- 版本：v0.2
- 状态：阶段 1 迁移中；ISA 公共层与核心 RTL 已实现，仿真器尚未迁移
- 更新日期：2026-09-11
- ISA 规范：`docs/isa/isa.md` v0.2

## 1. 项目目标

DC-Chip 面向低功耗嵌入式控制与周期性传感任务，最终需要在 Zynq-7020 FPGA
的 PL 中形成可综合、可验证、可运行的软件硬件闭环。目标负载包括周期性采样、
少量整数计算、阈值判断、状态控制和通信。

阶段 1 的当前里程碑是把 CPU 迁移到 **RV32E 过渡子集 v0.2**：使用标准
RISC-V 编码、32 位数据与地址、`x0`--`x15`，且只支持 `add`、`addi`、`lui`、
`lw`、`lbu`、`sw`、`sb` 和 `jalr`。该八指令子集只建立计算、间接控制流和
数据访存闭环；由于没有条件分支、中断、外设和睡眠/唤醒，它不能独立完成最终
传感任务，也不是完整 RV32E。

## 2. 最终课程交付

最终项目应提供：

1. ISA、微架构和存储映射规格；
2. CPU、片上存储、必要外设和 FPGA wrapper RTL；
3. 模块测试、程序测试和独立参考模型或差分测试；
4. 裸机运行时、测试程序和周期性传感演示；
5. 可复现的 Vivado 综合、实现、约束和上板流程；
6. 注明工具、阶段、约束和负载的面积、性能与功耗结果。

阶段 1 v0.2 只覆盖第 1 项的 CPU 相关规格，并为后续 CPU RTL、behavioral
simulation 和差分测试迁移建立验收契约。

## 3. 阶段 1 v0.2 功能范围

### 3.1 必须能力

- `XLEN=32`，32 位定长标准 RISC-V 编码，32 位 byte-addressed PC，
  `IALIGN=32` 和小端数据模型；
- 16 个 32 位整数寄存器 `x0`--`x15`，其中 `x0` 恒为零；
- 精确实现 `add`、`addi`、`lui`、`lw`、`lbu`、`sw`、`sb` 和 `jalr`；
- 只检查指令实际使用的寄存器字段，并把对 `x16`--`x31` 的使用视为非法；
- `LW/SW` 四字节对齐，`LBU/SB` 支持任意字节地址；
- 顺序、单发射、允许取指和数据存储停顿的 valid/ready 请求--响应接口；
- 精确、结构化、粘滞至 reset 的 illegal、取指、对齐和数据访问 fault；
- 成功提交 trace、索引式寄存器调试读取和自检 behavioral simulation；
- 独立参考模型和逐提交差分测试。

所有软件可见行为以 `docs/isa/isa.md` 为唯一规范源；微架构接口、提交边界和
fault 输出以 `docs/architecture/microarchitecture.md` 为准。

### 3.2 本里程碑排除项

- 完整 RV32E/RV32I、条件分支、`jal`、CSR、异常入口、中断、特权模式；
- 运行普通 GCC 生成程序的承诺、标准 ABI、`.bin`/ELF loader 和链接布局；
- AM 适配、外设、正式 IROM/DRAM/MMIO 地址和最小 SoC；
- Cache、复杂总线、流水线、分支预测和乱序执行；
- Vivado 工程、XDC、综合/实现、bitstream、真实 FPGA 验证和功耗测量。

这些能力须在对应规格和验收方法确定后另行实施，不能由 v0.2 八指令回归推断。

## 4. 实施状态与证据边界

| 层次 | 正式目标 | 2026-09-11 实际状态 |
| --- | --- | --- |
| ISA 规格 | RV32E 过渡子集 v0.2 | 已冻结于 `docs/isa/isa.md` |
| 微架构/存储契约 | 32 位握手、数据访问、结构化 fault | 已规格化并进入核心 RTL；仿真存储尚未实现 |
| ISA 公共层 | 32 位 package、严格 decoder、测试编码器 | 已实现；`make test-isa` 已验证八条编码、立即数和 RV32E 寄存器限制 |
| RTL 核心 | 16×32 位 v0.2 核心 | 已实现；ALU、regfile、八指令执行、双存储握手和七类 fault 通过模块级测试 |
| 仿真器/反汇编器 | 32 位镜像、状态、trace、fault | 32 位反汇编器已实现；wrapper、loader、状态和 fault **未实现** |
| 测试/参考模型 | v0.2 定向测试与 difftest | ISA、decoder、ALU、regfile 和 core 专项已实现；程序、参考模型和 difftest **未实现** |
| 软件/SoC/FPGA | 后续阶段 | `TODO` / 未验证 |

迁移期间允许核心先于仿真器切换。步骤 2.3 后以 `make test-isa`、`make lint`
和 `make test-unit` 作为已迁移范围的证据，完整 `make test` 要到步骤 2.4--2.5
恢复后才可重新作为累计门禁。不提供双 ISA 配置；后续迁移继续直接替换 v0.1
实现。

## 5. 阶段 1 v0.2 验收需求

| 编号 | 需求 | 后续验收方法 |
| --- | --- | --- |
| `F-01` | 八条指令的标准编码和语义与 ISA v0.2 一致 | decoder/core 定向测试与参考模型 |
| `F-02` | `x0` 恒零，`x1`--`x15` 正常读写 | regfile/core 自检 |
| `F-03` | 实际操作数编码为 `x16`--`x31` 时非法，`lui` 立即数不误判 | 穷举/定向 decoder 测试 |
| `F-04` | I/S 立即数正确拼接和符号扩展，ADD/ADDI 按模回绕 | 边界向量与差分测试 |
| `F-05` | `LW/LBU/SW/SB` 的小端 lane、扩展、对齐和错误行为正确 | 可停顿存储 BFM |
| `F-06` | `jalr` 使用旧 `rs1`、写 `pc+4`、清 bit 0 并检查 bit 1 | 定向 core 测试 |
| `F-07` | fault 指令不提交/写寄存器，失败 store 无副作用，fault 粘滞 | fault 注入与 reset 恢复测试 |
| `F-08` | 请求和响应在背压下稳定，不丢失或重复事务 | 随机 stall BFM 与断言 |
| `F-09` | 32 位 PC/指令 trace 与 16×32 位调试状态准确 | 逐提交检查 |
| `F-10` | RTL 与独立模型逐提交一致 | difftest，失败保留 seed 和上下文 |

## 6. 性能、资源与功耗

| 项目 | 当前目标 | 测量方法 |
| --- | --- | --- |
| 功能正确性 | 在任意有限合法 stall 下保持顺序、无丢失/重复提交 | behavioral simulation 与协议断言 |
| IPC/延迟 | `TODO`，取决于后续控制器和存储延迟 | 记录负载、提交数、周期数及 stall 模式 |
| 最高时钟频率 | `TODO`，需实际器件和时钟目标 | Vivado post-implementation timing summary |
| LUT/FF/BRAM/DSP | `TODO`，不预设数值 | Vivado synthesis/implementation utilization report |
| 动态与静态功耗 | `TODO`，不预设节能比例 | Vivado post-implementation power report，记录活动文件和负载 |

未经相应测量只能报告“未验证”或 `TODO`。behavioral simulation 不能证明综合、
时序、资源、功耗或板级结果。

## 7. 后续需求门槛

完整 RV32E、普通编译器程序、AM、IROM/DRAM/MMIO、外设、睡眠/唤醒和 FPGA
引脚只有在 ISA、存储映射、微架构、软件 ABI 及板卡文档同步更新后才能实施。
任何新机制必须说明目标负载收益、接口行为、失败模式和验证方法。
