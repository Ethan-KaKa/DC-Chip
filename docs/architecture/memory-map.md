# DC-Chip v0.2 地址与存储模型

- 版本：v0.2
- 状态：只冻结地址、字节序、访问宽度和 fault；区域分配仍为 `TODO`
- 更新日期：2026-09-11
- ISA 规范：`docs/isa/isa.md` v0.2

## 1. 地址模型

v0.2 使用统一的 32 位 byte-addressed 地址值，取值范围为
`0x00000000`--`0xffffffff`。PC、取指地址和 load/store 有效地址均是字节地址；
有效地址加法保留低 32 位。

这一定义只规定地址表示，不表示整个 4 GiB 空间都有物理存储。哪些地址可取指、
可读、可写或具有设备副作用，由后续正式区域表决定。

## 2. 字节序与 byte lane

指令和数据均采用小端布局。对四字节对齐地址 `A`：

| 地址 | 32 位值中的位 | 32 位总线 lane |
| --- | --- | --- |
| `A+0` | `[7:0]` | 0 |
| `A+1` | `[15:8]` | 1 |
| `A+2` | `[23:16]` | 2 |
| `A+3` | `[31:24]` | 3 |

指令取指一次返回从 PC 开始的四个字节，并按该表拼成 32 位指令。数据总线的
`lane = address[1:0]`；byte store 只使能对应 lane，其他 lane 不得改变。

## 3. 访问宽度与对齐

| 操作 | 宽度 | 合法地址 | 数据行为 |
| --- | ---: | --- | --- |
| instruction fetch | 4 byte | `addr[1:0] == 2'b00` | 返回一条 32 位指令 |
| `lw` | 4 byte | `addr[1:0] == 2'b00` | 小端读取 32 位 |
| `lbu` | 1 byte | 任意 | 读取目标 lane 并零扩展到 32 位 |
| `sw` | 4 byte | `addr[1:0] == 2'b00` | 写全部四个 lane |
| `sb` | 1 byte | 任意 | 写 `rs2[7:0]` 到目标 lane |

不支持跨 lane 拼接的未对齐 word 访问。`lw/sw` 在发出数据请求前检查对齐并分别
产生 load/store address misaligned；`lbu/sb` 不产生地址未对齐 fault。

取指要求四字节对齐。正常顺序 PC 每次增加 4；`jalr` 清除目标 bit 0 后仍检查
bit 1，若为一则在 `jalr` 上报告 instruction address misaligned，不发起目标
取指。

## 4. access fault 抽象行为

以下任一原因可由后续存储系统返回 access fault：

- 地址未映射；
- 区域不允许当前访问类型或宽度；
- 只读区域收到 store；
- 设备、总线或物理存储报告访问错误。

取指、load 和 store 错误分别形成 instruction/load/store access fault。错误
响应不携带有效读数据；失败 load 不写回，失败 store 不产生部分或完整内存
副作用。具体请求/响应与提交规则见 `docs/architecture/microarchitecture.md`。

本规范不定义虚拟内存、页故障、缓存一致性、原子性扩展或 MMIO 排序指令。

## 5. 正式区域表

下列项目尚未确定，均保持 `TODO`：

| 区域/属性 | 地址 | 容量 | 权限/副作用 | 物理实现 |
| --- | --- | --- | --- | --- |
| IROM | `TODO` | `TODO` | `TODO` | `TODO` |
| DRAM/片上 RAM | `TODO` | `TODO` | `TODO` | `TODO` |
| MMIO 总区域 | `TODO` | `TODO` | `TODO` | `TODO` |
| timer/GPIO/UART/sensor | `TODO` | `TODO` | `TODO` | `TODO` |

板卡、器件、容量、权限、地址译码和链接布局确定前，不得把任何临时地址写入
RTL、软件头文件或链接脚本。加入区域时必须同步更新本文件、SoC RTL、软件 ABI
和验证。

## 6. 仿真私有机制边界

behavioral simulation 可以使用私有镜像布局、终止地址或 host 交互机制，但它们
不是正式 SoC 地址映射，不在本文件分配地址。此类目标契约记录在
`docs/verification/simulator.md`，并必须与未来真实 MMIO 分配隔离。

截至 2026-09-11，核心 RTL 已使用上述 32 位 byte address 和访问宽度契约；
Verilator wrapper 与存储模型仍是冻结的 v0.1 接口且当前不可构建，尚不能作为
v0.2 仿真存储或端到端执行证据。
