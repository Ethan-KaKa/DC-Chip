# DC-Chip 验证计划

- 版本：v0.2
- 状态：v0.2 阶段 1 核心与仿真全链路已完成迁移与验证闭环
- 更新日期：2026-09-11
- ISA 规范：`docs/isa/isa.md` v0.2
- 仿真器接口：[`simulator.md`](simulator.md)

## 1. 验证目标与过渡状态

目标是用自检测试和独立参考模型证明 RV32E 过渡子集 v0.2 的编码、寄存器、
控制流、数据访问、stall、提交与 fault 行为一致，并让所有成功和失败路径可由
结构化结果及进程状态自动判断。

当前仓库状态：

| 层次 | 状态 | 能作为何种证据 |
| --- | --- | --- |
| v0.2 ISA/微架构/存储规格 | 已冻结 | 正式规格源与验收依据 |
| ISA package、decoder、编码器、反汇编器 | 已迁移至 v0.2 | `make test-isa` 的公共层专项证据 |
| ALU、regfile、core | 已迁移至 v0.2 | `make lint` 与 `make test-unit` 的模块级 behavioral simulation 证据 |
| 仿真存储与 32 位 HEX loader | 已迁移至 v0.2 | `make lint-mem` 与 `make test-memory` 的存储子系统证据 |
| Verilator wrapper、Simulation、SDB | 已迁移至 v0.2 | `make sim-build`、`make test-simulation`、`make test-wave`、`make test-sdb` |
| v0.2 独立参考模型与 lockstep difftest | 已迁移至 v0.2 | `make test-reference` 与 `make test-difftest` 独立验证证据 |
| v0.2 CLI 22 项集成与全回归 | 已迁移至 v0.2 | `make test-integration` 与 `make test` 端到端闭环证据 |
| Vivado、时序、资源、功耗、上板 | 未验证 | 不能从 behavioral simulation 推断 |

步骤 2.5 完成后，`make test` 恢复为全部测试的最高层累计回归入口；
已建立涵盖编码、模块、存储、独立参考模型、difftest 和端到端 CLI 的完整证据闭环。

## 2. v0.1 迁移前冻结记录

### 2.1 冻结点

- Git commit：`9bfb9a97153be05de34c6d2311c09f41cb6f43ab`
- 分支：`main`
- 工作树：迁移前预检为 clean
- 日期：2026-09-11
- 工具：GNU Make 4.3、Verilator 5.041 devel、Icarus/vvp 13.0 devel、
  G++ 13.3.0、Python 3.12.3、Kconfiglib 14.1.0
- 冻结命令：`make check-tools && make test`
- 结果：PASS；仅覆盖 v0.1

该提交是可执行 v0.1 基线的唯一长期恢复点。仓库不复制第二套 v0.1 规格，也不
增加双 ISA 开关。

### 2.2 已归档的 v0.1 累积执行记录

下表保留原阶段 A--J 的已执行证据；结果均是 behavioral simulation 或构建
门禁，不代表综合或硬件结果。

| 日期 | 命令/阶段 | 结果 | 已验证内容 |
| --- | --- | --- | --- |
| 2026-09-10 | `make check-tools`；`make help` | PASS | 阶段 A 工具和构建入口 |
| 2026-09-10 | `make lint-comb`；`make test-alu`；`make test-decoder` | PASS | 阶段 B，16 位 ALU、8 个 v0.1 opcode、保留/非规范编码 |
| 2026-09-10 | `make lint`；`make test-regfile`；`make test-core`；`make test-unit` | PASS | 阶段 C，4×16-bit regfile、单周期 core、reset/trace/非法冻结 |
| 2026-09-10 | `make sim-build`；ISA smoke；jump-loop | PASS | 阶段 D，DPI-C 取指、逐提交 trace 和最终状态 |
| 2026-09-10 | `make test-integration`；`make test`；`make clean && make test` | PASS | 阶段 E，17 个 CLI 用例及干净重建 |
| 2026-09-10 | `make test-config`；`make test` | PASS | 阶段 F，隔离 Dconfig、四种配置值和旧回归兼容 |
| 2026-09-10 | `make test-simulation`；`make test-integration`；`make test` | PASS | 阶段 G，Simulation 生命周期/停止优先级及 19 个 CLI 用例 |
| 2026-09-11 | `make test-disasm`；`make test` | PASS | 阶段 H，穷举 65,536 个 v0.1 指令字，其中 2,384 个规范编码 |
| 2026-09-11 | `make test-wave`；`make test`；`make clean && make test` | PASS | 阶段 I，WAVE-off/on、VCD 时间轴/路径和 CLI 兼容 |
| 2026-09-11 | `make test-sdb`；`make test-wave`；`make test` | PASS | 阶段 J，SDB-off/SDB-only/SDB+WAVE、断点及 batch 兼容 |
| 2026-09-11 | `git diff --check` | PASS | 各已归档阶段的源码和文档 whitespace 检查 |

v0.1 的精确 CLI、SDB、VCD、HEX 和退出码契约继续记录在
[`simulator.md`](simulator.md) 的“当前实现”部分，供迁移定位回归使用。

### 2.3 v0.2 规格冻结后的防回归记录

| 日期 | 命令 | 结果 | 证据边界 |
| --- | --- | --- | --- |
| 2026-09-11 | `make check-tools` | PASS | 工具版本与 2.1 节一致；curses import 和 C++17 syntax check 通过 |
| 2026-09-11 | `make test` | PASS | config、v0.1 反汇编穷举、RTL lint、4 个模块 testbench、Simulation 和 19 个 CLI 用例通过 |
| 2026-09-11 | `git diff --check` | PASS | 本次规格与 `AGENTS.md` 修改无 whitespace error |

这组结果发生在正式规格切换到 v0.2 之后，但被测代码没有随之迁移，因此仍只
是 v0.1 防回归证据，不是 v0.2 功能验收。

### 2.4 v0.2 ISA 公共层迁移记录

| 日期 | 命令 | 结果 | 证据边界 |
| --- | --- | --- | --- |
| 2026-09-11 | `make test-isa` | PASS | 测试编码器/HEX、GNU 编码与反汇编交叉校验、decoder lint/自检、C++ 反汇编专项 |
| 2026-09-11 | `make lint` | EXPECTED FAIL | v0.1 ALU 枚举和 core decoder 端口尚未迁移，确认步骤 2.3 的明确恢复边界 |

默认交叉工具为 GCC 13.3.0 和 GNU binutils 2.42，调用参数为
`-march=rv32e -mabi=ilp32e`，可分别通过 `RISCV_GCC` 和 `RISCV_OBJDUMP`
覆盖。该记录只证明 ISA 公共层，不覆盖 ALU、regfile、core、存储协议、
Simulation、SDB、difftest、综合或 FPGA。

### 2.5 v0.2 核心与存储协议迁移记录

| 日期 | 命令 | 结果 | 证据边界 |
| --- | --- | --- | --- |
| 2026-09-11 | `make check-tools` | PASS | 工具版本、Python curses 与 C++17 可用性 |
| 2026-09-11 | `make test-isa` | PASS | v0.2 编码、decoder 与反汇编公共层未回归 |
| 2026-09-11 | `make lint-comb`；`make lint` | PASS | 32 位 ALU、decoder、regfile 和握手式 core 通过 Verilator lint |
| 2026-09-11 | `make test-unit` | PASS | ALU、decoder、16×32-bit regfile、八指令执行、双通道握手和七类 fault 的模块级自检 |
| 2026-09-11 | `git diff --check` | PASS | 本步骤源码、测试和正式文档无 whitespace error |

core BFM 覆盖请求背压、请求接受当周期响应、延迟响应、四个 byte lane、I/S/U
立即数边界、`jalr rd==rs1`、错误响应、fault 粘滞和 reset 取消。store 的真实
内存副作用与仿真镜像已由步骤 2.4 补全；程序执行、SDB 和 difftest 仍待步骤 2.5；
本记录只属于 lint 与模块级 behavioral simulation。

### 2.6 v0.2 仿真存储与 tohost 迁移记录

| 日期 | 命令 | 结果 | 证据边界 |
| --- | --- | --- | --- |
| 2026-09-11 | `make lint-mem` | PASS | `sim_mem.sv` 仿真存储 RTL 通过 Verilator lint 检查 |
| 2026-09-11 | `make test-memory` | PASS | 32 位 8 字符 HEX 解析、IROM 同周期读/越界、DRAM 1-cycle 同步读/read-first/4-bit strobe/背压保持、`tohost=0xfffffff0` 退出与 reset 冲刷 |
| 2026-09-11 | `git diff --check` | PASS | 本步骤存储源码、测试和文档无 whitespace error |

### 2.7 v0.2 仿真器、SDB、参考模型与 Difftest 迁移记录

| 日期 | 命令 | 结果 | 证据边界 |
| --- | --- | --- | --- |
| 2026-09-11 | `make test-reference` | PASS | C++17 独立参考模型算术、访存、control/tohost 与七类 fault 单元测试 |
| 2026-09-11 | `make test-simulation` | PASS | Simulation 驱动引擎 16 寄存器快照、tohost 判定与 fault 采样自检 |
| 2026-09-11 | `make test-difftest` | PASS | RTL 与参考模型 lockstep 差分测试（定向测试、固定 seed 伪随机与 fault 比对） |
| 2026-09-11 | `make test-integration` | PASS | 22 项端到端 CLI 集成测试（覆盖退出码 0, 1, 2, 3, 4, 5 及全部错误诊断） |
| 2026-09-11 | `make test-wave` | PASS | WAVE-off/on 编译隔离、VCD 时间轴一致性与 CLI 回归 |
| 2026-09-11 | `make test-sdb` | PASS | SDB-off/on/wave 模式、交互命令、断点、非法指令停机与 CLI 回归 |
| 2026-09-11 | `make test` | PASS | config、ISA、disasm、lint、unit、memory、ref、sim、difftest、integration 全回归 |
| 2026-09-11 | `git diff --check` | PASS | 本步骤源码、测试与文档无 whitespace error |

本步骤证明了端到端仿真器、SDB 调试器、C++ 独立参考模型与 lockstep difftest 的完整实现。

## 3. v0.2 验收矩阵

| 类别 | 必测内容 | 主要方法 |
| --- | --- | --- |
| 编码 | 八条指令的标准 `opcode/funct3/funct7` 与格式；其他编码非法 | **已完成**：decoder 定向与功能码空间枚举（`make test-isa`） |
| 寄存器 | `x0` 恒零并忽略写；`x1`--`x15` 读写/reset | **已完成**：regfile 全寄存器与 core `rd=x0` 访问（`make test-regfile`） |
| RV32E 上界 | 实际 `rd/rs1/rs2` 使用 `x16`--`x31` 时非法 | **已完成**：decoder/反汇编逐字段拒绝（`make test-decoder`） |
| `lui` 特例 | 只检查 `rd`；立即数中与 `rs1/rs2` 重叠的位不得误判 | **已完成**：公共层定向测试（`make test-isa`） |
| 立即数 | I/S 拼接、`-2048/-1/0/2047`，U 型最低 12 位清零 | **已完成**：decoder、编码器与 core 边界执行（`make test-unit`） |
| 算术 | `add/addi` 只保留低 32 位，正负溢出均不 fault | **已完成**：ALU 边界、core 写回与参考模型（`make test-alu`、`make test-reference`） |
| load | `lw` 小端与四字节对齐；`lbu` 任意 lane、零扩展；`rd=x0` 仍访问 | **已完成**：32 位小端、LBU 零扩展、DRAM 同步读与 read-first（`make test-memory`） |
| store | `sw` 四 lane；`sb` 单 lane；错误响应无部分副作用 | **已完成**：4 位 byte-enable、握手沿生效、未映射无副作用（`make test-memory`） |
| `jalr` | 旧 `rs1`、`rd==rs1`、`pc+4`、清 bit 0、bit 1 对齐 fault | **已完成**：core 定向测试与 difftest 比对（`make test-core`、`make test-difftest`） |
| 取指 | 32 位 byte PC、每次 `+4`、四字节对齐、访问错误 | **已完成**：core 取指 BFM 与 IROM 协议自检（`make test-core`、`make test-memory`） |
| fault | 七种 cause、PC/指令字段、无提交/写回、粘滞、reset 恢复 | **已完成**：core fault 注入、存储 access fault 与 CLI 报告（`make test-unit`、`make test-integration`） |
| stall | 请求/响应任意背压、payload 稳定、无丢失/重复、最多一个在途 | **已完成**：背压保持、存储在握手沿写入（`make test-memory`） |
| reset | 未握手请求取消、已握手旧响应冲刷、不接收迟到响应 | **已完成**：在途事务撤销与未完成 store 丢弃（`make test-core`、`make test-memory`） |
| trace/debug | 32 位 PC/指令、每条成功指令一次提交、索引读取 16×32 位状态 | **已完成**：32 位 trace 捕获、debug regfile 读取（`make test-simulation`） |
| tohost/镜像 | 8 字符 HEX 加载、`tohost=0xfffffff0` 退出码捕获 | **已完成**：`make test-memory`、`make test-integration` 覆盖 0 与非 0 退出 |
| 程序 | 八指令 smoke、load/store lane、JALR loop、fault 负向镜像 | **已完成**：Verilator 22 项 CLI 集成与波形测试（`make test-integration`、`make test-wave`） |
| 参考模型 | 与 RTL 独立实现，逐提交比较 PC/寄存器/内存副作用/fault | **已完成**：C++ 独立参考模型与 lockstep difftest（`make test-reference`、`make test-difftest`） |

## 4. 模块与协议测试要求

所有 testbench 必须自检、具有有限 timeout，以非零状态报告失败，并给出最小
定位上下文。模块级顺序为：格式/lint、decoder/立即数、ALU、regfile、控制器
协议、core；失败时先在最小层级修复和复跑。

握手测试必须分别在请求和响应侧插入 0、1、多周期及伪随机 stall，并断言：

- `valid && !ready` 期间所有 payload 稳定；
- 一次请求恰好对应一次响应，不重复提交或访问；
- load/store 等待期间 PC、写回和 trace 不提前变化；
- misaligned 数据访问不发出请求；
- 错误响应不产生寄存器或内存副作用；
- reset/fault 后不接受旧响应或继续发请求。

随机测试必须打印并保留 seed；timeout 必须为有限正整数。不得通过增加无规范
依据的延时、脉冲或跳过比较来制造通过。

## 5. 独立参考模型与 difftest

参考模型必须根据 `docs/isa/isa.md` 独立实现，不能调用 RTL decoder 或复用
RTL 执行逻辑。可以借鉴 NEMU 的组织方法，但不能直接把完整 RV32 语义或 NEMU
异常环境当作本项目 v0.2 的执行结果。

每次 RTL `trace_valid` 后至少比较：

- 提交 PC 和 32 位指令；
- `x0`--`x15` 全部寄存器；
- 本条指令成功产生的内存写地址、宽度、lane 和数据；
- 下一 PC。

fault 路径比较 `fault_cause/fault_pc/fault_inst_valid/fault_inst`，并证明该指令
没有提交或体系结构副作用。存储 stall 周期只比较协议稳定性，不把周期数强加为
ISA 语义。

## 6. 镜像与仿真终止目标

v0.2 目标文本 HEX 每个有效行是一条 32 位指令，即恰好 8 个十六进制字符；
详细规则见 [`simulator.md`](simulator.md)。当前 loader 仍只接受 v0.1 的每行
4 个字符，因此该格式尚未实现。

阶段 1 仿真目标使用私有 `tohost=0xfffffff0`、guest exit code 和有限 timeout
形成自检程序终止闭环。它们不是正式 SoC MMIO 或 ISA 行为，不得写入
`memory-map.md`；当前仿真 wrapper/loader 尚未实现该机制。`.bin` 和 ELF loader
属于阶段 2。

## 7. 迁移实施门禁

后续步骤按以下顺序恢复规格与实现一致：

1. 迁移 ISA package、decoder、编码器和反汇编器，并通过 `make test-isa`
   （已完成）；
2. 迁移 ALU、regfile、控制器、32 位取指/data valid-ready 和结构化 fault
   （已完成模块级验证）；
3. 迁移 Verilator wrapper、loader、trace/debug、SDB 和 CLI；
4. 加入独立参考模型、difftest、stall/fault 和程序回归；
5. 删除 v0.1 裸机器码、`R0`--`R3` 和 16 位接口的剩余依赖。

每一阶段先运行目标专项测试，再从快速门禁开始重跑累计回归。当前完整
`make test` 因仿真器迁移窗口不可用；步骤 2.4--2.5 完成并恢复全部入口后，才能
把它重新作为 v0.2 累计回归。

## 8. 证据边界

Icarus 和 Verilator 结果只属于 behavioral simulation。lint、模块仿真、端到端
仿真和 difftest 均不能证明综合、post-synth、post-implementation、时序收敛、
资源、功耗或 FPGA 上板成功。软件测试、Vivado 流程和真实板卡验收目前均为
`TODO` / 未验证。

原始日志、波形和生成物只进入 `build/`。正式结果必须记录日期、commit、工具
版本、命令、配置、测试负载和 PASS/FAIL；失败必须保留最小复现命令及必要上下文。
