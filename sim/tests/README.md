# DC-Chip 仿真基础设施与工具链测试目录 (sim/tests)

本目录包含 DC-Chip 仿真器自身组件的元测试 (Meta-tests) 以及系统级集成边界检查：
- `test_isa.py`: RV32E 编码宏、硬件译码器与反汇编器跨工具一致性测试
- `test_disasm.cpp`: C++ 反汇编引擎格式化字符串与操作数提取自检
- `test_memory.cpp`: 双端口仿真内存模型多 byte-lane、掩码与边界自检
- `test_reference.cpp`: C++ 体系结构黄金模型 (ReferenceModel) 指令行为自检
- `test_simulation.cpp`: Verilator 仿真步进引擎状态机、快照与复位自检
- `test_difftest.cpp`: 差分测试引擎断言、mismatch 捕获与 skip_ref 自检
- `run_integration.sh`: 命令行 CLI、未对齐/非法指令异常注入正反例自检
