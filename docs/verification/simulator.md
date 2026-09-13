# DC-Chip Verilator 仿真器使用与迁移接口约定

- 文档版本：v0.2
- 状态：v0.2 仿真器迁移已完成（sim_top、Simulation 引擎、SDB、C++ 独立参考模型、difftest 与 22 项 CLI 集成验证通过）
- 更新日期：2026-09-11
- 目标 ISA 规范：[`../isa/isa.md`](../isa/isa.md) v0.2
- v0.1 实现冻结点：`9bfb9a97153be05de34c6d2311c09f41cb6f43ab`
- 验证计划：[`plan.md`](plan.md)

## 1. 适用范围

本文档定义 Verilator behavioral simulation 的 v0.2 现行接口契约，并归档冻结于
`9bfb9a9` 的 v0.1 历史参考。第 2--11 节描述仿真子系统通用的生命周期设计，
第 12 节详细记录已落盘实现的 **v0.2 完整执行与差分测试契约**。

当前接口包括 valid-ready 取指与访存边界、32 位 8 字符 HEX 镜像格式、命令行参数、
统一执行引擎、SDB 交互调试器、C++17 独立参考模型、lockstep 差分测试、VCD 波形、
运行生命周期和明确进程退出码。
实现位于 `sim/verilator/`，参考模型、difftest、引擎自检与 CLI 集成用例位于
`sim/tests/`。

步骤 2.5 已完成 wrapper、Simulation 引擎、SDB、参考模型与 difftest 的迁移；
`make sim-build`、`make testinfra list`、`make testinfra ALL=<names>`
与 `make test` 全面通过，建立了闭环的端到端仿真执行与回归保障。仿真器不定义
最终板级可执行文件 ABI，不能代替后续 Vivado 综合、实现、时序、功耗或 FPGA 上板证据。

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
         [--expect pc=<value>] [--sdb-off] [--nvboard-off] [--wave-off]
Vsim_top --help
```

| 参数 | 约定 |
| --- | --- |
| `--image <path>` | 必选且只能出现一次 |
| `--steps <n>` | 正整数提交数；默认等于镜像有效字数 |
| `--max-cycles <n>` | 正整数执行周期上限；默认 `steps+4` |
| `--trace` | 每条合法提交打印一行；不得重复 |
| `--expect <name=value>` | 可重复用于不同的 `r0`–`r3` 和 `pc`；同名不得重复 |
| `--sdb-off` | 关闭已编入的交互 SDB；只能出现一次 |
| `--nvboard-off` | 跳过 NVBoard 初始化、刷新和退出；只能出现一次 |
| `--wave-off` | 启动时不创建 VCD；SDB 中仍可用 `wave on` 延迟开启 |
| `--help` | 必须是唯一参数 |

数值只接受无符号十进制或带 `0x`/`0X` 前缀的十六进制。寄存器期望值
范围为 `0x0000`–`0xffff`，PC 范围为 `0x00`–`0xff`。负数、零步数、
溢出、缺值、未知参数、未知 expectation、重复单值参数或重复 expectation
均属于输入错误。严格无符号数解析由 `numeric.h/.cpp` 的纯 C++17
`dc_sim::parse_unsigned()` 统一提供，不接受符号、空值、尾随字符或溢出。

`CONFIG_DC_SIM_SDB=n` 时默认执行自动模式。`CONFIG_DC_SIM_SDB=y` 时，不带
`--sdb-off` 会在
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

`set_wave_enabled(false)` 只跳过后续 dump，CPU 和仿真时间继续推进；若启动时
使用 `--wave-off`，第一次恢复为 `true` 时才创建文件并从当前仿真时间开始记录；
否则继续写同一文件，不关闭、分段或改名。该接口当前只供执行引擎及测试
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
make sw tests [sdboff] [nvboardoff] [waveoff] [ALL=<names>]
make sw tests batch [ALL=<names>]
make testinfra list
make testinfra ALL=config,disasm,simulation,integration
make testinfra ALL=wave,sdb
make test
make clean
```

`make sim-build` 是纯构建命令，并按
package、decoder、ALU、regfile、core、wrapper 的顺序构建
`build/verilator/Vsim_top`；项目 C++ 源采用 C++17，并执行
`-Wall -Wextra -Wpedantic` 语法检查。

`make testinfra ALL=disasm` 使用纯 C++17 自检穷举全部 65,536 个指令字，其中 2,384 个
规范编码必须生成精确汇编，其余编码必须生成精确 `.word`。该测试不创建或
驱动 Verilator 模型。`make testinfra ALL=simulation` 在独立
`build/verilator-test/` Mdir 中直接调用引擎，
与正式 `build/verilator/Vsim_top` 隔离。`make testinfra ALL=integration` 的 19 个 CLI
用例逐项比较精确退出码，并对 summary、trace、普通非法、越界、timeout 和
状态失配执行精确文本断言。`make test` 依次运行配置、反汇编、RTL
lint/模块测试、Simulation 引擎自检和 CLI 集成测试。`make clean` 只允许删除
仓库根目录的默认 `build/`；本地 `.config` 由 `make clean` 保留。

`make testinfra ALL=wave` 另外构建彼此隔离的 WAVE-off/on 正式 CLI 和执行引擎。它检查
编译宏与链接产物、固定输出路径、截断覆盖、VCD header、时间 0、reset 与正常
执行双边沿、暂停间隙和状态等价，并在 WAVE-on 构建上复跑 19 个 CLI 用例及
不可打开目标的错误路径。

`make testinfra ALL=sdb` 使用 `build/test-fixtures/sdb/` 的隔离配置覆盖 SDB-off、
SDB-only 和 SDB+WAVE。它检查条件编译、提示符与逐字命令输出、断点恢复、数值
及用法错误、终止状态、自动 CLI 用例、交互选项冲突、运行时关闭参数，
以及 SDB 波形暂停间隙和状态等价。

## 12. v0.2 仿真与差分测试契约（完整实现）

本节记录步骤 2.5 落地实现的 v0.2 完整仿真器与差分测试契约。

### 12.1 RTL wrapper 与状态可见性

`sim/verilator/sim_top.sv` 实例化 `cpu_core` 与 `sim_mem`，对外暴露：

- 32 位 `trace_pc` 和 `trace_inst`，仅在合法提交时由 `trace_valid` 脉冲指示；
- 1 位 `is_skip_ref`，指示当前提交指令是否命中未在参考模型中精确建模的 MMIO 外设空间（difftest 据此同步目标寄存器并跳过比对）；
- 4 位 `debug_reg_addr` 输入与 32 位 `debug_reg_data` 输出，遍历 `x0`--`x15`；
- `fault_valid`、3 位 `fault_cause`、32 位 `fault_pc`、`fault_inst_valid` 和 32 位 `fault_inst`；
- 私有 `tohost_exit` 与 32 位 `guest_exit_code`；
- 当前 `fetch_pc` 与 `fetch_inst`（fault 时优先保持故障现场指令）。

### 12.2 镜像格式与加载契约

仿真器支持 32 位 8 字符 HEX 文本格式与原生二进制 (`.bin`) 格式，且支持同时加载指令镜像与数据镜像：

#### 12.2.1 32 位 8 字符 HEX 镜像格式
`sim/verilator/memory.cpp` 中的 `load_hex_image()` 支持每行恰好 8 个十六进制字符的 32 位指令：
- 支持 `#` 注释和空白字符；
- 指令按 4 字节连续映射至 IROM 空间（基址 `0x00000000`，容量 64 KiB，最多 16,384 条指令）；
- 超过容量、空文件、畸变字符或行长度不等于 8 均在模型创建前报错退出（exit code 1）。

#### 12.2.2 原生二进制 (`.bin`) 镜像格式
`sim/verilator/memory.cpp` 中的 `load_binary_image()` 支持将 GNU 工具链生成的小端 raw binary 直接载入内存：
- **指令镜像 (IROM)**：从 `0x00000000` 起载入。若文件字节数不是 4 的倍数，自动在末尾以零字节补齐至 4 字节边界；文件大小不得超过 `65536` 字节；
- **数据镜像 (DRAM)**：从 `0x20000000` 起载入。载入覆盖 `[0x20000000, 0x20000000 + size)`，剩余 DRAM 空间自动零初始化；文件大小不得超过 `65536` 字节；
- 文件不存在、空文件或文件大小超过区域容量时均报错退出（exit code 1）。

#### 12.2.3 命令行参数约定
```text
Vsim_top [--image <path> | --image-inst <path>] [--image-data <path>]
         [--format <auto|hex|bin>] [--steps <n>] [--max-cycles <n>]
         [--trace] [--expect <name=value>]
         [--sdb-off] [--nvboard-off] [--wave-off]
```
- `--image <path>`：默认指令镜像（向后兼容阶段 1，支持 `.hex` 与 `.bin`）；
- `--image-inst <path>`：显式指定指令镜像（与 `--image` 互斥）；
- `--image-data <path>`：可选，指定数据镜像；
- `--format <auto|hex|bin>`：格式显式指定；默认 `auto`（以 `.hex` 结尾判为 HEX，其余判为 raw binary）。

### 12.3 私有 `tohost` 终止机制

- 地址 `0xfffffff0` 为私有 tohost，只响应 4 字节 `sw` 指令；
- 写入值记录为 `guest_exit_code`；
- `guest_exit_code == 0` 时 host 进程退出码为 `0`；
- `guest_exit_code != 0` 时 host 进程退出码为 `5`，并向 `stderr` 打印 `error: guest exit code: <code_in_dec>`；
- load 或 `sb` 访问该地址均触发 `load access fault` 或 `store access fault`（exit code 2）。

### 12.4 仿真停止优先级与进程退出码

Simulation 引擎单个周期内的停止判定优先级严格为：

1. **`tohost` 终止**：若 guest 成功则 exit code 0，若 guest 失败则 exit code 5；
2. **结构化 fault**：exit code 2，打印精确故障类型、PC 与指令字；
3. **步数/周期完成**：若指定 `--steps` 或到达目标提交数，exit code 0；若存在 `--expect` 不匹配则 exit code 4；
4. **`max_cycles` 超时**：exit code 3，打印已消耗周期与提交数。

命令行与配置错误（缺参数、非法数字、文件不存在等）返回 exit code 1。

### 12.5 C++17 独立参考模型与 Difftest

- **独立参考模型**（`sim/verilator/reference_model.h/.cpp`）：完全独立于 RTL 的纯 C++17 解码与执行模型，支持 RV32E v0.2 的 8 条指令、16 个寄存器、DRAM 字节/字读写、7 种结构化 fault 判定与 tohost 退出；
- **差分测试框架**（`sim/verilator/difftest.h/.cpp`）：逐指令（lockstep）比对 DUT 与参考模型的提交 PC、提交指令、16 个寄存器状态、下条指令 PC、访存副作用与 fault 状态；
- **自检目标**：`make testinfra ALL=reference`（纯 C++ 单元测试）与 `make testinfra ALL=difftest-engine`（包含固定种子随机指令序列与 fault 的联合差分测试）。

### 12.6 回归验证入口

| 命令 | 覆盖范围 |
| --- | --- |
| `make testunit ALL=led` | 16 位 GPIO LED 控制器模块级测试（包含字/半字/字节读写、对齐与 ready 握手） |
| `make testunit ALL=interconnect` | SoC 总线互连测试（DRAM/MMIO/未映射错误地址路由与连续赋值稳定性） |
| `make testunit ALL=soc` | SoC 顶层软硬件集成自检（包含核心、互连、LED 与私有 tohost） |
| `make testunit` | 10 个模块与子系统测试及 RTL lint |
| `make testinfra ALL=reference` | C++ 独立参考模型指令、MMIO LED 与 fault 单元测试 |
| `make testinfra ALL=simulation` | C++ Simulation 驱动引擎自检 |
| `make sw tests batch` | 20 项 AM 裸机软件测试自动端到端运行验证（保留配置中的 difftest） |
| `make testinfra ALL=difftest-engine` | RTL 与独立参考模型的 lockstep 差分测试 |
| `make testinfra ALL=integration` | 端到端 CLI 正反例集成测试 |
| `make testinfra ALL=wave` | WAVE 宏开关、VCD 导出、暂停恢复与 CLI 回归 |
| `make testinfra ALL=sdb` | SDB 交互调试器命令、单步、断点、错误诊断与 CLI 回归 |
| `make testinfra ALL=unified-sim` | 全特性单一 `Vsim_top`、NVBoard 产物隔离与运行时关闭组合 |
| `make test` | 包含全部配置、ISA、disasm、lint、unit、mem、ref、sim、sw、difftest、integration 的全回归 |

### 12.7 NVBoard 虚拟外设验证环境（阶段 5 Phase 1）

为在无需下载真实 FPGA 板卡的情况下直观验证外设（如 LED 跑马灯、开关、数码管），仿真系统集成了 NVBoard 虚拟板卡支持：

1. **单一仿真器与零污染构建**：
   - Kconfig 宏 `CONFIG_DC_SIM_NVBOARD` 默认置为 `n`；设为 `y` 后，NVBoard 与其他功能共同编入唯一的 `build/verilator/Vsim_top`。
   - 自动绑定代码位于 `build/verilator/`，NVBoard 第三方对象与归档位于 `build/tools/nvboard/`，不在 submodule 中生成文件。
2. **引脚映射 (`constr/nvboard.nxdc`)**：
   ```text
   top=sim_top
   o_led (LD15, LD14, LD13, LD12, LD11, LD10, LD9, LD8, LD7, LD6, LD5, LD4, LD3, LD2, LD1, LD0)
   ```
   通过 NVBoard 的自动绑定生成工具 `python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py` 将 `dc_soc_top` 导出的 `o_led[15:0]` 信号映射到虚拟面板上的 16 颗 LED。
3. **主循环更新与生命周期**：
   在 `sim/verilator/simulation.cpp` 中：
   - 启动时调用 `nvboard_bind_all_pins(sim_top)` 与 `nvboard_init()`；
   - 每个时钟周期在DUT求值（`context_->timeInc(1)`）后调用 `nvboard_update()` 刷新界面；
   - 仿真退出时调用 `nvboard_quit()` 释放 SDL2 窗口资源。
4. **运行与交互命令**：
   ```bash
   make menuconfig                         # 启用 DC_SIM_NVBOARD
   make sw tests ALL=led_marquee          # 使用虚拟面板运行
   make sw tests nvboardoff ALL=led_marquee
   SDL_VIDEODRIVER=dummy make sw tests batch ALL=led_marquee
   ```
