#include "difftest.h"
#include "memory.h"
#include "reference_model.h"
#include "simulation.h"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error("test_difftest FAIL: " + message);
  }
}

std::uint32_t enc_add(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (rs2 << 20U) | (rs1 << 15U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_addi(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (rd << 7U) | 0b0010011;
}

std::uint32_t enc_lui(std::uint32_t rd, std::uint32_t imm20) {
  return (imm20 << 12U) | (rd << 7U) | 0b0110111;
}

std::uint32_t enc_lw(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (0b010 << 12U) | (rd << 7U) | 0b0000011;
}

std::uint32_t enc_lbu(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (0b100 << 12U) | (rd << 7U) | 0b0000011;
}

std::uint32_t enc_sw(std::uint32_t rs2, std::uint32_t rs1, std::int32_t imm) {
  const std::uint32_t uimm = static_cast<std::uint32_t>(imm) & 0xfffU;
  return ((uimm >> 5U) << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b010 << 12U) | ((uimm & 0x1fU) << 7U) | 0b0100011;
}

std::uint32_t enc_sb(std::uint32_t rs2, std::uint32_t rs1, std::int32_t imm) {
  const std::uint32_t uimm = static_cast<std::uint32_t>(imm) & 0xfffU;
  return ((uimm >> 5U) << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b000 << 12U) | ((uimm & 0x1fU) << 7U) | 0b0100011;
}

std::uint32_t enc_jalr(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (rd << 7U) | 0b1100111;
}

void write_hex_file(const std::string &path, const std::vector<std::uint32_t> &words) {
  std::ofstream out(path);
  if (!out.is_open()) {
    throw std::runtime_error("failed to open " + path + " for writing");
  }
  for (std::uint32_t word : words) {
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%08x\n", word);
    out << buf;
  }
}

void run_test_vector(const std::string &fixture_path,
                     const std::vector<std::uint32_t> &words,
                     std::uint64_t steps) {
  write_hex_file(fixture_path, words);
  std::string error;
  require(dc_sim::load_hex_image(fixture_path, &error), "load_hex_image: " + error);

  dc_sim::Simulation dut;
  dut.reset();

  dc_sim::ReferenceModel ref;
  ref.load_from_sim_memory();

  dc_sim::Difftest difftest(dut, ref);
  dc_sim::DifftestMismatch mismatch;
  for (std::uint64_t i = 0; i < steps; ++i) {
    bool ok = difftest.step_and_compare(1000, &mismatch);
    require(ok, mismatch.message);
  }
}

void test_directed(const std::string &temp_dir) {
  const std::string hex_file = temp_dir + "/test_directed.hex";
  std::vector<std::uint32_t> insts = {
      enc_addi(1, 0, 100),       // addi x1, x0, 100
      enc_addi(2, 0, -50),       // addi x2, x0, -50
      enc_add(3, 1, 2),          // add  x3, x1, x2 => 50
      enc_lui(4, 0x20000),       // lui  x4, 0x20000 => 0x20000000 (DRAM base)
      enc_sw(3, 4, 0),           // sw   x3, 0(x4) => DRAM[0..3] = 50
      enc_lw(5, 4, 0),           // lw   x5, 0(x4) => 50
      enc_addi(6, 0, 0x7f),      // addi x6, x0, 0x7f
      enc_sb(6, 4, 5),           // sb   x6, 5(x4) => DRAM[5] = 0x7f
      enc_lbu(7, 4, 5),          // lbu  x7, 5(x4) => 0x7f
      enc_lui(8, 0xfffff),       // lui  x8, 0xfffff
      enc_addi(8, 8, -16),       // addi x8, x8, -16 => 0xfffffff0
      enc_sw(0, 8, 0),           // sw   x0, 0(x8) => tohost exit 0
  };

  run_test_vector(hex_file, insts, insts.size());
}

void test_randomized(const std::string &temp_dir) {
  const std::string hex_file = temp_dir + "/test_random.hex";
  std::mt19937 rng(0xDC320001U); // Fixed seed from verification plan!

  std::vector<std::uint32_t> insts;
  // Initialize base address pointer: x1 = 0x20000000 (DRAM base)
  insts.push_back(enc_lui(1, 0x20000));

  // Generate 60 randomized computational / memory instructions
  for (int i = 0; i < 60; ++i) {
    const std::uint32_t op_type = rng() % 6;
    const std::uint32_t rd = (rng() % 14) + 2;  // x2..x15
    const std::uint32_t rs1 = (rng() % 14) + 2;
    const std::uint32_t rs2 = (rng() % 14) + 2;
    const std::int32_t imm12 = static_cast<std::int32_t>((rng() % 4096)) - 2048;

    switch (op_type) {
      case 0: // add
        insts.push_back(enc_add(rd, rs1, rs2));
        break;
      case 1: // addi
        insts.push_back(enc_addi(rd, rs1, imm12));
        break;
      case 2: // lui
        insts.push_back(enc_lui(rd, rng() % 0x10000));
        break;
      case 3: { // sw to DRAM
        const std::uint32_t word_offset = (rng() % 64) * 4;
        insts.push_back(enc_sw(rs2, 1, word_offset));
        break;
      }
      case 4: { // lw from DRAM
        const std::uint32_t word_offset = (rng() % 64) * 4;
        insts.push_back(enc_lw(rd, 1, word_offset));
        break;
      }
      case 5: { // sb to DRAM
        const std::uint32_t byte_offset = rng() % 256;
        insts.push_back(enc_sb(rs2, 1, byte_offset));
        break;
      }
    }
  }

  run_test_vector(hex_file, insts, insts.size());
}

void test_fault_difftest(const std::string &temp_dir) {
  // Test illegal instruction difftest
  {
    const std::string hex_file = temp_dir + "/test_fault_illegal.hex";
    std::vector<std::uint32_t> insts = {
        enc_addi(16, 0, 1), // x16 illegal
    };
    run_test_vector(hex_file, insts, 1);
  }

  // Test misaligned load difftest
  {
    const std::string hex_file = temp_dir + "/test_fault_misalign.hex";
    std::vector<std::uint32_t> insts = {
        enc_lui(1, 0x20000),
        enc_lw(2, 1, 1), // 0x20000001 misaligned
    };
    run_test_vector(hex_file, insts, 2);
  }
}

void test_binary_difftest(const std::string &temp_dir) {
  const std::string inst_bin = temp_dir + "/test_bin_inst.bin";
  const std::string data_bin = temp_dir + "/test_bin_data.bin";

  // Instruction image:
  // lui  x1, 0x20000       # DRAM base
  // lw   x2, 0(x1)         # read data from DRAM[0]
  // addi x3, x2, 42        # x3 = x2 + 42
  // sw   x3, 1, 4          # write to DRAM[4]
  // lui  x8, 0xfffff
  // addi x8, x8, -16       # 0xfffffff0
  // sw   x0, 8, 0          # tohost exit 0
  std::vector<std::uint32_t> insts = {
      enc_lui(1, 0x20000),
      enc_lw(2, 1, 0),
      enc_addi(3, 2, 42),
      enc_sw(3, 1, 4),
      enc_lui(8, 0xfffff),
      enc_addi(8, 8, -16),
      enc_sw(0, 8, 0),
  };

  std::vector<std::uint8_t> data = {100, 0, 0, 0};

  {
    std::ofstream out(inst_bin, std::ios::binary);
    require(out.is_open(), "failed to open " + inst_bin);
    for (std::uint32_t word : insts) {
      char bytes[4];
      bytes[0] = static_cast<char>(word & 0xff);
      bytes[1] = static_cast<char>((word >> 8) & 0xff);
      bytes[2] = static_cast<char>((word >> 16) & 0xff);
      bytes[3] = static_cast<char>((word >> 24) & 0xff);
      out.write(bytes, 4);
    }
  }

  {
    std::ofstream out(data_bin, std::ios::binary);
    require(out.is_open(), "failed to open " + data_bin);
    out.write(reinterpret_cast<const char *>(data.data()), static_cast<std::streamsize>(data.size()));
  }

  std::string error;
  require(dc_sim::load_binary_image(inst_bin, dc_sim::MemoryRegion::kIrom, &error), error);
  require(dc_sim::load_binary_image(data_bin, dc_sim::MemoryRegion::kDram, &error), error);

  dc_sim::Simulation dut;
  dut.reset();

  dc_sim::ReferenceModel ref;
  ref.load_from_sim_memory();

  dc_sim::Difftest difftest(dut, ref);
  dc_sim::DifftestMismatch mismatch;
  for (std::uint64_t i = 0; i < insts.size(); ++i) {
    bool ok = difftest.step_and_compare(1000, &mismatch);
    require(ok, mismatch.message);
  }
}

}  // namespace

int main(int argc, char **argv) {
  const std::string temp_dir = (argc > 1) ? argv[1] : ".";
  try {
    test_directed(temp_dir);
    test_randomized(temp_dir);
    test_fault_difftest(temp_dir);
    test_binary_difftest(temp_dir);
    std::cout << "test_difftest: PASS (all cases matched)\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "test_difftest: FAIL " << e.what() << "\n";
    return 1;
  }
}
