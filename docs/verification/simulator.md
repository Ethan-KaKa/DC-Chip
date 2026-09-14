# Verilator 仿真器接口

本文定义唯一仿真可执行文件、镜像、命令行、停止条件和 difftest 边界。构建配置
见 [`configuration.md`](configuration.md)，体系结构协议见
[`../architecture/microarchitecture.md`](../architecture/microarchitecture.md)。

## 1. 构建与边界

`make sim-build` 按当前 `.config` 构建唯一的 `build/verilator/Vsim_top`。SDB、VCD、
NVBoard 和 difftest 是该执行引擎的可配置组成部分，不生成彼此分叉的主仿真器。

`sim/verilator/sim_top.sv` 包装 `dc_soc_top` 与仿真 IROM/DRAM。文件加载、DPI-C、
终端输出、波形和 GUI 只属于仿真边界；可综合 CPU 与 SoC 不依赖宿主文件系统。

## 2. 镜像

仿真器分别接收 instruction 与 data 镜像：

- `.bin`：原始小端字节流；instruction 从 IROM base 装载，data 从 DRAM base 装载；
- `.hex`：每个有效行一个 32 位、8 个十六进制字符的 word，可含空行和 `#` 注释；
- `--format auto` 按扩展名选择，也可显式指定 `hex` 或 `bin`；
- 镜像超过对应 64 KiB 容量、格式非法或文件不可读时，在复位释放前失败。

AM 软件构建生成 `.inst.bin` 与 `.data.bin`；段布局和提取方式见
[`../architecture/software-abi.md`](../architecture/software-abi.md)。

## 3. 命令行

```text
Vsim_top [--image PATH | --image-inst PATH] [options]
```

| 参数 | 作用 |
| --- | --- |
| `--image` / `--image-inst` | 指令 `.hex` 或 `.bin`；两者是同一参数的别名 |
| `--image-data` | 可选 DRAM 数据镜像 |
| `--format auto|hex|bin` | 强制或自动选择格式 |
| `--steps N` | 执行 N 次提交 |
| `--max-cycles N` | 周期上限，默认 100000 |
| `--trace` | 每次提交打印一行 trace |
| `--expect xN=VALUE` / `--expect pc=VALUE` | 检查最终架构状态，可重复 |
| `--sdb-off`、`--nvboard-off`、`--wave-off` | 运行时关闭已编译功能 |
| `--diff-ref-so PATH` | 使用外部参考动态库代替内置模型 |
| `--help` | 单独使用时显示帮助 |

非法、重复、缺值或越界参数在构造 DUT 前失败。软件测试通常不直接拼接这些参数，
而通过 `make sw tests` 调度。

## 4. 执行与停止

执行引擎按完整低电平/高电平时钟周期推进，提交数只在 `trace_valid` 上升。单步
指令会运行到下一次提交、fault、`tohost`、断点或 timeout；不会把周期数当提交数。

停止优先级为：

1. `tohost` program exit；
2. 新进入的 fault；
3. observer 或 monitor 失败；
4. breakpoint；
5. 请求的提交/周期数量完成；
6. timeout。

进程退出码契约：0=成功，1=输入/用法错误，2=架构 fault，3=timeout，
4=状态或 difftest 不匹配，5=guest 非零退出，6=用户退出交互调试器。

`tohost` 的地址与合法访问见
[`../architecture/memory-map.md`](../architecture/memory-map.md)。guest 写 0 表示成功；
非零值保留为 guest 失败码并使宿主返回 5。

## 5. Difftest

启用 `DC_SIM_DIFFTEST` 后，主执行循环在每条提交指令上调用同一 Difftest 引擎：

- 默认 backend 是仓库内 C++ `ReferenceModel`；
- `--diff-ref-so` 可动态加载符合接口的 Spike backend；
- 初始化时同步 IROM、DRAM 和架构状态；普通提交让参考端执行一步，并比较提交 PC、
  指令、下一 PC 与全部 16 个寄存器；
- fault 比较发生与 cause/PC，不把双方同时 fault 当作程序成功；
- `is_skip_ref` 只随已提交的 MMIO 访存出现。Difftest 仍核对提交 PC，
  load 时同步目标寄存器，其他指令只同步下一 PC，再比较全部寄存器；
- DRAM 和仿真 `tohost` 不使用 `skip_ref`。扩大跳过范围必须先更新微架构协议、
  ReferenceModel、测试与 ADR。

官方 Spike 是可选的第二裁判，不替代默认自包含参考模型。构建与适配问题见
[`../debugging.md`](../debugging.md)。

## 6. SDB、VCD 与 NVBoard

- SDB 支持继续、单步、寄存器、内存、断点、表达式、波形控制和退出；具体命令由
  运行时 `help` 输出定义，不在本文复制清单。
- 启用 VCD 时输出路径从实际 `BUILD_DIR` 推导；`waveoff` 启动时不创建文件，SDB
  可在运行中开启同一个 recorder。
- NVBoard 默认使用仓库 `tools/nvboard` submodule 和 `constr/nvboard.nxdc` 绑定仿真
  顶层信号；通用 `NVBOARD_HOME` 会被忽略。只有 `DC_NVBOARD_HOME` 可显式覆盖源码
  位置；其第三方对象与归档始终位于 `build/tools/nvboard/`，不得污染源码树。受控
  patch 令 GUI UART 解码器按 SoC 的每 bit 432 个仿真周期采样，且不从通用环境变量
  读取字体或图片资源。
- UART DPI-C 字符镜像和 NVBoard GUI 不改变 UART FIFO、串行引脚或 MMIO 状态机。

## 7. 验证入口

通过 `make testinfra list` 发现仿真基础设施测试，通过 `make sw tests list` 发现
软件系统测试。修改本接口后至少运行对应 `testinfra` 项；涉及配置、公开 CLI 或
外部契约时再运行 `make test`。不要使用已移除的旧 `make test-*` 或 `make lint*`
入口。
