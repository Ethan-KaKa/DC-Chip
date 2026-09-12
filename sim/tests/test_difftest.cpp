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

std::uint32_t enc_sub(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0100000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b000 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_sll(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b001 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_slt(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b010 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_sltu(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b011 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_xor(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b100 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_srl(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b101 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_sra(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0100000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b101 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_or(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b110 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_and(std::uint32_t rd, std::uint32_t rs1, std::uint32_t rs2) {
  return (0b0000000 << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b111 << 12U) | (rd << 7U) | 0b0110011;
}

std::uint32_t enc_slli(std::uint32_t rd, std::uint32_t rs1, std::uint32_t shamt) {
  return ((shamt & 0x1fU) << 20U) | (rs1 << 15U) | (0b001 << 12U) | (rd << 7U) | 0b0010011;
}

std::uint32_t enc_srli(std::uint32_t rd, std::uint32_t rs1, std::uint32_t shamt) {
  return ((shamt & 0x1fU) << 20U) | (rs1 << 15U) | (0b101 << 12U) | (rd << 7U) | 0b0010011;
}

std::uint32_t enc_srai(std::uint32_t rd, std::uint32_t rs1, std::uint32_t shamt) {
  return (0b0100000 << 25U) | ((shamt & 0x1fU) << 20U) | (rs1 << 15U) | (0b101 << 12U) | (rd << 7U) | 0b0010011;
}

std::uint32_t enc_auipc(std::uint32_t rd, std::uint32_t imm20) {
  return (imm20 << 12U) | (rd << 7U) | 0b0010111;
}

std::uint32_t enc_jal(std::uint32_t rd, std::int32_t imm21) {
  const std::uint32_t imm = static_cast<std::uint32_t>(imm21);
  return (((imm >> 20U) & 0x1U) << 31U) |
         (((imm >> 1U) & 0x3ffU) << 21U) |
         (((imm >> 11U) & 0x1U) << 20U) |
         (((imm >> 12U) & 0xffU) << 12U) |
         (rd << 7U) | 0b1101111;
}

std::uint32_t enc_branch(std::uint32_t funct3, std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm13) {
  const std::uint32_t imm = static_cast<std::uint32_t>(imm13);
  return (((imm >> 12U) & 0x1U) << 31U) |
         (((imm >> 5U) & 0x3fU) << 25U) |
         (rs2 << 20U) | (rs1 << 15U) |
         (funct3 << 12U) |
         (((imm >> 1U) & 0xfU) << 8U) |
         (((imm >> 11U) & 0x1U) << 7U) |
         0b1100011;
}

std::uint32_t enc_beq(std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm) { return enc_branch(0b000, rs1, rs2, imm); }
std::uint32_t enc_bne(std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm) { return enc_branch(0b001, rs1, rs2, imm); }
std::uint32_t enc_blt(std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm) { return enc_branch(0b100, rs1, rs2, imm); }
std::uint32_t enc_bge(std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm) { return enc_branch(0b101, rs1, rs2, imm); }
std::uint32_t enc_bltu(std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm) { return enc_branch(0b110, rs1, rs2, imm); }
std::uint32_t enc_bgeu(std::uint32_t rs1, std::uint32_t rs2, std::int32_t imm) { return enc_branch(0b111, rs1, rs2, imm); }

std::uint32_t enc_lh(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (0b001 << 12U) | (rd << 7U) | 0b0000011;
}

std::uint32_t enc_lhu(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (0b101 << 12U) | (rd << 7U) | 0b0000011;
}

std::uint32_t enc_lb(std::uint32_t rd, std::uint32_t rs1, std::int32_t imm) {
  return ((static_cast<std::uint32_t>(imm) & 0xfffU) << 20U) | (rs1 << 15U) | (0b000 << 12U) | (rd << 7U) | 0b0000011;
}

std::uint32_t enc_sh(std::uint32_t rs2, std::uint32_t rs1, std::int32_t imm) {
  const std::uint32_t uimm = static_cast<std::uint32_t>(imm) & 0xfffU;
  return ((uimm >> 5U) << 25U) | (rs2 << 20U) | (rs1 << 15U) | (0b001 << 12U) | ((uimm & 0x1fU) << 7U) | 0b0100011;
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

void test_directed_rv32e(const std::string &temp_dir) {
  const std::string hex_file = temp_dir + "/test_directed_rv32e.hex";
  std::vector<std::uint32_t> insts = {
      // 0x00: auipc x1, 0x10 => x1 = 0x00010000
      enc_auipc(1, 0x10),
      // 0x04: jal x2, 8 => target = 0x04 + 8 = 0x0c, x2 = 0x08
      enc_jal(2, 8),
      // 0x08: should be skipped
      enc_addi(3, 0, 999),
      // 0x0c: addi x3, x0, 10
      enc_addi(3, 0, 10),
      // 0x10: addi x4, x0, 10
      enc_addi(4, 0, 10),
      // 0x14: beq x3, x4, 8 => target = 0x14 + 8 = 0x1c
      enc_beq(3, 4, 8),
      // 0x18: should be skipped
      enc_addi(5, 0, 888),
      // 0x1c: sub x5, x3, x4 => 0
      enc_sub(5, 3, 4),
      // 0x20: addi x6, x0, -1
      enc_addi(6, 0, -1),
      // 0x24: sltu x7, x5, x6 => 1 (0 < 0xffffffff unsigned)
      enc_sltu(7, 5, 6),
      // 0x28: slt x8, x6, x5 => 1 (-1 < 0 signed)
      enc_slt(8, 6, 5),
      // 0x2c: xor x9, x7, x8 => 0
      enc_xor(9, 7, 8),
      // 0x30: slli x10, x7, 4 => 16
      enc_slli(10, 7, 4),
      // 0x34: lui x11, 0x20000 => 0x20000000 (DRAM)
      enc_lui(11, 0x20000),
      // 0x38: sh x10, 2(x11) => DRAM[2..3] = 16
      enc_sh(10, 11, 2),
      // 0x3c: lh x12, 2(x11) => 16
      enc_lh(12, 11, 2),
      // 0x40: lhu x13, 2(x11) => 16
      enc_lhu(13, 11, 2),
      // 0x44: exit tohost
      enc_lui(14, 0xfffff),
      enc_addi(14, 14, -16),
      enc_sw(0, 14, 0),
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
        enc_lw(2, 1, 1), // 0x20000001 misaligned word
    };
    run_test_vector(hex_file, insts, 2);
  }

  // Test misaligned halfword load difftest
  {
    const std::string hex_file = temp_dir + "/test_fault_lh_misalign.hex";
    std::vector<std::uint32_t> insts = {
        enc_lui(1, 0x20000),
        enc_lh(2, 1, 1), // 0x20000001 misaligned halfword
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

void test_sw_difftest() {
  const std::vector<std::string> sw_cases = {
      "trm_smoke", "trm_exit_code", "calc_add", "dram_access", "heap_smoke", "jump_table",
      "cpu_dummy", "cpu_add", "cpu_sub_longlong", "cpu_bit", "cpu_bubble_sort", "cpu_select_sort",
      "cpu_fib", "cpu_recursion", "cpu_string", "cpu_leap_year", "cpu_if_else", "cpu_load_store",
      "led_marquee"
  };
  for (const auto &name : sw_cases) {
    const std::string inst_bin = "build/sw/tests/" + name + "/" + name + ".inst.bin";
    const std::string data_bin = "build/sw/tests/" + name + "/" + name + ".data.bin";

    std::ifstream check_file(inst_bin);
    if (!check_file.is_open()) {
      continue;
    }
    check_file.close();

    dc_sim::reset_memory();
    std::string error;
    require(dc_sim::load_binary_image(inst_bin, dc_sim::MemoryRegion::kIrom, &error), error);

    std::ifstream data_in(data_bin, std::ios::binary | std::ios::ate);
    if (data_in.is_open()) {
      if (data_in.tellg() > 0) {
        require(dc_sim::load_binary_image(data_bin, dc_sim::MemoryRegion::kDram, &error), error);
      }
    }

    dc_sim::Simulation dut;
    dut.reset();

    dc_sim::ReferenceModel ref;
    ref.load_from_sim_memory();

    dc_sim::Difftest difftest(dut, ref);
    dc_sim::DifftestMismatch mismatch;
    const std::uint64_t max_commits = (name == "led_marquee") ? 5000U : 50000U;
    const std::uint64_t max_cycles = (name == "led_marquee") ? 10000U : 100000U;
    bool ok = difftest.run_difftest(max_commits, max_cycles, &mismatch);
    require(ok, "sw difftest failed on " + name + ": " + mismatch.message);
  }
}

}  // namespace

int main(int argc, char **argv) {
  const std::string temp_dir = (argc > 1) ? argv[1] : ".";
  try {
    test_directed(temp_dir);
    test_directed_rv32e(temp_dir);
    test_randomized(temp_dir);
    test_fault_difftest(temp_dir);
    test_binary_difftest(temp_dir);
    test_sw_difftest();
    std::cout << "test_difftest: PASS (all cases matched)\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "test_difftest: FAIL " << e.what() << "\n";
    return 1;
  }
}
