# AGENTS.md

本文件适用于仓库根目录及全部子目录。DC-Chip 是面向低功耗嵌入式控制与
周期性传感任务的课程 SoC 项目；当前 CPU 实现项目定义的 RV32E v1.0 基础整数
指令集，使用 `x0`--`x15`。当前能力、未决项和证据边界见
[`docs/status.md`](docs/status.md)，不要从历史阶段名称推断现行能力。

## 开始任务

1. 先完整读取本文件与 `BUILD_RULES.md`。
2. 探测 `AGENTS.local.md`，兼容 `.localset.md`；存在时只按任务需要读取。它们是
   本地私有配置，绝不入 Git。未配置外部资源时可参考
   `AGENTS.local.example.md`。
3. 从 [`docs/README.md`](docs/README.md) 选择最多三个直接相关入口，不批量加载
   课件、参考工程或全部文档。
4. 每个新任务或新工作树首次执行任何 Git 命令前，完整读取 `GIT_RULES.md`，
   然后按其要求检查 status、diff、暂存区和 submodule。
5. 涉及 Makefile、脚本、配置、路径或外部工具时，以 `BUILD_RULES.md` 为准。

## 单一真源

| 契约或事实 | 权威位置 |
| --- | --- |
| ISA 编码和体系结构语义 | [`docs/isa/isa.md`](docs/isa/isa.md) |
| 地址、权限和 MMIO 副作用 | [`docs/architecture/memory-map.md`](docs/architecture/memory-map.md) |
| CPU、总线和提交协议 | [`docs/architecture/microarchitecture.md`](docs/architecture/microarchitecture.md) |
| 软件 ABI 与运行时 | [`docs/architecture/software-abi.md`](docs/architecture/software-abi.md) |
| 构建命令和测试清单 | `Makefile`、`make help`、`make list` |
| 当前能力、未决项和验证快照 | [`docs/status.md`](docs/status.md) |
| 板级已知事实和 TODO | [`docs/fpga/board.md`](docs/fpga/board.md) |

稳定契约不承载阶段日志；当前状态不复制完整规范；历史实现从 Git 恢复；重大
取舍写入 [`docs/decisions/`](docs/decisions/)。

## 工程边界

- 工作负载驱动：保持顺序、单发射、可解释和可验证；双发射、ROB、分支预测、
  Cache 或完整 AXI 必须先有负载或测量依据。
- ISA 变化必须同步检查 ISA 文档、RTL、参考模型、软件接口和测试。未列出的
  编码、扩展、CSR 与 `x16`--`x31` 均不得被默认为支持。
- CPU 核心不得包含板级引脚、ILA 或厂商 IP；Xilinx 专用逻辑隔离在 FPGA/SoC
  边界，并保留可仿真的行为路径。
- 普通 RTL 不用组合逻辑直接门控时钟；优先使用 clock-enable。复位释放、CDC
  和异步外设输入必须明确处理。
- valid/ready 数据与控制在握手前保持稳定；不得用延时、额外脉冲或跳过比较
  掩盖协议、流水线或异常问题。
- 仿真辅助代码放在 `` `ifndef SYNTHESIS `` 或 testbench 中；不直接编辑生成物、
  cache、`obj_dir`、镜像或 submodule 源码来制造修复。
- 源码、脚本和配置不得硬编码主机绝对路径；产物收敛至 `build/`。`make clean`
  保留 `.config` 与重型工具，完全重置使用 `make distclean`。

## 规格与证据纪律

- 尚未决定且会改变 ISA、地址映射、软件 ABI、总线协议或板级实现的事项，先向
  用户给出选择、推荐和理由；未决内容写 `TODO`，不得自行固化。
- 功耗、频率、资源和性能结论必须注明工具、实现阶段、时钟约束、活动文件与
  负载。没有测量时只能写“预计”、`TODO` 或“未验证”。
- behavioral simulation、lint、综合、post-synth、post-implementation、时序收敛
  和上板运行是不同证据；不得相互替代。
- 真实板卡完整料号、封装、速度等级、时钟、复位极性和引脚必须来自实物或官方
  板卡资料，不能仅凭“Zynq-7020”猜测。
- 课程原件位于 `docs/sources/`，默认只读；提炼内容写入正式文档并标注来源页码
  或幻灯片。外部 ysyx-workbench 只读参考，先读目标目录规则与许可证，不把其
  架构、地址或生成物当成本项目契约。

## 修改与完成

- 保留用户已有改动，只做本任务所需的小而完整的修改。接口变化同步更新所有
  实例、testbench、软件契约与相关文档。
- 不执行 `git add`、`git commit` 或 `git push`，除非用户明确要求；不得使用
  `--no-verify`。
- 验证按由快到慢展开：先运行最小相关检查，失败后再扩大上下文和回归范围。
  回归必须自检、失败返回非零、随机测试记录 seed、等待有超时。
- 完成时报告关键文件、设计影响、实际运行且通过/失败的命令，以及未执行的
  Vivado 或上板验证。稳定文档只在外部契约变化、重大方案取舍、疑难根因或
  昂贵实测证据出现时更新。

默认使用中文交流；代码、信号、命令与路径保留英文。先给结论，再给依据。
