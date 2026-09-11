#include "disasm.h"

#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>

namespace dc_sim {
namespace {

constexpr std::uint8_t kOpcodeLoad    = 0x03;
constexpr std::uint8_t kOpcodeMiscMem = 0x0f;
constexpr std::uint8_t kOpcodeOpImm   = 0x13;
constexpr std::uint8_t kOpcodeAuipc   = 0x17;
constexpr std::uint8_t kOpcodeStore   = 0x23;
constexpr std::uint8_t kOpcodeOp      = 0x33;
constexpr std::uint8_t kOpcodeLui     = 0x37;
constexpr std::uint8_t kOpcodeBranch  = 0x63;
constexpr std::uint8_t kOpcodeJalr    = 0x67;
constexpr std::uint8_t kOpcodeJal     = 0x6f;

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

std::int32_t sign_extend_b(std::uint32_t inst) {
  std::uint32_t imm = (((inst >> 31U) & 1U) << 12U) |
                      (((inst >> 7U) & 1U) << 11U) |
                      (((inst >> 25U) & 0x3fU) << 5U) |
                      (((inst >> 8U) & 0x0fU) << 1U);
  return static_cast<std::int32_t>((imm ^ 0x1000U) - 0x1000U);
}

std::int32_t sign_extend_j(std::uint32_t inst) {
  std::uint32_t imm = (((inst >> 31U) & 1U) << 20U) |
                      (((inst >> 12U) & 0xffU) << 12U) |
                      (((inst >> 20U) & 1U) << 11U) |
                      (((inst >> 21U) & 0x3ffU) << 1U);
  return static_cast<std::int32_t>((imm ^ 0x100000U) - 0x100000U);
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
  const std::int32_t immediate_b = sign_extend_b(instruction);
  const std::int32_t immediate_j = sign_extend_j(instruction);
  const std::uint32_t shamt = (instruction >> 20U) & 0x1fU;

  // LUI
  if (opcode == kOpcodeLui && valid_register(rd)) {
    const std::uint32_t immediate_u = instruction >> 12U;
    return "lui " + register_name(rd) + ", " + hex_value(immediate_u, 5);
  }

  // AUIPC
  if (opcode == kOpcodeAuipc && valid_register(rd)) {
    const std::uint32_t immediate_u = instruction >> 12U;
    return "auipc " + register_name(rd) + ", " + hex_value(immediate_u, 5);
  }

  // JAL
  if (opcode == kOpcodeJal && valid_register(rd)) {
    return "jal " + register_name(rd) + ", " + std::to_string(immediate_j);
  }

  // JALR
  if (opcode == kOpcodeJalr && funct3 == 0U && valid_register(rd) && valid_register(rs1)) {
    return "jalr " + register_name(rd) + ", " +
           std::to_string(immediate_i) + "(" + register_name(rs1) + ")";
  }

  // BRANCH
  if (opcode == kOpcodeBranch && valid_register(rs1) && valid_register(rs2)) {
    const char *mnemonic = nullptr;
    switch (funct3) {
      case 0: mnemonic = "beq"; break;
      case 1: mnemonic = "bne"; break;
      case 4: mnemonic = "blt"; break;
      case 5: mnemonic = "bge"; break;
      case 6: mnemonic = "bltu"; break;
      case 7: mnemonic = "bgeu"; break;
      default: break;
    }
    if (mnemonic != nullptr) {
      return std::string(mnemonic) + " " + register_name(rs1) + ", " +
             register_name(rs2) + ", " + std::to_string(immediate_b);
    }
  }

  // LOAD
  if (opcode == kOpcodeLoad && valid_register(rd) && valid_register(rs1)) {
    const char *mnemonic = nullptr;
    switch (funct3) {
      case 0: mnemonic = "lb"; break;
      case 1: mnemonic = "lh"; break;
      case 2: mnemonic = "lw"; break;
      case 4: mnemonic = "lbu"; break;
      case 5: mnemonic = "lhu"; break;
      default: break;
    }
    if (mnemonic != nullptr) {
      return std::string(mnemonic) + " " + register_name(rd) + ", " +
             std::to_string(immediate_i) + "(" + register_name(rs1) + ")";
    }
  }

  // STORE
  if (opcode == kOpcodeStore && valid_register(rs1) && valid_register(rs2)) {
    const char *mnemonic = nullptr;
    switch (funct3) {
      case 0: mnemonic = "sb"; break;
      case 1: mnemonic = "sh"; break;
      case 2: mnemonic = "sw"; break;
      default: break;
    }
    if (mnemonic != nullptr) {
      return std::string(mnemonic) + " " + register_name(rs2) + ", " +
             std::to_string(immediate_s) + "(" + register_name(rs1) + ")";
    }
  }

  // OP_IMM
  if (opcode == kOpcodeOpImm && valid_register(rd) && valid_register(rs1)) {
    switch (funct3) {
      case 0: return "addi " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(immediate_i);
      case 2: return "slti " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(immediate_i);
      case 3: return "sltiu " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(immediate_i);
      case 4: return "xori " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(immediate_i);
      case 6: return "ori " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(immediate_i);
      case 7: return "andi " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(immediate_i);
      case 1:
        if (funct7 == 0) {
          return "slli " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(shamt);
        }
        break;
      case 5:
        if (funct7 == 0) {
          return "srli " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(shamt);
        } else if (funct7 == 0x20) {
          return "srai " + register_name(rd) + ", " + register_name(rs1) + ", " + std::to_string(shamt);
        }
        break;
      default: break;
    }
  }

  // OP
  if (opcode == kOpcodeOp && valid_register(rd) && valid_register(rs1) && valid_register(rs2)) {
    const char *mnemonic = nullptr;
    switch (funct3) {
      case 0:
        if (funct7 == 0) mnemonic = "add";
        else if (funct7 == 0x20) mnemonic = "sub";
        break;
      case 1:
        if (funct7 == 0) mnemonic = "sll";
        break;
      case 2:
        if (funct7 == 0) mnemonic = "slt";
        break;
      case 3:
        if (funct7 == 0) mnemonic = "sltu";
        break;
      case 4:
        if (funct7 == 0) mnemonic = "xor";
        break;
      case 5:
        if (funct7 == 0) mnemonic = "srl";
        else if (funct7 == 0x20) mnemonic = "sra";
        break;
      case 6:
        if (funct7 == 0) mnemonic = "or";
        break;
      case 7:
        if (funct7 == 0) mnemonic = "and";
        break;
      default: break;
    }
    if (mnemonic != nullptr) {
      return std::string(mnemonic) + " " + register_name(rd) + ", " +
             register_name(rs1) + ", " + register_name(rs2);
    }
  }

  // FENCE
  if (opcode == kOpcodeMiscMem && funct3 == 0U) {
    return "fence";
  }

  return raw_word(instruction);
}

}  // namespace dc_sim
