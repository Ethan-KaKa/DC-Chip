#include "memory.h"

#include <fstream>
#include <string_view>
#include <utility>
#include <vector>

namespace {

constexpr std::size_t kInstructionCapacity = 256;
constexpr std::uint32_t kOutOfBoundsInstruction = 0x00008000U;

std::vector<std::uint16_t> image;
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

bool load_hex_image(const std::string &path, std::string *error) {
  std::ifstream input(path);
  if (!input.is_open()) {
    if (error != nullptr) {
      *error = location(path, 1) + "unable to open image";
    }
    return false;
  }

  std::vector<std::uint16_t> parsed_image;
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
    if (word.size() != 4) {
      if (error != nullptr) {
        *error = location(path, line_number) +
                 "instruction word must contain exactly 4 hex digits";
      }
      return false;
    }

    std::uint16_t value = 0;
    for (char character : word) {
      if (!is_ascii_hex(character)) {
        if (error != nullptr) {
          *error = location(path, line_number) +
                   "instruction word contains a non-hex character";
        }
        return false;
      }
      value = static_cast<std::uint16_t>(
          (static_cast<unsigned int>(value) << 4U) |
          hex_digit_value(character));
    }

    if (parsed_image.size() == kInstructionCapacity) {
      if (error != nullptr) {
        *error = location(path, line_number) +
                 "image exceeds the 256-word instruction capacity";
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

  image = std::move(parsed_image);
  clear_fetch_status();
  return true;
}

std::size_t image_word_count() { return image.size(); }

void clear_fetch_status() {
  saw_out_of_bounds = false;
  first_out_of_bounds_address = 0;
}

bool fetch_out_of_bounds() { return saw_out_of_bounds; }

std::uint32_t first_oob_address() {
  return first_out_of_bounds_address;
}

}  // namespace dc_sim

extern "C" std::uint32_t sim_imem_read(std::uint32_t word_addr) {
  if (word_addr < image.size()) {
    return image[word_addr];
  }
  if (!saw_out_of_bounds) {
    saw_out_of_bounds = true;
    first_out_of_bounds_address = word_addr;
  }
  return kOutOfBoundsInstruction;
}
