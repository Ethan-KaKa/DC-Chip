#include "disasm.h"

#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

struct Example {
  std::uint32_t instruction;
  const char *text;
};

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string hex_value(std::uint32_t value) {
  std::ostringstream output;
  output << "0x" << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(8) << value;
  return output.str();
}

void require_disassembly(std::uint32_t instruction, const std::string &expected) {
  const std::string actual = dc_sim::disassemble(instruction);
  require(actual == expected,
          hex_value(instruction) + " expected '" + expected + "' but got '" +
              actual + "'");
}

void require_raw(std::uint32_t instruction) {
  require_disassembly(instruction, ".word " + hex_value(instruction));
}

void test_specification_examples() {
  constexpr std::array<Example, 8> kExamples = {{
      {0x002081b3U, "add x3, x1, x2"},
      {0xfff08193U, "addi x3, x1, -1"},
      {0x123451b7U, "lui x3, 0x12345"},
      {0x0040a183U, "lw x3, 4(x1)"},
      {0x0010c183U, "lbu x3, 1(x1)"},
      {0x0020a223U, "sw x2, 4(x1)"},
      {0x002080a3U, "sb x2, 1(x1)"},
      {0x008082e7U, "jalr x5, 8(x1)"},
  }};

  for (const Example &example : kExamples) {
    require_disassembly(example.instruction, example.text);
  }
}

void test_immediate_boundaries() {
  require_disassembly(0x80008093U, "addi x1, x1, -2048");
  require_disassembly(0x7ff08093U, "addi x1, x1, 2047");
  require_disassembly(0x8000a023U, "sw x0, -2048(x1)");
  require_disassembly(0x7e20afa3U, "sw x2, 2047(x1)");
  require_disassembly(0xfffff7b7U, "lui x15, 0xfffff");
}

void test_exact_function_codes() {
  for (std::uint32_t funct3 = 0; funct3 < 8; ++funct3) {
    for (std::uint32_t funct7 = 0; funct7 < 128; ++funct7) {
      const std::uint32_t instruction =
          (funct7 << 25U) | (2U << 20U) | (1U << 15U) | (funct3 << 12U) |
          (3U << 7U) | 0x33U;
      if (funct3 == 0 && funct7 == 0) {
        require_disassembly(instruction, "add x3, x1, x2");
      } else {
        require_raw(instruction);
      }
    }
  }

  for (std::uint32_t funct3 = 0; funct3 < 8; ++funct3) {
    const std::uint32_t op_imm =
        (1U << 15U) | (funct3 << 12U) | (3U << 7U) | 0x13U;
    const std::uint32_t load =
        (1U << 15U) | (funct3 << 12U) | (3U << 7U) | 0x03U;
    const std::uint32_t store =
        (2U << 20U) | (1U << 15U) | (funct3 << 12U) | 0x23U;
    const std::uint32_t jalr =
        (1U << 15U) | (funct3 << 12U) | (3U << 7U) | 0x67U;

    if (funct3 == 0) {
      require_disassembly(op_imm, "addi x3, x1, 0");
      require_disassembly(store, "sb x2, 0(x1)");
      require_disassembly(jalr, "jalr x3, 0(x1)");
    } else {
      require_raw(op_imm);
      require_raw(jalr);
      if (funct3 == 2) {
        require_disassembly(store, "sw x2, 0(x1)");
      } else {
        require_raw(store);
      }
    }

    if (funct3 == 2) {
      require_disassembly(load, "lw x3, 0(x1)");
    } else if (funct3 == 4) {
      require_disassembly(load, "lbu x3, 0(x1)");
    } else {
      require_raw(load);
    }
  }
}

void test_rv32e_register_limit() {
  for (std::uint32_t reg = 0; reg < 16; ++reg) {
    const std::uint32_t instruction =
        (reg << 20U) | (reg << 15U) | (reg << 7U) | 0x33U;
    require_disassembly(instruction, "add x" + std::to_string(reg) + ", x" +
                                             std::to_string(reg) + ", x" +
                                             std::to_string(reg));
  }

  constexpr std::array<std::uint32_t, 16> kUpperRegisterEncodings = {{
      0x00208833U, 0x002800b3U, 0x010080b3U, 0x00008813U,
      0x00080093U, 0x0000a803U, 0x00082083U, 0x0000c803U,
      0x00084083U, 0x0100a023U, 0x00282023U, 0x01008023U,
      0x00280023U, 0x00008867U, 0x000800e7U, 0x00000837U,
  }};
  for (std::uint32_t instruction : kUpperRegisterEncodings) {
    require_raw(instruction);
  }

  // High immediate bits in LUI are data, not rs1/rs2 fields.
  require_disassembly(0xfffff7b7U, "lui x15, 0xfffff");
}

void test_unassigned_opcodes() {
  for (std::uint32_t opcode = 0; opcode < 128; ++opcode) {
    if (opcode != 0x03U && opcode != 0x13U && opcode != 0x23U &&
        opcode != 0x33U && opcode != 0x37U && opcode != 0x67U) {
      require_raw(opcode);
    }
  }
}

}  // namespace

int main() {
  try {
    test_specification_examples();
    test_immediate_boundaries();
    test_exact_function_codes();
    test_rv32e_register_limit();
    test_unassigned_opcodes();
  } catch (const std::exception &error) {
    std::cerr << "test_disasm: FAIL " << error.what() << '\n';
    return 1;
  }

  std::cout << "test_disasm: PASS (v0.2 directed and function-space cases)\n";
  return 0;
}
