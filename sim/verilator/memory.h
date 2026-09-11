#ifndef DC_CHIP_SIM_VERILATOR_MEMORY_H_
#define DC_CHIP_SIM_VERILATOR_MEMORY_H_

#include <cstddef>
#include <cstdint>
#include <string>

namespace dc_sim {

constexpr std::uint32_t kIromBase = 0x00000000U;
constexpr std::size_t kIromCapacityBytes = 65536U;
constexpr std::size_t kIromCapacityWords = 16384U;

constexpr std::uint32_t kDramBase = 0x20000000U;
constexpr std::size_t kDramCapacityBytes = 65536U;
constexpr std::size_t kDramCapacityWords = 16384U;

constexpr std::uint32_t kTohostAddr = 0xfffffff0U;

enum class MemoryRegion {
  kIrom,
  kDram,
};

enum class ImageFormat {
  kAuto,
  kHex,
  kBin,
};

bool load_hex_image(const std::string &path, std::string *error);
bool load_binary_image(const std::string &path, MemoryRegion region, std::string *error);
bool load_image(const std::string &path, MemoryRegion region, ImageFormat format, std::string *error);

std::size_t image_word_count();
std::size_t irom_loaded_bytes();
std::size_t dram_loaded_bytes();
void reset_memory();

std::uint32_t read_irom_word(std::size_t word_index);
std::uint32_t read_dram_word(std::size_t word_index);
void write_dram_byte(std::uint32_t byte_addr, std::uint8_t byte_val);

void clear_fetch_status();
bool fetch_out_of_bounds();
std::uint32_t first_oob_address();

}  // namespace dc_sim

extern "C" {
void sim_irom_read(std::uint32_t addr, std::uint32_t *data);
void sim_dram_read(std::uint32_t addr, std::uint32_t *data);
void sim_dram_write(std::uint32_t addr, std::uint32_t data, std::uint32_t wstrb);
std::uint32_t sim_imem_read(std::uint32_t word_addr);
}

#endif  // DC_CHIP_SIM_VERILATOR_MEMORY_H_
