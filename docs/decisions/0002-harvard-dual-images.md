# ADR-0002：采用 Harvard 隔离与双镜像

- 状态：Accepted
- 日期：2026-09-14
- 类型：retrospective
- Supersedes：无
- Superseded by：无
- 追溯提交：[`ae56921`](https://github.com/Ethan-KaKa/DC-Chip/commit/ae56921)

## 背景

CPU 有独立取指和数据通道，软件同时需要只读代码区与可写数据、堆栈。单一平坦
镜像会模糊访问权限，并使镜像装载、越界检查和 FPGA 片上存储映射难以验证。

## 决策

IROM 与 DRAM 使用独立地址区和访问权限：IFU 只能从 IROM 取指，LSU 只能访问
DRAM/MMIO；软件构建分别产生 `.inst.bin` 与 `.data.bin`。仿真 loader 独立检查
两个 64 KiB 区域的格式和容量。

## 后果

跨区访问可确定地产生 access fault，链接脚本和启动代码成为硬件/软件契约的一部分。
代价是构建、仿真、参考模型和未来 FPGA 初始化都必须处理双镜像；若未来允许从
DRAM 执行或统一存储，必须新建 ADR 并同步修改地址、权限与验证。
