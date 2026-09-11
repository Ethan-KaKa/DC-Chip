#include "memory.h"

#include <array>
#include <fstream>
#include <string_view>
#include <utility>
#include <vector>

namespace {

std::array<std::uint32_t, dc_sim::kIromCapacityWords> irom_storage{};
std::array<std::uint32_t, dc_sim::kDramCapacityWords> dram_storage{};
std::size_t loaded_word_count = 0;

bool saw_out_of_bounds = false;
std::uint32_t first_out_of_bounds_address = 0;

bool is_ascii_space(char character) {
  return character == ' ' || character == '\t' || character == '\n' ||
         character == '\r' || character == '\f' || character == '\v';
}

bool is_ascii_hex(char character) {
  return (character >= '0' && character <= '9') ||
         (character >= 'a' && character <= 'f') ||
         (character >= 'A' && character <= 'F');
}

unsigned int hex_digit_value(char character) {
  if (character >= '0' && character <= '9') {
    return static_cast<unsigned int>(character - '0');
  }
  if (character >= 'a' && character <= 'f') {
    return static_cast<unsigned int>(character - 'a') + 10U;
  }
  return static_cast<unsigned int>(character - 'A') + 10U;
}

std::string_view trim_ascii_space(std::string_view text) {
  while (!text.empty() && is_ascii_space(text.front())) {
    text.remove_prefix(1);
  }
  while (!text.empty() && is_ascii_space(text.back())) {
    text.remove_suffix(1);
  }
  return text;
}

std::string location(const std::string &path, std::size_t line_number) {
  return path + ":" + std::to_string(line_number) + ": ";
}

}  // namespace

namespace dc_sim {

void reset_memory() {
  irom_storage.fill(0);
  dram_storage.fill(0);
  loaded_word_count = 0;
  clear_fetch_status();
}

bool load_hex_image(const std::string &path, std::string *error) {
  std::ifstream input(path);
  if (!input.is_open()) {
    if (error != nullptr) {
      *error = location(path, 1) + "unable to open image";
    }
    return false;
  }

  std::vector<std::uint32_t> parsed_image;
  std::string line;
  std::size_t line_number = 0;
  while (std::getline(input, line)) {
    ++line_number;
    const std::size_t comment_position = line.find('#');
    if (comment_position != std::string::npos) {
      line.erase(comment_position);
    }

    const std::string_view word = trim_ascii_space(line);
    if (word.empty()) {
      continue;
    }
    if (word.size() != 8) {
      if (error != nullptr) {
        *error = location(path, line_number) +
                 "instruction word must contain exactly 8 hex digits";
      }
      return false;
    }

    std::uint32_t value = 0;
    for (char character : word) {
      if (!is_ascii_hex(character)) {
        if (error != nullptr) {
          *error = location(path, line_number) +
                   "instruction word contains a non-hex character";
        }
        return false;
      }
      value = (value << 4U) | hex_digit_value(character);
    }

    if (parsed_image.size() == kIromCapacityWords) {
      if (error != nullptr) {
        *error = location(path, line_number) +
                 "image exceeds the 256-word (1 KiB) instruction capacity";
      }
      return false;
    }
    parsed_image.push_back(value);
  }

  if (input.bad()) {
    if (error != nullptr) {
      *error = location(path, line_number + 1) + "error while reading image";
    }
    return false;
  }
  if (parsed_image.empty()) {
    if (error != nullptr) {
      *error = location(path, 1) + "image contains no instruction words";
    }
    return false;
  }

  reset_memory();
  for (std::size_t index = 0; index < parsed_image.size(); ++index) {
    irom_storage[index] = parsed_image[index];
  }
  loaded_word_count = parsed_image.size();
  return true;
}

std::size_t image_word_count() { return loaded_word_count; }

std::uint32_t read_irom_word(std::size_t word_index) {
  if (word_index < kIromCapacityWords) {
    return irom_storage[word_index];
  }
  return 0;
}

std::uint32_t read_dram_word(std::size_t word_index) {
  if (word_index < kDramCapacityWords) {
    return dram_storage[word_index];
  }
  return 0;
}

void write_dram_byte(std::uint32_t byte_addr, std::uint8_t byte_val) {
  if (byte_addr >= kDramBase &&
      byte_addr < (kDramBase + kDramCapacityBytes)) {
    const std::size_t word_index = (byte_addr - kDramBase) >> 2U;
    const std::size_t lane = byte_addr & 3U;
    const std::uint32_t shift = static_cast<std::uint32_t>(lane * 8U);
    dram_storage[word_index] = (dram_storage[word_index] & ~(0xffU << shift)) |
                               (static_cast<std::uint32_t>(byte_val) << shift);
  }
}

void clear_fetch_status() {
  saw_out_of_bounds = false;
  first_out_of_bounds_address = 0;
}

bool fetch_out_of_bounds() { return saw_out_of_bounds; }

std::uint32_t first_oob_address() {
  return first_out_of_bounds_address;
}

}  // namespace dc_sim

extern "C" {

void sim_irom_read(std::uint32_t addr, std::uint32_t *data) {
  if (data == nullptr) {
    return;
  }
  if (addr < dc_sim::kIromCapacityBytes && (addr & 3U) == 0) {
    const std::size_t word_index = addr >> 2U;
    *data = irom_storage[word_index];
  } else {
    *data = 0;
  }
}

void sim_dram_read(std::uint32_t addr, std::uint32_t *data) {
  if (data == nullptr) {
    return;
  }
  if (addr >= dc_sim::kDramBase &&
      addr < (dc_sim::kDramBase + dc_sim::kDramCapacityBytes)) {
    const std::size_t word_index = (addr - dc_sim::kDramBase) >> 2U;
    *data = dram_storage[word_index];
  } else {
    *data = 0;
  }
}

void sim_dram_write(std::uint32_t addr, std::uint32_t data, std::uint32_t wstrb) {
  if (addr >= dc_sim::kDramBase &&
      addr < (dc_sim::kDramBase + dc_sim::kDramCapacityBytes)) {
    const std::size_t word_index = (addr - dc_sim::kDramBase) >> 2U;
    for (std::size_t lane = 0; lane < 4; ++lane) {
      if ((wstrb >> lane) & 1U) {
        const std::uint32_t shift = static_cast<std::uint32_t>(lane * 8U);
        const std::uint32_t byte_val = (data >> shift) & 0xffU;
        dram_storage[word_index] =
            (dram_storage[word_index] & ~(0xffU << shift)) | (byte_val << shift);
      }
    }
  }
}

std::uint32_t sim_imem_read(std::uint32_t word_addr) {
  return dc_sim::read_irom_word(word_addr);
}

}
