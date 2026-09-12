# DC-Chip 主工程 Makefile
# 本 Makefile 采用模块化结构，各功能子集维护在 mk/ 目录下：
#   - mk/config.mk : Kconfig、defconfig 与配置生成
#   - mk/sim.mk    : Verilator 仿真器、NVBoard 与 Spike 构建
#   - mk/unit.mk   : 硬件单测 (testunit) 与 Verilator 静态 Lint
#   - mk/infra.mk  : 仿真基础设施测试 (testinfra: memory, reference, difftest等)
#   - mk/sw.mk     : 全系统软件测试 (sw tests / sw riscv-tests)
#   - mk/list.mk   : 自省与统一帮助呈现 (make list)

VERILATOR     ?= verilator
IVERILOG      ?= iverilog
VVP           ?= vvp
CXX           ?= c++
PYTHON        ?= python3
RISCV_GCC     ?= riscv64-linux-gnu-gcc
RISCV_OBJDUMP ?= riscv64-linux-gnu-objdump
RISCV_OBJCOPY ?= riscv64-linux-gnu-objcopy
BUILD_DIR     ?= build

.DEFAULT_GOAL := list

# 引入模块化规则文件
include mk/config.mk
include mk/unit.mk
include mk/infra.mk
include mk/sim.mk
include mk/sw.mk
include mk/list.mk

# 基础环境与工具链检查
check-paths:
	@$(PYTHON) scripts/check_repo_rules.py

init:
	@bash scripts/bootstrap.sh

check-tools:
	@set -eu; \
	check_tool() { \
		if ! command -v "$$1" >/dev/null 2>&1; then \
			printf 'error: required tool not found: %s. Run "make init" for setup advice.\n' "$$1" >&2; \
			exit 1; \
		fi; \
	}; \
	check_tool "$(VERILATOR)"; \
	check_tool "$(IVERILOG)"; \
	check_tool "$(VVP)"; \
	check_tool "$(CXX)"; \
	check_tool "$(PYTHON)"; \
	check_tool "$(RISCV_GCC)"; \
	check_tool "$(RISCV_OBJDUMP)"; \
	check_tool "$(RISCV_OBJCOPY)"; \
	version_output=$$(mktemp); \
	trap 'rm -f "$$version_output"' EXIT; \
	printf 'GNU Make %s\n' '$(MAKE_VERSION)'; \
	$(VERILATOR) --version; \
	$(IVERILOG) -V >"$$version_output" 2>&1; \
	sed -n '1p' "$$version_output"; \
	$(VVP) -V >"$$version_output" 2>&1; \
	sed -n '1p' "$$version_output"; \
	CCACHE_DISABLE=1 $(CXX) --version >"$$version_output" 2>&1; \
	sed -n '1p' "$$version_output"; \
	$(PYTHON) --version; \
	CCACHE_DISABLE=1 $(RISCV_GCC) --version >"$$version_output" 2>&1; \
	sed -n '1p' "$$version_output"; \
	$(RISCV_OBJDUMP) --version >"$$version_output" 2>&1; \
	sed -n '1p' "$$version_output"; \
	$(RISCV_OBJCOPY) --version >"$$version_output" 2>&1; \
	sed -n '1p' "$$version_output"; \
	$(PYTHON) -c 'import curses; print("Python curses import: PASS")'; \
	printf 'int main() { return 0; }\n' | \
		CCACHE_DISABLE=1 $(CXX) -std=c++17 -x c++ -fsyntax-only -; \
	printf 'C++17 syntax check: PASS\n'

# 全局一键回归入口: 涵盖 Layer 1 (Unit) + Layer 2 (Infra) + Layer 3 (SW Tests)
test:
	$(MAKE) --no-print-directory check-paths
	$(MAKE) --no-print-directory testunit batch
	$(MAKE) --no-print-directory testinfra batch
	$(MAKE) --no-print-directory sw tests batch

# 清理目标
clean:
	@set -eu; \
	repo_root='$(abspath .)'; \
	build_dir='$(abspath $(BUILD_DIR))'; \
	if [ "$$build_dir" != "$$repo_root/build" ]; then \
		printf 'error: refusing to clean non-default BUILD_DIR: %s\n' "$$build_dir" >&2; \
		exit 1; \
	fi; \
	rm -rf -- "$$build_dir"/unit "$$build_dir"/verilator "$$build_dir"/nvboard-sim \
		"$$build_dir"/sw "$$build_dir"/test-fixtures "$$build_dir"/verilator-test \
		"$$build_dir"/reference-test "$$build_dir"/difftest-test \
		"$$build_dir"/disasm-test "$$build_dir"/memory-test "$$build_dir"/dump.vcd

tools-clean:
	@if [ -d tools/nvboard ]; then \
		$(MAKE) -C tools/nvboard clean >/dev/null 2>&1 || true; \
	fi
	@if [ -d tools/spike/build ]; then \
		rm -rf tools/spike/build; \
	fi
	@if [ -d tools/spike-diff ]; then \
		$(MAKE) -C tools/spike-diff clean >/dev/null 2>&1 || true; \
	fi
	@rm -rf "$(BUILD_DIR)/tools/spike"
	@rm -f "$(BUILD_DIR)/dc-spike-so"

distclean: clean tools-clean
	@set -eu; \
	repo_root='$(abspath .)'; \
	build_dir='$(abspath $(BUILD_DIR))'; \
	if [ "$$build_dir" = "$$repo_root/build" ]; then \
		rm -rf -- "$$build_dir"; \
	fi; \
	rm -f .config .config.old

.PHONY: check-paths init check-tools test clean tools-clean distclean
