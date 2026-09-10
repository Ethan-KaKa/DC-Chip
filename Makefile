VERILATOR ?= verilator
IVERILOG  ?= iverilog
VVP       ?= vvp
CXX       ?= c++
PYTHON    ?= python3
BUILD_DIR ?= build
UNIT_DIR  := $(BUILD_DIR)/unit
SIM_DIR   := $(BUILD_DIR)/verilator
SIM_BIN   := $(SIM_DIR)/Vsim_top
SIM_TEST_DIR := $(BUILD_DIR)/verilator-test
SIM_TEST_BIN := $(SIM_TEST_DIR)/test_simulation
CONFIG_FILE := .config
CONFIG_DIR  := $(BUILD_DIR)/config
AUTO_CONF   := $(CONFIG_DIR)/auto.conf
CONFIG_H    := $(CONFIG_DIR)/config.h
CONFIG_STAMP := $(CONFIG_DIR)/.sync.stamp

ISA_PKG := rtl/core/dc_isa_pkg.sv
COMB_RTL := $(ISA_PKG) \
	rtl/core/decoder.sv \
	rtl/core/alu.sv
CORE_RTL := $(COMB_RTL) \
	rtl/core/regfile.sv \
	rtl/core/cpu_core.sv
UNIT_TBS := sim/tb/tb_alu.sv \
	sim/tb/tb_decoder.sv \
	sim/tb/tb_regfile.sv \
	sim/tb/tb_cpu_core.sv
SIM_RTL := $(CORE_RTL) \
	sim/verilator/sim_top.sv
SIM_ENGINE_CPP := sim/verilator/memory.cpp \
	sim/verilator/simulation.cpp
SIM_CLI_CPP := sim/verilator/main.cpp
SIM_CPP := $(SIM_ENGINE_CPP) $(SIM_CLI_CPP)
SIM_TEST_CPP := sim/tests/test_simulation.cpp
SIM_CONFIG_CXXFLAGS := -I$(abspath $(CONFIG_DIR)) \
	-I$(abspath sim/verilator) \
	-include $(abspath $(CONFIG_H))
SIM_CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic $(SIM_CONFIG_CXXFLAGS)
CONFIG_INPUTS := Dconfig \
	scripts/config.py \
	tools/kconfiglib/kconfiglib.py \
	tools/kconfiglib/menuconfig.py
CONFIG_CMD = $(PYTHON) scripts/config.py \
	--config "$(abspath $(CONFIG_FILE))" \
	--output-dir "$(abspath $(CONFIG_DIR))"

ifneq ($(filter sim-build sim test-simulation test-integration test,$(MAKECMDGOALS)),)
-include $(AUTO_CONF)
endif

.DEFAULT_GOAL := help

.PHONY: check-tools help defconfig menuconfig config-show test-config \
	lint-comb lint test-alu test-decoder test-regfile test-core test-unit \
	sim-build sim test-simulation test-integration test clean

check-tools:
	@set -eu; \
	check_tool() { \
		if ! command -v "$$1" >/dev/null 2>&1; then \
			printf 'error: required tool not found: %s\n' "$$1" >&2; \
			exit 1; \
		fi; \
	}; \
	check_tool "$(VERILATOR)"; \
	check_tool "$(IVERILOG)"; \
	check_tool "$(VVP)"; \
	check_tool "$(CXX)"; \
	check_tool "$(PYTHON)"; \
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
	$(PYTHON) -c 'import curses; print("Python curses import: PASS")'; \
	printf 'int main() { return 0; }\n' | \
		CCACHE_DISABLE=1 $(CXX) -std=c++17 -x c++ -fsyntax-only -; \
	printf 'C++17 syntax check: PASS\n'

defconfig:
	$(CONFIG_CMD) default

$(CONFIG_FILE): configs/default_defconfig
	$(CONFIG_CMD) default

$(CONFIG_STAMP): $(CONFIG_FILE) $(CONFIG_INPUTS)
	$(CONFIG_CMD) sync
	@touch $@

$(AUTO_CONF) $(CONFIG_H) &: | $(CONFIG_STAMP)
	@set -eu; \
	if [ ! -f "$(AUTO_CONF)" ] || [ ! -f "$(CONFIG_H)" ]; then \
		$(CONFIG_CMD) sync; \
	fi

menuconfig: $(CONFIG_FILE)
	CONFIG_="CONFIG_" KCONFIG_CONFIG_HEADER="" \
		KCONFIG_CONFIG="$(abspath $(CONFIG_FILE))" srctree="$(abspath .)" \
		$(PYTHON) tools/kconfiglib/menuconfig.py Dconfig
	$(CONFIG_CMD) sync

config-show:
	$(CONFIG_CMD) show

test-config:
	$(PYTHON) scripts/test_config.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/config" \
		--cxx "$(CXX)"

lint-comb:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module alu $(ISA_PKG) rtl/core/alu.sv
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module decoder $(ISA_PKG) rtl/core/decoder.sv

lint:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module cpu_core $(CORE_RTL)

$(UNIT_DIR):
	mkdir -p $@

$(UNIT_DIR)/tb_alu.vvp: $(ISA_PKG) rtl/core/alu.sv sim/tb/tb_alu.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_alu -o $@ $^

$(UNIT_DIR)/tb_decoder.vvp: $(ISA_PKG) rtl/core/decoder.sv sim/tb/tb_decoder.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_decoder -o $@ $^

$(UNIT_DIR)/tb_regfile.vvp: $(ISA_PKG) rtl/core/regfile.sv sim/tb/tb_regfile.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_regfile -o $@ $^

$(UNIT_DIR)/tb_cpu_core.vvp: $(CORE_RTL) sim/tb/tb_cpu_core.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_cpu_core -o $@ $^

test-alu: $(UNIT_DIR)/tb_alu.vvp
	$(VVP) $<

test-decoder: $(UNIT_DIR)/tb_decoder.vvp
	$(VVP) $<

test-regfile: $(UNIT_DIR)/tb_regfile.vvp
	$(VVP) $<

test-core: $(UNIT_DIR)/tb_cpu_core.vvp
	$(VVP) $<

test-unit:
	$(MAKE) --no-print-directory test-alu
	$(MAKE) --no-print-directory test-decoder
	$(MAKE) --no-print-directory test-regfile
	$(MAKE) --no-print-directory test-core

$(SIM_BIN): $(SIM_RTL) $(SIM_CPP) sim/verilator/memory.h \
	sim/verilator/simulation.h Makefile \
	$(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(SIM_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		--Mdir $(SIM_DIR) \
		-CFLAGS "-std=c++17 $(SIM_CONFIG_CXXFLAGS)" \
		$(SIM_RTL) $(SIM_CPP)
	@verilator_root=$$($(VERILATOR) --getenv VERILATOR_ROOT); \
	CCACHE_DISABLE=1 $(CXX) $(SIM_CXXFLAGS) -fsyntax-only \
		-I$(SIM_DIR) -Isim/verilator \
		-isystem "$$verilator_root/include" \
		-isystem "$$verilator_root/include/vltstd" $(SIM_CPP)

sim-build: $(SIM_BIN)

$(SIM_TEST_BIN): $(SIM_RTL) $(SIM_ENGINE_CPP) $(SIM_TEST_CPP) \
	sim/verilator/memory.h sim/verilator/simulation.h Makefile \
	$(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(SIM_TEST_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		--Mdir $(SIM_TEST_DIR) -o test_simulation \
		-CFLAGS "-std=c++17 $(SIM_CONFIG_CXXFLAGS)" \
		$(SIM_RTL) $(SIM_ENGINE_CPP) $(SIM_TEST_CPP)
	@verilator_root=$$($(VERILATOR) --getenv VERILATOR_ROOT); \
	CCACHE_DISABLE=1 $(CXX) $(SIM_CXXFLAGS) -fsyntax-only \
		-I$(SIM_TEST_DIR) -Isim/verilator \
		-isystem "$$verilator_root/include" \
		-isystem "$$verilator_root/include/vltstd" \
		$(SIM_ENGINE_CPP) $(SIM_TEST_CPP)

test-simulation: $(SIM_TEST_BIN)
	$(SIM_TEST_BIN) "$(abspath sim/tests)"

sim:
	@set -eu; \
	if [ -z '$(strip $(IMG))' ]; then \
		printf '%s\n' 'error: IMG is required; use make sim IMG=<hex> [STEPS=<n>] [TRACE=1]' >&2; \
		exit 1; \
	fi; \
	case '$(TRACE)' in \
		'') ;; \
		1) ;; \
		*) printf 'error: TRACE must be empty or 1, got: %s\n' '$(TRACE)' >&2; exit 1 ;; \
	esac
	$(MAKE) --no-print-directory sim-build
	@set -eu; \
	set -- --image '$(IMG)'; \
	if [ -n '$(strip $(STEPS))' ]; then \
		set -- "$$@" --steps '$(STEPS)'; \
	fi; \
	if [ '$(TRACE)' = 1 ]; then \
		set -- "$$@" --trace; \
	fi; \
	$(SIM_BIN) "$$@"

test-integration: sim-build
	TEST_FIXTURE_DIR="$(abspath $(BUILD_DIR))/test-fixtures" \
		bash sim/tests/run_integration.sh "$(abspath $(SIM_BIN))"

test:
	$(MAKE) --no-print-directory test-config
	$(MAKE) --no-print-directory lint
	$(MAKE) --no-print-directory test-unit
	$(MAKE) --no-print-directory test-simulation
	$(MAKE) --no-print-directory test-integration

clean:
	@set -eu; \
	repo_root='$(abspath .)'; \
	build_dir='$(abspath $(BUILD_DIR))'; \
	if [ "$$build_dir" != "$$repo_root/build" ]; then \
		printf 'error: refusing to clean non-default BUILD_DIR: %s\n' "$$build_dir" >&2; \
		exit 1; \
	fi; \
	rm -rf -- "$$build_dir"

help:
	@printf '%s\n' \
		'DC-Chip build entry points' \
		'' \
		'Available through simulator execution-engine step 2:' \
		'  make check-tools  Check required tools, Python curses, and C++17' \
		'  make help         Show this help without creating build output' \
		'  make defconfig    Reset .config to configs/default_defconfig' \
		'  make menuconfig   Edit .config with the vendored curses frontend' \
		'  make config-show  Show the effective simulator configuration' \
		'  make test-config  Test isolated configuration generation and use' \
		'  make lint-comb    Lint the combinational ALU and decoder' \
		'  make test-alu     Run the self-checking ALU testbench' \
		'  make test-decoder Run the self-checking decoder testbench' \
		'  make lint         Lint the complete CPU core' \
		'  make test-regfile Run the self-checking register-file testbench' \
		'  make test-core    Run the self-checking CPU-core testbench' \
		'  make test-unit    Run all four unit testbenches in order' \
		'  make sim-build    Build the Verilator DPI-C simulator' \
		'  make sim IMG=<hex> [STEPS=<n>] [TRACE=1]' \
		'  make test-simulation  Test the reusable Simulation engine' \
		'  make test-integration  Run positive and negative integration cases' \
		'  make test         Run config, lint, unit, engine, and CLI regression' \
		'  make clean        Remove only the repository-root build directory' \
		'' \
		'Configurable variables:' \
		'  VERILATOR, IVERILOG, VVP, CXX, PYTHON, BUILD_DIR' \
		'  IMG, STEPS and TRACE become active with make sim in stage D.' \
		'' \
		'Configuration files:' \
		'  .config is local and preserved by make clean.' \
		'  configs/default_defconfig is the tracked default.' \
		'  Simulator targets generate build/config/auto.conf and config.h.' \
		'  DC_SIM_SDB and DC_SIM_WAVE default to n and are not active yet.'
