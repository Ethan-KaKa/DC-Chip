# 疑难问题索引

这里只记录难以从代码直接看出的已证实根因。普通报错先从
[`README.md`](README.md) 的任务路由选择最小测试。

## Spike 共享库与 DC-Chip 地址布局

症状可能包括链接共享库时报 relocation/`-fPIC` 错误、初始化时报 IROM 与 debug
module 地址重叠，或连续用例中在 `processor_t::step()` 附近随机崩溃。

已证实根因分别是：Spike 静态对象默认不适合链接 `.so`；其默认 debug/reset
布局占用低地址；`sim_t` 保存传入 `cfg_t` 的指针，局部栈对象退出初始化后失效。
当前构建把补丁和产物隔离在 `build/tools/spike/`，不修改 submodule 工作树；适配
层持有覆盖完整共享库生命周期的配置与物理内存对象。

检查顺序：

1. 确认 `tools/spike` submodule 干净，补丁来自 `tools/spike-diff/spike.patch`；
2. 用 `make spike-build` 重建隔离产物；
3. 用 `make testinfra ALL=difftest-spike` 运行可选外部裁判；
4. 不把 Spike 的 trap/设备布局直接当成本项目 fault/MMIO 契约。

## RV32E `x15/x16` 边界

症状是普通算术似乎正常，但某条编译结果在 decoder、ReferenceModel 或 Spike 中
被判 illegal，或者 U/J/B/FENCE 误判未使用字段。

根因通常是工具链没有同时使用 `-march=rv32e -mabi=ilp32e`，或检查了指令并未
实际使用的五位寄存器字段。只对 [`isa/isa.md`](isa/isa.md) 列出的实际操作数
应用 bit 4 边界；软件必须检查最终反汇编，而不是只检查 C 源码。

最小复现入口是 `make testinfra ALL=isa`，再按需要运行
`make testunit ALL=decoder,core`。

## MMIO difftest 的 `is_skip_ref`

症状是 UART/Buttons 等动态读取在 DUT 与纯 ISA 参考模型间出现寄存器差异，或为
消除差异而扩大跳过后掩盖了真实 PC、DRAM 或 fault 错误。

根因是动态 MMIO 值不应由参考模型猜测，但跳过必须与产生该响应的已提交访存
精确绑定。`soc_interconnect` 生成响应属性，`cpu_core` 在提交拍转成
`trace_skip_ref`；difftest 仍比较提交 PC，只同步 load 的目标寄存器或下一 PC，
随后比较全部寄存器。`tohost` 和 DRAM 不属于跳过范围。

最小复现入口是 `make testinfra ALL=difftest-engine`，再运行相关
`make sw tests ALL=<peripheral-test>`。详细契约见
[`verification/simulator.md`](verification/simulator.md)。

## `tohost` 地址构造导致的伪通过

`lui reg, 0xfffff` 后再 `addi reg, reg, -16` 得到 `0xffffeff0`，不是
`0xfffffff0`。若 DUT 和自研模型都把错误地址判为 store access fault，只比较
双方 fault 可能把测试向量错误误当成匹配。

应使用 `addi reg, zero, -16` 构造 `tohost`，并要求定向测试确认实际观察到
program exit，而不只是“DUT 与参考端同时 fault”。外部 Spike backend 可作为
第二裁判，但不能取代明确的测试成功条件。
