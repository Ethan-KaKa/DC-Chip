# ADR-0004：显式隔离 MMIO CDC 与差分边界

- 状态：Accepted
- 日期：2026-09-14
- 类型：retrospective
- Supersedes：无
- Superseded by：无
- 追溯提交：[`7a19553`](https://github.com/Ethan-KaKa/DC-Chip/commit/7a19553)、[`b5dae64`](https://github.com/Ethan-KaKa/DC-Chip/commit/b5dae64)

## 背景

物理外设需要稳定时钟，而 CPU/片上存储需要保留独立频率探索空间；同时 UART、
Buttons 等动态 MMIO 状态不适合由纯 ISA 参考模型逐周期复现。让核心直接理解
具体外设，或在 difftest 中无条件跳过访存，都会破坏模块边界和错误可见性。

## 决策

MMIO 事务通过参数化 `mmio_cdc_bridge`：仿真同源时钟使用同步直通，FPGA 路径
使用单事务 toggle-handshake 和 2FF 同步。SoC 地址分流为每个响应产生
`skip_ref` 属性，核心只在对应访存提交拍导出 `trace_skip_ref`；difftest 仍检查
提交 PC，并只同步该指令受影响的参考状态。DRAM 与 `tohost` 不跳过。

## 后果

CPU 不依赖外设时钟与设备细节，动态 MMIO 不会制造伪差异，同时普通 ISA、DRAM
和 fault 仍被严格比较。异步桥每方向只允许一个在途事务并增加延迟；它不替代
板级时钟/复位约束和 CDC 分析。新增未建模空间不得直接扩大跳过范围，必须同步
地址真源、参考模型、测试和本 ADR 的 superseding 决策。
