# DC-Chip adapter for the pinned riscv-tests-am RV32UI source snapshot.
# The vendor directory is input-only.  Every generated image is delegated to
# sw/am and therefore lands under BUILD_DIR.

REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
# Do not inherit an unrelated Abstract Machine checkout from the host.  This
# adapter's ABI and link map are specifically DC-Chip's in-tree AM.
AM_HOME := $(REPO_ROOT)/sw/am
BUILD_DIR ?= $(REPO_ROOT)/build/sw
VENDOR_ROOT := $(dir $(lastword $(MAKEFILE_LIST)))vendor

RV32UI_TESTS := add addi and andi auipc beq bge bgeu blt bltu bne \
	jal jalr lb lbu lh lhu lui lw or ori sb sh sll slli slt slti sltiu \
	sltu sra srai srl srli sub sw xor xori
LOCAL_TESTS := fence
TESTS := $(RV32UI_TESTS) $(LOCAL_TESTS)

comma := ,
ALL_NAMES := $(subst $(comma), ,$(strip $(ALL)))
ifneq ($(strip $(ALL)),)
UNKNOWN := $(filter-out $(TESTS),$(ALL_NAMES))
ifneq ($(strip $(UNKNOWN)),)
$(error unknown riscv-tests ALL item(s): $(UNKNOWN); available: $(TESTS))
endif
SELECTED := $(ALL_NAMES)
else
SELECTED := $(TESTS)
endif

.PHONY: all list $(TESTS)
all: $(SELECTED)

list:
	@printf '%s\n' '$(TESTS)'

define RV32UI_RULE
$(1):
	$$(MAKE) --no-print-directory -f $$(AM_HOME)/Makefile \
		BUILD_DIR="$$(BUILD_DIR)" NAME="$(1)" \
		SRCS="$$(VENDOR_ROOT)/isa/rv32ui/$(1).S" \
		INC_PATH="$$(REPO_ROOT)/sw/riscv-tests/bridge $$(VENDOR_ROOT)/env/p $$(VENDOR_ROOT)/isa/macros/scalar" all
endef
$(foreach t,$(RV32UI_TESTS),$(eval $(call RV32UI_RULE,$(t))))

fence:
	$(MAKE) --no-print-directory -f $(AM_HOME)/Makefile \
		BUILD_DIR="$(BUILD_DIR)" NAME="$@" \
		SRCS="$(REPO_ROOT)/sw/riscv-tests/bridge/fence.S" \
		INC_PATH="$(REPO_ROOT)/sw/riscv-tests/bridge" all
