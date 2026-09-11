#include "reference_model.h"

#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error("test_reference FAIL: " + message);
  }
}

// Helper encoders
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

void test_arithmetic() {
  dc_sim::ReferenceModel model;
  model.load_irom({
      enc_addi(1, 0, 10),      // addi x1, x0, 10
      enc_addi(2, 0, -3),      // addi x2, x0, -3
      enc_add(3, 1, 2),        // add  x3, x1, x2 => 7
      enc_lui(4, 0x12345),     // lui  x4, 0x12345 => 0x12345000
      enc_addi(0, 1, 5),       // addi x0, x1, 5 (x0 must remain 0)
  });

  auto r1 = model.step();
  require(r1.committed && model.reg(1) == 10, "addi positive failed");

  auto r2 = model.step();
  require(r2.committed && model.reg(2) == 0xfffffffdu, "addi negative failed");

  auto r3 = model.step();
  require(r3.committed && model.reg(3) == 7, "add failed");

  auto r4 = model.step();
  require(r4.committed && model.reg(4) == 0x12345000u, "lui failed");

  auto r5 = model.step();
  require(r5.committed && model.reg(0) == 0, "x0 write discard failed");
}

void test_memory_access() {
  dc_sim::ReferenceModel model;
  model.load_irom({
      enc_lui(1, 1),            // lui x1, 1 => 0x00001000 (DRAM base)
      enc_addi(2, 0, 0x5a),     // addi x2, x0, 0x5a
      enc_sb(2, 1, 3),          // sb x2, 3(x1) => DRAM[3] = 0x5a
      enc_lbu(3, 1, 3),         // lbu x3, 3(x1) => 0x5a
      enc_addi(4, 0, 1234),     // addi x4, x0, 1234
      enc_sw(4, 1, 4),          // sw x4, 4(x1) => DRAM[4..7] = 1234
      enc_lw(5, 1, 4),          // lw x5, 4(x1) => 1234
  });

  model.step(); // lui
  model.step(); // addi x2
  auto r_sb = model.step();
  require(r_sb.committed && r_sb.mem_access && r_sb.mem_write && r_sb.mem_addr == 0x1003, "sb failed");
  require(model.read_dram_byte(0x1003) == 0x5a, "sb memory byte mismatch");

  auto r_lbu = model.step();
  require(r_lbu.committed && model.reg(3) == 0x5a, "lbu failed");

  model.step(); // addi x4
  auto r_sw = model.step();
  require(r_sw.committed && r_sw.mem_access && r_sw.mem_write && r_sw.mem_addr == 0x1004, "sw failed");
  require(model.read_dram_word(0x1004) == 1234, "sw memory word mismatch");

  auto r_lw = model.step();
  require(r_lw.committed && model.reg(5) == 1234, "lw failed");
}

void test_control_and_tohost() {
  dc_sim::ReferenceModel model;
  model.load_irom({
      enc_addi(1, 0, 16),       // addi x1, x0, 16
      enc_jalr(2, 1, 0),        // jalr x2, 0(x1) => pc=16, x2=8
      enc_addi(3, 0, 99),       // (skipped)
      enc_addi(4, 0, 99),       // (skipped)
      enc_addi(5, 0, -16),      // pc=16: addi x5, x0, -16 => 0xfffffff0 (tohost)
      enc_addi(6, 0, 42),       // addi x6, x0, 42
      enc_sw(6, 5, 0),          // sw x6, 0(x5) => tohost exit code 42
  });

  model.step(); // addi x1
  auto r_jalr = model.step();
  require(r_jalr.committed && r_jalr.next_pc == 16 && model.reg(2) == 8, "jalr failed");
  require(model.pc() == 16, "pc not updated to target");

  model.step(); // addi x5
  model.step(); // addi x6
  auto r_exit = model.step();
  require(r_exit.committed && r_exit.tohost_exit && r_exit.guest_exit_code == 42, "tohost exit failed");
}

void test_faults() {
  // 1. Illegal instruction: upper register x16
  {
    dc_sim::ReferenceModel model;
    model.load_irom({
        enc_addi(16, 0, 1), // x16 is forbidden
    });
    auto r = model.step();
    require(r.faulted && r.fault_cause == 1 && r.fault_inst_valid, "illegal register fault failed");
  }

  // 2. Misaligned load
  {
    dc_sim::ReferenceModel model;
    model.load_irom({
        enc_lui(1, 1),
        enc_lw(2, 1, 1), // addr = 0x1001 (misaligned)
    });
    model.step();
    auto r = model.step();
    require(r.faulted && r.fault_cause == 4, "load misaligned fault failed");
  }

  // 3. Misaligned store
  {
    dc_sim::ReferenceModel model;
    model.load_irom({
        enc_lui(1, 1),
        enc_sw(0, 1, 2), // addr = 0x1002 (misaligned)
    });
    model.step();
    auto r = model.step();
    require(r.faulted && r.fault_cause == 6, "store misaligned fault failed");
  }

  // 4. Misaligned jalr
  {
    dc_sim::ReferenceModel model;
    model.load_irom({
        enc_addi(1, 0, 2),
        enc_jalr(0, 1, 0), // target = 2 (bit 1 is 1)
    });
    model.step();
    auto r = model.step();
    require(r.faulted && r.fault_cause == 3, "jalr misaligned fault failed");
  }

  // 5. Instruction access fault (out of bounds)
  {
    dc_sim::ReferenceModel model;
    model.reset(0x400); // 1024 is out of 1 KiB IROM
    auto r = model.step();
    require(r.faulted && r.fault_cause == 2 && !r.fault_inst_valid, "instruction access fault failed");
  }

  // 6. Load access fault (out of DRAM)
  {
    dc_sim::ReferenceModel model;
    model.load_irom({
        enc_addi(1, 0, 0),
        enc_lw(2, 1, 0), // addr = 0 (IROM, not DRAM)
    });
    model.step();
    auto r = model.step();
    require(r.faulted && r.fault_cause == 5, "load access fault failed");
  }

  // 7. Store access fault (out of DRAM)
  {
    dc_sim::ReferenceModel model;
    model.load_irom({
        enc_addi(1, 0, 0),
        enc_sw(0, 1, 0), // addr = 0
    });
    model.step();
    auto r = model.step();
    require(r.faulted && r.fault_cause == 7, "store access fault failed");
  }
}

}  // namespace

int main() {
  try {
    test_arithmetic();
    test_memory_access();
    test_control_and_tohost();
    test_faults();
    std::cout << "test_reference: PASS (all tests passed)\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "test_reference: FAIL " << e.what() << "\n";
    return 1;
  }
}
