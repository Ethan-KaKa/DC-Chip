# DC-Chip Git 管理规则

本文件是仓库中 Git 操作的统一规则，适用于根目录及以后加入的所有子库。子目录可以补充项目专属规则，但不得降低这里的安全要求。

## AI 必做预检

1. 每个新任务或新工作树中，在首次执行任何 Git 命令前完整读取本文件；规则变化、上下文恢复或切换工作树后重新读取。
2. 读取后运行 `git status --short --branch`，并按需检查 `git diff`、`git diff --cached` 和 `git submodule status --recursive`。先区分用户已有改动与本任务改动。
3. 执行写操作前确认目标路径和影响范围；提交前审阅完整 staged diff；操作后再次检查状态。
4. 不默认使用 `git add .`、`git add -A` 或通配符批量暂存。只暂存已经核对、属于同一目的的明确路径或 hunk。

## Commit 内容规则

- 标题使用 `<area>: <imperative summary>`。`area` 是稳定的小写目录或子系统名，例如 `repo`、`rtl`、`soc`、`sim`、`sw`、`docs`；根级跨子系统改动使用 `repo`。
- summary 使用英文命令式现在时，以小写动词开始，不加句号。目标不超过 50 个字符，最长不超过 72 个字符。
- 简单且原因显然的改动可以只有标题；跨多个文件、改变行为或包含重要取舍时必须写正文。
- 标题与正文之间空一行。正文用 1–3 个自然段，按约 72 列换行，依次解释问题或动机、方案及理由、实际完成的验证或已知限制。
- 正文解释 why，不逐项复述 diff。一个 commit 只承载一个可独立理解、验证和回退的逻辑变化；出现多个无关主题时拆分 commit。
- 禁止使用 `update files`、`misc changes`、`WIP` 或只列文件名的标题。issue、`Co-authored-by:`、`Signed-off-by:` 等 trailer 只在事实成立或上游明确要求时添加。
- merge、revert、fixup 等 Git 特殊 commit 沿用 Git 生成的标准标题形式。验证结果只记录实际执行过的命令和结果。

基本结构：

```text
<area>: <imperative summary>

<problem or motivation>

<solution and rationale>

<verification or limitations, when relevant>
```

### 当前仓库的组织示例

仓库级 Git 规则独立成一个 commit：

```text
repo: enforce Git management policy

The repository lacks shared criteria for deciding what belongs in
history and no automated check catches risky staged content.

Document the required pre-Git review, add common ignore and text
attribute rules, and install a versioned pre-commit hook for secrets,
caches, whitespace errors, and large blobs.

The hook passes isolated checks for accepted content and each
rejection path.
```

项目初始规格、目录和最小验证入口组成一个 commit：

```text
repo: establish the course project workspace

Define a reproducible starting point for the CPU, SoC, software, and
FPGA work without treating reference implementations as project
requirements.

Add the initial specifications, source layout, build entry points, and
verification plan for the Zynq-7020 target.

Document all hardware parameters that remain undecided.
```

一项 CPU 功能及其测试组成一个 commit：

```text
rtl: implement integer execute unit

The core needs a self-contained execute stage before instruction-level
integration can begin.

Add the combinational ALU and directed self-checking tests for every
supported operation and boundary case.

The unit suite passes `make test-unit`.
```

## 应当纳入版本管理

- 源代码、RTL、脚本、测试、构建说明和人工维护的文档。
- 可复现实验所需的配置、存储映射、工作负载描述、小型输入和依赖锁文件。
- 已人工筛选并解释的小型结果摘要；记录输入、版本、命令、口径和来源。
- 仓库协作规则、共享忽略规则、属性规则，以及固定到明确 commit 的 submodule gitlink。

## 不应纳入版本管理

- 虚拟环境、依赖安装目录、缓存、临时文件、日志、波形、bitstream 和可重新生成的构建或仿真输出。
- 令牌、密码、私钥、真实 `.env`、机器专属配置和其他敏感信息。忽略规则不是已经泄露密钥的补救措施；发现泄露时应立即停止提交并轮换凭据。
- 可从权威来源重新取得的第三方二进制资料，以及缺少再分发授权的论文、课件和数据集副本。
- 未经评估的大型二进制。单文件超过 10 MiB 时，先选择外部存储或 Git LFS，并取得用户明确决定。

生成目录名称具有项目语义，例如 `build/`、`obj_dir/`、Vivado 工程目录和 `results/`。这类规则应放在对应子项目的 `.gitignore` 中，不在根规则中全局屏蔽。个人编辑器偏好应放入全局 ignore 或 `.git/info/exclude`，而不是共享 `.gitignore`。

## 安全操作边界

- 不覆盖、删除、回退或暂存与当前任务无关的用户改动。
- 未经明确授权，不提交、不推送、不创建或删除分支/标签，不改写历史，不更新 submodule 指针。
- 禁止使用破坏性命令处理无关改动。需要撤销、清理、强制推送、rebase 或 amend 时，先说明精确影响和恢复路径并获得授权。
- submodule 在父仓库中只提交 gitlink 与 `.gitmodules`。更新前记录旧/新 commit、原因和回归结果，不把上游源码复制进父仓库。
- 不使用 `--no-verify` 绕过 `.githooks/pre-commit`。新 clone 在首次提交前执行 `git config --local core.hooksPath .githooks`。

## 规则依据

- [Git：gitignore](https://git-scm.com/docs/gitignore)：共享忽略项进入受版本控制的 `.gitignore`；个人或本地规则使用其他 exclude 层级。
- [Git：git-commit](https://git-scm.com/docs/git-commit)：标题使用简短摘要，正文前保留空行。
- [Git：SubmittingPatches](https://git-scm.com/docs/SubmittingPatches)：逻辑变化分开提交，标题使用命令式，正文解释问题和方案理由。
- [Linux kernel：Submitting patches](https://kernel.org/doc/html/latest/process/submitting-patches.html)：按 subsystem 组织标题，并让 commit log 自包含。
- [Git：gitattributes](https://git-scm.com/docs/gitattributes)：用属性统一文本换行并明确二进制文件。
- [Git：githooks](https://git-scm.com/docs/githooks)：客户端钩子位于 hooks 目录或 `core.hooksPath`，只作为提交阶段的补充防线。
- [Pro Git：Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)：父仓库记录子模块路径和确定的提交。
- [GitHub：Repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits)：生成物宜放在 Git 之外，大型二进制宜使用 Git LFS。

客户端 hook 不能证明 AI 已经阅读规则，也不能覆盖 `status`、`add` 等全部 Git 命令；因此 `AGENTS.md` 的前置要求负责约束 AI，hook 只拦截可机械识别的提交风险。
