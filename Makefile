VERILATOR ?= verilator
IVERILOG  ?= iverilog
VVP       ?= vvp
CXX       ?= c++
PYTHON    ?= python3
RISCV_GCC     ?= riscv64-linux-gnu-gcc
RISCV_OBJDUMP ?= riscv64-linux-gnu-objdump
RISCV_OBJCOPY ?= riscv64-linux-gnu-objcopy
BUILD_DIR ?= build

UNIT_DIR  := $(BUILD_DIR)/unit
SIM_DIR   := $(BUILD_DIR)/verilator
SIM_BIN   := $(SIM_DIR)/Vsim_top
SIM_TEST_DIR := $(BUILD_DIR)/verilator-test
SIM_TEST_BIN := $(SIM_TEST_DIR)/test_simulation
REF_TEST_DIR := $(BUILD_DIR)/reference-test
REF_TEST_BIN := $(REF_TEST_DIR)/test_reference
DIFF_TEST_DIR := $(BUILD_DIR)/difftest-test
DIFF_TEST_BIN := $(DIFF_TEST_DIR)/test_difftest
DISASM_TEST_DIR := $(BUILD_DIR)/disasm-test
DISASM_TEST_BIN := $(DISASM_TEST_DIR)/test_disasm
MEM_TEST_DIR := $(BUILD_DIR)/memory-test
MEM_TEST_BIN := $(MEM_TEST_DIR)/test_memory
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
PERIPH_RTL := rtl/periph/led_controller.sv \
	rtl/periph/uart_controller.sv
SOC_RTL := rtl/soc/mmio_cdc_bridge.sv \
	rtl/soc/periph_interconnect.sv \
	rtl/soc/soc_interconnect.sv \
	rtl/soc/dc_soc_top.sv
MEM_RTL := sim/verilator/sim_mem.sv
MEM_TEST_CPP := sim/tests/test_memory.cpp
SIM_RTL := $(CORE_RTL) \
	$(PERIPH_RTL) \
	$(SOC_RTL) \
	$(MEM_RTL) \
	sim/verilator/sim_top.sv
SIM_ENGINE_CPP := sim/verilator/memory.cpp \
	sim/verilator/simulation.cpp
SIM_CLI_CPP := sim/verilator/numeric.cpp \
	sim/verilator/main.cpp
SIM_TEST_CPP := sim/tests/test_simulation.cpp
REF_CPP := sim/verilator/reference_model.cpp sim/verilator/memory.cpp
REF_TEST_CPP := sim/tests/test_reference.cpp
DIFF_CPP := sim/verilator/difftest.cpp $(REF_CPP)
DIFF_TEST_CPP := sim/tests/test_difftest.cpp
DISASM_CPP := sim/verilator/disasm.cpp
DISASM_TEST_CPP := sim/tests/test_disasm.cpp
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

ifneq ($(filter sim-build sim test-simulation test-reference test-difftest test-integration test,$(MAKECMDGOALS)),)
-include $(AUTO_CONF)
endif

ifeq ($(CONFIG_DC_SIM_SDB),y)
SIM_CLI_CPP += sim/verilator/disasm.cpp \
	sim/verilator/sdb.cpp
endif
SIM_CPP := $(SIM_ENGINE_CPP) $(SIM_CLI_CPP)

ifeq ($(CONFIG_DC_SIM_WAVE),y)
SIM_TRACE_FLAGS := --trace
endif

YSYX_WORKBENCH ?= /home/kaka/ysyx-workbench
NVBOARD_HOME ?= $(YSYX_WORKBENCH)/nvboard
NVBOARD_NXDC := constr/nvboard.nxdc
NVBOARD_DIR := $(BUILD_DIR)/nvboard-sim
NVBOARD_CONFIG_DIR := $(NVBOARD_DIR)/config
NVBOARD_BIND_CPP := $(NVBOARD_DIR)/auto_bind.cpp
NVBOARD_ARCHIVE := $(NVBOARD_HOME)/build/nvboard.a
NVBOARD_BIN := $(NVBOARD_DIR)/Vsim_top

NVBOARD_CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic \
	-I$(abspath $(NVBOARD_CONFIG_DIR)) \
	-I$(abspath sim/verilator) \
	-include $(abspath $(NVBOARD_CONFIG_DIR)/config.h) \
	-I$(NVBOARD_HOME)/usr/include $(shell sdl2-config --cflags 2>/dev/null)
NVBOARD_LDFLAGS := $(NVBOARD_ARCHIVE) $(shell sdl2-config --libs 2>/dev/null) -lSDL2_image -lSDL2_ttf

.DEFAULT_GOAL := help

.PHONY: check-tools help defconfig menuconfig config-show test-config \
	lint-isa lint-comb lint lint-mem test-isa test-alu test-decoder test-regfile test-core \
	test-led test-uart test-periph-interconnect test-cdc test-interconnect test-soc test-unit \
	test-disasm test-memory test-reference sim-build sim test-simulation test-difftest \
	test-integration test-wave test-sdb sw test-sw test \
	nvboard-build nvboard-run clean

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

lint-isa:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall -Wno-UNUSEDPARAM \
		--top-module decoder $(ISA_PKG) rtl/core/decoder.sv

lint-comb:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall -Wno-UNUSEDPARAM \
		--top-module alu $(ISA_PKG) rtl/core/alu.sv
	$(VERILATOR) --lint-only --language 1800-2012 -Wall -Wno-UNUSEDPARAM \
		--top-module decoder $(ISA_PKG) rtl/core/decoder.sv

lint:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module cpu_core $(CORE_RTL)

lint-mem:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module sim_mem $(MEM_RTL)

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

$(UNIT_DIR)/tb_led_controller.vvp: rtl/periph/led_controller.sv sim/tb/tb_led_controller.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_led_controller -Irtl/periph -o $@ $^

$(UNIT_DIR)/tb_uart_controller.vvp: rtl/periph/uart_controller.sv sim/tb/tb_uart_controller.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_uart_controller -Irtl/periph -o $@ $^

$(UNIT_DIR)/tb_periph_interconnect.vvp: rtl/soc/periph_interconnect.sv sim/tb/tb_periph_interconnect.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_periph_interconnect -Irtl/soc -o $@ $^

$(UNIT_DIR)/tb_mmio_cdc_bridge.vvp: rtl/soc/mmio_cdc_bridge.sv sim/tb/tb_mmio_cdc_bridge.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_mmio_cdc_bridge -Irtl/soc -o $@ $^

$(UNIT_DIR)/tb_soc_interconnect.vvp: rtl/soc/soc_interconnect.sv sim/tb/tb_soc_interconnect.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_soc_interconnect -Irtl/soc -o $@ $^

$(UNIT_DIR)/tb_dc_soc_top.vvp: $(CORE_RTL) $(PERIPH_RTL) $(SOC_RTL) sim/tb/tb_dc_soc_top.sv | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_dc_soc_top -Irtl/core -Irtl/soc -Irtl/periph -o $@ $^

test-alu: $(UNIT_DIR)/tb_alu.vvp
	$(VVP) $<

test-decoder: $(UNIT_DIR)/tb_decoder.vvp
	$(VVP) $<

test-regfile: $(UNIT_DIR)/tb_regfile.vvp
	$(VVP) $<

test-core: $(UNIT_DIR)/tb_cpu_core.vvp
	$(VVP) $<

test-led: $(UNIT_DIR)/tb_led_controller.vvp
	$(VVP) $<

test-uart: $(UNIT_DIR)/tb_uart_controller.vvp
	$(VVP) $<

test-periph-interconnect: $(UNIT_DIR)/tb_periph_interconnect.vvp
	$(VVP) $<

test-cdc: $(UNIT_DIR)/tb_mmio_cdc_bridge.vvp
	$(VVP) $<

test-interconnect: $(UNIT_DIR)/tb_soc_interconnect.vvp
	$(VVP) $<

test-soc: $(UNIT_DIR)/tb_dc_soc_top.vvp
	$(VVP) $<

test-unit:
	$(MAKE) --no-print-directory test-alu
	$(MAKE) --no-print-directory test-decoder
	$(MAKE) --no-print-directory test-regfile
	$(MAKE) --no-print-directory test-core
	$(MAKE) --no-print-directory test-led
	$(MAKE) --no-print-directory test-uart
	$(MAKE) --no-print-directory test-periph-interconnect
	$(MAKE) --no-print-directory test-cdc
	$(MAKE) --no-print-directory test-interconnect
	$(MAKE) --no-print-directory test-soc

$(DISASM_TEST_DIR):
	mkdir -p $@

$(DISASM_TEST_BIN): $(DISASM_CPP) $(DISASM_TEST_CPP) \
	sim/verilator/disasm.h Makefile | $(DISASM_TEST_DIR)
	CCACHE_DISABLE=1 $(CXX) -std=c++17 -Wall -Wextra -Wpedantic \
		-Isim/verilator -o $@ $(DISASM_CPP) $(DISASM_TEST_CPP)

test-disasm: $(DISASM_TEST_BIN)
	$(DISASM_TEST_BIN)

test-isa:
	@set -eu; \
	for tool in "$(RISCV_GCC)" "$(RISCV_OBJDUMP)"; do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			printf 'error: required RV32E cross-tool not found: %s\n' "$$tool" >&2; \
			exit 1; \
		fi; \
	done
	CCACHE_DISABLE=1 $(PYTHON) sim/tests/test_isa.py \
		--gcc "$(RISCV_GCC)" --objdump "$(RISCV_OBJDUMP)"
	$(MAKE) --no-print-directory lint-isa
	$(MAKE) --no-print-directory test-decoder
	$(MAKE) --no-print-directory test-disasm

$(MEM_TEST_BIN): $(MEM_RTL) sim/verilator/memory.cpp $(MEM_TEST_CPP) \
	sim/verilator/memory.h Makefile
	mkdir -p $(MEM_TEST_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_mem \
		--Mdir $(MEM_TEST_DIR) -o test_memory \
		-CFLAGS "-std=c++17 -I$(abspath sim/verilator)" \
		$(MEM_RTL) sim/verilator/memory.cpp $(MEM_TEST_CPP)
	@verilator_root=$$($(VERILATOR) --getenv VERILATOR_ROOT); \
	CCACHE_DISABLE=1 $(CXX) -std=c++17 -Wall -Wextra -Wpedantic -fsyntax-only \
		-I$(MEM_TEST_DIR) -Isim/verilator \
		-isystem "$$verilator_root/include" \
		-isystem "$$verilator_root/include/vltstd" \
		sim/verilator/memory.cpp $(MEM_TEST_CPP)

test-memory: $(MEM_TEST_BIN)
	$(MEM_TEST_BIN) "$(abspath $(BUILD_DIR)/test-fixtures/memory)"

$(SIM_BIN): $(SIM_RTL) $(SIM_CPP) sim/verilator/memory.h \
	sim/verilator/numeric.h sim/verilator/simulation.h \
	$(if $(filter y,$(CONFIG_DC_SIM_SDB)),sim/verilator/sdb.h sim/verilator/disasm.h) Makefile \
	$(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(SIM_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		$(SIM_TRACE_FLAGS) \
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
		$(SIM_TRACE_FLAGS) \
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

$(REF_TEST_BIN): $(REF_CPP) $(REF_TEST_CPP) sim/verilator/reference_model.h Makefile \
	$(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(REF_TEST_DIR)
	CCACHE_DISABLE=1 $(CXX) $(SIM_CXXFLAGS) -I$(REF_TEST_DIR) -o $@ $(REF_CPP) $(REF_TEST_CPP)

test-reference: $(REF_TEST_BIN)
	$(REF_TEST_BIN)

$(DIFF_TEST_BIN): $(SIM_RTL) $(SIM_ENGINE_CPP) $(DIFF_CPP) $(DIFF_TEST_CPP) \
	sim/verilator/memory.h sim/verilator/simulation.h \
	sim/verilator/reference_model.h sim/verilator/difftest.h Makefile \
	$(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(DIFF_TEST_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		$(SIM_TRACE_FLAGS) \
		--Mdir $(DIFF_TEST_DIR) -o test_difftest \
		-CFLAGS "-std=c++17 $(SIM_CONFIG_CXXFLAGS)" \
		$(SIM_RTL) $(SIM_ENGINE_CPP) $(DIFF_CPP) $(DIFF_TEST_CPP)
	@verilator_root=$$($(VERILATOR) --getenv VERILATOR_ROOT); \
	CCACHE_DISABLE=1 $(CXX) $(SIM_CXXFLAGS) -fsyntax-only \
		-I$(DIFF_TEST_DIR) -Isim/verilator \
		-isystem "$$verilator_root/include" \
		-isystem "$$verilator_root/include/vltstd" \
		$(SIM_ENGINE_CPP) $(DIFF_CPP) $(DIFF_TEST_CPP)

test-difftest: $(DIFF_TEST_BIN)
	@mkdir -p "$(abspath $(BUILD_DIR))/test-fixtures/difftest"
	$(DIFF_TEST_BIN) "$(abspath $(BUILD_DIR))/test-fixtures/difftest"

sim:
	@set -eu; \
	img='$(strip $(IMG))'; \
	data_img='$(strip $(DATA_IMG))'; \
	app='$(strip $(APP))'; \
	if [ -n "$$app" ]; then \
		$(MAKE) --no-print-directory sw; \
		if [ -z "$$img" ]; then \
			img='$(abspath $(BUILD_DIR))/sw/tests/'"$$app/$$app.inst.bin"; \
		fi; \
		if [ -z "$$data_img" ] && [ -f '$(abspath $(BUILD_DIR))/sw/tests/'"$$app/$$app.data.bin" ]; then \
			data_img='$(abspath $(BUILD_DIR))/sw/tests/'"$$app/$$app.data.bin"; \
		fi; \
	fi; \
	if [ -z "$$img" ]; then \
		printf '%s\n' 'error: IMG or APP is required; use make sim IMG=<path> [DATA_IMG=<path>] or make sim APP=<app_name>' >&2; \
		exit 1; \
	fi; \
	case '$(TRACE)' in \
		'') ;; \
		1) ;; \
		*) printf 'error: TRACE must be empty or 1, got: %s\n' '$(TRACE)' >&2; exit 1 ;; \
	esac; \
	case '$(BATCH)' in \
		'') ;; \
		1) ;; \
		*) printf 'error: BATCH must be empty or 1, got: %s\n' '$(BATCH)' >&2; exit 1 ;; \
	esac; \
	$(MAKE) --no-print-directory sim-build; \
	set -- --image "$$img"; \
	if [ -n "$$data_img" ]; then \
		set -- "$$@" --image-data "$$data_img"; \
	fi; \
	if [ -n '$(strip $(STEPS))' ]; then \
		set -- "$$@" --steps '$(STEPS)'; \
	fi; \
	if [ '$(TRACE)' = 1 ]; then \
		set -- "$$@" --trace; \
	fi; \
	if [ '$(BATCH)' = 1 ]; then \
		set -- "$$@" --batch; \
	fi; \
	$(SIM_BIN) "$$@"

sw:
	$(MAKE) -C sw/tests BUILD_DIR=$(abspath $(BUILD_DIR))/sw

test-sw: sw sim-build
	$(PYTHON) scripts/run_sw_tests.py \
		--simulator "$(abspath $(SIM_BIN))" \
		--test-dir "$(abspath $(BUILD_DIR))/sw/tests"

test-integration: sim-build
	TEST_FIXTURE_DIR="$(abspath $(BUILD_DIR))/test-fixtures" \
		bash sim/tests/run_integration.sh "$(abspath $(SIM_BIN))"

test-wave:
	$(PYTHON) scripts/test_wave.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/wave" \
		--make "$(MAKE)" --verilator "$(VERILATOR)" \
		--iverilog "$(IVERILOG)" --vvp "$(VVP)" \
		--cxx "$(CXX)" --python "$(PYTHON)"

test-sdb:
	$(PYTHON) scripts/test_sdb.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/sdb" \
		--make "$(MAKE)" --verilator "$(VERILATOR)" \
		--iverilog "$(IVERILOG)" --vvp "$(VVP)" \
		--cxx "$(CXX)" --python "$(PYTHON)"

$(NVBOARD_ARCHIVE):
	@if [ ! -d "$(NVBOARD_HOME)" ]; then \
		printf 'error: NVBOARD_HOME not found at %s. Set NVBOARD_HOME or YSYX_WORKBENCH.\n' '$(NVBOARD_HOME)' >&2; \
		exit 1; \
	fi
	$(MAKE) -C $(NVBOARD_HOME) nvboard-archive

$(NVBOARD_BIND_CPP): $(NVBOARD_NXDC)
	@mkdir -p $(dir $@)
	@if [ ! -d "$(NVBOARD_HOME)" ]; then \
		printf 'error: NVBOARD_HOME not found at %s. Set NVBOARD_HOME or YSYX_WORKBENCH.\n' '$(NVBOARD_HOME)' >&2; \
		exit 1; \
	fi
	$(PYTHON) $(NVBOARD_HOME)/scripts/auto_pin_bind.py $< $@

$(NVBOARD_DIR)/.sync.stamp: Dconfig $(CONFIG_INPUTS)
	@mkdir -p $(NVBOARD_CONFIG_DIR)
	@$(PYTHON) scripts/config.py --config $(NVBOARD_DIR)/.config --output-dir $(NVBOARD_CONFIG_DIR) set DC_SIM_NVBOARD=y
	@touch $@

$(NVBOARD_BIN): $(SIM_RTL) $(SIM_CPP) $(NVBOARD_BIND_CPP) $(NVBOARD_ARCHIVE) $(NVBOARD_DIR)/.sync.stamp Makefile
	@mkdir -p $(NVBOARD_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		$(SIM_TRACE_FLAGS) \
		--Mdir $(NVBOARD_DIR) \
		-CFLAGS "$(NVBOARD_CXXFLAGS)" \
		-LDFLAGS "$(NVBOARD_LDFLAGS)" \
		$(SIM_RTL) $(SIM_CPP) $(NVBOARD_BIND_CPP)

nvboard-build: $(NVBOARD_BIN)

nvboard-run: sw $(NVBOARD_BIN)
	@set -eu; \
	app='$(strip $(APP))'; \
	if [ -z "$$app" ]; then app='led_marquee'; fi; \
	inst_bin="$(abspath $(BUILD_DIR))/sw/tests/$$app/$$app.inst.bin"; \
	data_bin="$(abspath $(BUILD_DIR))/sw/tests/$$app/$$app.data.bin"; \
	if [ ! -f "$$inst_bin" ]; then \
		printf 'error: instruction image not found: %s. Build with make sw.\n' "$$inst_bin" >&2; \
		exit 1; \
	fi; \
	set -- --image-inst "$$inst_bin"; \
	if [ -f "$$data_bin" ] && [ -s "$$data_bin" ]; then \
		set -- "$$@" --image-data "$$data_bin"; \
	fi; \
	if [ '$(BATCH)' = 1 ]; then \
		set -- "$$@" --batch; \
	fi; \
	if [ -n '$(strip $(STEPS))' ]; then \
		set -- "$$@" --steps '$(strip $(STEPS))'; \
	fi; \
	if [ -n '$(strip $(MAX_CYCLES))' ]; then \
		set -- "$$@" --max-cycles '$(strip $(MAX_CYCLES))'; \
	fi; \
	printf 'Running %s on NVBoard...\n' "$$app"; \
	"$(NVBOARD_BIN)" "$$@"

test:
	$(MAKE) --no-print-directory test-config
	$(MAKE) --no-print-directory test-isa
	$(MAKE) --no-print-directory test-disasm
	$(MAKE) --no-print-directory lint-isa
	$(MAKE) --no-print-directory lint-comb
	$(MAKE) --no-print-directory lint
	$(MAKE) --no-print-directory lint-mem
	$(MAKE) --no-print-directory test-unit
	$(MAKE) --no-print-directory test-memory
	$(MAKE) --no-print-directory test-reference
	$(MAKE) --no-print-directory test-simulation
	$(MAKE) --no-print-directory sw
	$(MAKE) --no-print-directory test-difftest
	$(MAKE) --no-print-directory test-integration
	$(MAKE) --no-print-directory test-sw

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
		'Repository targets (see docs for the current migration boundary):' \
		'  make check-tools  Check required tools, Python curses, and C++17' \
		'  make help         Show this help without creating build output' \
		'  make defconfig    Reset .config to configs/default_defconfig' \
		'  make menuconfig   Edit .config with the vendored curses frontend' \
		'  make config-show  Show the effective simulator configuration' \
		'  make test-config  Test isolated configuration generation and use' \
		'  make test-isa     Test the v0.2 encoder, decoder, and disassembler' \
		'  make lint-isa     Lint the v0.2 ISA package and decoder' \
		'  make lint-comb    Lint the combinational ALU and decoder' \
		'  make test-alu     Run the self-checking ALU testbench' \
		'  make test-decoder Run the self-checking decoder testbench' \
		'  make lint         Lint the complete CPU core' \
		'  make lint-mem     Lint the simulation memory subsystem' \
		'  make test-regfile Run the self-checking register-file testbench' \
		'  make test-core    Run the self-checking CPU-core testbench' \
		'  make test-led     Run the self-checking LED controller testbench' \
		'  make test-uart    Run the self-checking UART controller testbench' \
		'  make test-periph-interconnect Run the self-checking periph interconnect testbench' \
		'  make test-cdc     Run the self-checking MMIO CDC bridge testbench' \
		'  make test-interconnect Run the self-checking interconnect testbench' \
		'  make test-soc     Run the self-checking SoC top testbench' \
		'  make test-unit    Run all ten unit testbenches in order' \
		'  make test-disasm  Test directed v0.2 ISA disassemblies' \
		'  make test-memory  Run self-checking simulation memory tests' \
		'  make test-reference Run self-checking C++ reference model tests' \
		'  make sim-build    Build the Verilator DPI-C simulator' \
		'  make sw           Build AM runtime and all software tests' \
		'  make test-sw      Run software tests on the Verilator simulator' \
		'  make sim [IMG=<hex|bin>] [DATA_IMG=<bin>] [APP=<name>] [STEPS=<n>] [TRACE=1] [BATCH=1]' \
		'  make test-simulation  Test the reusable Simulation engine' \
		'  make test-difftest    Run lockstep differential testing' \
		'  make test-integration  Run positive and negative integration cases' \
		'  make test-wave    Test isolated WAVE-off/on simulator builds' \
		'  make test-sdb     Test isolated SDB-off/on and SDB+WAVE builds' \
		'  make nvboard-build Build the NVBoard graphical simulator' \
		'  make nvboard-run [APP=<name>] Run an application on NVBoard graphical simulator' \
		'  make test         Run all config, disasm, RTL, ref, sw, difftest, and CLI regression' \
		'  make clean        Remove only the repository-root build directory' \
		'' \
		'Configurable variables:' \
		'  VERILATOR, IVERILOG, VVP, CXX, PYTHON, BUILD_DIR' \
		'  RISCV_GCC and RISCV_OBJDUMP select the RV32E cross-tools.' \
		'  IMG, STEPS, TRACE and BATCH become active with make sim.' \
		'' \
		'Configuration files:' \
		'  .config is local and preserved by make clean.' \
		'  configs/default_defconfig is the tracked default.' \
		'  Simulator targets generate build/config/auto.conf and config.h.' \
		'  DC_SIM_WAVE=y enables build-time VCD output at build/dump.vcd.' \
		'  DC_SIM_SDB=y makes SDB interactive mode the simulator default.'
