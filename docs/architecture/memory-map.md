# DC-Chip v0.2 地址与存储模型

- 版本：v0.2
- 状态：阶段 5 Phase 1 完成 MMIO 基地址（`0x10000000`）与 LED 控制器（`0x10000100`）规格冻结；timer/UART 待 Phase 2/3
- 更新日期：2026-09-12
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
| --- | --- | ---: | --- |
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

阶段 5 正式冻结 IROM、DRAM 以及 MMIO 外设区域的基地址、容量与访问权限：

| 区域/属性 | 地址范围 | 基线容量 | 权限与访问模型 | 错误行为 | 物理实现 |
| --- | --- | ---: | --- | --- | --- |
| **IROM** | `0x00000000`--`0x0000ffff` | 64 KiB | **只读/可执行**（仅允许 IFU 取指，四字节对齐） | LSU 读写触发 load/store access fault；未对齐取指触发 instruction misaligned | 片上 BRAM / 仿真 IROM 数组 |
| **DRAM** | `0x20000000`--`0x2000ffff` | 64 KiB | **可读/可写**（仅允许 LSU 访存，仿真支持扩展至 256 KiB） | IFU 取指触发 instruction access fault；未对齐 word 触发 misaligned | 片上 BRAM / 仿真 DRAM 数组 |
| **MMIO 总区域** | `0x10000000`--`0x1000ffff` | 64 KiB | **设备寄存器**（仅允许 LSU 访存，由总线路由至各外设） | IFU 取指触发 instruction access fault；未分配外设子空间触发 access fault | SoC Interconnect 译码 |
| **GPIO LED 控制器** | `0x10000100`--`0x10000103` | 4 字节 | **可读/可写**（低 16 位映射到 16 颗 LED，高 16 位保留为 0） | IFU 取指或未对齐多字节读写按规范返回错误 | `rtl/periph/led_controller.sv` |
| timer/UART/sensor | `0x10000200` 等 | 待定 | 阶段 5 后续子阶段规划中 | 访问未就绪外设地址触发 access fault | `TODO` |

### 5.1 Harvard 访问隔离与 Fault 契约

- **IFU 专属 IROM**：取指请求地址必须处于 `[0x00000000, 0x00010000)` 内且四字节对齐。若 IFU 尝试对 DRAM 区域（`0x20000000` 起）、MMIO 区域（`0x10000000` 起）或任何未映射空间取指，存储子系统返回错误，核心产生粘滞的 `instruction access fault`（`fault_cause = 3'd2`）；
- **LSU 路由与访问**：数据请求由 `soc_interconnect` 译码路由：
  - DRAM 区域：`[0x20000000, 0x20010000)` 内，转发至 DRAM 存储；
  - 私有 `tohost`：`0xfffffff0`，转发至仿真/主机监控；
  - MMIO 区域：`[0x10000000, 0x10010000)` 内，仅已实现外设（如 `0x10000100` LED）返回正常握手响应；未实现的外设地址直接返回 `rsp_error = 1`；
  - 未映射区域或尝试对 IROM 执行 load/store：总线互连立即返回 `rsp_error = 1`；
- 核心收到 `rsp_error` 时产生粘滞的 `load access fault`（`fault_cause = 3'd5`）或 `store access fault`（`fault_cause = 3'd7`）；
- 跨区域非法访问不会产生任何局部数据写入或寄存器写回，故障状态保持至复位。

### 5.2 GPIO LED 控制器寄存器定义（`0x10000100`）

| 偏移/地址 | 字段 | 位宽 | 读写权限 | 描述 |
| --- | --- | ---: | --- | --- |
| `0x10000100` | `LED[15:0]` | 16 | R/W | 16 颗用户发光二极管状态。写 1 点亮，写 0 熄灭。复位为 `0x0000`。 |
| `0x10000102` | 保留 | 16 | RO | 读恒为 0，写忽略。 |

- 支持 8 位（`sb`/`lbu`）、16 位（`sh`/`lhu`）和 32 位（`sw`/`lw`）对齐读写。
- 读操作直接返回当前寄存器锁存的值；写操作在请求握手成功拍同步更新寄存器并反映到输出管脚 `o_led[15:0]`。


## 6. 仿真私有机制边界

behavioral simulation 可以使用私有镜像布局、终止地址或 host 交互机制，但它们
不是正式 SoC 地址映射，不在本文件分配地址。此类目标契约记录在
`docs/verification/simulator.md`，并必须与未来真实 MMIO 分配隔离。

阶段 2 采用上述正式内存映射：IROM `0x00000000`（64 KiB）、DRAM `0x20000000`（64 KiB）
与 `0xfffffff0` 私有 `tohost`。仿真器支持从命令行同时加载指令镜像与数据镜像，
支持 raw binary (`.bin`) 与 32 位 8 字符 HEX 格式。
