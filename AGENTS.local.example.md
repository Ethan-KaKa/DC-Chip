# AGENTS.local.md - 本地个性化配置与外部参考（模板示例）

> 说明：本文件是受版本控制的模板。实际使用时，请将其复制为根目录下的 `AGENTS.local.md`（或 `.localset.md`）。
> `AGENTS.local.md` 和 `.localset.md` 已被 `.gitignore` 全局忽略，且有 pre-commit 钩子拦截，**绝不会提交到 Git 仓库**。
> AI 智能体在启动时会自动探测并读取该文件，将其中的外部路径与使用偏好加载到上下文中。

---

## 1. 外部代码库映射 (External Repositories)

# AI 在需要跨仓阅读外部开源实现或参考模型时，将使用以下只读路径（留空表示未配置）：
YSYX_WORKBENCH: /home/kaka/ysyx-workbench
# SPIKE_HOME: /opt/riscv/spike
# DC_NVBOARD_HOME: /path/to/nvboard

---

## 2. 个人文献与资料库 (Literature & Local Documents)

# AI 在需要查阅理论基础、课件、学术论文或个人架构笔记时查阅：
# PAPERS_DIR: /home/kaka/Documents/Papers/RISC-V
# COURSE_NOTES: /home/kaka/Documents/Notes/DC-Chip.md
# SPEC_DIR: /home/kaka/Documents/Specs/RISC-V-Privileged

---

## 3. 本地设备与环境定制 (Local Environment & Hardware)

# 本机特定的开发板设备端口、调试器或自定义编译器路径：
FPGA_UART_PORT: /dev/ttyUSB0
DEFAULT_APP: uart_hello

---

## 4. 个人 AI 协作习惯与偏好 (Personal AI Preferences)

# 您可以指示 AI 与您对话或编写代码时的个性化习惯（补充公共规则，不得削弱安全底线）：
- 架构与数据流通路解释时，优先使用 Mermaid 流程图或时序图辅助说明。
- 执行耗时较长或可能影响工作区的操作前，简要说明执行意图。
- 软件编写时默认提供清晰的边界断言（assert）与诊断信息。
