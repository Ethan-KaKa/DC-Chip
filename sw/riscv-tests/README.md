# RISC-V RV32E 回归适配套件

本目录使用固定的 `riscv-tests-am` RV32UI 源码和 DC-Chip AM 运行时，覆盖当前 ISA
表所列全部非 `fence` 基础指令，并由本地最小程序补充 `fence`。使用：

```bash
make sw riscv-tests list
make sw riscv-tests ALL=addi,lw
make sw riscv-tests batch
```

构建产物仅写入 `build/sw/riscv-tests/`；`vendor/` 是只读输入。测试结果由现有
`tohost` 退出通道判定，未实现签名比对或 RISCOF 认证。上游 commit、许可证和桥接
边界见 [`UPSTREAM.md`](UPSTREAM.md)。
