# DC-Chip 硬件单测目录 (sim/tb)

本目录包含 DC-Chip 针对各个可综合 RTL 模块的纯硬件白盒单元测试 (Unit Testbench)，使用 Icarus Verilog (`iverilog + vvp`) 运行。
测试不依赖 CPU 指令取指或 C 语言软件栈，专注于毫秒级快速阻断模块内部的时序逻辑与接口握手协议错误。

## 模块测试清单
- `tb_alu.sv`: 算术逻辑单元运算、位移与分支比较标志位自检
- `tb_decoder.sv`: RV32E 37条基础指令译码、立即数重组与非法指令识别自检
- `tb_regfile.sv`: 通用寄存器堆 (x0--x15) 读写、内部旁路与 x0 写保护自检
- `tb_cpu_core.sv`: 单周期 CPU 核心取指、译码、执行与写回流水自检
- `tb_led_controller.sv`: 16位 MMIO LED 控制器读写、字节使能与管脚输出自检
- `tb_uart_controller.sv`: MMIO UART 控制器 16字节 FIFO、波特率分频与收发移位自检
- `tb_buttons_controller.sv`: 8位 MMIO Buttons 输入同步、只读访问与响应错误自检
- `tb_seg7_controller.sv`: 8位十六进制七段数码管 MMIO 读写、字节使能与全字形译码自检
- `tb_periph_interconnect.sv`: 1-to-N 外设总线路由器地址分流与未映射地址总线错误自检
- `tb_mmio_cdc_bridge.sv`: CPU 与外设跨时钟域 MMIO 握手桥异步四相翻转自检
- `tb_soc_interconnect.sv`: SoC 内存与外设地址空间译码分流与 access fault 契约自检
- `tb_dc_soc_top.sv`: `dc_soc_subsystem` 总线级集成、指令取指与 DRAM 访存时序自检
