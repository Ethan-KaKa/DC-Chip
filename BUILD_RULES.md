# DC-Chip 构建、环境、路径与协作规则 (BUILD_RULES.md)

本文件是 DC-Chip 仓库在构建系统设计、环境初始化、路径引用、产物隔离与个人协作配置方面的统一规则，与 `GIT_RULES.md` 共同构成仓库的基础纪律规范。

---

## 1. 核心原则

1. **宿主无关性 (Host Agnostic)**：任何源码、脚本与构建文件不得假设特定的主机用户名、固定安装路径或网络状态。
2. **源码只读隔离 (Out-of-Tree Builds)**：源码树与外部子模块（Submodules）必须保持纯净（Read-Only），所有编译生成物统一收敛于 `build/`。
3. **分层配置隔离 (Hierarchical Config)**：公共架构契约入库；个人机器专属路径、外部文献资料库与 AI 交互习惯由本地私有文件承载，绝不入 Git。
4. **一键快速自举 (One-Command Bootstrap)**：新协作者克隆仓库后，通过一条标准命令即可完成依赖诊断、子模块检出与就绪。

---

## 2. 路径治理与相对寻址规范

### 2.1 绝对路径零容忍
- **严禁项**：
  - 严禁在代码（`*.sv`, `*.c`, `*.cpp`, `*.h`）、构建脚本（`Makefile`, `*.mk`）、自动化脚本（`*.py`, `*.sh`）中硬编码主机绝对路径（如 `/home/username/`、`/Users/` 等）。
  - 严禁在生成文件（`auto.conf`、`config.h`、编译后的可执行文件和头文件依赖列表）中持久化主机绝对路径。
  - 严禁测试脚本假定当前工作目录（CWD）在特定的子目录。

### 2.2 锚点自解算准则 (Self-Resolving Root Anchor)
所有相对寻址必须以各自组件自身的文件物理位置为锚点，向上推导 `REPO_ROOT`：

- **根目录 Makefile**：
  ```makefile
  REPO_ROOT := $(abspath $(CURDIR))
  ```
- **子目录 Makefile（如 `sw/am/Makefile`、`sw/tests/Makefile`）**：
  ```makefile
  REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
  ```
- **Python 脚本**：
  ```python
  from pathlib import Path
  REPO_ROOT = Path(__file__).resolve().parents[1]  # 根据脚本深度动态推导
  ```
- **Bash 脚本**：
  ```bash
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  ```

### 2.3 外部工具路径三级回退 (Three-tier Override)
涉及第三方工具（如 NVBoard、Spike、交叉工具链），必须支持分层覆盖：
1. **最高优先级**：命令行显式传参（例如 `make SPIKE_HOME=/opt/spike`）；
2. **次高优先级**：环境变量（例如 `export NVBOARD_HOME=...`）；
3. **兜底回退**：本地私有配置 `AGENTS.local.md` 或仓库自带相对路径（`$(REPO_ROOT)/tools/...`）。

---

## 3. 本地私有配置与个人偏好规范

协作者往往拥有自己的外部开源代码库（如 `ysyx-workbench`）、个人学术文献库（论文、技术规范、个人笔记）或定制的 AI 偏好。为防止个人绝对路径污染公共仓库，实行本地私有配置机制：

1. **文件约定**：
   - 首选命名：`AGENTS.local.md`；
   - 兼容别名：`.localset.md`；
   - 受控模板：`AGENTS.local.example.md`（版本受控，供复制参考）。
2. **Git 防污染铁律**：
   - `AGENTS.local.md`、`.localset.md` 及 `*.local.md` 必须在 `.gitignore` 中全局忽略；
   - `.githooks/pre-commit` 会机械化检查暂存区，**坚决阻断**任何私有配置文件的暂存与提交。
3. **AI 智能体读取契约**：
   - AI 在开启任务或需要外部引用时，必须先探测根目录下是否存在 `AGENTS.local.md` 或 `.localset.md`；
   - 若存在，按需加载其中的外部路径（如 `YSYX_WORKBENCH`、`PAPERS_DIR`）与个人工作流偏好；
   - 若不存在，使用仓库默认相对路径，并可提示协作者通过模板创建。
4. **安全与权责边界**：
   - 本地私有配置仅用于**补充只读外部资源映射与交互偏好**；
   - **绝对禁止**通过本地配置覆盖、削弱项目的体系结构契约（ISA 规格、内存映射）或跳过安全提交检查。

---

## 4. 构建产物拓扑与清理分级契约

### 4.1 集中式产物拓扑
所有构建输出必须收敛至 `build/` 之下，禁止在源码目录或外部子模块中遗留生成物：
```text
build/
├── config/              # Kconfig 自动生成的头文件与同步戳
├── unit/                # Iverilog 单元测试目标
├── verilator/           # Verilator DPI-C 仿真可执行程序与目标文件
├── nvboard-sim/         # NVBoard 图形仿真目标
├── sw/                  # 裸机 AM 运行时与测试程序二进制镜像
├── test-fixtures/       # 临时测试夹具与输出
└── tools/               # 外部重型工具（如 Spike）的隔离构建与安装目录
```

### 4.2 子模块只读原则 (Submodule Read-Only Rule)
- `tools/nvboard`、`tools/spike` 等子模块必须作为**只读源码树**使用；
- 父仓库构建不得在子模块工作区留下 untracked 临时文件，避免导致 `git status` 显示 `modified content` 脏状态。

### 4.3 标准分级清理契约 (Tiered Clean Hierarchy)
借鉴 GNU Coding Standards 与 Linux 内核设计，严格区分清理目标：

- **`make clean`（高频日常清理）**：
  - 清理范围：`build/unit`、`build/verilator`、`build/nvboard-sim`、`build/sw`、`build/test-fixtures`；
  - **严格保留**：`.config`（个性化配置）、`build/tools/`（编译耗时的重型外部工具库）；
  - 目标耗时：< 1 秒，保证日常修改 CPU 代码后极速重构。
- **`make tools-clean`（工具重构清理）**：
  - 清理范围：清理 `build/tools/` 下的工具产物及调用子模块内部的 clean 目标。
- **`make distclean` / `make mrproper`（彻底复原）**：
  - 清理范围：彻底删除整个 `build/` 目录、删除 `.config` 与 `.config.old`，使工作树恢复到刚 `git clone` 后的纯净状态。

---

## 5. 一键快速自举标准 (Fast Bootstrap)

新协作者或 CI 环境只需运行：
```bash
make init
# 或执行交互式自举脚本: ./scripts/bootstrap.sh
```

流水线分为五个自底向上的幂等层级（已就绪步骤秒级跳过）：
1. **Layer 0 (Doctor)**：环境与依赖工具检查（Verilator, Iverilog, RISC-V GCC, Python3, SDL2, dtc 等）。若缺失，打印针对当前 OS（Ubuntu/Debian/Arch/macOS）精确的一键复制安装命令；
2. **Layer 1 (Submodules)**：并发浅克隆子模块（`git submodule update --init --recursive --depth 1`），大幅节约带宽与时间；
3. **Layer 2 (Config)**：检查是否存在 `.config`，若无则自动根据 `configs/default_defconfig` 初始化；
4. **Layer 3 (Tools)**：按需预编译 NVBoard 静态库与 Spike 运行环境；
5. **Layer 4 (Hooks & Guidance)**：自动配置 `git config --local core.hooksPath .githooks`，提示复制 `AGENTS.local.example.md`。

---

## 6. 持续维护与机械化防线

规则不能只停留在文档上，必须通过多层防御机制自动守卫：

1. **Pre-commit 提交拦截**：
   - 自动扫描暂存区变动文本，拦截 `/home/`、`/Users/` 等硬编码主机绝对路径；
   - 自动阻断暂存 `AGENTS.local.md`、`.localset.md`、`*.local.md`；
   - 检查子模块是否处于 dirty 状态；
   - 阻止二进制归档与中间生成物误入。
2. **Makefile 自检目标**：
   - 运行 `make check-paths`：快速静态扫描仓库合规性；
   - 纳入 `make test` 全回归闭环，破坏规则的代码无法通过测试。

---

## 7. 规则依据与权威参考

- [GNU Coding Standards: Makefile Conventions](https://www.gnu.org/prep/standards/html_node/Makefile-Conventions.html)
- [The Twelve-Factor App: Dependencies, Config, Dev/prod parity](https://12factor.net/)
- [Linux Kernel: Documentation/kbuild](https://www.kernel.org/doc/html/latest/kbuild/)
- [Reproducible Builds Specification: Build Path Invariance](https://reproducible-builds.org/docs/build-path/)
- [Pro Git Book: Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [Git Documentation: gitignore](https://git-scm.com/docs/gitignore)
