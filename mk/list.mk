# mk/list.mk - 公开命令语法、帮助与测试自省

empty :=
space := $(empty) $(empty)
CLI_GOALS := $(strip $(MAKECMDGOALS))
CLI_GOALS_KEY := $(subst $(space),:,$(CLI_GOALS))
CLI_FIRST := $(word 1,$(CLI_GOALS))
CLI_SECOND := $(word 2,$(CLI_GOALS))
CLI_TAIL := $(wordlist 3,$(words $(CLI_GOALS)),$(CLI_GOALS))
CLI_RUNTIME_OFF := sdboff nvboardoff waveoff

ifneq ($(filter sim nvboard-build nvboard-run,$(CLI_FIRST)),)
$(error removed command "make $(CLI_FIRST)"; run software through "make sw tests")
endif

# 拒绝已删除的变量式运行入口，且必须发生在任何 recipe 执行前。
ifneq ($(filter command line,$(origin BATCH)),)
$(error BATCH is no longer supported; use "make sw tests batch")
endif
ifneq ($(filter command line,$(origin WAVE)),)
$(error WAVE is no longer supported; use the waveoff runtime modifier)
endif
ifneq ($(filter command line,$(origin DIFFTEST)),)
$(error DIFFTEST is controlled only by .config and cannot be overridden at runtime)
endif

# 分层命令使用多个 Make goal 表达子命令。这里在解析阶段验证完整组合。
ifeq ($(CLI_FIRST),sw)
ifeq ($(CLI_SECOND),tests)
ifneq ($(filter-out list batch $(CLI_RUNTIME_OFF),$(CLI_TAIL)),)
$(error invalid sw tests modifier in "$(CLI_TAIL)")
endif
ifneq ($(word 2,$(filter sdboff,$(CLI_TAIL))),)
$(error duplicate sw tests modifier: sdboff)
endif
ifneq ($(word 2,$(filter nvboardoff,$(CLI_TAIL))),)
$(error duplicate sw tests modifier: nvboardoff)
endif
ifneq ($(word 2,$(filter waveoff,$(CLI_TAIL))),)
$(error duplicate sw tests modifier: waveoff)
endif
ifneq ($(filter list,$(CLI_TAIL)),)
ifneq ($(CLI_GOALS_KEY),sw:tests:list)
$(error list cannot be combined with ALL, batch, or runtime modifiers)
endif
ifneq ($(strip $(ALL)),)
$(error list cannot be combined with ALL, batch, or runtime modifiers)
endif
endif
ifneq ($(filter batch,$(CLI_TAIL)),)
ifneq ($(CLI_GOALS_KEY),sw:tests:batch)
$(error batch already implies sdboff nvboardoff waveoff; extra modifiers are redundant)
endif
endif
else ifeq ($(CLI_SECOND),riscv-tests)
ifeq ($(filter $(CLI_GOALS_KEY),sw:riscv-tests sw:riscv-tests:list sw:riscv-tests:batch),)
$(error invalid command "make $(CLI_GOALS)"; run "make list")
endif
else ifeq ($(CLI_SECOND),demo)
ifeq ($(filter $(CLI_GOALS_KEY),sw:demo:list sw:demo:build sw:demo:run),)
$(error invalid command "make $(CLI_GOALS)"; run "make list")
endif
else ifneq ($(CLI_SECOND),)
$(error invalid command "make $(CLI_GOALS)"; run "make help" or "make list")
endif
else ifneq ($(word 2,$(CLI_GOALS)),)
CLI_VALID_MULTI_GOALS := testunit:list testunit:batch testinfra:list testinfra:batch
ifeq ($(filter $(CLI_GOALS_KEY),$(CLI_VALID_MULTI_GOALS)),)
$(error invalid command "make $(CLI_GOALS)"; run "make help" or "make list")
endif
endif

ifneq ($(filter batch tests riscv-tests sdboff nvboardoff waveoff,$(CLI_GOALS_KEY)),)
$(error "$(CLI_GOALS)" is a subcommand, not a standalone target; run "make list")
endif

ifneq ($(strip $(ALL)),)
ifeq ($(filter _%,$(firstword $(CLI_GOALS))),)
CLI_ALL_PREFIX := $(word 1,$(CLI_GOALS))$(if $(word 2,$(CLI_GOALS)),:$(word 2,$(CLI_GOALS)))
CLI_ALL_GOALS := testunit testinfra sw:tests sw:riscv-tests sw:demo
ifeq ($(filter $(CLI_ALL_PREFIX),$(CLI_ALL_GOALS)),)
$(error ALL is only valid with testunit, testinfra, "sw tests", or "sw riscv-tests", without list/batch)
endif
ifneq ($(filter list,$(wordlist 2,$(words $(CLI_GOALS)),$(CLI_GOALS))),)
$(error ALL cannot be combined with list)
endif
ifneq ($(filter batch,$(wordlist 2,$(words $(CLI_GOALS)),$(CLI_GOALS))),)
ifneq ($(CLI_ALL_PREFIX),sw:tests)
$(error ALL cannot be combined with batch for this suite)
endif
endif
endif
endif

ifeq ($(CLI_GOALS_KEY),list)
list:
	@$(PYTHON) scripts/test_runner.py --list-suites
else
list:
	@:
endif

# 这些 goal 只承载分层命令的语法位置；实际行为由首个 goal 分派。
batch tests riscv-tests demo build run sdboff nvboardoff waveoff:
	@:

help:
	@printf '%s\n' \
		'DC-Chip 构建与操作指南' \
		'' \
		'初始化与环境:' \
		'  make init          初始化依赖、submodule、配置、工具与 Git hooks' \
		'  make check-tools   检查主机工具与 RISC-V 交叉工具链' \
		'  make check-paths   检查路径、文档链接和本地配置规则' \
		'' \
		'配置:' \
		'  make defconfig     将 .config 重置为仓库默认配置' \
		'  make menuconfig    交互式编辑本地配置' \
		'  make config-show   显示当前生效的仿真配置' \
		'' \
		'构建与运行:' \
		'  make sw            构建全部 AM 软件镜像' \
		'  make sim-build     按 .config 构建唯一的 Verilator 仿真器' \
		'  make spike-build   构建可选的 Spike 参考模型 backend' \
		'' \
		'测试:' \
		'  make list          进入测试总入口并查看全部受支持的测试命令' \
		'' \
		'清理:' \
		'  make clean         清理日常产物，保留 .config 与 build/tools' \
		'  make tools-clean   清理外部工具构建产物' \
		'  make distclean     删除全部构建产物与本地配置' \
		'  make mrproper      make distclean 的同义入口' \
		'' \
		'所有命令都应从仓库根目录执行；再次查看本页请运行 make help。'

.PHONY: list batch tests riscv-tests sdboff nvboardoff waveoff help
