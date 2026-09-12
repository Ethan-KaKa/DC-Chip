# mk/sim.mk - Verilator 仿真器与 NVBoard 虚拟板构建模块

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

SIM_CPP := $(SIM_ENGINE_CPP) $(SIM_CLI_CPP)

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
		-LDFLAGS "-ldl" \
		$(SIM_RTL) $(SIM_CPP)

sim-build: $(SIM_BIN)

# 命令行单程序执行目标
sim:
	@set -eu; \
	img='$(strip $(IMG))'; \
	data_img='$(strip $(DATA_IMG))'; \
	app='$(strip $(APP))'; \
	if [ -n "$$app" ]; then \
		if [ -z "$$img" ]; then \
			img='$(abspath $(BUILD_DIR))/sw/tests/'"$$app/$$app.inst.bin"; \
		fi; \
		if [ ! -f "$$img" ]; then \
			printf 'error: image not found for APP=%s (%s)\nPlease build software first using "make sw" or specify IMG=<path>\n' "$$app" "$$img" >&2; \
			exit 1; \
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

# NVBoard 支持
NVBOARD_HOME ?= $(abspath tools/nvboard)
ifneq ($(wildcard $(abspath tools/nvboard)/scripts/nvboard.mk),)
override NVBOARD_HOME := $(abspath tools/nvboard)
endif
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

init-nvboard:
	@if [ ! -d "tools/nvboard/.git" ]; then \
		git submodule update --init --recursive tools/nvboard; \
	fi

$(NVBOARD_ARCHIVE):
	@if [ ! -d "$(NVBOARD_HOME)" ] || [ ! -f "$(NVBOARD_HOME)/scripts/nvboard.mk" ]; then \
		printf 'error: NVBOARD_HOME not found or uninitialized at %s. Run "make init-nvboard" or set NVBOARD_HOME.\n' '$(NVBOARD_HOME)' >&2; \
		exit 1; \
	fi
	$(MAKE) -f $(NVBOARD_HOME)/scripts/nvboard.mk -C $(NVBOARD_HOME) nvboard-archive NVBOARD_HOME=$(NVBOARD_HOME)

$(NVBOARD_BIND_CPP): $(NVBOARD_NXDC)
	@mkdir -p $(dir $@)
	@if [ ! -d "$(NVBOARD_HOME)" ] || [ ! -f "$(NVBOARD_HOME)/scripts/auto_pin_bind.py" ]; then \
		printf 'error: NVBOARD_HOME not found or uninitialized at %s. Run "make init-nvboard" or set NVBOARD_HOME.\n' '$(NVBOARD_HOME)' >&2; \
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

test-difftest-spike: sw $(DIFF_TEST_BIN) $(SPIKE_SO)
	@mkdir -p "$(abspath $(BUILD_DIR))/test-fixtures/difftest"
	@DIFF_REF_SO="$(abspath $(SPIKE_SO))" $(DIFF_TEST_BIN) "$(abspath $(BUILD_DIR))/test-fixtures/difftest"

.PHONY: sim-build sim init-nvboard nvboard-build nvboard-run init-spike spike-build test-difftest-spike
