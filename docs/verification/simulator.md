# DC-Chip Verilator 仿真器使用与接口约定

- 版本：v0.1
- 状态：阶段 D–E 基线及仿真配置步骤 1 已实现
- 更新日期：2026-09-10
- ISA 规范：[`../isa/isa.md`](../isa/isa.md)
- 验证计划：[`plan.md`](plan.md)

## 1. 适用范围

本文记录当前 Verilator behavioral simulation 的稳定使用接口，包括 DPI-C
取指边界、HEX 镜像格式、命令行参数、运行生命周期和退出码。实现位于
`sim/verilator/`，集成用例位于 `sim/tests/`。

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

## 5. 仿真生命周期与判定

CLI 和镜像校验成功后，驱动创建模型并执行：

1. 初始化 `clk=0`、`rst=1`，驱动两个完整同步复位周期；
2. 在低电平释放复位并清除加载期间产生的组合取指越界记录；
3. 每个非复位上升沿 `eval()` 后统计一次周期，并仅在 `trace_valid=1` 时
   增加提交计数；
4. 按“目标提交完成、非法状态、超时”的固定顺序判断结果；
5. 模型创建后的每个退出路径都调用 `final()`。

目标提交完成优先于检查该沿之后的组合状态，因此最后一次合法提交造成的
下一地址越界预取不会覆盖成功结果。尚未完成目标时，实际执行保留编码、
非规范编码或越界返回的 `0x8000` 均按非法指令处理。

## 6. 输出与退出码

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

## 7. 构建配置边界

仿真器构建通过根目录 `Dconfig` 接收 `DC_SIM_SDB` 和 `DC_SIM_WAVE`，两项
默认均为 `n`。当前步骤 1 只建立 `.config`、Make `auto.conf` 和 C++
`config.h` 的生成与传递；两个开关尚不改变 RTL、构建选项、CLI 或运行行为，
也不能据此声称 SDB 或 VCD 已实现。完整配置接口见
[`configuration.md`](configuration.md)。

默认配置下 Verilator 仍以 `VM_TRACE=0` 构建。`--trace` 仍只是既有的逐提交
文本输出参数，与尚未实现的 VCD 功能无关。

## 8. 构建与回归入口

```bash
make sim-build
make sim IMG=<hex> [STEPS=<n>] [TRACE=1]
make test-config
make test-integration
make test
make clean
```

`make sim` 要求 `IMG` 非空，`TRACE` 只能为空或 `1`。`make sim-build` 按
package、decoder、ALU、regfile、core、wrapper 的顺序构建
`build/verilator/Vsim_top`；项目 C++ 源采用 C++17，并执行
`-Wall -Wextra -Wpedantic` 语法检查。

`make test-integration` 对正向程序和负向输入逐项比较精确退出码，
`make test` 依次运行配置测试、lint、模块测试和集成测试。`make clean` 只允许删除
仓库根目录的默认 `build/`。所有生成物、fixture 和日志必须留在被忽略的
`/build/` 中；本地 `.config` 由 `make clean` 保留。
