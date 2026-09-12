# mk/unit.mk - 硬件单测与静态测试模块 (Layer 1)

UNIT_DIR := $(BUILD_DIR)/unit

ISA_PKG := rtl/core/dc_isa_pkg.sv
COMB_RTL := $(ISA_PKG) \
	rtl/core/decoder.sv \
	rtl/core/alu.sv
CORE_RTL := $(COMB_RTL) \
	rtl/core/regfile.sv \
	rtl/core/cpu_core.sv
PERIPH_RTL := rtl/periph/led_controller.sv \
	rtl/periph/uart_controller.sv
SOC_RTL := rtl/soc/mmio_cdc_bridge.sv \
	rtl/soc/periph_interconnect.sv \
	rtl/soc/soc_interconnect.sv \
	rtl/soc/dc_soc_top.sv

# 静态规则检查 (Lint)
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

# 单元编译规则
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

# 各单独单测运行目标
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

# 历史兼容目标
test-unit:
	$(PYTHON) scripts/test_runner.py --suite unit --batch

# 统一新入口: make testunit [list | batch | ALL=...]

testunit:
	@case "$(word 2,$(MAKECMDGOALS))" in \
		list)  $(PYTHON) scripts/test_runner.py --suite unit --list ;; \
		batch) $(PYTHON) scripts/test_runner.py --suite unit --batch ;; \
		*)     if [ -n "$(ALL)" ]; then \
				$(PYTHON) scripts/test_runner.py --suite unit --filter "$(ALL)"; \
			   else \
				$(PYTHON) scripts/test_runner.py --suite unit --batch; \
			   fi ;; \
	esac

.PHONY: lint-isa lint-comb lint lint-mem \
	test-alu test-decoder test-regfile test-core test-led test-uart \
	test-periph-interconnect test-cdc test-interconnect test-soc \
	test-unit testunit
