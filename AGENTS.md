# AGENTS.md

> 本文件适用于仓库根目录及全部子目录。进入项目后先读本文件，再读与任务直接相关的资料；不要一次性加载全部课件或参考工程。

## 项目概述

本项目是数字电路设计课程项目，目标是在 **Zynq-7020 FPGA** 上渐进实现一款面向“低功耗嵌入式控制与周期性传感任务”的 RV32E 过渡子集 CPU，并提供最小可用的 SoC 与软件配套。阶段 1 v0.2 采用标准 RISC-V 编码，但只支持八条指令和 `x0`--`x15`，未完成扩展与验证前不得宣称完整 RV32E 或普通 RV32E 软件兼容。

最终交付不只是能够综合的 CPU RTL，还应形成一条可复现的闭环：

1. ISA 与微架构规格；
2. CPU、片上存储和必要外设 RTL；
3. 仿真、参考模型或差分测试；
4. 裸机运行时、测试程序和演示程序；
5. Vivado 综合、实现、时序约束和 FPGA 上板验证；
6. 面积、性能与功耗结果，以及课程报告材料。

## 当前状态（2026-09-12）

- 当前目录已初始化为 Git 仓库，默认分支为 `main`。
- 阶段 1 已完成八指令基线全链路迁移；阶段 2 已完成 64 KiB IROM（`0x00000000`）与 64 KiB DRAM（`0x20000000`）的 Harvard 架构隔离与双 `.bin` 镜像装载；阶段 3 已完成仓库内自包含的 AM-like 裸机中间层（`sw/am/`）、`scripts/check_isa_subset.py` 自动化审计工具与 6 项定向软件测试套件；阶段 4 已全面补全 RV32E v1.0（37 条标准基础整数指令、`x0`--`x15` 严格边界）、`sw/am/` 自包含 `klib`（含 `memset/memcpy/memcmp/strlen/strcmp/strcpy/strcat/check`）、12 项 `am-kernels` 基准测试（总计 18 项软件回归测试）以及软硬件仿真/差分全闭环。
- 阶段 5 Phase 1 已完成：
  - RTL：16 位 GPIO LED 控制器（`rtl/periph/led_controller.sv`，MMIO `0x10000100`）、SoC 总线互连交叉开关（`rtl/soc/soc_interconnect.sv`，支持 DRAM/MMIO/未映射错误地址路由并使用纯连续赋值杜绝调度环）以及顶层 SoC（`rtl/soc/dc_soc_top.sv`，导出 `o_led[15:0]` 并接入 `sim/verilator/sim_top.sv`）。
  - AM 设备层：建立 `sw/am/include/amdev.h`（标准设备抽象）与 `sw/am/src/ioe.c`（支持 `AM_GPIO_LED` 读写及 `led_write`/`led_read` 封装）。
  - 软件与测试：新增 `sw/tests/led_marquee/` 跑马灯自检程序，全套软件测试增至 19 项。
  - 参考模型与差分：`sim/verilator/reference_model.cpp` 扩充 MMIO LED 读写与未映射 MMIO fault 检查，`test_reference` 与 `test_difftest` 适配并全 PASS。
  - NVBoard 虚拟外设：引入 `CONFIG_DC_SIM_NVBOARD` Kconfig 配置（默认 `n` 保持 CI headless），通过 `constr/nvboard.nxdc` 绑定 16 颗虚拟 LED，提供独立隔离构建 `make nvboard-build` 与运行 `make nvboard-run [APP=led_marquee]`。
- 构建系统与回归闭环全面增强：新增 `make test-led`、`make test-interconnect`、`make test-soc`，单元测试套件增至 7 个；`make test-unit`、`make test-isa`、`make test-disasm`、`make test-memory`、`make test-reference`、`make test-simulation`、`make sw`、`make test-sw`（19 项）、`make test-difftest`、`make test-integration`、`make test-wave`、`make test-sdb` 以及最高层 `make test` 全面 PASS。
- v0.1 可执行基线冻结在 commit `9bfb9a97153be05de34c6d2311c09f41cb6f43ab`；不提供双 ISA 开关，旧语义只由 Git历史和迁移前验证记录保留。
- 正式 MMIO 扩展（timer/UART/sensor）、板卡具体型号/封装、时钟频率、板级复位极性仍属于阶段 5 后续子阶段规划中。
- 在对应规格落盘前，不得把上述未决项当成既定事实写入 RTL 或测试。

## 设计原则

### 1. 工作负载驱动

优先服务周期性采样、少量计算、阈值判断、状态控制和通信这类任务。基线设计倾向于：

- 简单、可解释、可验证的顺序单发射核；
- 定时器、GPIO、UART 和可替换的传感器接口/模型；
- 空闲等待、时钟使能和中断唤醒；
- 小而明确的片上存储与 MMIO 地址空间。

不要仅因为参考 NPC 已经具备某项能力，就直接引入双发射、ROB、分支预测、复杂 Cache 或完整 AXI。任何增加面积、切换活动、验证难度的机制都应由目标工作负载或测量结果证明其必要性。

### 2. ISA 规范与扩展纪律

- `docs/isa/isa.md` 是指令编码和体系结构语义的唯一规范源；RTL、仿真模型、软件接口和测试不得各自定义不同语义。
- 阶段 1 v0.2 只实现手册精确列出的 8 条标准编码；其他标准、保留或自定义编码全部按非法指令处理。
- 每条指令必须记录编码、操作数、伪代码、未使用字段、边界行为和汇编表示；禁止用隐式别名或未记录行为换取实现简化。
- 每次增删指令必须同步检查：ISA 文档、RTL 译码/执行、独立参考模型、汇编接口和测试用例。
- NPC/NEMU 只能借鉴仿真组织和差分测试方法；NEMU 的完整 RISC-V 执行环境不能直接代替本项目八指令子集、存储接口和 fault 契约的独立参考模型。

### 3. 低功耗必须可测量

- FPGA 阶段优先使用寄存器 clock-enable；不要在普通 RTL 中用组合逻辑直接门控时钟。
- 若确需 Xilinx 时钟原语，将其隔离在 FPGA wrapper 中，并同时保留可仿真的行为模型。
- 睡眠/唤醒协议必须说明：可唤醒源、体系结构状态保持、在途事务处理和首条唤醒指令行为。
- 功耗结论必须注明工具、实现阶段、时钟约束、活动文件和测试负载。无测量时只能写“预计”或 `TODO`，不能编造节能比例。

### 4. FPGA 与仿真边界清晰

- 默认假设自研 CPU/SoC 位于 Zynq-7020 的 PL；PS 是否用于下载、调试、存储或通信属于待定架构决策。
- 板卡料号、package、speed grade 和引脚必须从实际板卡资料确认，不能仅凭“Zynq-7020”猜测约束。
- behavioral simulation、lint、综合、post-synth、post-implementation、时序收敛和上板运行是不同证据；报告结果时必须注明阶段。
- Xilinx IP、ILA、MMCM/PLL、BRAM 等实例放在 FPGA/SoC 边界，不要污染可移植的 CPU 核心。

## 资料与参考实现

### 课程资料（项目内，只读原件）

- `docs/sources/lab/lab1.pptx`：Vivado、基础 RTL、仿真、约束与下载流程。
- `docs/sources/lab/lab2.pptx`：CPU 数据通路、寄存器、PC、ALU。
- `docs/sources/lab/lab3.pptx`：控制器、状态转移、课程示例 ISA。
- `docs/sources/lab/lab4.pptx`：CPU 集成、benchmark、存储器 BFM、访存/分支扩展。
- `docs/sources/lab/lab5.pptx`：指令扩展、ILA 与 FPGA 验证。
- `docs/sources/ppt/`：课程背景资料。
- `docs/sources/文档模版/`：课程提交模板。

`docs/sources/` 保存教师提供的原始文件。除非用户明确要求，不要改名、覆盖或重新保存这些文件；提炼出的规格和笔记应写入 `docs/` 下的新文档，并标注来源文件和页码/幻灯片编号。

### ysyx-workbench（仓库外，默认只读）

参考根目录：`/home/kaka/ysyx-workbench`

| 内容 | 主要用途 | 注意事项 |
| --- | --- | --- |
| `npc/` | CPU RTL、Verilator 仿真框架、difftest、调试设施 | 当前实现是复杂 RV32IM 双发射核，只借鉴所需模块与方法，不照搬架构 |
| `nemu/` | RV32 参考执行、监视器与差分测试 | 只借鉴参考模型接口与验证方法，不能把完整 RV32 环境直接当作本项目 v0.2 子集契约 |
| `JYDSoC/` | 简单 SoC、DRAM/MMIO、UART、虚拟板级交互 | 地址、接口时序和复位方式必须按本项目重新规格化 |
| `nvboard/` | Verilator 图形化外设验证 | 用于前期交互验证，不能代替真实 Zynq 板卡验证 |
| `abstract-machine/` | 裸机运行时、链接脚本、平台抽象 | 可参考现有 `riscv32-jydsoc`、`npc`、`ysyxsoc` 平台 |
| `am-kernels/` | CPU/AM 测试、hello、microbench 等负载 | 先运行小型定向测试，再扩大到应用/benchmark |
| `ysyxSoC/` | 更完整的 SoC 集成范例 | 仅在需要相应总线/外设时参考，避免过早引入复杂度 |

使用外部参考时遵守以下规则：

- 默认只读，不直接修改 `/home/kaka/ysyx-workbench`；用户明确要求跨仓修改时再操作。
- 先读目标子目录自己的 `AGENTS.md`、README、Makefile 和许可证。
- 区分“阅读借鉴”“改写移植”“原样复制”。复制代码前检查许可证，保留版权/许可证信息，并在项目文档中记录来源路径和必要的版本/提交信息。
- 不在本项目构建脚本中长期依赖个人绝对路径。通过可配置变量（如 `YSYX_WORKBENCH`、`NEMU_HOME`、`AM_HOME`、`NVBOARD_HOME`）接入，并提供合理的报错信息。
- 不引用参考工程的 `build/`、`obj_dir/`、日志、波形或其他生成物作为源文件。

## 建议目录布局

在开始相应工作时按需创建，不要一次性生成空目录：

```text
rtl/
  core/       # 与板卡无关的 CPU 核心
  soc/        # 总线、地址译码、片上存储集成
  periph/     # timer/GPIO/UART/sensor 等可综合外设
  fpga/       # Zynq-7020 顶层和 Xilinx 专用 wrapper
sim/
  tb/         # 模块与 SoC testbench、BFM
  verilator/  # C/C++ 仿真驱动及 difftest 接入
sw/
  am/         # 本项目 AM 平台适配（若采用）
  tests/      # 汇编/C 定向测试
  firmware/   # 周期性传感演示程序
constr/       # XDC 与时序约束
scripts/      # 可复现的构建、回归、镜像生成脚本
docs/
  architecture/
  isa/
  verification/
  fpga/
  decisions/  # 重要决策及其理由
build/        # 生成物，不作为源码
```

### 临时工作目录

`docs/00-temp/` 是长期保留的本地过程文件目录。Git 只跟踪其中的
`.gitignore`；草稿、分析记录和其他暂存内容不得提交。有长期价值的结论应
先提炼到对应的正式文档，再删除临时副本。

## 规格先行

写 CPU 主体 RTL 前，至少先形成以下最小规格：

1. `docs/requirements.md`：目标负载、功能范围、课程交付、性能/资源/功耗目标及其测量方法。
2. `docs/isa/isa.md`：指令/数据/地址宽度、寄存器数量、指令编码与语义、复位 PC、非法指令及异常/中断范围。
3. `docs/architecture/microarchitecture.md`：数据通路、控制方式、流水级、stall/flush、存储访问和睡眠/唤醒。
4. `docs/architecture/memory-map.md`：ROM/RAM/MMIO 地址、宽度、对齐、访问副作用。
5. `docs/verification/plan.md`：模块测试、指令测试、差分测试、软件测试、综合和上板验收。
6. `docs/fpga/board.md`：实际板卡、器件完整料号、时钟、复位、UART/JTAG/LED/按键/传感器引脚。

如果任务会决定上述内容，应先把选择、替代方案和理由告诉用户；得到足够信息后记录决策。未决内容统一标记 `TODO`，不要自行补全。

## RTL 设计约定

- 新代码优先使用 SystemVerilog（`.sv`）；若工具链或课程模板要求 Verilog-2001，则在相关目录文档中说明。
- 核心 RTL 保持可综合、参数和位宽显式。避免隐式 net、未定宽常量、组合环和综合不可移植结构。
- 时序状态使用非阻塞赋值，组合逻辑使用阻塞赋值；组合块必须完整赋默认值，避免锁存器。
- 统一复位极性与同步/异步策略。复位释放、跨时钟输入和外设异步输入要考虑同步与亚稳态。
- 模块接口必须记录请求/响应时序。若使用 valid/ready，数据和控制必须在握手前保持稳定，背压与 flush 不得丢失或重复事务。
- CPU 核心不得直接包含板级引脚、ILA 或厂商 IP；通过清晰接口连接 SoC/FPGA wrapper。
- 内存映射只能有一个规范源。RTL、软件头文件、链接脚本和测试中的地址必须与其一致。
- 对非法指令、未对齐访问、总线错误和复位期间输出给出明确行为，即使当前策略只是 trap 或受控停机。
- 仿真辅助代码放在 `` `ifndef SYNTHESIS `` 条件块或独立 testbench 中，不让 `$finish`、DPI、波形逻辑进入综合路径。

## 软件约定

- 软件生成器、汇编器或编码宏必须明确目标 ISA 版本，并与硬件实现和链接布局一致。
- 在正式汇编器可用前，为每条指令提供集中维护的最小编码宏或生成接口；应用代码不要散落裸机器码。
- 链接脚本、启动代码、trap/中断入口和 MMIO 头文件均视为硬件/软件 ABI 的一部分。
- 首个演示程序应体现目标场景：定时唤醒、读取传感值或模型、进行轻量计算、控制 GPIO/UART、再次进入空闲。
- benchmark 结果同时报告代码版本、编译参数、时钟、指令/周期口径和输入规模。

## 验证顺序

按由快到慢的顺序建立证据，失败时在最小层级定位：

1. 格式检查、lint、编译/elaboration；
2. ALU、寄存器堆、PC、译码、访存接口、timer 等模块级自检 testbench；
3. 每条已分配指令的定向测试、非法编码测试与边界条件；
4. 小程序与存储器 BFM；
5. RV32E 过渡子集独立参考模型差分测试；
6. `am-kernels` 中适用的 CPU/AM 测试和演示程序；
7. NVBoard 交互仿真（若接入）；
8. Vivado 综合、实现、时序/资源/功耗分析；
9. bitstream、ILA 和真实 Zynq-7020 板级验收。

回归必须采用自检方式并返回非零失败状态。仅“波形看起来正确”不能作为唯一验证依据。随机测试应记录 seed；超时必须有上限；失败应保留最小可复现命令和必要日志。

## 变更工作流

### Git 操作前置规则（强制）

- 每个新任务或新工作树中首次执行任何 Git 命令前，必须完整读取根目录 `GIT_RULES.md`；规则变化、上下文恢复或切换工作树后也要重新读取。
- 读取后按 `GIT_RULES.md` 执行状态、diff、暂存区和 submodule 预检，区分用户已有改动与本任务改动。
- 不得使用 `--no-verify` 绕过仓库 hook；若 `GIT_RULES.md` 缺失或不可读，停止会改变仓库或远端状态的 Git 操作。

### 开始任务前

1. 检查当前目录结构和版本控制状态，保留不属于本任务的用户改动。
2. 阅读与任务直接相关的规格、课件和外部参考入口。
3. 明确本次修改影响 CPU、SoC、软件 ABI、验证还是 FPGA 约束中的哪些层。
4. 对尚未决定且会显著改变设计的事项，先给出选项与推荐，不要直接固化进实现。

### 修改时

- 保持改动小而完整，不顺手重构无关代码。
- 修改接口时同步更新所有实例、testbench 和相关文档。
- 修复协议/流水线问题时解释根因，不用延时、额外脉冲或跳过比较来掩盖错误。
- 不覆盖用户已有改动，不删除无法确认用途的文件。
- 不执行 `git add`、`git commit`、`git push`，除非用户明确要求；即使用户要求提交，也先确认暂存范围。

### 完成任务后

- 运行与风险相称的最小回归，并准确报告执行命令、通过项、失败项和未执行项。
- 不能运行 Vivado/上板时明确写“未验证”，不得从 RTL 仿真推断时序或硬件结果。
- 新命令、新目录或稳定架构约束形成后，更新本文件或对应 `docs/` 文档，避免知识只留在对话中。

## 构建命令状态

当前所有底层工具、模块级、存储级、仿真器引擎、独立参考模型、difftest、
SDB 以及全回归入口均已全面恢复并适配 v0.2：

```bash
make check-tools
make help
make defconfig
make menuconfig
make config-show
make test-config
make lint-isa
make test-isa
make lint-comb
make test-alu
make test-decoder
make lint
make lint-mem
make test-regfile
make test-core
make test-led
make test-interconnect
make test-soc
make test-unit
make test-disasm
make test-memory
make test-reference
make sim-build
make test-simulation
make sw
make test-sw
make sim [IMG=<hex|bin>] [DATA_IMG=<bin>] [APP=<name>] [STEPS=<n>] [TRACE=1] [BATCH=1]
make nvboard-build
make nvboard-run [APP=<name>] [BATCH=1] [STEPS=<n>]
make test-difftest
make test-integration
make test-wave
make test-sdb
make test
make clean
```

`BATCH=1` 用于在 SDB 构建中显式选择 batch。后续 FPGA 流程仍未实现，
未实现前不得声称已经运行：

```bash
make fpga-synth
make fpga-bitstream
```

不要把 Vivado 的临时工程目录当成唯一构建方法；脚本、源文件清单、顶层、器件型号和 XDC 应可追踪、可复现。

## 禁止行为

- 不编造 ISA、地址、引脚、时钟、资源、性能、功耗或测试结果。
- 不把当前 16 位 4 寄存器 v0.1 实现误称为 RISC-V，也不在 v0.2 全部迁移并验证前宣称完整 RV32E 或普通 RISC-V 软件兼容。
- 不把 ysyx NPC 的现有架构、模块前缀、内存映射或竞赛约束直接当成本项目要求。
- 不为通过仿真而破坏 valid/ready、存储时序、异常精确性或软硬件 ABI。
- 不直接编辑生成物、Vivado cache、Verilator `obj_dir` 或二进制镜像来制造“修复”。
- 不把 NVBoard 通过、behavioral sim 通过或综合成功等同于 FPGA 上板完成。

## 输出要求

- 默认使用中文交流；代码、信号、命令与路径保留英文。
- 先给结论，再给依据。对不确定内容使用 `TODO` 或“未验证”。
- 代码变更说明应列出关键文件、设计影响和验证结果；不要用大段粘贴替代 diff 或文件链接。
- 任何数字结论都应附带测量环境或来源。
