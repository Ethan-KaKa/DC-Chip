# DC-Chip

DC-Chip 是一个数字电路设计课程项目：在 Zynq-7020 的 PL 侧渐进构建面向低功耗
嵌入式控制与周期性传感任务的 RV32E CPU、最小 SoC、裸机运行时和验证闭环。

当前实现覆盖项目定义的 RV32E v1.0 基础整数指令集、分离的 IROM/DRAM、MMIO
UART、LED、Buttons 和八位七段数码管，并提供模块自检、Verilator 仿真、独立
参考模型、逐提交 difftest、SDB、VCD 与 NVBoard 支持。准确状态和证据边界见
[`docs/status.md`](docs/status.md)；真实 FPGA 综合、实现与上板仍未验证。

## 快速开始

```bash
make init
make help
make list
make test
```

`make test` 使用隔离的默认配置运行仓库默认三层回归，不读取或改写本地
`.config`。只需查看工具环境时运行 `make check-tools`；配置仿真特性时使用
`make defconfig`、`make menuconfig` 和 `make config-show`。

## 文档与协作

- 唯一文档入口与任务路由：[`docs/README.md`](docs/README.md)
- 当前实现状态：[`docs/status.md`](docs/status.md)
- 仓库协作规则：[`AGENTS.md`](AGENTS.md)
- 构建与路径规则：[`BUILD_RULES.md`](BUILD_RULES.md)
- Git 操作规则：[`GIT_RULES.md`](GIT_RULES.md)

具体测试名称和受支持命令始终以 `make help`、`make list` 及其分层 `list` 入口为准，
不在 README 中复制易漂移的数量或清单。
