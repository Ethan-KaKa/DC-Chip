# ADR-0003：维护仓库内自包含 AM-like 运行时

- 状态：Accepted
- 日期：2026-09-14
- 类型：retrospective
- Supersedes：无
- Superseded by：无
- 追溯提交：[`d94076a`](https://github.com/Ethan-KaKa/DC-Chip/commit/d94076a)

## 背景

外部 Abstract Machine 工程可供借鉴，但直接依赖个人工作区会破坏可复现性，也会
把与本项目 ISA、Harvard 布局和 MMIO 不一致的平台契约带入构建。

## 决策

在 `sw/am/` 维护最小、自包含的 AM-like 启动、链接、TRM、`klib` 与设备抽象。
外部实现只读参考；公共构建不依赖个人绝对路径。软件统一以 RV32E/ILP32E 编译，
并对最终反汇编做项目 ISA 审计。

## 后果

仓库可独立构建和回归，软件 ABI 与硬件映射有明确所有权；代价是只维护任务实际
需要的 API，不承诺完整 AM 或 libc 兼容。新增运行时接口时必须先说明负载需求，
并同步 [`../architecture/software-abi.md`](../architecture/software-abi.md) 和测试。
