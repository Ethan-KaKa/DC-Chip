# DC-Chip 项目需求

本文件定义稳定目标、范围和验收边界。当前完成度与最近验证不在此维护，见
[`status.md`](status.md)。

## 1. 目标与负载

DC-Chip 面向低功耗嵌入式控制与周期性传感任务，目标是在 Zynq-7020 FPGA 的
PL 中形成一套可解释、可验证、可运行的软件硬件闭环。代表性负载包括周期性
采样、少量整数计算、阈值判断、状态控制和 UART/GPIO 通信。

架构选择应由这些负载和测量结果驱动。默认采用简单的顺序单发射 CPU、小而明确
的片上存储与 MMIO；Cache、复杂流水线、分支预测、多发射、乱序执行和完整 AXI
不是默认需求。

## 2. 功能范围

### 2.1 CPU 与体系结构

- 32 位小端、定长指令、`IALIGN=32`；复位 PC 为 `0x00000000`。
- 执行 [`isa/isa.md`](isa/isa.md) 定义的项目 RV32E v1.0 基础整数指令，只有
  `x0`--`x15`；其他编码、扩展、CSR、特权指令与越界寄存器访问非法。
- 顺序、单发射，无推测执行；取指和数据访问允许背压。
- 非法指令、取指/数据访问错误和地址未对齐产生结构化 fault；fault 指令不得
  提交或产生部分副作用。

### 2.2 SoC 与软件

- IROM 与 DRAM 采用 Harvard 隔离，正式地址、容量、权限和外设副作用由
  [`architecture/memory-map.md`](architecture/memory-map.md) 定义。
- 提供最小 MMIO 外设和可替换的传感器接口；未映射或非法访问必须显式报错。
- 提供与 [`architecture/software-abi.md`](architecture/software-abi.md) 一致的
  裸机启动、链接布局、运行时、设备抽象、测试程序和最终周期性传感演示。
- 软件产物必须经过 ISA 审计，不得依赖未实现的指令扩展或 `x16`--`x31`。

### 2.3 验证与交付

最终课程交付应包含：

1. ISA、微架构、地址映射、软件 ABI 与板级规格；
2. CPU、片上存储、必要外设和 FPGA wrapper RTL；
3. 模块自检、程序测试、独立参考模型与逐提交差分测试；
4. 裸机运行时、定向测试和周期性传感演示；
5. 可复现的 Vivado 综合、实现、约束、bitstream 和上板流程；
6. 带完整测量条件的面积、性能、时序与功耗结果。

## 3. 非目标与边界

- 不承诺 RV32I 的 32 寄存器 ABI，也不支持 M/A/F/D/C、CSR、特权模式或虚拟内存。
- timer、sensor、睡眠/唤醒与中断只有在 ISA、微架构、地址和软件契约同步定义后
  才进入范围；当前状态见 [`status.md`](status.md)。
- PS 的职责、板卡型号、器件完整料号、时钟、复位与引脚不能从“Zynq-7020”推断，
  以 [`fpga/board.md`](fpga/board.md) 为准。
- NVBoard 和 behavioral simulation 只提供功能证据，不能证明真实 FPGA 时序、
  资源、功耗或板级电气行为。

## 4. 验收要求

| 编号 | 要求 | 验收证据 |
| --- | --- | --- |
| `F-01` | ISA 编码、立即数、寄存器边界与语义一致 | decoder/core 定向测试、ISA 跨工具检查、difftest |
| `F-02` | 请求/响应在有限背压下不丢失、不重复，payload 保持稳定 | 协议 testbench、仿真超时和断言 |
| `F-03` | load/store lane、扩展、对齐、权限与失败副作用正确 | core、memory、interconnect 与软件定向测试 |
| `F-04` | fault 精确、粘滞至 reset，fault 指令不提交 | fault 注入、reference 与 integration 测试 |
| `F-05` | 每条成功指令只提交一次，RTL 与独立模型状态一致 | trace 检查与逐提交 difftest |
| `F-06` | 软件镜像、启动、链接、退出和设备接口与硬件契约一致 | ISA 审计与 `sw tests` |
| `F-07` | 构建入口、配置与生成物可复现且不污染源码/submodule | `make check-paths`、Make CLI 与配置测试 |
| `F-08` | FPGA 实现满足已确认板级约束 | Vivado 综合/实现报告与真实上板记录；当前未验证 |

回归命令和测试清单由 `make help`、`make list` 动态提供，验证策略见
[`verification/plan.md`](verification/plan.md)。

## 5. 性能、资源与功耗

| 指标 | 目标 | 合法证据 |
| --- | --- | --- |
| 功能正确性 | 对任意有限合法 stall 保持顺序且无丢失/重复提交 | behavioral simulation 与协议断言 |
| 延迟、IPC | `TODO`，按代表性负载定义 | 记录版本、配置、负载、周期、提交数与 stall 模式 |
| 最高频率 | `TODO`，待器件与约束冻结 | Vivado post-implementation timing summary |
| LUT/FF/BRAM/DSP | `TODO`，不预设数值 | Vivado synthesis/implementation utilization report |
| 静态/动态功耗 | `TODO`，不预设节能比例 | Vivado post-implementation power report，含活动与负载 |

没有相应测量时只能报告 `TODO`、预计或未验证。
