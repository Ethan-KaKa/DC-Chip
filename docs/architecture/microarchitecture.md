# DC-Chip RV32E 过渡子集微架构

- 版本：v0.2
- 状态：阶段 1 目标契约；RTL 端口和控制器尚未迁移
- 更新日期：2026-09-11
- ISA 规范：`docs/isa/isa.md` v0.2

## 1. 目标模型与当前实现边界

v0.2 核心采用顺序、单发射、非流水模型：同一时刻最多处理一条未提交指令，
程序顺序与提交顺序一致，不推测执行，不在 fault 后继续取指。取指通道最多一个
在途事务，数据通道最多一个在途事务；load/store 完成前核心停顿。

本文冻结后续 RTL 必须实现的接口、握手、提交和 fault 契约，不固定每条指令
的周期数，也不要求零等待存储。实现可以在没有 stall 时优化周期数，但不得改变
可见顺序或副作用边界。

截至 2026-09-11，现有 `cpu_core` 仍是自定义 ISA v0.1 的 4×16-bit 单周期核，
使用 8 位字地址和组合零等待 `imem`。下述 32 位接口、数据通道和结构化 fault
均 **尚未实现**，留待步骤 2.2--2.5；本步不修改任何 RTL 端口。

## 2. 目标数据通路

```text
PC -> fetch handshake -> instruction register -> decoder -> regfile -> execute
                                                        |          |
                                                        |          +-> JALR
                                                        +-> address -> data handshake
                                                                   |
commit/trace/fault <- control <- writeback <-----------------------+
```

目标模块职责：

- ISA package：32 位宽度、字段、功能码和 fault cause 常量；
- decoder/immediate generator：精确识别八条指令和使用中的 RV32E 寄存器字段；
- regfile：16×32-bit 双组合读、单同步写，`x0` 恒零；
- execute/address unit：32 位回绕加法、LUI、JALR 和有效地址；
- controller：请求/响应、stall、提交、fault 粘滞和 reset；
- core wrapper：trace、索引式 debug regfile 和结构化 fault 输出。

核心继续使用单一 `clk` 和同步高有效 `rst`。板级复位极性、异步同步和释放
电路属于 FPGA wrapper，仍为 `TODO`。

## 3. 取指请求--响应协议

目标端口如下；名称可在 RTL 实施前做不改变语义的统一调整，但宽度和握手契约
必须保持：

| 方向 | 端口 | 宽度 | 语义 |
| --- | --- | ---: | --- |
| output | `imem_req_valid` | 1 | 取指请求有效 |
| input | `imem_req_ready` | 1 | 接收请求 |
| output | `imem_req_addr` | 32 | 四字节对齐的 byte address |
| input | `imem_rsp_valid` | 1 | 取指响应有效 |
| output | `imem_rsp_ready` | 1 | 核心可接收响应 |
| input | `imem_rsp_rdata` | 32 | 小端拼成的指令字 |
| input | `imem_rsp_error` | 1 | 本次取指 access fault |

请求在 `req_valid && req_ready` 的上升沿被接收；响应在
`rsp_valid && rsp_ready` 的上升沿被接收。`imem_req_valid=1` 且尚未握手时，
地址必须稳定。`imem_rsp_valid=1` 且尚未握手时，响应数据与错误位必须由响应方
保持稳定。

核心不能把请求接受等同于响应完成，也不能重复发出同一 PC。响应错误直接形成
`instruction access fault`，响应数据无效且不得译码。当前指令提交或 fault 前
不发出下一条推测取指，因此不会把顺序预取错误误报为已执行错误。

## 4. 数据请求--响应协议

| 方向 | 端口 | 宽度 | 语义 |
| --- | --- | ---: | --- |
| output | `dmem_req_valid` | 1 | 数据请求有效 |
| input | `dmem_req_ready` | 1 | 接收请求 |
| output | `dmem_req_addr` | 32 | 有效 byte address |
| output | `dmem_req_write` | 1 | 1=store，0=load |
| output | `dmem_req_size` | 2 | `00`=byte，`10`=32-bit word；其他值不使用 |
| output | `dmem_req_wdata` | 32 | 按地址 lane 放置的 store 数据 |
| output | `dmem_req_wstrb` | 4 | 每位对应一个 byte lane |
| input | `dmem_rsp_valid` | 1 | load/store 完成响应有效 |
| output | `dmem_rsp_ready` | 1 | 核心可接收响应 |
| input | `dmem_rsp_rdata` | 32 | 包含所请求地址所在 32 位小端字 |
| input | `dmem_rsp_error` | 1 | 本次 load/store access fault |

数据通道使用与取指相同的 valid/ready 规则。请求未被接受时，地址、读写类型、
size、写数据和 strobe 必须保持稳定；响应被背压时，数据和错误位必须稳定。
每条 load/store 只发出一次请求，并等待唯一一次响应，等待期间不提交且不发出
下一条取指。

lane 约定：`lane = addr[1:0]`。`lbu` 从
`dmem_rsp_rdata[8*lane +: 8]` 零扩展；`sb` 令 `wstrb = 4'b0001 << lane`，并把
`rs2[7:0]` 放入对应 `wdata` lane。`lw/sw` 地址低两位必须为零，使用完整 32 位
数据和 `wstrb=4'b1111`。load 的 `wdata/wstrb` 必须为零。

所有 store 也必须收到完成响应。只有 `dmem_rsp_error=0` 的响应才能使 store
副作用和指令提交成立；错误响应表示目标未发生任何部分或完整写入。

## 5. 控制流程与提交边界

一次提交是指一条指令的全部体系结构效果在同一上升沿变得可见，并用
`trace_valid` 报告一次。不得提前报告、重复报告或把 fault 指令报告为提交。

| 指令类别 | 提交条件 | 同一提交沿的效果 |
| --- | --- | --- |
| `add/addi/lui` | 已成功取指、合法译码并完成执行 | 可选寄存器写回；`pc <- old_pc+4` |
| `lw/lbu` | 数据成功响应被接收 | 写回 load 值；`pc <- old_pc+4` |
| `sw/sb` | store 成功响应被接收 | 内存写完成；`pc <- old_pc+4` |
| `jalr` | 目标四字节对齐 | 可选 link 写回；`pc <- target` |
| 任一 fault | 永不提交 | 进入粘滞 fault，无指令副作用 |

写 `x0` 被 regfile 丢弃，但合法指令仍按上述条件提交。`jalr rd==rs1` 时先锁存
旧 `rs1`，再在提交沿同时写 link 和更新 PC。

## 6. fault 模型

目标 fault 输出为：

| 方向 | 端口 | 宽度 | 语义 |
| --- | --- | ---: | --- |
| output | `fault_valid` | 1 | 粘滞 fault 状态，reset 清除 |
| output | `fault_cause` | 3 | 下表编码 |
| output | `fault_pc` | 32 | fault 指令 PC |
| output | `fault_inst_valid` | 1 | `fault_inst` 是否来自成功取指 |
| output | `fault_inst` | 32 | fault 指令；取指失败时无效 |

| `fault_cause` | 类别 |
| ---: | --- |
| `3'd0` | 无 fault，仅在 `fault_valid=0` 时使用 |
| `3'd1` | illegal instruction |
| `3'd2` | instruction access fault |
| `3'd3` | instruction address misaligned |
| `3'd4` | load address misaligned |
| `3'd5` | load access fault |
| `3'd6` | store address misaligned |
| `3'd7` | store access fault |

fault 在检测到它的上升沿锁存，并保持到 reset。fault 指令不提交、不更新 PC、
不写寄存器；失败 store 不产生内存副作用。fault 状态期间请求 valid 和响应
ready 均为零，trace 无效。

数据地址不对齐在请求前检查，因而不会与该访问的 access fault 同时出现。
`jalr` 清 bit 0 后若 bit 1 为一，产生 instruction address misaligned；不写回
link。成功取指后发现非法编码时 `fault_inst_valid=1`；取指响应错误时为 0。

## 7. trace 与调试可见性

目标验证接口如下：

| 方向 | 端口 | 宽度 | 语义 |
| --- | --- | ---: | --- |
| output | `trace_valid` | 1 | 当前上升沿恰好提交一条指令 |
| output | `trace_pc` | 32 | 所提交指令的旧 PC |
| output | `trace_inst` | 32 | 所提交的完整指令字 |
| input | `debug_reg_addr` | 4 | 选择 `x0`--`x15` |
| output | `debug_reg_data` | 32 | 所选寄存器当前架构值 |

索引式 debug 接口替代 v0.1 的 64 位 `{R3,R2,R1,R0}` 拼接总线，避免扩展成
512 位公共端口。它只用于验证可见性，不参与执行控制。后续参考模型应在每次
`trace_valid` 后比较 PC 和全部 16 个寄存器，并另行比较已完成 store 副作用。

## 8. reset 与取消规则

`rst` 为同步高有效，优先于正常控制、提交和 fault。上升沿采样到 `rst=1` 时：

- PC 设为参数化 reset PC，`x1`--`x15` 清零，`x0` 保持零；
- 清除 trace、fault（含 cause/PC/指令 payload）和内部指令/数据在途标记；
- reset 期间不得发出新请求，也不得接收响应。

尚未握手的请求在 reset 时取消。reset 前已握手但尚未响应的事务被核心放弃，
其迟到响应不得与 reset 后的新请求配对；SoC adapter/存储模型必须同步冲刷或
丢弃这类响应。reset 不回滚已经成功完成的外部 store，但未成功完成的 store
不得因迟到响应而在 reset 后提交。

## 9. 暂停、未知值和实现纪律

- 任一通道可无限背压；验证必须使用有限 timeout，核心状态在 stall 中保持；
- 控制或关键译码字段含 X/Z 时，不得产生写回、store 或跳转；仿真应报错，具体
  X 传播策略不属于综合后的 ISA 行为；
- 普通 RTL 不直接门控时钟；低功耗优先使用 clock-enable；
- DPI-C、文件操作、`$finish`、ILA 和厂商原语不得进入可移植核心；
- 未来流水化、并行取指或多个在途事务必须先修订本规范的提交、flush 和 ID
  规则，不能在当前接口上隐式加入。
