#include "disasm.h"

#include <iomanip>
#include <sstream>
#include <string>

namespace dc_sim {
namespace {

std::string hex_value(std::uint16_t value, int width) {
  std::ostringstream output;
  output << "0x" << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(width) << value;
  return output.str();
}

std::string register_name(std::uint8_t index) {
  return "R" + std::to_string(index);
}

std::string register_instruction(const char *mnemonic, std::uint8_t rd,
                                 std::uint8_t rs) {
  return std::string(mnemonic) + " " + register_name(rd) + ", " +
         register_name(rs);
}

std::string immediate_instruction(const char *mnemonic, std::uint8_t rd,
                                  std::uint8_t immediate) {
  return std::string(mnemonic) + " " + register_name(rd) + ", #" +
         hex_value(immediate, 2);
}

std::string raw_word(std::uint16_t instruction) {
  return ".word " + hex_value(instruction, 4);
}

}  // namespace

std::string disassemble(std::uint16_t instruction) {
  const std::uint8_t opcode =
      static_cast<std::uint8_t>((instruction >> 12U) & 0x0fU);
  const std::uint8_t rd =
      static_cast<std::uint8_t>((instruction >> 10U) & 0x03U);
  const std::uint8_t rs =
      static_cast<std::uint8_t>((instruction >> 8U) & 0x03U);
  const std::uint8_t immediate =
      static_cast<std::uint8_t>(instruction & 0xffU);

  switch (opcode) {
    case 0x0:
      if (rs == 0) {
        return immediate_instruction("MOVI", rd, immediate);
      }
      break;
    case 0x1:
      if (immediate == 0) {
        return register_instruction("MOV", rd, rs);
      }
      break;
    case 0x2:
      if (rs == 0) {
        return immediate_instruction("ADDI", rd, immediate);
      }
      break;
    case 0x3:
      if (immediate == 0) {
        return register_instruction("ADD", rd, rs);
      }
      break;
    case 0x4:
      if (immediate == 0) {
        return register_instruction("SUB", rd, rs);
      }
      break;
    case 0x5:
      if (immediate == 0) {
        return register_instruction("AND", rd, rs);
      }
      break;
    case 0x6:
      if (immediate == 0) {
        return register_instruction("OR", rd, rs);
      }
      break;
    case 0x7:
      if (rd == 0 && rs == 0) {
        return "JUMP #" + hex_value(immediate, 2);
      }
      break;
    default:
      break;
  }

  return raw_word(instruction);
}

}  // namespace dc_sim
