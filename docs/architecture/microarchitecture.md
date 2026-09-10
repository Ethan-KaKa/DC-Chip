# DC-Chip 初版 CPU 微架构

- 版本：v0.1
- 状态：初版 CPU 实施基线
- 更新日期：2026-09-10
- ISA 规范：`docs/isa/isa.md` v0.1

## 1. 总体结构

初版核心是单周期、顺序、单发射设计。合法指令在组合零等待指令接口下于一个上升沿提交，没有流水级、stall、flush 或分支预测。

```text
PC -> instruction interface -> decoder -> regfile -> ALU -> writeback
 |                                |                    |
 +---------------------------- next PC <--------------+
```

核心由以下可综合模块组成：

- `dc_isa_pkg`：公共宽度、opcode 和 ALU 操作类型；
- `decoder`：字段拆分、控制生成和非法编码检查；
- `alu`：16 位组合算术与逻辑；
- `regfile`：4×16-bit 双组合读、单同步写寄存器堆；
- `cpu_core`：PC、提交状态、非法状态和模块连接。

## 2. 核心接口

| 方向 | 端口 | 宽度 | 语义 |
| --- | --- | --- | --- |
| input | `clk` | 1 | 上升沿提交状态 |
| input | `rst` | 1 | 同步高有效核心复位 |
| output | `imem_addr` | 8 | 当前执行 PC，单位为 16 位指令字 |
| input | `imem_rdata` | 16 | 当前地址的零等待组合指令字 |
| output | `trace_valid` | 1 | 最近一个上升沿提交了合法指令 |
| output | `trace_pc` | 8 | 最近一次合法提交的旧 PC |
| output | `trace_inst` | 16 | 最近一次合法提交的指令字 |
| output | `debug_regs` | 64 | `{R3,R2,R1,R0}` |
| output | `illegal_inst` | 1 | 粘滞非法状态，复位清零 |

`debug_regs` 和 trace 端口只提供验证可见性，不参与执行控制。核心不得依赖仿真器内部层次路径读取架构状态。

## 3. 单周期数据流

1. `pc_q` 组合驱动 `imem_addr`；
2. 指令接口在同一周期组合返回 `imem_rdata`；
3. decoder 解析 `opcode=inst[15:12]`、`rd=inst[11:10]`、`rs=inst[9:8]` 和 `imm8=inst[7:0]`；
4. regfile 同时读取 `Rd` 当前值和 `Rs` 当前值；
5. ALU 左操作数为 `Rd`，右操作数选择 `Rs` 或零扩展 `imm8`；
6. 默认 next PC 为 `pc_q + 8'd1`，`JUMP` 使用 `imm8` 作为绝对字地址；
7. 合法寄存器写和 PC 更新在同一上升沿发生；trace 同时记录该沿提交的旧 PC 与当前指令。

16 位加减法自然丢弃高位。立即数只做零扩展。`R0` 与其他寄存器完全相同，可读可写。

## 4. 控制与提交

decoder 的安全默认值必须禁止写寄存器、禁止跳转并标记非法。只有满足 ISA v0.1 规范字段约束的 `0x0`–`0x7` opcode 才能覆盖为合法控制。

正常时序行为如下：

```text
if rst:
    PC, R0-R3, trace payload, trace_valid, illegal_inst <- 0
else if illegal_inst:
    keep PC, registers and trace payload; trace_valid <- 0
else if current instruction is illegal:
    illegal_inst <- 1; keep PC, registers and trace payload; trace_valid <- 0
else:
    execute instruction; update PC; trace_valid <- 1
    trace_pc <- old PC; trace_inst <- current instruction
```

连续合法执行时 `trace_valid` 可以连续为 1。非法指令所在上升沿不产生提交，reset 是非法冻结状态的唯一恢复方式。

## 5. 复位

核心 `rst` 为同步高有效信号；只有上升沿采样到 `rst=1` 时才清零状态。regfile 与 `cpu_core` 使用同一复位，并保证 reset 优先于寄存器写和正常提交。

板级输入极性、异步输入同步器和复位释放电路属于 FPGA wrapper，尚为 `TODO`，不得进入可移植核心。

## 6. 指令访问协议

- 请求地址始终有效并等于当前 PC；
- 返回值必须在当前周期组合稳定；
- 接口没有 enable、valid、ready、错误响应或背压；
- 核心不会发起数据访问；
- 仿真 DPI wrapper、未来 ROM/BRAM wrapper 和 SoC adapter 位于核心边界之外。

同步 ROM、可变延迟存储和总线接入为 `TODO`。引入这些能力前必须重新定义握手、在途事务、stall/flush 和 trace 提交条件。

## 7. 非法与未知值

- opcode `0x8`–`0xF` 非法；
- 立即数指令的非零 `rs`、寄存器指令的非零 `imm8`、`JUMP` 的非零 `rd` 或 `rs` 非法；
- opcode 或规范条件含 X/Z 时不得产生寄存器写或跳转；
- 初版没有异常入口、原因寄存器或返回指令。

仿真环境可以在核心进入非法状态后终止，但 `$finish`、DPI-C 和文件访问不得进入 `rtl/core/`。

## 8. 未实现能力

数据访存、MMIO、异常、中断、睡眠/唤醒、流水线和 clock gating 均为 `TODO`。FPGA 阶段若需要低功耗控制，优先使用寄存器 clock-enable；厂商时钟原语只能位于 FPGA wrapper。
