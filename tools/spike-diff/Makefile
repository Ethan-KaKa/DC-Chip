SPIKE_SRC_DIR ?= $(abspath ../spike)
SPIKE_BUILD_DIR ?= $(SPIKE_SRC_DIR)/build
BUILD_DIR ?= $(abspath ../../build)

INC_DIRS = $(SPIKE_SRC_DIR) \
           $(SPIKE_BUILD_DIR) \
           $(SPIKE_SRC_DIR)/riscv \
           $(SPIKE_SRC_DIR)/fesvr \
           $(SPIKE_SRC_DIR)/disasm \
           $(SPIKE_SRC_DIR)/customext \
           $(SPIKE_SRC_DIR)/fdt \
           $(SPIKE_SRC_DIR)/softfloat

INCLUDES = $(addprefix -I, $(INC_DIRS))

SPIKE_LIBS = $(SPIKE_BUILD_DIR)/libriscv.a \
             $(SPIKE_BUILD_DIR)/libdisasm.a \
             $(SPIKE_BUILD_DIR)/libsoftfloat.a \
             $(SPIKE_BUILD_DIR)/libfesvr.a \
             $(SPIKE_BUILD_DIR)/libfdt.a

TARGET = $(BUILD_DIR)/dc-spike-so

CXX ?= g++
CXXFLAGS ?= -std=c++20 -O2 -fPIC -Wall -Wextra

.PHONY: all clean $(TARGET)

all: $(TARGET)

$(TARGET): dc_spike_diff.cc $(SPIKE_LIBS)
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -shared $(INCLUDES) dc_spike_diff.cc \
		-Wl,--whole-archive $(SPIKE_LIBS) -Wl,--no-whole-archive \
		-lpthread -lboost_system -lboost_regex -o $@
	@echo "Built: $@"

clean:
	rm -f $(TARGET)
