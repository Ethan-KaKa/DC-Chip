# ADR-0001：从教学基线演进到项目 RV32E v1.0

- 状态：Accepted
- 日期：2026-09-14
- 类型：retrospective
- Supersedes：无
- Superseded by：无
- 追溯提交：[`5db47a1`](https://github.com/Ethan-KaKa/DC-Chip/commit/5db47a1)、[`b56ed82`](https://github.com/Ethan-KaKa/DC-Chip/commit/b56ed82)

## 背景

早期 16 位教学核不足以承载标准工具链和目标嵌入式软件。项目先用八条标准编码
建立 32 位数据、地址、寄存器和 fault 闭环，再扩展到当前项目定义的 RV32E
v1.0 基础整数指令集。长期保留双 ISA 开关会放大 RTL、参考模型和测试矩阵。

## 决策

直接迁移并冻结一个现行 ISA：32 位小端、`IALIGN=32`、`x0`--`x15`，支持
[`../isa/isa.md`](../isa/isa.md) 列出的标准指令；其他编码、扩展、CSR、特权
指令和对 `x16`--`x31` 的实际引用一律非法。不保留旧 ISA 运行开关，旧语义只
由 Git 历史恢复。

## 后果

GNU 工具链可统一使用 `-march=rv32e -mabi=ilp32e`，但所有软件仍须做 ISA 与
寄存器审计。任何增删指令必须同步更新 ISA 真源、RTL、反汇编、参考模型、编码器
和测试。项目不因此宣称支持 RV32I、扩展 ISA 或特权环境。
