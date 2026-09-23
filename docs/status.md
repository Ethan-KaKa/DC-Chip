# 当前状态

- 快照日期：2026-09-23
- 证据范围：RTL lint/behavioral simulation、Verilator、软件回归与差分测试
- FPGA 综合、实现、时序、资源、功耗与真实上板：**未验证**

## 已实现

- CPU：顺序单发射、一次最多一条在途指令；实现
  [`isa/isa.md`](isa/isa.md) 定义的 RV32E v1.0 基础整数指令及严格
  `x0`--`x15` 边界，fault 粘滞至 reset。
- 存储：64 KiB IROM（`0x00000000`）与 64 KiB DRAM（`0x20000000`）Harvard
  隔离，使用独立 `.inst.bin` / `.data.bin` 镜像；协议 controller 与可替换
  `irom`/`dram` 叶子分离，仿真私有 `tohost` 位于 `0xfffffff0`。
- SoC：MMIO UART、16 位 LED、Buttons 输入与八位十六进制七段数码管；CPU/内存
  与外设之间提供同步直通或异步 toggle-handshake CDC 路径。
- 软件：仓库内自包含 AM-like 运行时、`klib`、格式化输出、设备抽象、ISA 审计、
  定向测试、AM-kernels 工作负载与 UART/LED/SEG7 演示路径。
- 验证：Icarus/Verilator 模块自检、C++ 独立参考模型、可选 Spike backend、逐提交
  difftest、MMIO `is_skip_ref` 同步、SDB、VCD 和 NVBoard。
- 构建：`make help` 提供入口，`make list` 动态发现测试；`make test` 使用隔离默认
  配置运行默认三层回归。

## 未完成或未决

- timer、sensor、睡眠/唤醒、中断和对应演示尚未规格化或实现。
- 板卡厂商型号、完整 part、package、speed grade、输入时钟、复位极性、真实引脚
  和 PS 职责仍为 `TODO`，详见 [`fpga/board.md`](fpga/board.md)。
- Vivado 可复现工程、综合/实现、bitstream、ILA 和真实 Zynq-7020 验收未实现。
- RV32E ISA 回归：固定 `riscv-tests-am` RV32UI 源码快照，通过 AM/`tohost` 运行
  当前 ISA 表所列全部非 `fence` 指令用例及本地 `fence` 自检；这不是 signature 比对或 RISCOF
  认证，来源与兼容边界见 [`../sw/riscv-tests/UPSTREAM.md`](../sw/riscv-tests/UPSTREAM.md)。

## 最近验证快照

本节只记录实际执行结果；具体测试名称始终通过 `make list` 动态查询。

- 2026-09-14：`make check-paths` PASS。
- 2026-09-14：`make testinfra ALL=make-cli,repo-rules` 2/2 PASS；规则检查器的
  隔离用例覆盖正常/断裂/外部/fragment 链接、重命名、删除、临时内容引用与误跟踪。
- 2026-09-14：`make testunit list`、`make testinfra list`、`make sw tests list`
  均成功输出当前动态清单。
- 2026-09-14：`make test` PASS：13/13 RTL 单元与 lint、13/13 默认基础设施、
  21/21 软件系统测试和 38/38 pinned RV32E ISA 回归。使用
  `build/test-fixtures/full-regression/` 下的隔离 default defconfig；未运行可选 Spike
  回归。
- 2026-09-23：`rtl/core` 模块边界整理后 `make test` PASS：15/15 RTL 单元与
  lint、13/13 默认基础设施、21/21 软件系统测试和 38/38 pinned RV32E ISA
  回归。新增 execute 与 LSU 定向单测；使用隔离 default defconfig，未运行可选
  Spike 回归。
- 2026-09-23：`rtl/soc` 模块边界整理后，`dc_soc_top` 成为自包含 SoC，行为
  IROM/DRAM 可由同端口 Vivado IP 替换；`make check-paths` PASS，`make test` PASS：
  15/15 RTL 单元与 lint、13/13 默认基础设施、21/21 软件系统测试和 38/38 pinned
  RV32E ISA 回归。Vivado 综合、IP 参数核对、post-synth、post-implementation 与
  上板仍未执行。

历史八指令 v0.2 是演进过程，不是当前能力。v0.1 可执行基线冻结于
[`9bfb9a9`](https://github.com/Ethan-KaKa/DC-Chip/commit/9bfb9a97153be05de34c6d2311c09f41cb6f43ab)，
其余历史从 Git 提交恢复。
