#ifndef DC_CHIP_SIM_VERILATOR_MEMORY_H_
#define DC_CHIP_SIM_VERILATOR_MEMORY_H_

#include <cstddef>
#include <cstdint>
#include <string>

namespace dc_sim {

bool load_hex_image(const std::string &path, std::string *error);
std::size_t image_word_count();
void clear_fetch_status();
bool fetch_out_of_bounds();
std::uint32_t first_oob_address();

}  // namespace dc_sim

extern "C" std::uint32_t sim_imem_read(std::uint32_t word_addr);

#endif  // DC_CHIP_SIM_VERILATOR_MEMORY_H_
