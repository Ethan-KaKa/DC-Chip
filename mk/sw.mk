# mk/sw.mk - 全系统软件编译与测试调度模块 (Layer 3)

# 统一入口:
#   make sw                             -> 仅编译所有软件镜像
#   make sw tests [list|batch|ALL=...]  -> 运行全系统微测试
#   make sw riscv-tests [list|batch...] -> 运行合规套件
#   make sw demo [list|build|run]       -> 构建或运行交互式演示
SW_TEST_TAIL := $(wordlist 3,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
SW_TEST_BATCH := $(filter batch,$(SW_TEST_TAIL))
SW_TEST_SDB_OFF := $(filter sdboff,$(SW_TEST_TAIL))$(SW_TEST_BATCH)
SW_TEST_NVBOARD_OFF := $(filter nvboardoff,$(SW_TEST_TAIL))$(SW_TEST_BATCH)
SW_TEST_WAVE_OFF := $(filter waveoff,$(SW_TEST_TAIL))$(SW_TEST_BATCH)
SW_TEST_RUNTIME_ARGS := \
	$(if $(SW_TEST_SDB_OFF),--sdb-off) \
	$(if $(SW_TEST_NVBOARD_OFF),--nvboard-off) \
	$(if $(SW_TEST_WAVE_OFF),--wave-off)
SW_TEST_INTERACTIVE_ARG := $(if $(and $(filter y,$(CONFIG_DC_SIM_SDB)),$(if $(SW_TEST_SDB_OFF),,y)),--interactive)

ifeq ($(CLI_CHECK_ONLY),1)
sw:
	@:
else
sw:
	@if [ -z "$(word 2,$(MAKECMDGOALS))" ]; then \
		$(MAKE) -C sw/tests BUILD_DIR=$(abspath $(BUILD_DIR))/sw; \
	else \
		case "$(word 2,$(MAKECMDGOALS))" in \
			tests) \
				case "$(SW_TEST_TAIL)" in \
				list)  $(PYTHON) scripts/test_runner.py --suite sw-tests --list --make "$(MAKE)" ;; \
				*)     if [ -n "$(ALL)" ]; then \
						$(PYTHON) scripts/test_runner.py --suite sw-tests --filter "$(ALL)" \
							--simulator "$(abspath $(SIM_BIN))" \
							--test-dir "$(abspath $(BUILD_DIR))/sw/tests" --make "$(MAKE)" \
							--build-dir "$(abspath $(BUILD_DIR))" \
							--config-file "$(abspath $(CONFIG_FILE))" \
							$(SW_TEST_RUNTIME_ARGS) $(SW_TEST_INTERACTIVE_ARG); \
					   else \
						$(PYTHON) scripts/test_runner.py --suite sw-tests --batch \
							--simulator "$(abspath $(SIM_BIN))" \
							--test-dir "$(abspath $(BUILD_DIR))/sw/tests" --make "$(MAKE)" \
							--build-dir "$(abspath $(BUILD_DIR))" \
							--config-file "$(abspath $(CONFIG_FILE))" \
							$(SW_TEST_RUNTIME_ARGS) $(SW_TEST_INTERACTIVE_ARG); \
					   fi ;; \
				esac ;; \
			riscv-tests) \
				case "$(word 3,$(MAKECMDGOALS))" in \
				list)  $(PYTHON) scripts/test_runner.py --suite riscv-tests --list --make "$(MAKE)" ;; \
				batch) $(PYTHON) scripts/test_runner.py --suite riscv-tests --batch --make "$(MAKE)" \
						--simulator "$(abspath $(SIM_BIN))" --build-dir "$(abspath $(BUILD_DIR))" \
						--config-file "$(abspath $(CONFIG_FILE))" --sdb-off --nvboard-off --wave-off ;; \
				*)     if [ -n "$(ALL)" ]; then \
						$(PYTHON) scripts/test_runner.py --suite riscv-tests --filter "$(ALL)" --make "$(MAKE)" \
							--simulator "$(abspath $(SIM_BIN))" --build-dir "$(abspath $(BUILD_DIR))" \
							--config-file "$(abspath $(CONFIG_FILE))" --sdb-off --nvboard-off --wave-off; \
					   else \
						$(PYTHON) scripts/test_runner.py --suite riscv-tests --batch --make "$(MAKE)" \
							--simulator "$(abspath $(SIM_BIN))" --build-dir "$(abspath $(BUILD_DIR))" \
							--config-file "$(abspath $(CONFIG_FILE))" --sdb-off --nvboard-off --wave-off; \
					   fi ;; \
						esac ;; \
			demo) \
				case "$(ALL)" in ""|uart_led_demo) ;; *) printf 'error: unknown demo in ALL: %s\n' "$(ALL)" >&2; exit 1 ;; esac; \
				case "$(word 3,$(MAKECMDGOALS))" in \
				list)  $(PYTHON) scripts/test_runner.py --suite sw-demos --list ;; \
				build) $(MAKE) -C sw/demo BUILD_DIR=$(abspath $(BUILD_DIR))/sw build ;; \
				run)   $(MAKE) --no-print-directory sim-build && \
					$(MAKE) -C sw/demo BUILD_DIR=$(abspath $(BUILD_DIR))/sw build && \
					$(if $(filter y,$(CONFIG_DC_SIM_NVBOARD)),,if [ "$(CONFIG_DC_SIM_NVBOARD)" != "y" ]; then printf 'error: demo run requires DC_SIM_NVBOARD=y in .config\n' >&2; exit 1; fi;) \
					$(abspath $(SIM_BIN)) --image-inst $(abspath $(BUILD_DIR))/sw/demo/uart_led_demo/uart_led_demo.inst.bin --image-data $(abspath $(BUILD_DIR))/sw/demo/uart_led_demo/uart_led_demo.data.bin --sdb-off ;; \
				*) printf 'error: make sw demo requires list, build, or run\n' >&2; exit 1 ;; \
				esac ;; \
			*) \
				printf 'error: 未知的 sw 子目标 "%s". 支持: make sw tests [list|batch|ALL=...], make sw demo [list|build|run] 或 make sw riscv-tests [list|batch]\n' "$(word 2,$(MAKECMDGOALS))" >&2; \
				exit 1 ;; \
		 esac; \
	fi
endif

.PHONY: sw
