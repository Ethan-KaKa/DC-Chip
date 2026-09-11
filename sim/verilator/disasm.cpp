#include "disasm.h"

#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>

namespace dc_sim {
namespace {

constexpr std::uint8_t kOpcodeLoad = 0x03;
constexpr std::uint8_t kOpcodeOpImm = 0x13;
constexpr std::uint8_t kOpcodeStore = 0x23;
constexpr std::uint8_t kOpcodeOp = 0x33;
constexpr std::uint8_t kOpcodeLui = 0x37;
constexpr std::uint8_t kOpcodeJalr = 0x67;

std::string hex_value(std::uint32_t value, int width) {
  std::ostringstream output;
  output << "0x" << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(width) << value;
  return output.str();
}

std::string register_name(std::uint8_t index) {
  return "x" + std::to_string(index);
}

std::int32_t sign_extend_12(std::uint32_t value) {
  const std::uint32_t immediate = value & 0xfffU;
  return static_cast<std::int32_t>((immediate ^ 0x800U) - 0x800U);
}

bool valid_register(std::uint8_t index) { return index < 16U; }

std::string raw_word(std::uint32_t instruction) {
  return ".word " + hex_value(instruction, 8);
}

}  // namespace

std::string disassemble(std::uint32_t instruction) {
  const std::uint8_t opcode =
      static_cast<std::uint8_t>(instruction & 0x7fU);
  const std::uint8_t rd =
      static_cast<std::uint8_t>((instruction >> 7U) & 0x1fU);
  const std::uint8_t funct3 =
      static_cast<std::uint8_t>((instruction >> 12U) & 0x07U);
  const std::uint8_t rs1 =
      static_cast<std::uint8_t>((instruction >> 15U) & 0x1fU);
  const std::uint8_t rs2 =
      static_cast<std::uint8_t>((instruction >> 20U) & 0x1fU);
  const std::uint8_t funct7 =
      static_cast<std::uint8_t>((instruction >> 25U) & 0x7fU);
  const std::int32_t immediate_i = sign_extend_12(instruction >> 20U);
  const std::uint32_t immediate_s_bits =
      ((instruction >> 20U) & 0xfe0U) | ((instruction >> 7U) & 0x1fU);
  const std::int32_t immediate_s = sign_extend_12(immediate_s_bits);

  if (opcode == kOpcodeOp && funct3 == 0U && funct7 == 0U &&
      valid_register(rd) && valid_register(rs1) && valid_register(rs2)) {
    return "add " + register_name(rd) + ", " + register_name(rs1) + ", " +
           register_name(rs2);
  }
  if (opcode == kOpcodeOpImm && funct3 == 0U && valid_register(rd) &&
      valid_register(rs1)) {
    return "addi " + register_name(rd) + ", " + register_name(rs1) + ", " +
           std::to_string(immediate_i);
  }
  if (opcode == kOpcodeLui && valid_register(rd)) {
    const std::uint32_t immediate_u = instruction >> 12U;
    return "lui " + register_name(rd) + ", " + hex_value(immediate_u, 5);
  }
  if (opcode == kOpcodeLoad && (funct3 == 2U || funct3 == 4U) &&
      valid_register(rd) && valid_register(rs1)) {
    const char *mnemonic = funct3 == 2U ? "lw" : "lbu";
    return std::string(mnemonic) + " " + register_name(rd) + ", " +
           std::to_string(immediate_i) + "(" + register_name(rs1) + ")";
  }
  if (opcode == kOpcodeStore && (funct3 == 0U || funct3 == 2U) &&
      valid_register(rs1) && valid_register(rs2)) {
    const char *mnemonic = funct3 == 2U ? "sw" : "sb";
    return std::string(mnemonic) + " " + register_name(rs2) + ", " +
           std::to_string(immediate_s) + "(" + register_name(rs1) + ")";
  }
  if (opcode == kOpcodeJalr && funct3 == 0U && valid_register(rd) &&
      valid_register(rs1)) {
    return "jalr " + register_name(rd) + ", " +
           std::to_string(immediate_i) + "(" + register_name(rs1) + ")";
  }

  return raw_word(instruction);
}

}  // namespace dc_sim
