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
  std::uint16_t instruction;
  const char *text;
};

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string hex_value(std::uint16_t value, int width) {
  std::ostringstream output;
  output << "0x" << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(width) << value;
  return output.str();
}

std::string register_name(std::uint8_t index) {
  return "R" + std::to_string(index);
}

std::string expected_disassembly(std::uint16_t instruction,
                                 bool *canonical) {
  const std::uint8_t opcode =
      static_cast<std::uint8_t>((instruction >> 12U) & 0x0fU);
  const std::uint8_t rd =
      static_cast<std::uint8_t>((instruction >> 10U) & 0x03U);
  const std::uint8_t rs =
      static_cast<std::uint8_t>((instruction >> 8U) & 0x03U);
  const std::uint8_t immediate =
      static_cast<std::uint8_t>(instruction & 0xffU);

  *canonical = false;
  const char *mnemonic = nullptr;
  bool immediate_form = false;
  if ((opcode == 0x0 || opcode == 0x2) && rs == 0) {
    mnemonic = opcode == 0x0 ? "MOVI" : "ADDI";
    immediate_form = true;
  } else if (opcode >= 0x1 && opcode <= 0x6 && opcode != 0x2 &&
             immediate == 0) {
    constexpr std::array<const char *, 7> kMnemonics = {
        nullptr, "MOV", nullptr, "ADD", "SUB", "AND", "OR"};
    mnemonic = kMnemonics[opcode];
  } else if (opcode == 0x7 && rd == 0 && rs == 0) {
    *canonical = true;
    return "JUMP #" + hex_value(immediate, 2);
  }

  if (mnemonic != nullptr) {
    *canonical = true;
    std::string text = std::string(mnemonic) + " " + register_name(rd) +
                       ", ";
    if (immediate_form) {
      return text + "#" + hex_value(immediate, 2);
    }
    return text + register_name(rs);
  }

  return ".word " + hex_value(instruction, 4);
}

void test_specification_examples() {
  constexpr std::array<Example, 8> kExamples = {{
      {0x0402, "MOVI R1, #0x02"},
      {0x1900, "MOV R2, R1"},
      {0x2408, "ADDI R1, #0x08"},
      {0x3600, "ADD R1, R2"},
      {0x4600, "SUB R1, R2"},
      {0x5600, "AND R1, R2"},
      {0x6600, "OR R1, R2"},
      {0x7008, "JUMP #0x08"},
  }};

  for (const Example &example : kExamples) {
    const std::string actual = dc_sim::disassemble(example.instruction);
    require(actual == example.text,
            "specification example " + hex_value(example.instruction, 4) +
                " expected '" + example.text + "' but got '" + actual +
                "'");
  }
}

void test_all_instruction_words() {
  std::uint32_t canonical_count = 0;
  for (std::uint32_t word = 0; word <= 0xffffU; ++word) {
    const std::uint16_t instruction = static_cast<std::uint16_t>(word);
    bool canonical = false;
    const std::string expected =
        expected_disassembly(instruction, &canonical);
    const std::string actual = dc_sim::disassemble(instruction);
    require(actual == expected,
            "instruction " + hex_value(instruction, 4) + " expected '" +
                expected + "' but got '" + actual + "'");
    if (canonical) {
      ++canonical_count;
    }
  }

  require(canonical_count == 2384,
          "canonical instruction count is not 2384");
}

}  // namespace

int main() {
  try {
    test_specification_examples();
    test_all_instruction_words();
  } catch (const std::exception &error) {
    std::cerr << "test_disasm: FAIL " << error.what() << '\n';
    return 1;
  }

  std::cout << "test_disasm: PASS (65536 instruction words)\n";
  return 0;
}
