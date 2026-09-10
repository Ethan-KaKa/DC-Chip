VERILATOR ?= verilator
IVERILOG  ?= iverilog
VVP       ?= vvp
CXX       ?= c++
BUILD_DIR ?= build
UNIT_DIR  := $(BUILD_DIR)/unit
SIM_DIR   := $(BUILD_DIR)/verilator
SIM_BIN   := $(SIM_DIR)/Vsim_top

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
SIM_CPP := sim/verilator/memory.cpp \
	sim/verilator/main.cpp
SIM_CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic

.DEFAULT_GOAL := help

.PHONY: check-tools help lint-comb lint test-alu test-decoder \
	test-regfile test-core test-unit sim-build sim test-integration test clean

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
	printf 'int main() { return 0; }\n' | \
		CCACHE_DISABLE=1 $(CXX) -std=c++17 -x c++ -fsyntax-only -; \
	printf 'C++17 syntax check: PASS\n'

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

$(SIM_BIN): $(SIM_RTL) $(SIM_CPP) sim/verilator/memory.h Makefile
	mkdir -p $(SIM_DIR)
	CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		--Mdir $(SIM_DIR) \
		-CFLAGS "-std=c++17" \
		$(SIM_RTL) $(SIM_CPP)
	@verilator_root=$$($(VERILATOR) --getenv VERILATOR_ROOT); \
	$(CXX) $(SIM_CXXFLAGS) -fsyntax-only \
		-I$(SIM_DIR) -Isim/verilator \
		-isystem "$$verilator_root/include" \
		-isystem "$$verilator_root/include/vltstd" $(SIM_CPP)

sim-build: $(SIM_BIN)

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
	$(MAKE) --no-print-directory lint
	$(MAKE) --no-print-directory test-unit
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
		'Available in stages A-E:' \
		'  make check-tools  Check required tools and C++17 support' \
		'  make help         Show this help without creating build output' \
		'  make lint-comb    Lint the combinational ALU and decoder' \
		'  make test-alu     Run the self-checking ALU testbench' \
		'  make test-decoder Run the self-checking decoder testbench' \
		'  make lint         Lint the complete CPU core' \
		'  make test-regfile Run the self-checking register-file testbench' \
		'  make test-core    Run the self-checking CPU-core testbench' \
		'  make test-unit    Run all four unit testbenches in order' \
		'  make sim-build    Build the Verilator DPI-C simulator' \
		'  make sim IMG=<hex> [STEPS=<n>] [TRACE=1]' \
		'  make test-integration  Run positive and negative integration cases' \
		'  make test         Run lint, unit, and integration regression' \
		'  make clean        Remove only the repository-root build directory' \
		'' \
		'Configurable variables:' \
		'  VERILATOR, IVERILOG, VVP, CXX, BUILD_DIR' \
		'  IMG, STEPS and TRACE become active with make sim in stage D.'
