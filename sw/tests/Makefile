REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
AM_ROOT   := $(REPO_ROOT)/sw/am
BUILD_DIR ?= $(REPO_ROOT)/build/sw
TEST_BUILD_DIR := $(BUILD_DIR)/tests

RISCV_GCC     ?= $(shell which riscv64-unknown-elf-gcc 2>/dev/null || which riscv64-linux-gnu-gcc 2>/dev/null || echo riscv64-linux-gnu-gcc)
RISCV_OBJDUMP ?= $(shell which riscv64-unknown-elf-objdump 2>/dev/null || which riscv64-linux-gnu-objdump 2>/dev/null || echo riscv64-linux-gnu-objdump)
RISCV_OBJCOPY ?= $(shell which riscv64-unknown-elf-objcopy 2>/dev/null || which riscv64-linux-gnu-objcopy 2>/dev/null || echo riscv64-linux-gnu-objcopy)
PYTHON        ?= python3

AM_INC_DIR := $(AM_ROOT)/include
AM_LDSCRIPT := $(AM_ROOT)/scripts/link.ld
CHECK_ISA   := $(PYTHON) $(REPO_ROOT)/scripts/check_isa_subset.py

CFLAGS := -march=rv32e -mabi=ilp32e -mstrict-align -nostdlib \
	-fno-pic -fno-pie -static -mcmodel=medlow \
	-fno-asynchronous-unwind-tables -fno-builtin -fno-stack-protector \
	-O2 -Wall -Wextra -Wno-main \
	-I$(AM_INC_DIR)

LDFLAGS := -nostdlib -static -mcmodel=medlow \
	-T $(AM_LDSCRIPT) \
	-Wl,--gc-sections \
	-Wl,--build-id=none \
	-lgcc

AM_OBJS := $(BUILD_DIR)/am/start.S.o $(BUILD_DIR)/am/trm.c.o $(BUILD_DIR)/am/klib.c.o

TESTS := trm_smoke trm_exit_code calc_add dram_access heap_smoke jump_table \
	cpu_dummy cpu_add cpu_sub_longlong cpu_bit cpu_bubble_sort cpu_select_sort \
	cpu_fib cpu_recursion cpu_string cpu_leap_year cpu_if_else cpu_load_store

TARGET_INST_BINS := $(foreach t,$(TESTS),$(TEST_BUILD_DIR)/$(t)/$(t).inst.bin)

.PHONY: all clean $(TESTS)

all: $(TARGET_INST_BINS)

$(AM_OBJS):
	@$(MAKE) -C $(AM_ROOT) BUILD_DIR=$(BUILD_DIR)

# Rule for each test
define TEST_RULE
$$(TEST_BUILD_DIR)/$(1)/$(1).elf: $$(firstword $$(wildcard $$(REPO_ROOT)/sw/tests/$(1)/*.c $$(REPO_ROOT)/sw/tests/$(1)/*.S)) $$(AM_OBJS)
	@mkdir -p $$(dir $$@)
	$$(RISCV_GCC) $$(CFLAGS) $$< $$(AM_OBJS) $$(LDFLAGS) -o $$@

$$(TEST_BUILD_DIR)/$(1)/$(1).txt: $$(TEST_BUILD_DIR)/$(1)/$(1).elf
	$$(RISCV_OBJDUMP) -d $$< > $$@
	$$(CHECK_ISA) $$@

$$(TEST_BUILD_DIR)/$(1)/$(1).inst.bin: $$(TEST_BUILD_DIR)/$(1)/$(1).txt
	$$(RISCV_OBJCOPY) -S -O binary -j .text $$(TEST_BUILD_DIR)/$(1)/$(1).elf $$@
	$$(RISCV_OBJCOPY) -S -O binary -j .rodata -j .rodata.* -j .data -j .data.* -j .sdata -j .sdata.* $$(TEST_BUILD_DIR)/$(1)/$(1).elf $$(TEST_BUILD_DIR)/$(1)/$(1).data.bin

$(1): $$(TEST_BUILD_DIR)/$(1)/$(1).inst.bin
endef

$(foreach t,$(TESTS),$(eval $(call TEST_RULE,$(t))))

clean:
	rm -rf $(TEST_BUILD_DIR)
