# DC-Chip Verilator 仿真器使用与接口约定

- 版本：v0.1
- 状态：阶段 D–E 基线及仿真调试基础设施步骤 1–3 已实现
- 更新日期：2026-09-11
- ISA 规范：[`../isa/isa.md`](../isa/isa.md)
- 验证计划：[`plan.md`](plan.md)

## 1. 适用范围

本文记录当前 Verilator behavioral simulation 的稳定使用接口，包括 DPI-C
取指边界、HEX 镜像格式、命令行参数、统一执行引擎、运行生命周期和退出码。
实现位于 `sim/verilator/`，反汇编器、引擎自检与 CLI 集成用例位于
`sim/tests/`。

仿真器只支持 ISA v0.1 的组合零等待取指协议。它不定义最终可执行文件
ABI，也不能作为综合、时序、功耗或 FPGA 上板证据。

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
         [--expect pc=<value>]
Vsim_top --help
```

| 参数 | 约定 |
| --- | --- |
| `--image <path>` | 必选且只能出现一次 |
| `--steps <n>` | 正整数提交数；默认等于镜像有效字数 |
| `--max-cycles <n>` | 正整数执行周期上限；默认 `steps+4` |
| `--trace` | 每条合法提交打印一行；不得重复 |
| `--expect <name=value>` | 可重复用于不同的 `r0`–`r3` 和 `pc`；同名不得重复 |
| `--help` | 必须是唯一参数 |

数值只接受无符号十进制或带 `0x`/`0X` 前缀的十六进制。寄存器期望值
范围为 `0x0000`–`0xffff`，PC 范围为 `0x00`–`0xff`。负数、零步数、
溢出、缺值、未知参数、未知 expectation、重复单值参数或重复 expectation
均属于输入错误。

## 5. Simulation 执行引擎

`simulation.h/.cpp` 提供与 CLI 分离的 `dc_sim::Simulation`。公开头文件通过
PIMPL 隐藏 `Vsim_top`、`VerilatedContext` 等 Verilator 类型；每个实例独占
context、模型、时钟相位、仿真时间及周期/提交计数，析构时只调用一次
`final()`。`main.cpp` 只保留参数解析、镜像加载、batch 调度、格式化与退出码
映射。

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

## 6. 最小反汇编接口

`disasm.h/.cpp` 提供与 DUT 状态无关的纯 C++17 接口：

```cpp
std::string dc_sim::disassemble(std::uint16_t instruction);
```

该接口覆盖 ISA v0.1 的 8 条指令，并执行与 RTL decoder 相同的规范字段
检查。助记符和寄存器名使用大写，8 位立即数使用两位小写十六进制，例如
`MOVI R1, #0x02`、`ADD R1, R2` 和 `JUMP #0x08`。保留 opcode 或未使用字段
非零的非规范编码统一输出四位小写十六进制 `.word 0xXXXX`，不产生合法别名。

步骤 3 只建立供后续 SDB 使用的接口，现有 `--trace`、summary 和错误输出不
调用反汇编器，因而其文本契约保持不变。

## 7. 输出与退出码

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
| 1 | CLI 或 HEX 镜像错误 |
| 2 | 实际执行非法指令或越界取指返回的非法字 |
| 3 | 达到最大周期数 |
| 4 | 最终寄存器或 PC 不匹配 |

## 8. 构建配置边界

仿真器构建通过根目录 `Dconfig` 接收 `DC_SIM_SDB` 和 `DC_SIM_WAVE`，两项
默认均为 `n`。当前步骤 1 只建立 `.config`、Make `auto.conf` 和 C++
`config.h` 的生成与传递；两个开关尚不改变 RTL、构建选项、CLI 或运行行为，
也不能据此声称 SDB 或 VCD 已实现。完整配置接口见
[`configuration.md`](configuration.md)。

默认配置下 Verilator 仍以 `VM_TRACE=0` 构建。`--trace` 仍只是既有的逐提交
文本输出参数，与尚未实现的 VCD 功能无关。

## 9. 构建与回归入口

```bash
make sim-build
make sim IMG=<hex> [STEPS=<n>] [TRACE=1]
make test-config
make test-disasm
make test-simulation
make test-integration
make test
make clean
```

`make sim` 要求 `IMG` 非空，`TRACE` 只能为空或 `1`。`make sim-build` 按
package、decoder、ALU、regfile、core、wrapper 的顺序构建
`build/verilator/Vsim_top`；项目 C++ 源采用 C++17，并执行
`-Wall -Wextra -Wpedantic` 语法检查。

`make test-disasm` 使用纯 C++17 自检穷举全部 65,536 个指令字，其中 2,384 个
规范编码必须生成精确汇编，其余编码必须生成精确 `.word`。该测试不创建或
驱动 Verilator 模型。`make test-simulation` 在独立
`build/verilator-test/` Mdir 中直接调用引擎，
与正式 `build/verilator/Vsim_top` 隔离。`make test-integration` 的 19 个 CLI
用例逐项比较精确退出码，并对 summary、trace、普通非法、越界、timeout 和
状态失配执行精确文本断言。`make test` 依次运行配置、反汇编、RTL
lint/模块测试、Simulation 引擎自检和 CLI 集成测试。`make clean` 只允许删除
仓库根目录的默认 `build/`；本地 `.config` 由 `make clean` 保留。
