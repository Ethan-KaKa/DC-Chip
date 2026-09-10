# DC-Chip 初版代码详细实施计划

- 状态：实施中（阶段 A 已完成，阶段 B–E 未执行）
- 更新日期：2026-09-10
- 上位构思：`docs/00-temp/initial-build-concept.md`
- 规范来源：`docs/isa/isa.md` v0.1

## 1. 目的与完成定义

本文档把初版构思细化为可以逐项实施和验收的代码计划。实现者不得在编码期间重新选择 ISA、模块边界、复位方式、取指协议或测试工具；确需改变时，必须先更新正式规格和本文档。

初版代码完成必须同时满足：

1. 8 条已分配指令全部按 ISA v0.1 执行；
2. 8 个保留 opcode 和所有非规范字段组合均能被识别为非法；
3. CPU 核心不包含 DPI-C、文件操作、仿真终止或厂商原语；
4. Icarus 模块级回归和 Verilator 端到端回归均自检通过；
5. `make lint`、`make sim`、`make test` 提供统一、可重复入口；
6. 所有失败路径返回非零状态并给出可定位的 PC、指令或输入行号；
7. 不宣称综合、时序、功耗或 FPGA 上板已经验证。

## 2. 实施范围与前置条件

### 2.1 本次代码范围

- SystemVerilog 2012 单周期 CPU 核心；
- 组合、零等待的指令存储器接口；
- Verilator DPI-C 指令存储器 wrapper；
- C++17 HEX loader、时钟驱动、trace 和状态检查；
- Icarus 自检模块 testbench；
- Verilator 集成测试、Makefile 和生成物忽略规则。

### 2.2 明确不做

- 数据存储器、load/store、MMIO 和外设；
- 条件分支、状态标志、`HALT`、中断和异常入口；
- 流水线、stall、flush、valid/ready 和 Cache；
- NEMU difftest、SDB、反汇编器、ELF 或 binary loader；
- NVBoard、Vivado 工程、Xilinx IP、XDC 和 bitstream；
- 汇编器、编译器、运行时和链接脚本。

### 2.3 开始 RTL 前的文档门槛

按照根 `AGENTS.md`，实现 CPU 主体 RTL 前需先为以下正式文档建立最小版本：

- `docs/requirements.md`：本里程碑的工作负载、功能范围和验证口径；数值性能、资源、功耗目标未知时写 `TODO`；
- `docs/architecture/microarchitecture.md`：归档本文确定的单周期数据流、端口、复位、提交和非法冻结行为；
- `docs/architecture/memory-map.md`：只定义 256×16-bit 指令字空间，数据和 MMIO 区域标 `TODO`；
- `docs/verification/plan.md`：归档模块级与集成回归矩阵；
- `docs/fpga/board.md`：板卡、器件、引脚和板级复位均按实际信息填写，未知项写 `TODO`。

阶段 A 已建立上述正式文档并完成一致性检查。后续阶段修改稳定接口或验证口径时，必须先更新对应正式文档；临时计划稿不得成为 RTL 或测试的规范依赖。

## 3. 目标源码布局

只在开始相应工作时创建目录和文件：

```text
rtl/core/
  dc_isa_pkg.sv
  decoder.sv
  alu.sv
  regfile.sv
  cpu_core.sv
sim/tb/
  tb_alu.sv
  tb_regfile.sv
  tb_decoder.sv
  tb_cpu_core.sv
sim/verilator/
  sim_top.sv
  main.cpp
  memory.cpp
  memory.h
sim/tests/
  run_integration.sh
  isa_smoke.hex
  jump_loop.hex
  illegal_reserved.hex
  illegal_noncanonical.hex
  malformed.hex
  too_wide.hex
  empty.hex
Makefile
.gitignore
build/                 # 生成物，不纳入版本管理
```

`build/` 在根 `.gitignore` 中使用 `/build/` 精确忽略。已有日志忽略规则继续生效；本阶段不生成波形，因此不预先增加 VCD/FST 规则。

## 4. RTL 公共约定

### 4.1 语言与风格

- 使用 SystemVerilog `.sv` 和 `logic` 类型；禁止隐式 net；
- 时序状态只在 `always_ff @(posedge clk)` 中使用非阻塞赋值；
- 组合逻辑使用 `always_comb` 或连续赋值，先给安全默认值；
- 常量使用显式位宽，不使用未定宽常量参与 PC 或数据运算；
- package 必须是 RTL 编译列表第一项；
- 不在 `rtl/core` 中使用 `initial`、`#delay`、`$finish`、DPI 或 Verilator 层次注释；
- 模块端口使用 `_i`/`_o` 后缀，内部状态寄存器使用 `_q`，下一状态使用 `_d`。

### 4.2 `dc_isa_pkg.sv`

package 集中定义：

```systemverilog
localparam int unsigned INST_WIDTH = 16;
localparam int unsigned DATA_WIDTH = 16;
localparam int unsigned REG_ADDR_WIDTH = 2;
localparam int unsigned REG_COUNT = 4;
localparam int unsigned PC_WIDTH = 8;

typedef enum logic [3:0] {
  OPC_MOVI = 4'h0,
  OPC_MOV  = 4'h1,
  OPC_ADDI = 4'h2,
  OPC_ADD  = 4'h3,
  OPC_SUB  = 4'h4,
  OPC_AND  = 4'h5,
  OPC_OR   = 4'h6,
  OPC_JUMP = 4'h7
} opcode_e;

typedef enum logic [2:0] {
  ALU_PASS_B,
  ALU_ADD,
  ALU_SUB,
  ALU_AND,
  ALU_OR
} alu_op_e;
```

不为 `0x8`–`0xF` 创建有效枚举项。硬件中的字段切片仍按 ISA 固定位置 `[15:12]`、`[11:10]`、`[9:8]`、`[7:0]`，不要通过结构体重排位序。

## 5. RTL 模块设计

### 5.1 `decoder.sv`

接口固定为：

| 方向 | 端口 | 类型/宽度 |
| --- | --- | --- |
| input | `inst_i` | `logic [15:0]` |
| output | `rd_addr_o` | `logic [1:0]` |
| output | `rs_addr_o` | `logic [1:0]` |
| output | `imm_o` | `logic [15:0]` |
| output | `alu_op_o` | `alu_op_e` |
| output | `alu_src_imm_o` | `logic` |
| output | `reg_write_o` | `logic` |
| output | `jump_o` | `logic` |
| output | `legal_o` | `logic` |

字段输出始终直接来自指令；`imm_o={8'h00,inst_i[7:0]}`。组合块默认设置为 `legal_o=0`、`reg_write_o=0`、`jump_o=0`、`alu_src_imm_o=0` 和 `alu_op_o=ALU_PASS_B`，再按 opcode 覆盖。

控制表固定如下：

| Opcode | 规范条件 | ALU | B 输入 | 写寄存器 | 跳转 |
| --- | --- | --- | --- | --- | --- |
| `MOVI` | `rs==0` | `PASS_B` | `imm_o` | 是 | 否 |
| `MOV` | `imm8==0` | `PASS_B` | `Rs` | 是 | 否 |
| `ADDI` | `rs==0` | `ADD` | `imm_o` | 是 | 否 |
| `ADD` | `imm8==0` | `ADD` | `Rs` | 是 | 否 |
| `SUB` | `imm8==0` | `SUB` | `Rs` | 是 | 否 |
| `AND` | `imm8==0` | `AND` | `Rs` | 是 | 否 |
| `OR` | `imm8==0` | `OR` | `Rs` | 是 | 否 |
| `JUMP` | `rd==0 && rs==0` | `PASS_B` | 不使用 | 否 | 是 |
| 其他 | 无 | 安全默认 | 不使用 | 否 | 否 |

使用普通 `case` 加 `default`，不使用 `casex/casez`；含 X/Z 的 opcode 或规范条件不得变成合法指令。

### 5.2 `alu.sv`

接口固定为两个 16 位操作数、一个 `alu_op_e` 和一个 16 位结果：

```text
lhs_i[15:0], rhs_i[15:0], op_i -> result_o[15:0]
```

行为：

- `ALU_PASS_B`：返回 `rhs_i`；
- `ALU_ADD`：返回 `lhs_i + rhs_i` 的低 16 位；
- `ALU_SUB`：返回 `lhs_i - rhs_i` 的低 16 位；
- `ALU_AND`：逐位与；
- `ALU_OR`：逐位或；
- default：返回 `16'h0000`。

ALU 不产生 carry、overflow、zero 或 sign 标志，也不自行判断指令合法性。

### 5.3 `regfile.sv`

接口固定为：

```text
clk_i, rst_i
raddr_a_i[1:0] -> rdata_a_o[15:0]
raddr_b_i[1:0] -> rdata_b_o[15:0]
we_i, waddr_i[1:0], wdata_i[15:0]
debug_regs_o[63:0]
```

- 两个读端口为组合读；
- 写端口在上升沿且 `we_i=1` 时更新；
- `rst_i=1` 的上升沿优先清零全部四个寄存器；
- `R0` 与其他寄存器完全相同，可读可写；
- `debug_regs_o={regs_q[3],regs_q[2],regs_q[1],regs_q[0]}`；
- 写沿前读到旧值，写沿后组合读和 debug 总线反映新值。

### 5.4 `cpu_core.sv`

公共接口固定为：

| 方向 | 端口 | 宽度 | 语义 |
| --- | --- | --- | --- |
| input | `clk` | 1 | 上升沿提交 |
| input | `rst` | 1 | 同步高有效复位 |
| output | `imem_addr` | 8 | 当前执行 PC |
| input | `imem_rdata` | 16 | 零等待组合指令字 |
| output | `trace_valid` | 1 | 最近一个上升沿提交了合法指令 |
| output | `trace_pc` | 8 | 最近合法提交的指令 PC |
| output | `trace_inst` | 16 | 最近合法提交的指令字 |
| output | `debug_regs` | 64 | `{R3,R2,R1,R0}` |
| output | `illegal_inst` | 1 | 粘滞非法状态 |

组合数据流：

1. `imem_addr=pc_q`；
2. decoder 解析 `imem_rdata`；
3. regfile 用 `rd`、`rs` 同时读取两个值；
4. `lhs=Rd`，`rhs` 根据 `alu_src_imm` 选择 `Rs` 或零扩展立即数；
5. 默认 `pc_d=pc_q+8'd1`，`jump_o=1` 时改为 `imm_o[7:0]`；
6. regfile 写使能为 `legal && reg_write && !illegal_q && !rst`；
7. 写地址为 `rd`，写数据为 ALU 结果。

核心时序逻辑：

```text
if rst:
    pc=0, illegal=0, trace_valid=0, trace_pc=0, trace_inst=0
else:
    trace_valid=0
    if illegal already set:
        keep PC and trace payload, do not write registers
    else if decoder says illegal:
        illegal=1, keep PC and trace payload, do not write registers
    else:
        pc=pc_d
        trace_valid=1
        trace_pc=old pc
        trace_inst=current imem_rdata
```

regfile 使用同一个 `rst` 独立同步复位。连续合法执行时 `trace_valid` 可以连续多个周期保持高电平；C++ 驱动只在每个上升沿后采样一次，因此每次采样代表一条提交。

### 5.5 非法状态与未知值

- 首次非法指令所在上升沿置位 `illegal_inst`；该指令不提交；
- `trace_pc/trace_inst` 保留最近一次合法提交，不伪装成非法指令 trace；
- 当前非法 PC 和指令由仿真 wrapper 的 `fetch_pc/fetch_inst` 提供诊断；
- 非法状态置位后，即使组合输入变化也不得恢复执行；
- reset 是唯一恢复方式；
- RTL testbench 要显式验证 opcode 含 X 时不会产生寄存器写使能或跳转。

## 6. 仿真 wrapper

`sim_top.sv` 是仿真专用顶层，端口包括 `clk`、`rst`，以及传给 C++ 的：

```text
trace_valid
trace_pc[7:0]
trace_inst[15:0]
debug_regs[63:0]
illegal_inst
fetch_pc[7:0]
fetch_inst[15:0]
```

wrapper 导入：

```systemverilog
import "DPI-C" function int unsigned sim_imem_read(
  input int unsigned word_addr
);
```

组合调用时把 `fetch_pc` 零扩展为 32 位，DPI 返回值低 16 位赋给 `fetch_inst` 和核心 `imem_rdata`。高 16 位忽略。wrapper 不包含时钟生成、复位生成、`$finish` 或程序状态判断。

## 7. C++ 指令内存

### 7.1 `memory.h` 接口

```cpp
bool load_hex_image(const std::string &path, std::string *error);
std::size_t image_word_count();
void clear_fetch_status();
bool fetch_out_of_bounds();
std::uint32_t first_oob_address();
extern "C" std::uint32_t sim_imem_read(std::uint32_t word_addr);
```

除 DPI 函数外，其余符号放入项目命名空间，避免全局名称污染。

### 7.2 HEX 解析算法

逐行执行：

1. 保存一基行号；
2. 删除第一个 `#` 及其后内容；
3. 删除首尾 ASCII 空白；
4. 空行跳过且不占指令地址；
5. 非空内容必须恰好 4 个十六进制字符；
6. 使用无符号转换得到 `uint16_t`；
7. 第 257 个有效指令出现时立即报容量错误。

文件不存在、不可读、没有有效指令、字符非法、长度不是 4 或容量超限均返回 `false`，错误文本包含路径和行号。先解析到临时 vector，全部成功后再替换全局镜像，避免失败加载留下半份数据。

### 7.3 DPI 读取行为

- `word_addr < image.size()`：返回对应 16 位指令的零扩展值；
- 否则：保存第一次越界地址、设置越界标志并返回 `0x00008000`；
- DPI 函数本身不打印，避免一次组合求值被多次调用时刷屏；
- driver 仅在核心真正因该返回值进入非法状态时报告越界。

最后一条规则很重要：一条正常的最终指令提交后，组合逻辑可能立即预取镜像末尾之外的下一 PC。若指定提交步数已经达到，driver 必须先正常结束，不能因这个尚未提交的组合预取误报失败。

## 8. C++ 驱动

### 8.1 CLI

可执行文件名为 `Vsim_top`，支持：

```text
--image <path>             必选
--steps <positive-u64>     可选，默认等于有效指令数
--trace                    可选，逐提交打印
--expect <name=value>      可重复，name 为 r0/r1/r2/r3/pc
--max-cycles <positive-u64> 可选，默认 steps+4
--help                     打印帮助并返回 0
```

数字接受十进制或 `0x` 前缀十六进制。寄存器期望值必须在 `0x0000`–`0xFFFF`，PC 必须在 `0x00`–`0xFF`。未知参数、缺值、零、负数、溢出、未知 expectation 名或重复 expectation 均返回退出码 1。

允许 `max-cycles < steps`，用于验证超时路径。计算默认 `steps+4` 时必须检查无符号溢出。

### 8.2 仿真生命周期

1. 解析 CLI 并加载 HEX；
2. 调用 `Verilated::commandArgs`，建立 context 和 `Vsim_top`；
3. 设置 `clk=0`、`rst=1` 并求值；
4. 驱动两个完整复位周期，每个周期依次 `clk=0/eval`、`clk=1/eval`；
5. 在低电平解除 `rst` 并求值；
6. 逐周期推进，在每个上升沿 `eval` 后采样输出；
7. 核心 `illegal_inst=1` 时返回 2，并用 `fetch_pc/fetch_inst` 和内存越界状态区分诊断；
8. `trace_valid=1` 时提交计数加一，并在启用 trace 时打印；
9. 提交计数达到 `steps` 时立即比较期望状态并结束；
10. 尚未完成且周期计数达到 `max-cycles` 时返回 3；
11. 调用 `final()`，释放模型与 context。

上升沿后的判断顺序固定为：已提交步数完成检查、非法状态、继续运行、超时。完成检查只基于本沿实际 `trace_valid`；这样最终合法提交后的组合越界预取不会覆盖成功结果，而之前已经置位的非法状态也不可能被当作提交。

### 8.3 Trace 与摘要

启用 `--trace` 时每条提交输出：

```text
cycle=1 commit=1 pc=0x00 inst=0x0402 r0=0x0000 r1=0x0002 r2=0x0000 r3=0x0000
```

无论是否启用 trace，正常结束输出提交数、周期数、最终 PC 和四个寄存器。失败输出原因和最小上下文，不打印未经测量的 IPC、频率或功耗。

### 8.4 退出码

| 退出码 | 条件 |
| --- | --- |
| 0 | 帮助输出，或达到目标提交数且全部 expectation 匹配 |
| 1 | CLI 或 HEX 加载错误 |
| 2 | 保留 opcode、非规范编码或实际执行到的越界取指 |
| 3 | 最大周期数耗尽 |
| 4 | 最终寄存器或 PC 不匹配 |

资源清理在所有已经建立 Verilated 模型的退出路径执行。

## 9. 构建系统

### 9.1 变量与源文件顺序

根 Makefile 定义：

```make
VERILATOR ?= verilator
IVERILOG  ?= iverilog
VVP       ?= vvp
CXX       ?= c++
BUILD_DIR ?= build
```

RTL 源列表显式列出，`dc_isa_pkg.sv` 必须在首位，不使用递归 `find` 收集未知生成物。C++ 使用 `-std=c++17 -Wall -Wextra -Wpedantic`。

### 9.2 目标契约

当前阶段 A 只实现 `make check-tools` 和 `make help`。`help` 将其余目标明确标记为后续阶段规划接口；下列目标只有在对应阶段完成后才可宣称可用或已经验证。

- `make check-tools`：依次检查 `verilator`、`iverilog`、`vvp` 和 C++17 编译器是否可执行，打印实际版本；任一工具缺失或不满足构建要求时给出工具名并失败，不自动安装；
- `make help`：列出本节中真实存在的目标，以及 `BUILD_DIR`、`IMG`、`STEPS` 和 `TRACE` 参数；执行帮助不得隐式编译、运行测试或创建 `build/`；
- `make lint-comb`：只对 package、decoder 和 ALU 运行 Verilator `--lint-only -Wall`，用于组合模块阶段的最小 lint 门禁；
- `make lint`：对全部核心 RTL 运行 Verilator `--lint-only -Wall --top-module cpu_core`；warning 导致失败，不使用 `-Wno-fatal` 掩盖问题；
- `make test-alu`、`make test-decoder`、`make test-regfile`、`make test-core`：分别编译并运行对应 Icarus 自检 testbench，输出位于 `build/unit/`；
- `make test-unit`：严格按 ALU、decoder、regfile、cpu_core 的顺序聚合上述四个细粒度目标，任一失败立即停止；
- `make sim-build`：用 Verilator `--cc --exe --build --top-module sim_top --Mdir build/verilator` 建立 C++ 仿真器；
- `make sim IMG=<hex> [STEPS=<n>] [TRACE=1]`：先构建，再运行指定镜像；缺少 `IMG` 时给出用法并失败；
- `make test-integration`：构建仿真器后调用 `sim/tests/run_integration.sh`；
- `make test`：严格按 lint、unit、integration 顺序运行，任何一级失败立即停止；
- `make clean`：只删除已解析的仓库根 `build/`，不删除源码、文档、镜像或其他目录；

Makefile 不自动安装工具，不依赖 `/home/kaka/ysyx-workbench`，也不读取 NPC 生成物。工具缺失时保留原始 command-not-found 或提供清晰的检查错误。

## 10. 模块级测试

所有 testbench 使用 SystemVerilog 自检和 `$fatal(1, ...)` 报错；成功时打印单行 PASS 后 `$finish`。每个测试设置有限超时，禁止无限等待。

### 10.1 `tb_alu.sv`

覆盖：

- `PASS_B` 的零、全一和交替位；
- 普通 ADD/SUB；
- `16'hFFFF + 1 = 0`；
- `0 - 1 = 16'hFFFF`；
- AND/OR 的零、全一、`16'hAAAA`/`16'h5555`；
- 非法 ALU 枚举值返回零。

### 10.2 `tb_regfile.sv`

覆盖：

- 复位上升沿清零四个寄存器；
- `we=0` 时状态保持；
- 逐一写读 `R0`–`R3`；
- 两个组合读端口可同时读取不同寄存器；
- 写沿前为旧值、写沿后为新值；
- reset 与 write 同时有效时 reset 优先；
- `debug_regs` 拼接顺序正确。

### 10.3 `tb_decoder.sv`

覆盖：

- 8 个规范示例机器码及全部控制输出；
- `MOVI/ADDI` 的非零 `rs`；
- `MOV/ADD/SUB/AND/OR` 的非零 `imm8`；
- `JUMP` 的非零 `rd` 或 `rs`；
- `0x8`–`0xF` 每个保留 opcode；
- opcode 含 X 时 `legal=0`、`reg_write=0`、`jump=0`。

### 10.4 `tb_cpu_core.sv`

使用 testbench 内的 256×16-bit 组合 ROM，不使用 DPI。覆盖：

- 两周期同步复位期间无提交且架构状态全零；
- ISA smoke 程序连续 8 次提交的每条 PC、指令和最终状态；
- `JUMP` 不写寄存器，下一提交来自目标地址；
- 普通指令在 PC `0xFF` 提交后回绕到 `0x00`；
- 非法指令当拍不提交、不写寄存器、PC 保持；
- 非法状态后即使 ROM 内容变化仍冻结，复位后恢复；
- 连续合法指令下 `trace_valid` 每个采样沿均为 1，trace payload 对应当拍旧 PC。

## 11. Verilator 集成测试

### 11.1 正向镜像

`isa_smoke.hex`：

```text
0402
1900
2408
3600
4600
5600
6600
7008
```

运行 8 步，期望：

```text
R0=0x0000 R1=0x0002 R2=0x0002 R3=0x0000 PC=0x08
```

`jump_loop.hex`：

```text
0401
2401
7001
```

运行 5 步，执行序列为 PC `0,1,2,1,2`，期望 `R1=0x0003`、`PC=0x01`。

### 11.2 非法与输入错误

- `illegal_reserved.hex` 首条为 `8000`，期望退出 2；
- `illegal_noncanonical.hex` 首条为 `0100`，即 `MOVI` 的 `rs!=0`，期望退出 2；
- `malformed.hex` 包含非十六进制字符，期望退出 1；
- `too_wide.hex` 包含 5 位数据，期望退出 1；
- `empty.hex` 只有空白或注释，期望退出 1；
- 不存在的路径期望退出 1；
- runner 在 `build/test-fixtures/` 生成 257 行镜像，期望退出 1；
- `jump_loop.hex --steps 5 --max-cycles 2` 期望退出 3；
- smoke 使用错误 `--expect r1=0`，期望退出 4；
- 重复 expectation 和未知 CLI 参数期望退出 1。

### 11.3 Runner 规则

`run_integration.sh` 使用 `set -euo pipefail`，接收仿真器绝对或仓库相对路径，定义 `expect_success` 和 `expect_exit` helper。每个负向用例必须核对精确退出码，不能只接受“非零”。临时生成物只写入 `build/test-fixtures/`。

## 12. 实施阶段与验收点

本节的五个阶段是累积门禁，不是可以并行完成的任务清单。阶段 N 的退出条件全部满足并留下验证记录后，才允许进入阶段 N+1。每个阶段至少记录执行日期、实际命令、PASS/FAIL、`make check-tools` 报告的工具版本和未执行项；完整原始日志只保存在被 `/build/` 忽略的生成目录中，不纳入版本管理。

任何命令失败时立即停止当前阶段，不继续运行本阶段后续命令，也不得开始下一阶段。修复应限制在能够解释失败的最小层级，不得通过改变 ISA、放宽非法编码检查、删除或跳过断言、忽略 warning、延长至无上限超时或修改约定退出码来制造通过。修复后先重跑原失败目标，再从阶段 A 开始按顺序重跑截至当前阶段的全部累计门禁。

### 阶段 A：规格与构建骨架

**执行状态：已完成（2026-09-10）**

- 已建立五份正式规格、`dc_isa_pkg.sv`、显式源列表、根 Makefile 和 `/build/` 忽略规则；
- `make check-tools`：PASS；实际环境为 GNU Make 4.3、Verilator 5.041 devel、Icarus/vvp 13.0 devel、G++ 13.3.0，C++17 syntax check PASS；
- `make help`：PASS；只将阶段 A 的两个目标列为可用，阶段 B–E 目标明确标记为未实现，执行前后均未创建 `build/`；
- package Icarus 语法探测、缺失工具负向检查、正式文档独立性、源列表顺序、Markdown、空目录和生成物审阅均通过；
- 详细执行证据记录在 `docs/verification/plan.md`，阶段 B–E 仍为未执行。

**进入条件**

- `docs/isa/isa.md` v0.1 仍是唯一 ISA 规范源，本文与上位构思已完成审阅；
- 尚未开始 CPU 主体 RTL；第 2.3 节所列正式文档允许以未知项为 `TODO`，但不得把未决板卡、存储或性能参数固化为事实。

**本阶段修改内容**

- 完成 `docs/requirements.md`、`docs/architecture/microarchitecture.md`、`docs/architecture/memory-map.md`、`docs/verification/plan.md` 和 `docs/fpga/board.md` 的最小正式版本；
- 仅按实际文件创建目录，加入根 Makefile 和根 `.gitignore` 中的 `/build/` 精确规则，不创建空占位目录；
- 加入 `dc_isa_pkg.sv` 和显式 RTL/testbench 源列表，保证 package 位于每个相关编译列表首项；
- 实现本阶段即可独立工作的 `check-tools` 和 `help`，后续目标可以先以明确的依赖文件为前提，但 `help` 中不得宣称尚未实现的目标已经验证通过。

**按顺序执行的验证命令**

```bash
make check-tools
make help
```

**预期结果**

- `make check-tools` 返回 0，逐项打印 Verilator、Icarus Verilog、vvp 和 C++ 编译器的实际版本；若环境缺工具，本阶段必须停在此处并把后续项记为未执行；
- `make help` 返回 0，列出的目标和参数与第 9.2 节一致，且不创建 `build/`；
- 人工审阅确认正式规格不与 ISA 冲突、源列表顺序明确、仓库中没有空目录或被跟踪的生成物。

**退出条件**

- 两条命令均通过，正式文档门槛与构建骨架审阅通过；
- 阶段记录包含命令、结果、工具版本和所有仍为 `TODO` 的未决项。

**失败后的停止与重测规则**

- 任一工具缺失、帮助与实际目标不一致、规格冲突或生成物规则错误时停止，不得开始 decoder/ALU；
- 修复后先重跑失败的检查，再依次重跑 `make check-tools`、`make help`，两项均通过后才可退出阶段 A。

### 阶段 B：组合译码与 ALU

**进入条件**

- 阶段 A 的退出条件全部满足，且阶段 A 的验证记录可复查；
- decoder、ALU 的端口、合法编码和非规范字段行为仍与第 4、5 节及 ISA v0.1 一致。

**本阶段修改内容**

- 完成 `dc_isa_pkg.sv`、`decoder.sv`、`alu.sv`、`tb_decoder.sv` 和 `tb_alu.sv`；
- 实现 `lint-comb`、`test-alu` 和 `test-decoder` 细粒度目标，测试失败必须返回非零状态。

**按顺序执行的验证命令**

```bash
make lint-comb
make test-alu
make test-decoder
```

**预期结果**

- `make lint-comb` 无 warning、error 或 latch 报告并返回 0；
- `make test-alu` 覆盖第 10.1 节全部算术、按位、回绕和非法操作边界，打印单行 PASS 并返回 0；
- `make test-decoder` 验证 8 条合法 opcode、`0x8`–`0xF` 的 8 个保留 opcode、全部列出的非规范字段类型以及含 X opcode 的安全输出，打印单行 PASS 并返回 0。

**退出条件**

- 三条命令依次通过；所有 8 条基础指令的规范编码和每类非法编码均有自检断言；
- 阶段 A、B 的累计门禁复跑通过并完成记录。

**失败后的停止与重测规则**

- 首个失败即停止，不得为 ALU/decoder 单测失败继续接入 regfile 或 cpu_core；
- 修复后先重跑失败目标，再依次重跑阶段 A 的两项命令和本阶段三项命令，全部通过后才可进入阶段 C。

### 阶段 C：寄存器堆与 CPU 核心

**进入条件**

- 阶段 A、B 的累计门禁全部通过；
- reset、`R0` 可写、PC、trace、非法冻结与恢复语义已经归档到正式微架构和验证文档。

**本阶段修改内容**

- 完成 `regfile.sv`、`cpu_core.sv`、`tb_regfile.sv` 和 `tb_cpu_core.sv`；
- 实现 `test-regfile`、`test-core` 和聚合的 `test-unit`，并把 `lint` 扩展到全部核心 RTL；
- 保持 `rtl/core/` 不含 DPI-C、文件操作、仿真终止和厂商原语。

**按顺序执行的验证命令**

```bash
make lint
make test-regfile
make test-core
make test-unit
```

**预期结果**

- `make lint` 对全部核心 RTL 零 warning、零 error 并返回 0；
- `make test-regfile` 验证同步复位、写保持、`R0`–`R3` 可写、双组合读、沿前/沿后值、复位优先级和 debug 拼接顺序；
- `make test-core` 验证复位、PC 递增与回绕、JUMP、8 条指令 smoke、逐提交 trace 对齐、非法当拍不提交、粘滞冻结及 reset 恢复；
- `make test-unit` 从 ALU 开始依次重跑全部四个模块测试，四项均打印 PASS，任何子项失败都使聚合目标返回非零。

**退出条件**

- 四条命令依次通过，纯 SystemVerilog 环境已经覆盖全部基础指令和核心非法状态语义；
- 代码审阅确认 `R0` 未被实现为常零，trace 对应旧 PC，核心没有仿真或厂商依赖；
- 阶段 A–C 的累计门禁复跑通过并完成记录。

**失败后的停止与重测规则**

- 首个失败即停止，不得继续实现或联调 DPI wrapper；应在 regfile/core 的最小失败层修复，不能用 testbench 延时或跳过 trace 比较掩盖时序错误；
- 修复后先重跑失败目标，再从阶段 A 起按原顺序重跑截至 `make test-unit` 的全部门禁，全部通过后才可进入阶段 D。

### 阶段 D：DPI-C 端到端闭环

**进入条件**

- 阶段 A–C 的累计门禁全部通过；
- DPI 边界、HEX loader、CLI、退出码、完成检查优先级和两个正向镜像的期望状态与第 6–11 节一致。

**本阶段修改内容**

- 完成 `sim_top.sv`、`memory.h`、`memory.cpp`、`main.cpp`、`isa_smoke.hex` 和 `jump_loop.hex`；
- 实现 `sim-build` 和 `sim`，但本阶段用已构建的 `Vsim_top` 直接传入完整参数，以固定端到端验收口径；
- trace 输出必须足以核对每次提交的 PC、指令和寄存器状态。

**按顺序执行的验证命令**

```bash
make sim-build
build/verilator/Vsim_top --image sim/tests/isa_smoke.hex --steps 8 --trace \
  --expect r0=0x0000 --expect r1=0x0002 --expect r2=0x0002 \
  --expect r3=0x0000 --expect pc=0x08
build/verilator/Vsim_top --image sim/tests/jump_loop.hex --steps 5 --trace \
  --expect r0=0x0000 --expect r1=0x0003 --expect r2=0x0000 \
  --expect r3=0x0000 --expect pc=0x01
```

上述路径使用默认 `BUILD_DIR=build`；若实施时覆盖 `BUILD_DIR`，三条命令必须一致改用同一已解析目录并在验证记录中写明。

**预期结果**

- `make sim-build` 完成 Verilator/C++17 构建并返回 0；
- smoke 提交恰好 8 次，trace PC 依次为 `0,1,2,3,4,5,6,7`，最终 `R0=0x0000 R1=0x0002 R2=0x0002 R3=0x0000 PC=0x08`；
- jump-loop 提交恰好 5 次，trace PC 依次为 `0,1,2,1,2`，最终 `R0=0x0000 R1=0x0003 R2=0x0000 R3=0x0000 PC=0x01`；
- 两次运行均返回 0；达到最后一次目标提交后出现的组合越界预取不触发退出码 2，也不覆盖成功结果。

**退出条件**

- 三条命令依次通过，trace 序列、提交数与所有显式 expectation 完全匹配；
- 阶段 A–D 的累计门禁复跑通过并完成记录。

**失败后的停止与重测规则**

- 构建、trace、状态或越界处理任一失败即停止，不得提前加入负向 runner，也不得通过增加多余提交、忽略预取状态或放宽 expectation 绕过；
- 修复后先重跑失败目标或失败镜像，再从阶段 A 起按原顺序重跑截至本阶段两个正向镜像的全部门禁，全部通过后才可进入阶段 E。

### 阶段 E：完整正负回归

**进入条件**

- 阶段 A–D 的累计门禁全部通过；
- 第 8.4 节退出码契约已经冻结，所有负向测试都能唯一映射到预期退出码。

**本阶段修改内容**

- 加入 `illegal_reserved.hex`、`illegal_noncanonical.hex`、`malformed.hex`、`too_wide.hex`、`empty.hex` 和 `run_integration.sh`；
- runner 覆盖实际执行非法指令、文件不存在、空镜像、格式错误、超宽行、257 个有效字、超时、最终状态失配、重复 expectation 和未知 CLI 参数；
- 实现 `test-integration` 和总 `test`，确保负向 helper 核对精确退出码，而不是只接受任意非零。

**按顺序执行的验证命令**

```bash
make test-integration
make test
make clean && make test
```

第三条命令是干净重建门禁：`make clean` 成功后才执行完整回归，不允许复用旧的 `build/` 结果。验收完成后执行 `make clean` 清理生成目录；用 `git status --short` 和 `git ls-files build '*.log' '*.vcd' '*.fst'` 审阅时，生成物不得出现在已跟踪或待纳入版本管理的文件中。

**预期结果**

- `make test-integration` 的两个正向程序返回 0；非法指令返回 2，loader/CLI 错误返回 1，超时返回 3，状态失配返回 4，并且每个负向用例都核对精确退出码；
- `make test` 严格按 lint、四个模块测试、集成测试顺序全部通过；
- `make clean && make test` 能从空的默认生成目录重建并重复得到相同结果；
- 最终审阅确认 `/build/` 忽略有效，没有 `build/`、日志或波形生成物被跟踪，且大日志没有写入源码目录。

**退出条件**

- 三条门禁命令依次通过，所有正向、非法、loader、timeout、状态失配和 CLI 用例都有可定位结果；
- 清理与版本控制审阅通过，阶段 A–E 的最终验证记录完整；
- 证据只标记为 Icarus/Verilator behavioral simulation，不宣称综合、时序、功耗或 FPGA 上板通过。

**失败后的停止与重测规则**

- 首个失败即停止发布或宣称初版完成；必须保留失败命令、精确退出码和最小上下文，并在对应的最低层级修复；
- 修复后先重跑失败目标，再从阶段 A 起按顺序重跑全部累计门禁，最后再次执行 `make clean && make test`；只有所有命令通过且生成物审阅无误，阶段 E 才可退出。

## 13. 设计影响与风险检查

- 受影响层：ISA 落地、CPU 核心、behavioral simulation 和验证入口；不影响 SoC、软件 ABI、FPGA wrapper 或 XDC。
- 流水线风险：初版无流水线和 valid/ready，不存在 stall/flush 丢事务问题；未来引入握手后不能复用“一拍一提交”假设。
- 关键风险：规范字段检查遗漏、`R0` 被误做常零、立即数误符号扩展、JUMP 被误做相对/字节地址、trace 采到下一条 PC、组合 DPI 越界预取误判、package 编译顺序错误。
- 仿真证据边界：Icarus/Verilator 通过只证明相应 behavioral simulation；不能推断综合、post-synth、post-implementation、时序收敛或上板结果。
- 外部代码：只借鉴 NPC 的组织方法，不复制其 RV32IM、SoC、调试或生成代码；如后续复制任何代码，先检查许可证并记录来源。

## 14. 当前工具环境

阶段 A 通过 `make check-tools` 确认的本机工具为：

- Verilator 5.041 development build；
- Icarus Verilog/vvp 13.0 development build；
- GCC/G++ 13.3.0；
- GNU Make 4.3。

这些版本是 2026-09-10 阶段 A 的实际执行环境，不是兼容性承诺。命令和结果已记录到 `docs/verification/plan.md`；更换环境或开始后续阶段时必须重新运行工具检查。
