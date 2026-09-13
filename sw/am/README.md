# DC-Chip AM 构建接口

`build.mk` 是 DC-Chip 裸机应用的公共构建规则。它统一提供 RV32E/`ilp32e`
编译参数、AM runtime 对象、链接脚本、ISA 审计以及 IROM/DRAM 双镜像生成。

应用 Makefile 只需要设置输出目录，并调用：

```makefile
include $(REPO_ROOT)/sw/am/build.mk
$(eval $(call AM_DEFINE_APP,my-app,$(BUILD_DIR)/my-app,path/to/main.c))
```

`AM_CFLAGS`、`AM_LDFLAGS` 和工具链变量属于 AM 平台契约。应用如有必要，
只能通过 `AM_APP_CFLAGS` 或 `AM_APP_LDFLAGS` 追加自身选项，不应重新定义
ISA、ABI、链接脚本或 runtime 对象。

每个应用目标生成 `.elf`、`.txt`、`.inst.bin` 和 `.data.bin`；其中反汇编
会自动经过 `check_isa_subset.py` 审计。
