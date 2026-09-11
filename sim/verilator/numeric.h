#ifndef DC_CHIP_SIM_VERILATOR_NUMERIC_H_
#define DC_CHIP_SIM_VERILATOR_NUMERIC_H_

#include <cstdint>
#include <string_view>

namespace dc_sim {

bool parse_unsigned(std::string_view text, std::uint64_t *value);

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_NUMERIC_H_
