REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
AM_ROOT   := $(REPO_ROOT)/sw/am
BUILD_DIR ?= $(REPO_ROOT)/build/sw
TEST_BUILD_DIR := $(BUILD_DIR)/tests
AM_BUILD_DIR := $(BUILD_DIR)/am
include $(AM_ROOT)/build.mk

TESTS := trm_smoke trm_exit_code calc_add dram_access heap_smoke jump_table \
	cpu_dummy cpu_add cpu_sub_longlong cpu_bit cpu_bubble_sort cpu_select_sort \
	cpu_fib cpu_recursion cpu_string cpu_leap_year cpu_if_else cpu_load_store \
	led_marquee uart_hello seg7_hex

TARGET_INST_BINS := $(foreach t,$(TESTS),$(TEST_BUILD_DIR)/$(t)/$(t).inst.bin)

.PHONY: all clean $(TESTS)

all: $(TARGET_INST_BINS)

# Rule for each test
define TEST_RULE
$(1)_SRC := $$(firstword $$(wildcard $$(REPO_ROOT)/sw/tests/$(1)/*.c $$(REPO_ROOT)/sw/tests/$(1)/*.S))
$$(eval $$(call AM_DEFINE_APP,$(1),$$(TEST_BUILD_DIR)/$(1),$$($(1)_SRC)))
$(1): $$(AM_APP_$(1)_INST)
endef

$(foreach t,$(TESTS),$(eval $(call TEST_RULE,$(t))))

clean:
	rm -rf $(TEST_BUILD_DIR)
