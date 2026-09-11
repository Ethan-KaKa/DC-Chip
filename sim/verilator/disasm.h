#ifndef DC_CHIP_SIM_VERILATOR_DISASM_H_
#define DC_CHIP_SIM_VERILATOR_DISASM_H_

#include <cstdint>
#include <string>

namespace dc_sim {

std::string disassemble(std::uint32_t instruction);

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_DISASM_H_
