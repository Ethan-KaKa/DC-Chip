# DC-Chip Verilator 仿真器使用与迁移接口约定

- 文档版本：v0.2
- 状态：v0.1 执行接口已归档；v0.2 反汇编器与核心已迁移，仿真器尚未迁移
- 更新日期：2026-09-11
- 目标 ISA 规范：[`../isa/isa.md`](../isa/isa.md) v0.2
- v0.1 实现冻结点：`9bfb9a97153be05de34c6d2311c09f41cb6f43ab`
- 验证计划：[`plan.md`](plan.md)

## 1. 适用范围

本文分别归档 Verilator behavioral simulation 的 v0.1 稳定接口，以及后续
步骤 2.2--2.5 必须实现的 v0.2 目标契约。第 2--11 节除特别说明外描述冻结于
`9bfb9a9` 的 **v0.1 归档实现**；第 12 节描述 v0.2 目标及迁移状态。两者不得
混作同一可执行接口。

当前接口包括 DPI-C 取指边界、HEX 镜像格式、命令行参数、统一执行引擎、SDB、
VCD 波形、运行生命周期和退出码。
实现位于 `sim/verilator/`，反汇编器、引擎自检与 CLI 集成用例位于
`sim/tests/`。

步骤 2.2--2.3 已迁移公共 ISA 层、独立反汇编器和核心 RTL；wrapper、loader、
Simulation 与 SDB 仍为 v0.1 接口，因此在步骤 2.4--2.5 完成前不再构建。
既有仿真结果只作为迁移前防回归证据，核心模块测试也不能证明 v0.2 端到端
仿真已经可用。仿真器不定义最终可执行文件 ABI，不能作为综合、时序、功耗或
FPGA 上板证据。

## 2. RTL 与 DPI-C 边界

`sim_top` 实例化可综合的 `cpu_core`，自身不生成时钟、复位或 `$finish`。
wrapper 对 C++ 暴露以下状态：

| 信号 | 宽度 | 含义 |
| --- | ---: | --- |
| `trace_valid` | 1 | 最近一个上升沿提交了一条合法指令 |
| `trace_pc` | 8 | 最近合法提交的指令 PC |
| `trace_inst` | 16 | 最近合法提交的指令字 |
| `debug_regs` | 64 | `{R3,R2,R1,R0}` |
| `illegal_inst` | 1 | 核心粘滞非法指令状态 |
| `fetch_pc` | 8 | 当前组合取指字地址 |
| `fetch_inst` | 16 | 当前组合取指指令 |

取指通过以下全局 C-linkage DPI 函数完成：

```cpp
extern "C" std::uint32_t sim_imem_read(std::uint32_t word_addr);
```

DPI 返回值只使用低 16 位。已加载镜像之外的地址返回保留编码 `0x8000`，
并只记录第一次越界地址；组合 DPI 调用本身不打印消息。其他 C++ 接口位于
`dc_sim` 命名空间。

## 3. HEX 镜像格式

镜像按有效行顺序映射到 8 位字地址 `0x00`–`0xff`：

- 先删除每行 `#` 及其后的注释，再裁剪 ASCII 空白；
- 空行和纯注释行不占地址；
- 每个有效行必须恰好包含 4 个 ASCII 十六进制字符，大小写均可；
- 镜像必须包含 1–256 个有效指令字；
- 文件打开或读取失败、空镜像、非法字符、错误宽度和第 257 个有效字均
  在模型创建前失败；
- loader 先解析到临时 vector，完整成功后才替换当前镜像；错误信息包含
  文件路径和一基行号。

示例：

```text
0402  # MOVI R1, #0x02
1900  # MOV  R2, R1
7002  # JUMP #0x02
```

## 4. 命令行接口

底层可执行文件接口为：

```text
Vsim_top --image <path> [--steps <n>] [--max-cycles <n>] [--trace]
         [--expect r0=<value>] ... [--expect r3=<value>]
         [--expect pc=<value>] [--batch]
Vsim_top --help
```

| 参数 | 约定 |
| --- | --- |
| `--image <path>` | 必选且只能出现一次 |
| `--steps <n>` | 正整数提交数；默认等于镜像有效字数 |
| `--max-cycles <n>` | 正整数执行周期上限；默认 `steps+4` |
| `--trace` | 每条合法提交打印一行；不得重复 |
| `--expect <name=value>` | 可重复用于不同的 `r0`–`r3` 和 `pc`；同名不得重复 |
| `--batch` | 显式选择原有非交互执行；只能出现一次 |
| `--help` | 必须是唯一参数 |

数值只接受无符号十进制或带 `0x`/`0X` 前缀的十六进制。寄存器期望值
范围为 `0x0000`–`0xffff`，PC 范围为 `0x00`–`0xff`。负数、零步数、
溢出、缺值、未知参数、未知 expectation、重复单值参数或重复 expectation
均属于输入错误。严格无符号数解析由 `numeric.h/.cpp` 的纯 C++17
`dc_sim::parse_unsigned()` 统一提供，不接受符号、空值、尾随字符或溢出。

`CONFIG_DC_SIM_SDB=n` 时默认模式与 `--batch` 均执行原有 batch，参数、summary、
trace、诊断及退出码保持一致。`CONFIG_DC_SIM_SDB=y` 时，不带 `--batch` 会在
镜像加载和 reset 后进入 SDB；交互模式允许 `--max-cycles`，但拒绝 `--steps`、
`--trace` 和 `--expect`，若同时出现则按上述三项顺序报告第一个冲突。SDB 的
默认绝对周期上限为镜像有效字数加 4，保持有限超时。

## 5. Simulation 执行引擎

`simulation.h/.cpp` 提供与 CLI 分离的 `dc_sim::Simulation`。公开头文件通过
PIMPL 隐藏 `Vsim_top`、`VerilatedContext` 等 Verilator 类型；每个实例独占
context、模型、时钟相位、仿真时间及周期/提交计数。波形构建的析构顺序固定为
VCD `flush()`、`close()`，随后 DUT `final()`；非波形构建只执行 `final()`。
`main.cpp` 只保留参数解析、镜像加载、batch 调度、格式化与退出码映射。

主要状态和控制接口如下：

- `ArchitecturalState` 包含当前 `fetch_pc/fetch_inst`、`R0`–`R3`、reset 后
  非复位 `cycles`、`commits` 和包含 reset 推进在内的单调 `time`；
- `StepEvent` 描述本周期提交及其 PC/指令、是否进入非法状态，以及是否实际
  执行了越界取指；
- `reset()`、`step_cycle()`、`step_instruction(max_cycles)`、
  `run_until(target, count, max_cycles, breakpoints)` 和 `snapshot()` 构成统一
  推进入口；
- `RunTarget` 区分无数量目标、周期目标和提交目标；`StopReason` 区分周期或
  提交完成、执行前断点、普通非法、越界取指、超时，并为后续 SDB 预留
  `quit`。

`reset()` 必须且只能在执行前调用一次。它从稳定低电平驱动两个完整同步复位
周期，在低电平释放 reset，并清除模型加载和 reset 期间的 DPI 越界记录；这些
边沿推进 `time`，但 `cycles` 和 `commits` 保持为零。未 reset 就步进或重复
reset 属于内部接口误用，以 C++ 异常明确失败。

`step_cycle()` 总是从稳定低电平开始，依次完成上升沿和下降沿并回到低电平；
每次只增加一个非复位周期，且只在 `trace_valid=1` 时增加一次提交。提交事件
保存上升沿对应的 `trace_pc/trace_inst`。batch 模式逐次调用
`step_instruction()`，所以 `--steps` 始终按提交而非时钟周期计数。

`run_until()` 的 `count` 相对本次调用起点，`max_cycles` 是 reset 后的绝对全局
周期上限；断点集合使用 8 位 PC，并在目标指令执行前检查。每轮固定按以下
顺序停止：

1. 执行前已达到全局周期上限；
2. 执行前断点；
3. 推进一个完整周期；
4. 达到提交目标；
5. 实际进入非法状态，并按 DPI 首次越界地址细分普通非法与越界取指；
6. 达到全局周期上限；
7. 达到周期目标。

只有 `illegal_inst=1` 且 DPI 首次越界地址等于该周期实际执行的 `fetch_pc` 时，
停止原因为越界取指。提交目标先于非法分类，因此最后一次合法提交造成的下一
地址组合预取不会覆盖成功结果；下一次步进才会实际执行并报告越界。

## 6. 编译期 VCD 波形

只有生成的 `config.h` 定义 `CONFIG_DC_SIM_WAVE` 时，`Simulation` 才公开：

```cpp
void set_wave_enabled(bool enabled);
bool wave_enabled() const;
const std::string &wave_path() const;
```

构造后的默认状态为开启记录。模型首个 reset 边沿前在时间 0 dump 初始状态；
以后每个上升沿和下降沿 `eval()` 后使用同一 `VerilatedContext` 的单调时间 dump。
两个同步 reset 周期因此位于波形中，但仍不计入 `cycles` 或 `commits`。

`set_wave_enabled(false)` 只跳过后续 dump，CPU 和仿真时间继续推进；恢复为
`true` 后继续写同一文件，不关闭、分段或改名。该接口当前只供执行引擎及测试
和启用 WAVE 的 SDB 使用。

输出路径不依赖启动工作目录。Linux 构建从 `/proc/self/exe` 解析真实可执行
文件，要求其位于 `<BUILD_DIR>/verilator*/<binary>`，并将唯一波形截断写入
`<BUILD_DIR>/dump.vcd`。路径无法解析或文件无法打开时，诊断包含完整目标路径
并返回退出码 1；已经构造的 PIMPL 仍按正常顺序清理。帮助、CLI 参数错误和
HEX 加载错误均发生在模型创建前，不创建或覆盖波形。

关闭配置时 Verilator 不接收 `--trace`，`VM_TRACE=0`、`VM_TRACE_VCD=0`，VCD
头文件、公开接口、tracer 成员和 dump 调用均不参与编译。

## 7. v0.1 最小反汇编接口（归档）

`disasm.h/.cpp` 提供与 DUT 状态无关的纯 C++17 接口：

```cpp
std::string dc_sim::disassemble(std::uint16_t instruction);
```

该接口覆盖 ISA v0.1 的 8 条指令，并执行与 RTL decoder 相同的规范字段
检查。助记符和寄存器名使用大写，8 位立即数使用两位小写十六进制，例如
`MOVI R1, #0x02`、`ADD R1, R2` 和 `JUMP #0x08`。保留 opcode 或未使用字段
非零的非规范编码统一输出四位小写十六进制 `.word 0xXXXX`，不产生合法别名。

这些行为只存在于冻结 commit。当前源码接口已迁移为
`std::string dc_sim::disassemble(std::uint32_t instruction)`，支持 v0.2 八条
指令、小写 `x0`--`x15`、有符号 I/S 立即数和五位十六进制 LUI 字段；其他编码
统一输出 `.word 0xXXXXXXXX`。SDB 尚未迁移，不能把该纯函数测试视为 SDB 可用。

## 8. SDB 接口与命令契约

只有 `CONFIG_DC_SIM_SDB=y` 时，正式仿真器才编译 `sdb.cpp`、`disasm.cpp` 并
从 `sdb.h` 调用：

```cpp
dc_sim::RunResult dc_sim::run_sdb(
    dc_sim::Simulation &simulation,
    std::uint64_t max_cycles,
    std::istream &input,
    std::ostream &output,
    std::ostream &errors);
```

每轮先向 `output` 写入并 flush 固定提示符 `(dc-sdb) `，包括 stdin 重定向和
EOF。`q` 或 EOF 返回 `StopReason::quit`；实际非法、越界取指和 timeout 在输出
停止状态、向 `errors` 复用 batch 精确诊断后返回对应 `RunResult`。`main.cpp`
将三者映射为退出码 `2/2/3`。解析错误只写 `errors` 并继续命令循环。

固定命令为：

```text
help                 Show this help
q                    Quit the debugger
c                    Continue execution
si [N]               Step N committed instructions (default 1)
sc [N]               Step N cycles (default 1)
b <pc>               Set an execution-before breakpoint
d <id>               Delete a breakpoint
info r               Show registers and current instruction
info b               Show breakpoints
info wave            Show waveform state
wave on              Resume waveform recording
wave off             Pause waveform recording
```

最后三项只在 WAVE 构建中注册和显示。非 WAVE 构建把 `info wave` 作为未知 info
目标，把 `wave` 作为未知命令。PC 接受十进制或带 `0x`/`0X` 前缀的十六进制，
范围为 0–255；步数和断点 ID 必须为正 `uint64_t`。参数数量错误统一以
`error: usage: <syntax>` 报告，未知命令以
`error: unknown command '<token>'` 报告。

断点表按单调 ID 排序，ID 从 1 开始且删除后不复用；同一 PC 去重并返回原 ID。
断点在指令执行前命中。SDB 为刚命中的 PC 保留一次抑制状态，让下一条执行命令
可以越过该断点；目标指令提交后立即恢复。自跳转回相同 PC 因而会再次命中；
若一个周期尚未提交，抑制状态跨命令保留。所有 `c/si/sc` 都循环调用
`Simulation::run_until()`，每次最多推进一个完整周期，所以沿用引擎的 timeout、
非法及越界优先级。

步进完成先打印 `stopped: commits complete` 或 `stopped: cycles complete`；最后
周期若提交，再打印 `commit pc=... inst=... asm="..."`，最后打印包含当前指令、
四个寄存器、周期、提交和时间的 `state`。断点、非法、越界和 timeout 也打印
当前 `state`。WAVE 构建的波形状态固定为
`wave=on|off path=<absolute-path> time=<N>`。

## 9. 输出与退出码

trace 使用固定宽度小写十六进制，格式为：

```text
cycle=<n> commit=<n> pc=0x00 inst=0x0402 r0=0x0000 r1=0x0002 r2=0x0000 r3=0x0000
```

正常达到目标提交数时，无论是否启用 trace 都输出：

```text
summary commits=<n> cycles=<n> pc=0x00 r0=0x0000 r1=0x0000 r2=0x0000 r3=0x0000
```

| 退出码 | 条件 |
| ---: | --- |
| 0 | 帮助，或目标提交完成且全部 expectation 匹配 |
| 1 | CLI、HEX 镜像或 VCD 初始化错误 |
| 2 | 实际执行非法指令或越界取指返回的非法字 |
| 3 | 达到最大周期数 |
| 4 | 最终寄存器或 PC 不匹配 |

SDB 中 `q` 和 EOF 返回 0；实际非法或越界取指返回 2；timeout 返回 3。SDB
命令解析错误不终止进程，因此没有独立退出码。

## 10. 构建配置边界

仿真器构建通过根目录 `Dconfig` 接收 `DC_SIM_SDB` 和 `DC_SIM_WAVE`，两项
默认均为 `n`。`DC_SIM_WAVE=y` 选择本节的编译期 VCD 行为；
`DC_SIM_SDB=y` 选择交互式 SDB 前端。完整配置接口见
[`configuration.md`](configuration.md)。

默认配置下 Verilator 仍以 `VM_TRACE=0` 构建。CLI `--trace` 始终只是既有的
逐提交文本输出参数，与 VCD 编译期开关互相独立。

## 11. 构建与回归入口

```bash
make sim-build
make sim IMG=<hex> [STEPS=<n>] [TRACE=1] [BATCH=1]
make test-config
make test-disasm
make test-simulation
make test-integration
make test-wave
make test-sdb
make test
make clean
```

`make sim` 要求 `IMG` 非空，`TRACE` 和 `BATCH` 都只能为空或 `1`；`BATCH=1`
映射为 `--batch`。`make sim-build` 按
package、decoder、ALU、regfile、core、wrapper 的顺序构建
`build/verilator/Vsim_top`；项目 C++ 源采用 C++17，并执行
`-Wall -Wextra -Wpedantic` 语法检查。

冻结的 `make test-disasm` 使用纯 C++17 自检穷举全部 65,536 个指令字，其中 2,384 个
规范编码必须生成精确汇编，其余编码必须生成精确 `.word`。该测试不创建或
驱动 Verilator 模型。`make test-simulation` 在独立
`build/verilator-test/` Mdir 中直接调用引擎，
与正式 `build/verilator/Vsim_top` 隔离。`make test-integration` 的 19 个 CLI
用例逐项比较精确退出码，并对 summary、trace、普通非法、越界、timeout 和
状态失配执行精确文本断言。`make test` 依次运行配置、反汇编、RTL
lint/模块测试、Simulation 引擎自检和 CLI 集成测试。`make clean` 只允许删除
仓库根目录的默认 `build/`；本地 `.config` 由 `make clean` 保留。

`make test-wave` 另外构建彼此隔离的 WAVE-off/on 正式 CLI 和执行引擎。它检查
编译宏与链接产物、固定输出路径、截断覆盖、VCD header、时间 0、reset 与正常
执行双边沿、暂停间隙和状态等价，并在 WAVE-on 构建上复跑 19 个 CLI 用例及
不可打开目标的错误路径。

`make test-sdb` 使用 `build/test-fixtures/sdb/` 的隔离配置覆盖 SDB-off、
SDB-only 和 SDB+WAVE。它检查条件编译、提示符与逐字命令输出、断点恢复、数值
及用法错误、终止状态、19 个 batch CLI 用例、交互选项冲突、`BATCH=1` 传递，
以及 SDB 波形暂停间隙和状态等价。

## 12. v0.2 目标契约（部分迁移）

本节冻结迁移后的仿真器边界。步骤 2.2--2.3 已迁移纯反汇编接口、核心 RTL
及其 32 位取指/data 握手、debug 和 fault 端口；wrapper、loader、Simulation、
SDB 和 CLI 仍未迁移，因此当前没有可执行仿真器。不得让 loader 自动猜测 ISA，
且不提供双 ISA 开关。

### 12.1 RTL wrapper 与状态

目标 `sim_top` 必须暴露 `docs/architecture/microarchitecture.md` 定义的 32 位
取指/data valid-ready 请求--响应通道，并向执行引擎提供：

- 32 位 `trace_pc` 和 `trace_inst`，仅在成功提交时由 `trace_valid` 报告；
- 4 位索引加 32 位数据的 debug regfile 读取，可遍历 `x0`--`x15`；
- `fault_valid`、3 位 cause、32 位 PC/指令和指令有效位组成的结构化 fault；
- 当前 fetch PC/指令、周期数、提交数和统一仿真时间。

核心已移除 v0.1 的 8 位 PC、16 位指令、64 位 `{R3,R2,R1,R0}` 和单一
`illegal_inst`；wrapper 与 C++ 仿真层仍待同步。32 位 trace 文本必须使用八位
小写十六进制 PC/指令；寄存器状态使用 `x0`--`x15` 和八位十六进制值。精确行
格式将在 CLI 迁移实现时与测试一同冻结，当前文档不声称它已经可用。

### 12.2 目标文本 HEX

v0.2 文本 HEX 延续当前注释与空行规则，但每个有效行必须恰好包含 8 个 ASCII
十六进制字符，表示一条完整 32 位指令。有效行 `n` 放在
`reset_pc + 4*n` 的私有仿真取指位置；地址计算溢出必须在模型创建前报错。

目标示例：

```text
00100093  # addi x1, x0, 1
002081b3  # add  x3, x1, x2
00008067  # jalr x0, 0(x1)
```

loader 必须事务性解析，文件/行诊断规则继续保持明确。当前 loader 仍要求每行
4 个字符并映射到 8 位指令字地址；8 字符 loader **尚未实现**。
`scripts/rv32e_encode.py` 已提供严格编码和 8 字符测试 HEX 生成接口，并校验
寄存器、立即数、起始 PC 对齐、32 位范围及地址回绕。原 v0.1 HEX 和裸机器码
将在迁移完成时移除，不长期兼容。`.bin` 和 ELF loader 属于阶段 2，本阶段不
定义。

### 12.3 私有 `tohost` 终止机制

阶段 1 v0.2 behavioral simulation 将地址 `0xfffffff0` 定义为仿真私有
`tohost`，只用于让自检 guest 终止：

- 对该地址成功执行一次四字节 `sw` 时停止，写入的 32 位值记录为
  `guest_exit_code`；
- `guest_exit_code=0` 表示 guest 成功，非零表示 guest 自检失败；
- `sb`、load 或其他地址不触发终止；
- 该 store 按正常成功指令提交，并在提交后报告 guest exit；
- 若 store 自身得到错误响应，则按 `store access fault` 停止，不报告 guest exit；
- guest exit 的 host 进程退出码映射和精确输出文本在 CLI 迁移时冻结为测试
  契约，当前为 `TODO`。

`tohost` 不是 ISA 指令、正式 MMIO 外设或 SoC ABI，不进入
`docs/architecture/memory-map.md`。仿真内存模型应在正式地址译码之外拦截它，
未来若正式 memory map 冲突，必须迁移私有地址而不能默认为硬件寄存器。

### 12.4 timeout 与停止优先级

目标执行引擎仍使用 reset 后绝对、有限、正整数 `max_cycles`。请求或响应 stall
消耗周期并计入 timeout；没有提交不等于仿真挂死。一个周期结束后若同时满足
多个条件，目标停止优先级为：

1. 成功提交的 `tohost` guest exit；
2. 本周期锁存的结构化 fault；
3. 达到调用者要求的提交/周期目标；
4. 达到绝对 `max_cycles`。

执行周期开始前已经达到 `max_cycles` 时不得再推进。精确 breakpoint 交互优先级
在 SDB 迁移时补充；当前 v0.1 的停止优先级和退出码继续以第 5、8、9 节为准。

### 12.5 迁移验收

目标 loader、wrapper、Simulation、SDB、VCD、反汇编器和 batch CLI 必须共享
同一 32 位状态与推进时间轴。纯反汇编器已通过 `make test-isa`；迁移测试仍需
覆盖所有 fault、任意 valid/ready stall、16 个寄存器、32 位 trace、8 字符
loader HEX、`tohost` 成功/失败、timeout 和参考模型 difftest。各项只能按实际
专项结果分别标记，不得由反汇编测试推断仿真器可用。
