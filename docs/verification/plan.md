# DC-Chip 初版验证计划

- 版本：v0.1
- 状态：初版 CPU 基线及仿真调试基础设施步骤 0–8 已完成并归档
- 更新日期：2026-09-11
- ISA 规范：`docs/isa/isa.md` v0.1
- 仿真器接口：[`simulator.md`](simulator.md)

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
| F | Dconfig 配置基础设施 | `make test-config`；`make test` | 隔离配置测试、四种配置值/头文件编译、既有回归兼容 |
| G | 统一 Simulation 执行引擎 | `make test-simulation`；`make test-integration`；`make test` | 生命周期、周期/提交步进、停止优先级及 CLI 兼容 |
| H | ISA v0.1 最小反汇编器 | `make test-disasm`；`make test` | 8 条指令格式、规范字段、全部 16 位编码及 batch 输出兼容 |
| I | 编译期 VCD 波形 | `make test-wave`；`make test` | WAVE-off 零 VCD 代码、WAVE-on 时间轴/路径/暂停、CLI 兼容与错误处理 |
| J | 可配置 SDB 与 CLI 整合 | `make test-sdb`；`make test-wave`；`make test` | SDB-off batch 兼容、交互命令契约、断点恢复、SDB+WAVE 共用时间轴 |

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

HEX 镜像、DPI-C 边界、命令行参数、运行生命周期和退出码的稳定接口以
[`simulator.md`](simulator.md) 为准；本节只定义需要覆盖的验证场景。

正向测试包括：

- ISA smoke：提交 PC 为 `0,1,2,3,4,5,6,7`，最终 `R0=0x0000 R1=0x0002 R2=0x0002 R3=0x0000 PC=0x08`；
- jump-loop：提交 PC 为 `0,1,2,1,2`，最终 `R0=0x0000 R1=0x0003 R2=0x0000 R3=0x0000 PC=0x01`；
- 达到目标提交数后的组合越界预取不覆盖成功结果；
- 单步 trace 的首条指令为 `cycle=1 commit=1`，两个 reset 周期不进入用户计数；
- jump-loop 五条完整 trace 的周期、提交、PC、寄存器与 summary 逐字匹配。

负向测试包括保留 opcode、非规范编码、文件不存在、空镜像、非法字符、非 4 位数据、超过 256 个有效字、超时、最终状态失配、重复 expectation、未知参数和缺失参数。

SDB 定向测试另外覆盖提示符、帮助和 EOF，周期/提交步进，当前指令反汇编，
断点设置/去重/删除/稳定 ID/执行前命中及自跳转恢复，严格无符号数错误，命令
用法错误，非法/越界/timeout 状态，以及 WAVE 命令的幂等暂停和恢复。SDB-on
构建必须用 `--batch` 重跑既有 19 个 CLI 用例；SDB-off 的默认 batch 与显式
`--batch` 必须保持等价。

## 5. 退出码契约

| 退出码 | 条件 |
| --- | --- |
| 0 | 帮助输出，或达到目标提交数且所有 expectation 匹配 |
| 1 | CLI 或 HEX 加载错误 |
| 2 | 实际执行保留 opcode、非规范编码或越界取指返回的非法字 |
| 3 | 最大周期数耗尽 |
| 4 | 最终寄存器或 PC 不匹配 |

SDB 的 `q` 或 stdin EOF 返回 0；非法和越界取指仍返回 2，timeout 仍返回 3。
交互命令解析错误打印诊断后继续，不直接产生进程退出码。

负向 runner 必须比较精确退出码，不能只判断“非零”。失败消息至少包含相关 PC、指令、输入路径、输入行号或参数名之一。

## 6. 回归规则

- lint warning 视为失败，不使用全局 warning waiver 掩盖问题；
- 随机测试若加入，必须记录 seed；
- 超时必须为有限正整数；
- 修复协议或时序问题时不得增加无规范依据的延时、脉冲或跳过比较；
- 原始大日志、波形和生成物只进入 `/build/`，不得纳入版本管理；
- `make test` 固定按 config、disassembler、lint、unit、Simulation engine、CLI
  integration 顺序执行并在首个失败处停止。
- `make test-sdb` 和 `make test-wave` 使用各自隔离配置矩阵，不修改根 `.config`；
  二者作为配置专项回归独立执行。

## 7. 验证执行记录

### 阶段 A

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make check-tools` | PASS | GNU Make 4.3；Verilator 5.041 devel；Icarus/vvp 13.0 devel；G++ 13.3.0；C++17 syntax check PASS |
| 2026-09-10 | `make help` | PASS | 当前列出阶段 A–E 可用目标；目标本身不创建构建输出 |

### 阶段 B

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make lint-comb` | PASS | Verilator 5.041 devel；分别以 `alu`、`decoder` 为 top；零 warning、零 error |
| 2026-09-10 | `make test-alu` | PASS | Icarus/vvp 13.0 devel behavioral simulation；覆盖 5 种已分配操作、16 位加减回绕、3 个未分配值及 X/Z 操作码 |
| 2026-09-10 | `make test-decoder` | PASS | Icarus/vvp 13.0 devel behavioral simulation；覆盖 8 个规范示例、全部保留 opcode、各类非规范字段及 opcode/规范条件中的 X/Z |

阶段 A–B 的五条累计门禁已按顺序复跑并通过。两个 testbench 均为有限超时自检，成功时分别输出单行 `tb_alu: PASS` 和 `tb_decoder: PASS`。生成物仅位于被忽略的 `build/unit/`。

### 阶段 C

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make lint` | PASS | Verilator 5.041 devel；以 `cpu_core` 为 top，按 package、decoder、ALU、regfile、core 顺序检查；零 warning、零 error |
| 2026-09-10 | `make test-regfile` | PASS | Icarus/vvp 13.0 devel behavioral simulation；覆盖同步复位、写保持、`R0`–`R3`、双组合读、沿前/沿后值、复位优先及 debug 拼接 |
| 2026-09-10 | `make test-core` | PASS | Icarus/vvp 13.0 devel behavioral simulation；覆盖两周期复位、8 条 ISA smoke、JUMP loop、PC 回绕、连续 trace、非法冻结及 reset 恢复 |
| 2026-09-10 | `make test-unit` | PASS | 顺序递归执行 ALU、decoder、regfile、cpu_core；四项均返回 0 且各自输出单行 PASS |

阶段 A–C 的九条累计门禁已按顺序复跑并通过。四个 testbench 均为有限超时自检，生成物仅为被 `/build/` 忽略的 `build/unit/tb_alu.vvp`、`tb_decoder.vvp`、`tb_regfile.vvp` 和 `tb_cpu_core.vvp`。

### 阶段 D

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make sim-build` | PASS | Verilator 5.041 devel、G++ 13.3.0；package、decoder、ALU、regfile、core、wrapper 显式顺序构建；项目 C++ 源以 C++17、`-Wall -Wextra -Wpedantic` 检查；零 warning、零 error |
| 2026-09-10 | `Vsim_top --image sim/tests/isa_smoke.hex --steps 8 --trace ...` | PASS | Verilator behavioral simulation；提交 PC 为 `0,1,2,3,4,5,6,7`；最终 `R0=0x0000 R1=0x0002 R2=0x0002 R3=0x0000 PC=0x08` |
| 2026-09-10 | `Vsim_top --image sim/tests/jump_loop.hex --steps 5 --trace ...` | PASS | Verilator behavioral simulation；提交 PC 为 `0,1,2,1,2`；最终 `R0=0x0000 R1=0x0003 R2=0x0000 R3=0x0000 PC=0x01` |

阶段 A–D 的十二条累计门禁已按顺序复跑并通过。两个程序均返回 0；smoke 的最后一次合法提交后，PC `0x08` 的组合越界预取未覆盖成功结果。Verilator 生成物仅位于被 `/build/` 忽略的 `build/verilator/`。

### 阶段 E

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make test-integration` | PASS | Verilator behavioral simulation；17 个用例逐项核对精确退出码：成功/帮助为 0，CLI/HEX 错误为 1，非法或越界取指为 2，超时为 3，状态失配为 4 |
| 2026-09-10 | `make test` | PASS | 按 lint、四个 Icarus 模块测试、Verilator 集成测试顺序执行；全部返回 0 |
| 2026-09-10 | `make clean && make test` | PASS | 从空的默认 `build/` 重新生成四个 `.vvp` 和 `Vsim_top` 后重复通过 17 个集成用例；构建零 warning、零 error |

阶段 A–E 的十五条累计门禁均已通过。阶段 E runner 覆盖两个正向程序、保留 opcode、非规范编码、实际越界取指、文件不存在、空镜像、非法字符、错误宽度、257 个有效字、超时、状态失配、重复 expectation、未知参数、缺少参数值和缺少必选镜像。

Vivado 综合/实现、时序、资源、功耗和真实板卡仍未验证。

### 阶段 F：仿真调试基础设施步骤 0–1

步骤 0 在引入配置前冻结阶段 A–E 基线：

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make check-tools` | PASS | GNU Make 4.3；Verilator 5.041 devel；Icarus/vvp 13.0 devel；G++ 13.3.0 |
| 2026-09-10 | `make test` | PASS | RTL lint、4 个模块 testbench 和 17 个精确退出码集成用例全部通过；Verilator 为 `VM_TRACE=0` |

该基线锁定两周期同步 reset 且不计入执行周期、`--steps` 按 `trace_valid`
提交计数、最后一次目标提交优先于提交后的组合越界预取，以及退出码
`0/1/2/3/4` 和既有 trace/summary/错误格式。步骤 1 不修改这些期望来掩盖
差异。

步骤 1 的配置测试使用
`build/test-fixtures/config/.config` 和
`build/test-fixtures/config/generated/`，不读写仓库根 `.config`：

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make check-tools` | PASS | 增加 Python 3.12.3 与标准库 `curses` import；原有工具及 C++17 检查保持通过 |
| 2026-09-10 | `make help`（无 `.config`、无 `build/`） | PASS | 未创建 `.config` 或 `build/` |
| 2026-09-10 | `make test-config` | PASS | default/set/show/sync、错误输入事务性、文件错误、mtime、路径隔离、vendored menuconfig/curses import、四种配置值及 C++17 头文件编译均通过 |
| 2026-09-10 | `make test` | PASS | 配置测试、RTL lint、4 个模块 testbench 与原有 17 个集成用例通过；默认配置仍为 `VM_TRACE=0` |

Kconfiglib 固定为 v14.1.0，三个上游原文件的 SHA-256 已与
`tools/kconfiglib/UPSTREAM.md` 一致。步骤 1 仅验证配置值传递和 C++ 编译；
SDB、VCD 波形、执行引擎、反汇编功能均未实现。Vivado 综合/实现、时序、
资源、功耗和真实板卡仍未验证。

### 阶段 G：仿真调试基础设施步骤 2

步骤 2 将模型生命周期、reset、稳定低电平周期推进、仿真时间、周期/提交计数
和停止分类统一收敛到 `Simulation`。独立引擎测试使用
`build/verilator-test/`，不与正式 CLI 的 Verilator Mdir 混用。CLI 保持原参数、
输出与退出码，并逐次按提交调用指令步进接口。

执行引擎自检覆盖 reset 状态和计数、单周期提交、jump-loop 五次指令步进、
周期/提交目标、执行前断点、普通非法、实际越界、绝对全局 timeout、末次合法
提交优先级，以及未 reset 执行和重复 reset 的明确失败。CLI runner 保留原有
17 个退出码用例，并增加单步与 jump-loop 精确 trace，总计 19 个用例；同时对
成功 summary、trace、普通非法、越界、timeout 和状态失配执行精确文本断言。

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-10 | `make check-tools`；修改前 `make test` | PASS | GNU Make 4.3；Verilator 5.041 devel；Icarus/vvp 13.0 devel；G++ 13.3.0；修改前 17 项基线全部通过 |
| 2026-09-10 | `make help`（临时移开 `.config` 且清空 `build/`） | PASS | 未创建 `.config` 或 `build/`，随后原样恢复本地配置 |
| 2026-09-10 | `make test-simulation` | PASS | 独立 Mdir 直接验证 Simulation 生命周期、步进、停止原因与误用路径 |
| 2026-09-10 | `make test-integration` | PASS | 19 个 CLI 用例精确退出码全部通过，新增两项精确 trace 及六类精确文本断言 |
| 2026-09-10 | `make test` | PASS | config、RTL lint、4 个模块 testbench、Simulation engine 和 CLI integration 全部通过 |
| 2026-09-10 | `make clean && make test` | PASS | 从空 `build/` 重建两个隔离的 Verilator Mdir；默认配置为 `n/n` 且正式 CLI 为 `VM_TRACE=0` |
| 2026-09-10 | `git diff --check` | PASS | 本任务源码与文档变更无 whitespace error |

步骤 2 不实现或启用 SDB、断点恢复策略、反汇编或 VCD，也不修改 RTL、ISA、
DPI 接口、HEX 格式或软件 ABI。Vivado 综合/实现、时序、资源、功耗和真实板卡
仍未验证。

### 阶段 H：仿真调试基础设施步骤 3

步骤 3 新增与 DUT 状态无关的纯 C++17 最小反汇编接口。它覆盖 ISA v0.1 的
8 条指令并重复执行规范字段检查；保留 opcode 和已分配 opcode 的非规范编码
统一输出 `.word 0xXXXX`，不产生合法别名。该接口尚未接入 batch trace，原有
CLI 文本和退出码保持不变。

反汇编自检先逐项核对手册中的 8 个示例，再穷举全部 65,536 个 16 位指令字。
其中 2,384 个规范编码必须生成精确汇编，其余 63,152 个编码必须生成精确
`.word`。测试使用独立的 C++17 可执行文件，不创建或驱动 Verilator 模型。

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-11 | `make test-disasm` | PASS | G++ 13.3.0；`-Wall -Wextra -Wpedantic`；8 个规范样例及全部 65,536 个编码通过 |
| 2026-09-11 | `make test` | PASS | config、disassembler、RTL lint、4 个模块 testbench、Simulation engine 和 19 个 CLI 用例全部通过 |
| 2026-09-11 | `make clean`；`make test` | PASS | 从空 `build/` 重建；反汇编穷举、两个隔离的 Verilator 构建及既有回归全部通过 |
| 2026-09-11 | `git diff --check`；新文件独立 `--check` | PASS | 已跟踪 diff 和 3 个新增 C++ 文件均无 whitespace error |

步骤 3 不实现或启用 SDB、断点恢复或 VCD，也不修改 RTL、ISA、DPI 接口、
HEX 格式、batch trace、退出码或软件 ABI。Vivado 综合/实现、时序、资源、
功耗和真实板卡仍未验证。

### 阶段 I：仿真调试基础设施步骤 4

步骤 4 将 `DC_SIM_WAVE` 接入 Verilator 和统一 `Simulation` 时间轴。关闭配置
不编译或链接 VCD；开启配置从首个 reset 边沿前的时间 0 开始，将唯一波形
截断写入由真实可执行文件推导的 `<BUILD_DIR>/dump.vcd`。暂停记录只形成时间戳
间隙，不改变 CPU 推进、体系结构状态、周期/提交计数或停止结果。

`make test-wave` 使用 `build/test-fixtures/wave/off/` 和 `on/` 下的配置与构建
目录。WAVE-off 检查两个 Verilator Mdir 均为 `VM_TRACE=0`、
`VM_TRACE_VCD=0`，不存在 VCD 实现产物或波形；WAVE-on 检查对应值均为 1、
时间 0/reset/执行双边沿、暂停两周期后的时间戳间隙、固定路径、截断覆盖、
状态等价、模型创建前错误不产生波形、19 个 CLI 用例兼容，以及不可打开目标
返回 1 并报告完整路径。

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-11 | `make check-tools` | PASS | GNU Make 4.3；Verilator 5.041 devel；Icarus/vvp 13.0 devel；G++ 13.3.0；Python 3.12.3 |
| 2026-09-11 | `make test-wave` | PASS | 隔离 WAVE-off/on 正式 CLI 和执行引擎构建；WAVE-on 复跑 19 个精确 CLI 用例 |
| 2026-09-11 | `make test` | PASS | 默认 `DC_SIM_WAVE=n`；config、disassembler、RTL lint、4 个模块测试、执行引擎和 19 个 CLI 用例全部通过 |
| 2026-09-11 | `make clean`；`make test` | PASS | 从空 `build/` 干净重建；正式 CLI 和执行引擎均为 `VM_TRACE=0`、`VM_TRACE_VCD=0` |
| 2026-09-11 | `git diff --check` | PASS | 本步骤源码、测试、Make、Dconfig 与正式文档无 whitespace error |

步骤 4 不实现 SDB、断点恢复或 SDB `wave` 命令，也不修改 RTL、ISA、DPI、
HEX 格式、batch 文本输出或软件 ABI。Vivado 综合/实现、时序、资源、功耗和
真实板卡仍未验证。

### 阶段 J：仿真调试基础设施步骤 5–8

步骤 5–6 将配置期 SDB 接入正式仿真器。SDB、batch 和 VCD 复用统一
`Simulation` 时间轴；SDB 只以单周期 `run_until()` 调用推进模型。执行前断点
由按 ID 排序的表和 PC 去重索引维护，刚命中的 PC 在下一次执行命令中临时
抑制，并在对应指令提交后立即恢复，因此 jump loop 返回相同 PC 时会再次命中。

`make test-sdb` 在 `build/test-fixtures/sdb/` 中隔离构建 SDB-off、SDB-only 和
SDB+WAVE。测试逐字检查提示符、帮助、状态、步进、断点和错误诊断；检查
SDB-off 不编译或链接 SDB/反汇编对象；在 SDB-on 上以 `--batch` 重跑 19 个
既有 CLI 用例；并验证 WAVE 命令幂等、暂停时间戳间隙和体系结构状态等价。

步骤 7 用 SDB-off、SDB-only、WAVE-only 和 SDB+WAVE 四种隔离构建完成配置、
执行控制、SDB、波形及 batch 兼容验证。步骤 8 将稳定接口、生命周期、错误
契约和实测结果归档到正式验证文档；临时实施计划完成使命后删除，不作为长期
规范源。

| 日期 | 命令 | 结果 | 环境或备注 |
| --- | --- | --- | --- |
| 2026-09-11 | `make check-tools` | PASS | GNU Make 4.3；Verilator 5.041 devel；Icarus/vvp 13.0 devel；G++ 13.3.0；Python 3.12.3 |
| 2026-09-11 | `make help` | PASS | 列出 SDB、`BATCH=1` 及隔离测试入口 |
| 2026-09-11 | `make test-sdb` | PASS | 三种隔离构建及 SDB 命令、CLI、断点、波形用例全部通过 |
| 2026-09-11 | `make test-wave` | PASS | WAVE-off/on 专项回归及 19 个既有 CLI 用例通过 |
| 2026-09-11 | `make test` | PASS | 默认 SDB/WAVE 均关闭；配置、反汇编、RTL、引擎和 19 个 CLI 用例通过 |
| 2026-09-11 | `make clean`；`make test` | PASS | 从空 `build/` 完整重建默认配置并通过 |
| 2026-09-11 | `git diff --check` | PASS | 本步骤源码、测试、Make、Dconfig 与正式文档无 whitespace error |

步骤 5–8 不实现 watchpoint、表达式、内存扫描、寄存器修改、readline、命令
别名、ftrace、difftest 或新 ISA 指令，也不修改 RTL、DPI、HEX、存储映射或
软件 ABI。Vivado 综合/实现、时序、资源、功耗和真实板卡仍未验证。

## 8. 后续方向与验证

仿真调试基础设施归档后，按以下顺序推进：

1. 建立集中维护的指令编码工具，并让编码器与反汇编器共享 ISA 测试向量；
2. 实现独立的自定义 ISA 参考模型和逐提交差分测试；
3. 决定数据存储、MMIO 地址图与取指握手扩展，并先更新正式规格；
4. 按规格实现最小 SoC、timer/GPIO/UART 和周期性传感演示。

软件测试、Vivado 综合/实现、post-implementation timing、功耗分析和真实板卡
验收均为 `TODO`。ISA 扩展或核心引入流水线后，应优先扩大逐提交 PC/寄存器
差分检查。
