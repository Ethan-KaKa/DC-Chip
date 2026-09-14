# mk/infra.mk - 仿真基础设施测试模块 (Layer 2)

DISASM_TEST_DIR := $(BUILD_DIR)/disasm-test
DISASM_TEST_BIN := $(DISASM_TEST_DIR)/test_disasm
MEM_TEST_DIR    := $(BUILD_DIR)/memory-test
MEM_TEST_BIN    := $(MEM_TEST_DIR)/test_memory
REF_TEST_DIR    := $(BUILD_DIR)/reference-test
REF_TEST_BIN    := $(REF_TEST_DIR)/test_reference
DIFF_TEST_DIR   := $(BUILD_DIR)/difftest-test
DIFF_TEST_BIN   := $(DIFF_TEST_DIR)/test_difftest
SIM_TEST_DIR    := $(BUILD_DIR)/verilator-test
SIM_TEST_BIN    := $(SIM_TEST_DIR)/test_simulation

MEM_RTL         := sim/verilator/sim_mem.sv
MEM_TEST_CPP    := sim/tests/test_memory.cpp
DISASM_CPP      := sim/verilator/disasm.cpp
DISASM_TEST_CPP := sim/tests/test_disasm.cpp
REF_CPP         := sim/verilator/reference_model.cpp sim/verilator/memory.cpp
REF_TEST_CPP    := sim/tests/test_reference.cpp
DIFF_CPP        := sim/verilator/difftest.cpp sim/verilator/dynamic_ref_backend.cpp $(REF_CPP)
DIFF_TEST_CPP   := sim/tests/test_difftest.cpp
SIM_TEST_CPP    := sim/tests/test_simulation.cpp

# 1. 反汇编引擎测试
_test-infra-make-cli:
	$(PYTHON) scripts/test_make_cli.py --make "$(MAKE)"

_test-infra-repo-rules:
	$(PYTHON) scripts/test_repo_rules.py

$(DISASM_TEST_DIR):
	mkdir -p $@

$(DISASM_TEST_BIN): $(DISASM_CPP) $(DISASM_TEST_CPP) sim/verilator/disasm.h $(BUILD_MAKEFILES) | $(DISASM_TEST_DIR)
	CCACHE_DISABLE=1 $(CXX) -std=c++17 -Wall -Wextra -Wpedantic \
		-Isim/verilator -o $@ $(DISASM_CPP) $(DISASM_TEST_CPP)

_test-infra-disasm: $(DISASM_TEST_BIN)
	$(DISASM_TEST_BIN)

# 2. ISA 编解码与反汇编一致性测试
_test-infra-isa:
	@set -eu; \
	for tool in "$(RISCV_GCC)" "$(RISCV_OBJDUMP)"; do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			printf 'error: required cross-tool not found: %s\n' "$$tool" >&2; \
			exit 1; \
		fi; \
	done
	CCACHE_DISABLE=1 $(PYTHON) sim/tests/test_isa.py \
		--gcc "$(RISCV_GCC)" --objdump "$(RISCV_OBJDUMP)"
	$(MAKE) --no-print-directory _lint-isa
	$(MAKE) --no-print-directory _test-unit-decoder
	$(MAKE) --no-print-directory _test-infra-disasm

# 3. 仿真内存模型测试
$(MEM_TEST_BIN): $(MEM_RTL) sim/verilator/memory.cpp $(MEM_TEST_CPP) sim/verilator/memory.h $(BUILD_MAKEFILES)
	mkdir -p $(MEM_TEST_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_mem \
		--Mdir $(MEM_TEST_DIR) -o test_memory \
		-CFLAGS "-std=c++17 -I$(abspath sim/verilator)" \
		$(MEM_RTL) sim/verilator/memory.cpp $(MEM_TEST_CPP)

_test-infra-memory: $(MEM_TEST_BIN)
	$(MEM_TEST_BIN) "$(abspath $(BUILD_DIR)/test-fixtures/memory)"

# 4. 参考模型行为自检
$(REF_TEST_BIN): $(REF_CPP) $(REF_TEST_CPP) sim/verilator/reference_model.h $(BUILD_MAKEFILES) $(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(REF_TEST_DIR)
	CCACHE_DISABLE=1 $(CXX) $(SIM_CXXFLAGS) -I$(REF_TEST_DIR) -o $@ $(REF_CPP) $(REF_TEST_CPP)

_test-infra-reference: $(REF_TEST_BIN)
	$(REF_TEST_BIN)

# 5. 仿真步进引擎自检
$(SIM_TEST_BIN): $(SIM_RTL) $(SIM_ENGINE_CPP) $(SIM_TEST_CPP) sim/verilator/memory.h sim/verilator/simulation.h $(BUILD_MAKEFILES) $(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(SIM_TEST_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		$(SIM_TRACE_FLAGS) \
		--Mdir $(SIM_TEST_DIR) -o test_simulation \
		-CFLAGS "-std=c++17 $(SIM_CONFIG_CXXFLAGS)" \
		$(SIM_RTL) $(SIM_ENGINE_CPP) $(SIM_TEST_CPP)

_test-infra-simulation: $(SIM_TEST_BIN)
	$(SIM_TEST_BIN) "$(abspath sim/tests)"

# 6. 差分测试引擎断言与 skip_ref 自检
$(DIFF_TEST_BIN): $(SIM_RTL) $(SIM_ENGINE_CPP) $(DIFF_CPP) $(DIFF_TEST_CPP) \
	sim/verilator/memory.h sim/verilator/simulation.h \
	sim/verilator/reference_model.h sim/verilator/difftest.h $(BUILD_MAKEFILES) $(CONFIG_H) $(AUTO_CONF)
	mkdir -p $(DIFF_TEST_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		$(SIM_TRACE_FLAGS) \
		--Mdir $(DIFF_TEST_DIR) -o test_difftest \
		-CFLAGS "-std=c++17 $(SIM_CONFIG_CXXFLAGS)" \
		-LDFLAGS "-ldl" \
		$(SIM_RTL) $(SIM_ENGINE_CPP) $(DIFF_CPP) $(DIFF_TEST_CPP)

_test-infra-difftest-engine: $(DIFF_TEST_BIN)
	@mkdir -p "$(abspath $(BUILD_DIR))/test-fixtures/difftest"
	$(DIFF_TEST_BIN) "$(abspath $(BUILD_DIR))/test-fixtures/difftest"

# 7. 集成异常与命令行测试
_test-infra-integration: sim-build
	TEST_FIXTURE_DIR="$(abspath $(BUILD_DIR))/test-fixtures" \
		bash sim/tests/run_integration.sh "$(abspath $(SIM_BIN))"

# 8. 波形与 SDB 单测
_test-infra-wave:
	$(PYTHON) scripts/test_wave.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/wave" \
		--make "$(MAKE)" --verilator "$(VERILATOR)" \
		--iverilog "$(IVERILOG)" --vvp "$(VVP)" \
		--cxx "$(CXX)" --python "$(PYTHON)"

_test-infra-sdb:
	$(PYTHON) scripts/test_sdb.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/sdb" \
		--make "$(MAKE)" --verilator "$(VERILATOR)" \
		--iverilog "$(IVERILOG)" --vvp "$(VVP)" \
		--cxx "$(CXX)" --python "$(PYTHON)"

_test-infra-unified-sim:
	$(PYTHON) scripts/test_unified_sim.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/unified-sim" \
		--make "$(MAKE)" --python "$(PYTHON)"

# 统一新入口: make testinfra [list | batch | ALL=...]

INFRA_TEST_ROOT := $(abspath $(BUILD_DIR))/test-fixtures/infra-regression
INFRA_TEST_BUILD_DIR := $(INFRA_TEST_ROOT)/build
INFRA_TEST_CONFIG := $(INFRA_TEST_ROOT)/.config

testinfra:
	@case "$(word 2,$(MAKECMDGOALS))" in \
		list)  $(PYTHON) scripts/test_runner.py --suite infra --list --make "$(MAKE)" ;; \
		*)     $(PYTHON) scripts/config.py --config "$(INFRA_TEST_CONFIG)" \
				--output-dir "$(INFRA_TEST_BUILD_DIR)/config" default >/dev/null; \
			if [ -n "$(ALL)" ]; then \
				$(PYTHON) scripts/test_runner.py --suite infra --filter "$(ALL)" --make "$(MAKE)" \
					--build-dir "$(INFRA_TEST_BUILD_DIR)" --config-file "$(INFRA_TEST_CONFIG)"; \
			else \
				$(PYTHON) scripts/test_runner.py --suite infra --batch --make "$(MAKE)" \
					--build-dir "$(INFRA_TEST_BUILD_DIR)" --config-file "$(INFRA_TEST_CONFIG)"; \
			fi ;; \
	esac

.PHONY: _test-infra-make-cli _test-infra-repo-rules _test-infra-disasm _test-infra-isa _test-infra-memory \
	_test-infra-reference _test-infra-simulation _test-infra-difftest-engine \
	_test-infra-integration _test-infra-wave _test-infra-sdb \
	_test-infra-unified-sim testinfra
