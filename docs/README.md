# DC-Chip 文档入口

先按任务选择入口，再读源码。每项最多列出三个先读文档；命令与测试清单以
`make help`、`make list` 为准。

## 任务路由

| 任务 | 先读（按顺序） | 最小验证入口 |
| --- | --- | --- |
| 修改 ISA、译码或执行 | [`isa/isa.md`](isa/isa.md)、[`architecture/microarchitecture.md`](architecture/microarchitecture.md)、[`verification/plan.md`](verification/plan.md) | `make testinfra ALL=isa`，再按需 `make testunit ALL=core` |
| 修改存储、互连或 MMIO | [`architecture/memory-map.md`](architecture/memory-map.md)、[`architecture/microarchitecture.md`](architecture/microarchitecture.md)、[`verification/plan.md`](verification/plan.md) | `make testunit ALL=interconnect,soc` |
| 修改 AM、链接或驱动 | [`architecture/software-abi.md`](architecture/software-abi.md)、[`architecture/memory-map.md`](architecture/memory-map.md)、[`verification/plan.md`](verification/plan.md) | `make sw tests ALL=<name>` |
| 修改仿真器、SDB 或 difftest | [`verification/simulator.md`](verification/simulator.md)、[`verification/configuration.md`](verification/configuration.md)、[`debugging.md`](debugging.md) | `make testinfra ALL=<name>` |
| 修改构建、配置或路径 | [`../BUILD_RULES.md`](../BUILD_RULES.md)、[`verification/configuration.md`](verification/configuration.md)、[`documentation.md`](documentation.md) | `make check-paths`、`make testinfra ALL=make-cli,repo-rules` |
| 修改 FPGA wrapper 或约束 | [`fpga/board.md`](fpga/board.md)、[`architecture/memory-map.md`](architecture/memory-map.md)、[`requirements.md`](requirements.md) | 先完成文档中的板级 TODO；Vivado 流程当前未实现 |
| 维护正式文档 | [`documentation.md`](documentation.md)、[`status.md`](status.md)、[`decisions/`](decisions/) | `make check-paths` |

## 权威地图

- ISA 编码和语义：[`isa/isa.md`](isa/isa.md)
- 地址、权限和 MMIO 副作用：[`architecture/memory-map.md`](architecture/memory-map.md)
- CPU、总线、提交和 fault 协议：[`architecture/microarchitecture.md`](architecture/microarchitecture.md)
- 软件 ABI 与运行时：[`architecture/software-abi.md`](architecture/software-abi.md)
- 验证策略和仿真器接口：[`verification/plan.md`](verification/plan.md)、[`verification/simulator.md`](verification/simulator.md)
- 当前能力和最近验证：[`status.md`](status.md)
- 重大历史取舍：[`decisions/`](decisions/)

## 一屏任务卡

开始修改前写清五项即可：目标、范围、最多三个入口、最小验证、停止条件。先跑
最小验证；只有失败或契约不清时才扩大阅读与回归。课程原件位于 `sources/`，默认
只读，只有任务明确需要时再按文件和页码读取。
