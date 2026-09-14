# DC-Chip 验证计划

本文定义当前验证策略、分层入口和证据边界；仿真组件及数据流见
[`simulation-design.md`](simulation-design.md)。测试清单不在文档中复制，始终通过
`make list`、`make testunit list`、`make testinfra list` 和
`make sw tests list` 查询。

## 1. 目标

- ISA 编码、寄存器边界、指令语义和 fault 与权威规格一致。
- valid/ready 在 stall、背压、reset 和错误响应下不丢失、不重复、不产生提前副作用。
- RTL、独立参考模型、软件 ABI、地址映射和仿真终止行为一致。
- 每一层失败都能返回非零并保留最小命令、seed 或必要诊断。
- 明确区分静态检查、behavioral simulation、综合、实现、时序、功耗和上板证据。

## 2. 分层验证

| 层 | 内容 | 公开入口 |
| --- | --- | --- |
| 仓库规则 | 路径、私有配置、Markdown 断链、临时内容隔离 | `make check-paths` |
| RTL 单元 | ALU、decoder、regfile、core、外设、CDC、互连、SoC、lint | `make testunit list` / `make testunit` |
| 仿真基础设施 | 配置、ISA、存储、反汇编、参考模型、仿真引擎、difftest、CLI、SDB、VCD | `make testinfra list` / `make testinfra` |
| 软件系统 | AM 启动、链接、运行时、算法与 MMIO 外设程序，以及 pinned RV32E ISA 回归适配 | `make sw tests list` / `make sw tests` / `make sw riscv-tests` |
| 完整默认回归 | 隔离 default defconfig 下的前三层默认集合 | `make test` |
| 可选外部裁判 | 官方 Spike backend | `make testinfra ALL=difftest-spike` |
| FPGA | 综合、实现、时序、资源、功耗、bitstream、ILA、上板 | `TODO`，当前无公开 Make 入口 |

`testunit` 与 `testinfra` 省略子命令时运行默认 batch。裸 `sw tests` 服从本地
`.config`；`batch` 关闭交互 SDB、NVBoard 与 VCD，但不关闭编译进仿真器的
difftest。完整 CLI 以 `make help` 和 `make list` 为准。

## 3. 覆盖重点

### 3.1 ISA 与核心

- 每条支持指令的编码、立即数、边界值、别名反汇编与执行结果；
- 所有实际使用字段的 `x15/x16` 边界，且不误判未使用字段；
- `x0` 写保护、算术回绕、符号/无符号比较和移位边界；
- taken/not-taken branch、JAL/JALR link 与目标对齐；
- byte/halfword/word lane、符号扩展、对齐和 store 无部分副作用；
- 七类 fault、fault 指令不提交、状态粘滞和 reset 恢复。

### 3.2 总线、存储与外设

- 请求与响应各自背压时 payload 稳定，每个事务恰好一次；
- IROM/DRAM Harvard 权限、边界、双镜像和 `tohost` 访问限制；
- DRAM read-first、写 strobe、响应握手后的副作用；
- MMIO 地址分流、未映射错误、UART FIFO/RX、LED lane、Buttons 同步与只读、
  SEG7 字形和 byte lane；
- `ASYNC_CDC=0/1` 两条路径，包括异步 toggle-handshake 与 reset 后空闲状态。

### 3.3 参考模型与软件

- C++ ReferenceModel 独立实现 ISA、内存和 fault，不复用 RTL 译码逻辑；
- 每次普通提交比较旧 PC、指令、下一 PC 和 `x0`--`x15`；MMIO 只通过受限的
  `is_skip_ref` 协议同步，详见 [`simulator.md`](simulator.md)；
- 固定 seed 随机向量和定向 fault 用例；发现失败时记录 seed；
- 每个软件镜像使用 `-march=rv32e -mabi=ilp32e`，通过 ISA 审计后再运行；
- `make sw riscv-tests` 运行固定 `riscv-tests-am` 快照中与当前 ISA 表所列全部非
  `fence` 基础指令对应的 RV32UI 用例，加本地极小 `fence` 自检；它通过 AM `tohost`
  判定，不做 signature 比对，也不是 RISCOF 认证。
- guest 成功/失败、fault、timeout 和宿主输入错误必须映射到可判定退出状态。

## 4. 执行策略

任务先选择一个最小入口：例如 decoder 变化先跑 `make testinfra ALL=isa`，MMIO
变化先跑对应 unit 与一项软件测试。最小层失败时在该层定位；通过后再扩展到受影响
层，外部契约或构建规则变化最终运行 `make test`。

随机测试必须固定并打印 seed；所有循环等待有上限；失败日志只保留复现需要的
摘要，波形和完整生成物留在 `build/`，不入 Git。

## 5. 证据记录

[`../status.md`](../status.md) 只记录最近实际执行的命令和结果，不把旧阶段累计
日志搬入本计划。历史八指令基线与迁移过程从 Git 提交恢复；重大验证边界由 ADR
记录。

当前没有 Vivado 综合、post-synth、post-implementation、时序、功耗或真实上板
证据。Icarus、Verilator、difftest 或 NVBoard PASS 不得被表述为这些阶段已通过。
