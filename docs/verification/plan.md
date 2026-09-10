# DC-Chip 初版验证计划

- 版本：v0.1
- 状态：初版 CPU 实施基线
- 更新日期：2026-09-10
- ISA 规范：`docs/isa/isa.md` v0.1

## 1. 验证目标与证据边界

验证目标是证明初版 RTL 与 ISA v0.1、微架构及存储映射一致，并使所有成功和失败路径可由进程退出码自动判断。

Icarus 和 Verilator 的通过结果只标记为 behavioral simulation。lint、模块仿真或端到端仿真均不能证明综合、post-synth、post-implementation、时序收敛、资源、功耗或 FPGA 上板成功；这些证据在实际板卡和 Vivado 流程确定前均为“未验证”。

## 2. 累积门禁

| 阶段 | 实施内容 | 顺序门禁 | 主要验收 |
| --- | --- | --- | --- |
| A | 正式规格、package、构建骨架 | `make check-tools`；`make help` | 工具可用，规格一致，无生成物 |
| B | decoder、ALU 及单测 | `make lint-comb`；`make test-alu`；`make test-decoder` | ALU 边界、8 条合法 opcode、8 个保留 opcode 和非规范字段 |
| C | regfile、cpu_core 及单测 | `make lint`；`make test-regfile`；`make test-core`；`make test-unit` | reset、R0、PC、trace、非法冻结与恢复 |
| D | DPI-C 端到端闭环 | `make sim-build`；smoke；jump-loop | 精确 trace、最终状态和组合越界预取处理 |
| E | 完整正负回归 | `make test-integration`；`make test`；`make clean && make test` | 精确退出码和干净重建 |

阶段必须顺序完成。任一命令失败后立即停止，不运行当前阶段的后续命令，也不进入下一阶段。修复后先重跑失败项，再从阶段 A 起重跑截至当前阶段的所有累计门禁。

## 3. 模块级验证

所有 testbench 必须自检、设置有限超时，并用 `$fatal(1, ...)` 报告失败。成功时打印单行 PASS 并返回 0。

| 对象 | 必测内容 |
| --- | --- |
| ALU | PASS_B；ADD/SUB 正常与 16 位回绕；AND/OR 边界；非法操作返回零 |
| decoder | 8 条合法编码；8 个保留 opcode；全部规范字段限制；含 X opcode 的安全输出 |
| regfile | 同步复位；`R0`–`R3` 可写；双组合读；沿前旧值/沿后新值；复位优先；debug 拼接 |
| cpu_core | 两周期复位；ISA smoke；JUMP；PC 回绕；逐提交 trace；非法不提交、冻结及复位恢复 |

## 4. 集成验证

正向测试包括：

- ISA smoke：提交 PC 为 `0,1,2,3,4,5,6,7`，最终 `R0=0x0000 R1=0x0002 R2=0x0002 R3=0x0000 PC=0x08`；
- jump-loop：提交 PC 为 `0,1,2,1,2`，最终 `R0=0x0000 R1=0x0003 R2=0x0000 R3=0x0000 PC=0x01`；
- 达到目标提交数后的组合越界预取不覆盖成功结果。

负向测试包括保留 opcode、非规范编码、文件不存在、空镜像、非法字符、非 4 位数据、超过 256 个有效字、超时、最终状态失配、重复 expectation、未知参数和缺失参数。

## 5. 退出码契约

| 退出码 | 条件 |
| --- | --- |
| 0 | 帮助输出，或达到目标提交数且所有 expectation 匹配 |
| 1 | CLI 或 HEX 加载错误 |
| 2 | 实际执行保留 opcode、非规范编码或越界取指返回的非法字 |
| 3 | 最大周期数耗尽 |
| 4 | 最终寄存器或 PC 不匹配 |

负向 runner 必须比较精确退出码，不能只判断“非零”。失败消息至少包含相关 PC、指令、输入路径、输入行号或参数名之一。

## 6. 回归规则

- lint warning 视为失败，不使用全局 warning waiver 掩盖问题；
- 随机测试若加入，必须记录 seed；
- 超时必须为有限正整数；
- 修复协议或时序问题时不得增加无规范依据的延时、脉冲或跳过比较；
- 原始大日志、波形和生成物只进入 `/build/`，不得纳入版本管理；
- `make test` 固定按 lint、unit、integration 顺序执行并在首个失败处停止。

## 7. 验证执行记录

### 阶段 A

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make check-tools` | PASS | GNU Make 4.3；Verilator 5.041 devel；Icarus/vvp 13.0 devel；G++ 13.3.0；C++17 syntax check PASS |
| 2026-09-10 | `make help` | PASS | 列出阶段 A 可用目标和后续规划目标；未创建 `build/` |

阶段 B–E：未执行。

## 8. 后续验证

独立参考模型、软件测试、Vivado 综合/实现、post-implementation timing、功耗分析和真实板卡验收均为 `TODO`。ISA 扩展或核心引入流水线后，应优先增加逐提交 PC/寄存器差分检查。
