# mk/sim.mk - 单一 Verilator 仿真器与可选 Spike backend 构建模块

SIM_DIR      := $(BUILD_DIR)/verilator
SIM_BIN      := $(SIM_DIR)/Vsim_top

SIM_RTL := $(CORE_RTL) \
	$(PERIPH_RTL) \
	$(SOC_RTL) \
	$(MEMORY_LEAF_RTL) \
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
ifneq ($(CONFIG_DC_SIM_SDB),y)
SIM_CLI_CPP += sim/verilator/disasm.cpp
endif
SIM_CLI_CPP += sim/verilator/reference_model.cpp \
	sim/verilator/dynamic_ref_backend.cpp \
	sim/verilator/difftest.cpp
endif

ifeq ($(CONFIG_DC_SIM_WAVE),y)
SIM_TRACE_FLAGS := --trace
endif

# NVBoard uses the same Vsim_top and execution loop as every other mode. Its
# generated binding and third-party objects stay under build/, never under the
# read-only submodule source tree.  Do not honor the generic NVBOARD_HOME:
# unrelated environments (for example ysyx-workbench) must not replace this
# repository's pinned submodule.  DC_NVBOARD_HOME is the explicit escape hatch.
DC_NVBOARD_HOME ?= tools/nvboard
NVBOARD_SOURCE_HOME := $(abspath $(DC_NVBOARD_HOME))
NVBOARD_NXDC := constr/nvboard.nxdc
NVBOARD_TOOL_DIR := $(abspath $(BUILD_DIR))/tools/nvboard
NVBOARD_BIND_CPP := $(SIM_DIR)/auto_bind.cpp
NVBOARD_SOURCE_STAMP := $(NVBOARD_TOOL_DIR)/.source-path
NVBOARD_COMPAT_PATCH := tools/nvboard-dc-compat.patch
NVBOARD_COMPAT_VERSION := dc-nvboard-uart-432-v3
NVBOARD_COMPAT_STAMP := $(NVBOARD_TOOL_DIR)/.compat-$(NVBOARD_COMPAT_VERSION)
NVBOARD_PATCH_SRC_DIR := $(NVBOARD_TOOL_DIR)/src
NVBOARD_SRCS := $(sort $(wildcard $(NVBOARD_SOURCE_HOME)/src/*.cpp))
NVBOARD_OBJS := $(patsubst $(NVBOARD_SOURCE_HOME)/src/%.cpp,$(NVBOARD_TOOL_DIR)/%.o,$(NVBOARD_SRCS))
NVBOARD_ARCHIVE := $(NVBOARD_TOOL_DIR)/nvboard.a

ifeq ($(CONFIG_DC_SIM_NVBOARD),y)
SIM_CPP_EXTRA := $(NVBOARD_BIND_CPP)
SIM_CXXFLAGS += -I$(NVBOARD_SOURCE_HOME)/usr/include \
	$(shell sdl2-config --cflags 2>/dev/null)
SIM_LDFLAGS += $(NVBOARD_ARCHIVE) $(shell sdl2-config --libs 2>/dev/null) \
	-lSDL2_image -lSDL2_ttf
SIM_EXTRA_DEPS += $(NVBOARD_BIND_CPP) $(NVBOARD_ARCHIVE)
endif

SIM_CPP := $(SIM_ENGINE_CPP) $(SIM_CLI_CPP) $(SIM_CPP_EXTRA)

$(SIM_BIN): $(SIM_RTL) $(SIM_CPP) sim/verilator/memory.h \
	sim/verilator/numeric.h sim/verilator/simulation.h \
	$(if $(filter y,$(CONFIG_DC_SIM_SDB) $(CONFIG_DC_SIM_DIFFTEST)),sim/verilator/disasm.h) $(BUILD_MAKEFILES) \
	$(CONFIG_H) $(AUTO_CONF) $(SIM_EXTRA_DEPS)
	mkdir -p $(SIM_DIR)
	@rm -f -- "$(SIM_BIN)"
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

.PHONY: _force-nvboard-source-check

# Object file names are source-basename based, so remember the configured source
# root. This prevents a previously selected external tree from being reused
# after returning to the pinned submodule. The compatibility stamp also records
# the patch version, so objects built with the upstream 16-cycle UART sampler
# cannot be reused after the DC-Chip UART decoder is applied.
$(NVBOARD_SOURCE_STAMP): _force-nvboard-source-check
	@mkdir -p $(dir $@)
	@source_path='$(NVBOARD_SOURCE_HOME)'; \
	if [ ! -d "$$source_path" ] || [ ! -f "$$source_path/scripts/nvboard.mk" ] || \
		[ ! -f "$$source_path/src/uart.cpp" ] || [ ! -f "$$source_path/src/font.cpp" ] || \
		[ ! -f "$$source_path/src/render.cpp" ]; then \
		printf 'error: DC_NVBOARD_HOME is not a compatible NVBoard source tree: %s. Run "make init-nvboard" or set DC_NVBOARD_HOME.\n' "$$source_path" >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$@" ] || ! printf '%s\n' "$$source_path" | cmp -s - "$@"; then \
		printf '%s\n' "$$source_path" > "$@"; \
	fi


# Copy and patch only the sources whose behavior is part of DC-Chip's
# UART/resource contract. The patch is intentionally strict: a source-version
# mismatch fails here rather than silently building a GUI with bad UART output.
$(NVBOARD_COMPAT_STAMP): $(NVBOARD_SOURCE_STAMP) \
	$(NVBOARD_COMPAT_PATCH) $(NVBOARD_SOURCE_HOME)/src/uart.cpp \
	$(NVBOARD_SOURCE_HOME)/src/font.cpp $(NVBOARD_SOURCE_HOME)/src/render.cpp
	@rm -rf -- "$(NVBOARD_PATCH_SRC_DIR)"
	@mkdir -p "$(NVBOARD_PATCH_SRC_DIR)"
	@cp "$(NVBOARD_SOURCE_HOME)/src/uart.cpp" "$(NVBOARD_PATCH_SRC_DIR)/uart.cpp"
	@cp "$(NVBOARD_SOURCE_HOME)/src/font.cpp" "$(NVBOARD_PATCH_SRC_DIR)/font.cpp"
	@cp "$(NVBOARD_SOURCE_HOME)/src/render.cpp" "$(NVBOARD_PATCH_SRC_DIR)/render.cpp"
	@patch --batch --fuzz=0 -d "$(NVBOARD_TOOL_DIR)" -p1 < "$(abspath $(NVBOARD_COMPAT_PATCH))"
	@printf '%s %s\n' '$(NVBOARD_COMPAT_VERSION)' '$(NVBOARD_SOURCE_HOME)' > "$@"

# Every object depends on the selected source set and compatibility stamp. This
# deliberately over-rebuilds a small third-party archive when its source root
# changes, avoiding stale basename-derived objects across source-tree switches.
$(NVBOARD_OBJS): $(NVBOARD_TOOL_DIR)/%.o: $(NVBOARD_COMPAT_STAMP) $(NVBOARD_SRCS)
	@mkdir -p $(dir $@)
	@source="$(NVBOARD_SOURCE_HOME)/src/$*.cpp"; \
	if [ -f "$(NVBOARD_PATCH_SRC_DIR)/$*.cpp" ]; then source="$(NVBOARD_PATCH_SRC_DIR)/$*.cpp"; fi; \
	CCACHE_DISABLE=1 $(CXX) -MMD -O3 -I"$(NVBOARD_SOURCE_HOME)/include" \
		-DDC_NVBOARD_HOME=\"$(NVBOARD_SOURCE_HOME)\" \
		$$(sdl2-config --cflags 2>/dev/null) -c -o "$@" "$$source"

$(NVBOARD_ARCHIVE): $(NVBOARD_OBJS)
	@mkdir -p $(dir $@)
	ar rcs $@ $^

$(NVBOARD_BIND_CPP): $(NVBOARD_NXDC) $(NVBOARD_SOURCE_STAMP)
	@mkdir -p $(dir $@)
	@if [ ! -d "$(NVBOARD_SOURCE_HOME)" ] || [ ! -f "$(NVBOARD_SOURCE_HOME)/scripts/auto_pin_bind.py" ]; then \
		printf 'error: DC_NVBOARD_HOME not found or uninitialized at %s. Run "make init-nvboard" or set DC_NVBOARD_HOME.\n' '$(NVBOARD_SOURCE_HOME)' >&2; \
		exit 1; \
	fi
	$(PYTHON) $(NVBOARD_SOURCE_HOME)/scripts/auto_pin_bind.py $< $@

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
