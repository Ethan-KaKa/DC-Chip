include $(dir $(lastword $(MAKEFILE_LIST)))build.mk

.PHONY: all clean

# Compatibility entry point for assembly-only riscv-tests-am workloads.  The
# imported wrapper passes NAME, SRCS and INC_PATH; ordinary AM users continue
# to include build.mk and call AM_DEFINE_APP directly.
ifneq ($(strip $(NAME)),)
RISCV_TEST_BUILD_DIR ?= $(BUILD_DIR)/riscv-tests/$(NAME)
AM_APP_CFLAGS += $(addprefix -I,$(INC_PATH))
$(eval $(call AM_DEFINE_APP,$(NAME),$(RISCV_TEST_BUILD_DIR),$(SRCS)))
all: $(AM_APP_$(NAME)_INST)
else
all: $(AM_OBJS)
endif

clean:
	rm -rf $(AM_BUILD_DIR)
