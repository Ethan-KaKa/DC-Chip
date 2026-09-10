VERILATOR ?= verilator
IVERILOG  ?= iverilog
VVP       ?= vvp
CXX       ?= c++
BUILD_DIR ?= build

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

.DEFAULT_GOAL := help

.PHONY: check-tools help

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

help:
	@printf '%s\n' \
		'DC-Chip build entry points' \
		'' \
		'Available in stage A:' \
		'  make check-tools  Check required tools and C++17 support' \
		'  make help         Show this help without creating build output' \
		'' \
		'Planned for later stages (not implemented yet):' \
		'  make lint-comb' \
		'  make lint' \
		'  make test-alu' \
		'  make test-decoder' \
		'  make test-regfile' \
		'  make test-core' \
		'  make test-unit' \
		'  make sim-build' \
		'  make sim IMG=<hex> [STEPS=<n>] [TRACE=1]' \
		'  make test-integration' \
		'  make test' \
		'  make clean' \
		'' \
		'Configurable variables:' \
		'  VERILATOR, IVERILOG, VVP, CXX, BUILD_DIR' \
		'  IMG, STEPS and TRACE become active with make sim in stage D.'
