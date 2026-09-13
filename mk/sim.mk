# mk/sim.mk - 单一 Verilator 仿真器与可选 Spike backend 构建模块

SIM_DIR      := $(BUILD_DIR)/verilator
SIM_BIN      := $(SIM_DIR)/Vsim_top

SIM_RTL := $(CORE_RTL) \
	$(PERIPH_RTL) \
	$(SOC_RTL) \
	$(MEM_RTL) \
	sim/verilator/sim_top.sv

SIM_ENGINE_CPP := sim/verilator/memory.cpp \
	sim/verilator/simulation.cpp
SIM_CLI_CPP := sim/verilator/numeric.cpp \
	sim/verilator/main.cpp

SIM_CONFIG_CXXFLAGS := -I$(abspath $(CONFIG_DIR)) \
	-I$(abspath sim/verilator) \
	-include $(abspath $(CONFIG_H))
SIM_CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic $(SIM_CONFIG_CXXFLAGS)
SIM_LDFLAGS := -ldl
SIM_EXTRA_DEPS :=

# Kconfig 特性条件编入
ifeq ($(CONFIG_DC_SIM_SDB),y)
SIM_CLI_CPP += sim/verilator/disasm.cpp \
	sim/verilator/sdb.cpp
endif

ifeq ($(CONFIG_DC_SIM_DIFFTEST),y)
SIM_CLI_CPP += sim/verilator/reference_model.cpp \
	sim/verilator/dynamic_ref_backend.cpp \
	sim/verilator/difftest.cpp
endif

ifeq ($(CONFIG_DC_SIM_WAVE),y)
SIM_TRACE_FLAGS := --trace
endif

# NVBoard uses the same Vsim_top and execution loop as every other mode. Its
# generated binding and third-party objects stay under build/, never under the
# read-only submodule source tree.
NVBOARD_HOME ?= $(abspath tools/nvboard)
NVBOARD_NXDC := constr/nvboard.nxdc
NVBOARD_TOOL_DIR := $(abspath $(BUILD_DIR))/tools/nvboard
NVBOARD_BIND_CPP := $(SIM_DIR)/auto_bind.cpp
NVBOARD_SRCS := $(sort $(wildcard $(NVBOARD_HOME)/src/*.cpp))
NVBOARD_OBJS := $(patsubst $(NVBOARD_HOME)/src/%.cpp,$(NVBOARD_TOOL_DIR)/%.o,$(NVBOARD_SRCS))
NVBOARD_ARCHIVE := $(NVBOARD_TOOL_DIR)/nvboard.a

ifeq ($(CONFIG_DC_SIM_NVBOARD),y)
SIM_CPP_EXTRA := $(NVBOARD_BIND_CPP)
SIM_CXXFLAGS += -I$(NVBOARD_HOME)/usr/include \
	$(shell sdl2-config --cflags 2>/dev/null)
SIM_LDFLAGS += $(NVBOARD_ARCHIVE) $(shell sdl2-config --libs 2>/dev/null) \
	-lSDL2_image -lSDL2_ttf
SIM_EXTRA_DEPS += $(NVBOARD_BIND_CPP) $(NVBOARD_ARCHIVE)
endif

SIM_CPP := $(SIM_ENGINE_CPP) $(SIM_CLI_CPP) $(SIM_CPP_EXTRA)

$(SIM_BIN): $(SIM_RTL) $(SIM_CPP) sim/verilator/memory.h \
	sim/verilator/numeric.h sim/verilator/simulation.h \
	$(if $(filter y,$(CONFIG_DC_SIM_SDB)),sim/verilator/sdb.h sim/verilator/disasm.h) $(BUILD_MAKEFILES) \
	$(CONFIG_H) $(AUTO_CONF) $(SIM_EXTRA_DEPS)
	mkdir -p $(SIM_DIR)
	CCACHE_DISABLE=1 CXX="$(CXX)" $(VERILATOR) --cc --exe --build \
		--language 1800-2012 -Wall --top-module sim_top \
		$(SIM_TRACE_FLAGS) \
		--Mdir $(SIM_DIR) \
		-CFLAGS "$(SIM_CXXFLAGS)" \
		-LDFLAGS "$(SIM_LDFLAGS)" \
		$(SIM_RTL) $(SIM_CPP)

sim-build: $(SIM_BIN)

init-nvboard:
	@if [ ! -d "tools/nvboard/.git" ]; then \
		git submodule update --init --recursive tools/nvboard; \
	fi

$(NVBOARD_TOOL_DIR)/%.o: $(NVBOARD_HOME)/src/%.cpp
	@if [ ! -d "$(NVBOARD_HOME)" ] || [ ! -f "$(NVBOARD_HOME)/scripts/nvboard.mk" ]; then \
		printf 'error: NVBOARD_HOME not found or uninitialized at %s. Run "make init-nvboard" or set NVBOARD_HOME.\n' '$(NVBOARD_HOME)' >&2; \
		exit 1; \
	fi
	@mkdir -p $(dir $@)
	CCACHE_DISABLE=1 $(CXX) -MMD -O3 -I$(NVBOARD_HOME)/include \
		$(shell sdl2-config --cflags 2>/dev/null) -c -o $@ $<

$(NVBOARD_ARCHIVE): $(NVBOARD_OBJS)
	@mkdir -p $(dir $@)
	ar rcs $@ $^

$(NVBOARD_BIND_CPP): $(NVBOARD_NXDC)
	@mkdir -p $(dir $@)
	@if [ ! -d "$(NVBOARD_HOME)" ] || [ ! -f "$(NVBOARD_HOME)/scripts/auto_pin_bind.py" ]; then \
		printf 'error: NVBOARD_HOME not found or uninitialized at %s. Run "make init-nvboard" or set NVBOARD_HOME.\n' '$(NVBOARD_HOME)' >&2; \
		exit 1; \
	fi
	$(PYTHON) $(NVBOARD_HOME)/scripts/auto_pin_bind.py $< $@

-include $(NVBOARD_OBJS:.o=.d)

# Spike Golden Model 支持
SPIKE_SUBMODULE_DIR ?= $(abspath tools/spike)
SPIKE_OUT_DIR       := $(abspath $(BUILD_DIR))/tools/spike
SPIKE_SRC_DIR       := $(SPIKE_OUT_DIR)/src
SPIKE_BUILD_DIR     := $(SPIKE_OUT_DIR)/build
SPIKE_SO            := $(BUILD_DIR)/dc-spike-so

init-spike:
	@if [ ! -d "tools/spike/.git" ] && [ ! -f "tools/spike/.git" ]; then \
		git submodule update --init --recursive tools/spike; \
	fi
	@mkdir -p "$(SPIKE_SRC_DIR)" "$(SPIKE_BUILD_DIR)"
	@if [ ! -f "$(SPIKE_SRC_DIR)/configure" ]; then \
		printf 'Exporting clean tools/spike source to %s...\n' "$(SPIKE_SRC_DIR)"; \
		if [ -d "$(SPIKE_SUBMODULE_DIR)/.git" ] || [ -f "$(SPIKE_SUBMODULE_DIR)/.git" ]; then \
			git -C "$(SPIKE_SUBMODULE_DIR)" archive HEAD | tar -x -C "$(SPIKE_SRC_DIR)"; \
		else \
			cp -a "$(SPIKE_SUBMODULE_DIR)/." "$(SPIKE_SRC_DIR)/"; \
		fi; \
		printf 'Applying patch tools/spike-diff/spike.patch...\n'; \
		patch -d "$(SPIKE_SRC_DIR)" -p1 < tools/spike-diff/spike.patch; \
	fi

$(SPIKE_SO): init-spike
	@if [ ! -f "$(SPIKE_BUILD_DIR)/Makefile" ]; then \
		cd "$(SPIKE_BUILD_DIR)" && "$(SPIKE_SRC_DIR)/configure" --prefix=/usr/local; \
	fi
	$(MAKE) -C "$(SPIKE_BUILD_DIR)" -j$$(nproc) CFLAGS="-fPIC -O2" CXXFLAGS="-fPIC -O2"
	$(MAKE) -C tools/spike-diff SPIKE_SRC_DIR="$(SPIKE_SRC_DIR)" SPIKE_BUILD_DIR="$(SPIKE_BUILD_DIR)" BUILD_DIR="$(abspath $(BUILD_DIR))"

spike-build: $(SPIKE_SO)

_test-infra-difftest-spike: sw $(DIFF_TEST_BIN) $(SPIKE_SO)
	@mkdir -p "$(abspath $(BUILD_DIR))/test-fixtures/difftest"
	@DIFF_REF_SO="$(abspath $(SPIKE_SO))" $(DIFF_TEST_BIN) "$(abspath $(BUILD_DIR))/test-fixtures/difftest"

.PHONY: sim-build init-nvboard init-spike spike-build _test-infra-difftest-spike
