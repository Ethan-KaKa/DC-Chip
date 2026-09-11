#include "reference_model.h"

#include "memory.h"
#include "simulation.h"

namespace dc_sim {
namespace {

constexpr std::uint32_t kIromBytes = static_cast<std::uint32_t>(kIromCapacityBytes);
constexpr std::uint32_t kDramBytes = static_cast<std::uint32_t>(kDramCapacityBytes);

constexpr std::uint32_t kOpcodeLoad   = 0b0000011;
constexpr std::uint32_t kOpcodeOpImm  = 0b0010011;
constexpr std::uint32_t kOpcodeStore  = 0b0100011;
constexpr std::uint32_t kOpcodeOp     = 0b0110011;
constexpr std::uint32_t kOpcodeLui    = 0b0110111;
constexpr std::uint32_t kOpcodeJalr   = 0b1100111;

std::int32_t sext12(std::uint32_t val12) {
  const std::uint32_t sign = (val12 >> 11U) & 1U;
  return static_cast<std::int32_t>(sign ? (val12 | 0xfffff000U) : (val12 & 0x00000fffU));
}

}  // namespace

ReferenceModel::ReferenceModel() {
  reset(0);
}

void ReferenceModel::reset(std::uint32_t reset_pc) {
  pc_ = reset_pc;
  regs_.fill(0);
  dram_.fill(0);
  in_fault_ = false;
  fault_cause_ = 0;
  fault_pc_ = 0;
}

void ReferenceModel::load_irom(const std::vector<std::uint32_t> &words) {
  irom_.fill(0);
  const std::size_t count = std::min(words.size(), irom_.size());
  for (std::size_t i = 0; i < count; ++i) {
    irom_[i] = words[i];
  }
}

void ReferenceModel::load_from_sim_memory() {
  for (std::size_t i = 0; i < irom_.size(); ++i) {
    irom_[i] = ::dc_sim::read_irom_word(i);
  }
  for (std::size_t i = 0; i < dram_.size() / 4; ++i) {
    const std::uint32_t word = ::dc_sim::read_dram_word(i);
    dram_[i * 4 + 0] = static_cast<std::uint8_t>(word & 0xffU);
    dram_[i * 4 + 1] = static_cast<std::uint8_t>((word >> 8U) & 0xffU);
    dram_[i * 4 + 2] = static_cast<std::uint8_t>((word >> 16U) & 0xffU);
    dram_[i * 4 + 3] = static_cast<std::uint8_t>((word >> 24U) & 0xffU);
  }
}


void ReferenceModel::write_dram_byte(std::uint32_t addr, std::uint8_t byte_val) {
  if (addr >= kDramBase && addr < kDramBase + kDramBytes) {
    dram_[addr - kDramBase] = byte_val;
  }
}

std::uint8_t ReferenceModel::read_dram_byte(std::uint32_t addr) const {
  if (addr >= kDramBase && addr < kDramBase + kDramBytes) {
    return dram_[addr - kDramBase];
  }
  return 0;
}

std::uint32_t ReferenceModel::read_dram_word(std::uint32_t addr) const {
  if (addr >= kDramBase && addr + 4 <= kDramBase + kDramBytes && (addr & 3U) == 0) {
    const std::size_t offset = addr - kDramBase;
    return static_cast<std::uint32_t>(dram_[offset]) |
           (static_cast<std::uint32_t>(dram_[offset + 1]) << 8U) |
           (static_cast<std::uint32_t>(dram_[offset + 2]) << 16U) |
           (static_cast<std::uint32_t>(dram_[offset + 3]) << 24U);
  }
  return 0;
}

ReferenceStepResult ReferenceModel::step() {
  ReferenceStepResult result;

  if (in_fault_) {
    result.faulted = true;
    result.fault_cause = fault_cause_;
    result.fault_pc = fault_pc_;
    return result;
  }

  // 1. Fetch check
  if ((pc_ & 3U) != 0 || pc_ < kIromBase || pc_ >= kIromBase + kIromBytes) {
    in_fault_ = true;
    fault_cause_ = static_cast<std::uint8_t>(FaultCause::instruction_access);
    fault_pc_ = pc_;
    result.faulted = true;
    result.fault_cause = fault_cause_;
    result.fault_pc = fault_pc_;
    result.fault_inst_valid = false;
    result.fault_inst = 0;
    return result;
  }

  const std::uint32_t word_idx = (pc_ - kIromBase) >> 2U;
  const std::uint32_t inst = irom_[word_idx];

  const std::uint32_t opcode = inst & 0x7fU;
  const std::uint32_t rd     = (inst >> 7U) & 0x1fU;
  const std::uint32_t funct3 = (inst >> 12U) & 0x7U;
  const std::uint32_t rs1    = (inst >> 15U) & 0x1fU;
  const std::uint32_t rs2    = (inst >> 20U) & 0x1fU;
  const std::uint32_t funct7 = (inst >> 25U) & 0x7fU;

  auto fail_illegal = [&]() {
    in_fault_ = true;
    fault_cause_ = static_cast<std::uint8_t>(FaultCause::illegal_instruction);
    fault_pc_ = pc_;
    result.faulted = true;
    result.fault_cause = fault_cause_;
    result.fault_pc = fault_pc_;
    result.fault_inst_valid = true;
    result.fault_inst = inst;
    return result;
  };

  // 2. Decode & validate RV32E operand ranges
  switch (opcode) {
    case kOpcodeOp: { // add
      if (rd >= 16 || rs1 >= 16 || rs2 >= 16 || funct3 != 0b000 || funct7 != 0b0000000) {
        return fail_illegal();
      }
      const std::uint32_t res = regs_[rs1] + regs_[rs2];
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = res;
      if (rd != 0) {
        regs_[rd] = res;
      }
      pc_ += 4U;
      return result;
    }

    case kOpcodeOpImm: { // addi
      if (rd >= 16 || rs1 >= 16 || funct3 != 0b000) {
        return fail_illegal();
      }
      const std::int32_t imm = sext12(inst >> 20U);
      const std::uint32_t res = regs_[rs1] + static_cast<std::uint32_t>(imm);
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = res;
      if (rd != 0) {
        regs_[rd] = res;
      }
      pc_ += 4U;
      return result;
    }

    case kOpcodeLui: { // lui
      if (rd >= 16) {
        return fail_illegal();
      }
      const std::uint32_t imm = inst & 0xfffff000U;
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = imm;
      if (rd != 0) {
        regs_[rd] = imm;
      }
      pc_ += 4U;
      return result;
    }

    case kOpcodeLoad: { // lw, lbu
      if (rd >= 16 || rs1 >= 16) {
        return fail_illegal();
      }
      const std::int32_t imm = sext12(inst >> 20U);
      const std::uint32_t addr = regs_[rs1] + static_cast<std::uint32_t>(imm);

      if (funct3 == 0b010) { // lw
        if ((addr & 3U) != 0) {
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::load_misaligned);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        if (addr < kDramBase || addr + 4U > kDramBase + kDramBytes) {
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::load_access);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        const std::uint32_t rdata = read_dram_word(addr);
        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.reg_write = (rd != 0);
        result.reg_waddr = static_cast<std::uint8_t>(rd);
        result.reg_wdata = rdata;
        result.mem_access = true;
        result.mem_write = false;
        result.mem_addr = addr;
        result.mem_size = 4;
        if (rd != 0) {
          regs_[rd] = rdata;
        }
        pc_ += 4U;
        return result;
      } else if (funct3 == 0b100) { // lbu
        if (addr < kDramBase || addr >= kDramBase + kDramBytes) {
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::load_access);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        const std::uint32_t rdata = read_dram_byte(addr);
        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.reg_write = (rd != 0);
        result.reg_waddr = static_cast<std::uint8_t>(rd);
        result.reg_wdata = rdata;
        result.mem_access = true;
        result.mem_write = false;
        result.mem_addr = addr;
        result.mem_size = 1;
        if (rd != 0) {
          regs_[rd] = rdata;
        }
        pc_ += 4U;
        return result;
      } else {
        return fail_illegal();
      }
    }

    case kOpcodeStore: { // sw, sb
      if (rs1 >= 16 || rs2 >= 16) {
        return fail_illegal();
      }
      const std::uint32_t raw_imm = ((inst >> 25U) << 5U) | ((inst >> 7U) & 0x1fU);
      const std::int32_t imm = sext12(raw_imm);
      const std::uint32_t addr = regs_[rs1] + static_cast<std::uint32_t>(imm);

      if (funct3 == 0b010) { // sw
        if ((addr & 3U) != 0) {
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::store_misaligned);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        if (addr == kTohostAddr) {
          result.committed = true;
          result.commit_pc = pc_;
          result.commit_inst = inst;
          result.next_pc = pc_ + 4U;
          result.mem_access = true;
          result.mem_write = true;
          result.mem_addr = addr;
          result.mem_size = 4;
          result.mem_wdata = regs_[rs2];
          result.mem_wstrb = 0xfU;
          result.tohost_exit = true;
          result.guest_exit_code = regs_[rs2];
          pc_ += 4U;
          return result;
        }
        if (addr < kDramBase || addr + 4U > kDramBase + kDramBytes) {
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::store_access);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        const std::size_t offset = addr - kDramBase;
        const std::uint32_t wval = regs_[rs2];
        dram_[offset + 0] = static_cast<std::uint8_t>(wval & 0xffU);
        dram_[offset + 1] = static_cast<std::uint8_t>((wval >> 8U) & 0xffU);
        dram_[offset + 2] = static_cast<std::uint8_t>((wval >> 16U) & 0xffU);
        dram_[offset + 3] = static_cast<std::uint8_t>((wval >> 24U) & 0xffU);

        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.mem_access = true;
        result.mem_write = true;
        result.mem_addr = addr;
        result.mem_size = 4;
        result.mem_wdata = wval;
        result.mem_wstrb = 0xfU;
        pc_ += 4U;
        return result;
      } else if (funct3 == 0b000) { // sb
        if (addr == kTohostAddr) { // Only sw allowed to tohost
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::store_access);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        if (addr < kDramBase || addr >= kDramBase + kDramBytes) {
          in_fault_ = true;
          fault_cause_ = static_cast<std::uint8_t>(FaultCause::store_access);
          fault_pc_ = pc_;
          result.faulted = true;
          result.fault_cause = fault_cause_;
          result.fault_pc = fault_pc_;
          result.fault_inst_valid = true;
          result.fault_inst = inst;
          return result;
        }
        const std::size_t offset = addr - kDramBase;
        const std::uint8_t bval = static_cast<std::uint8_t>(regs_[rs2] & 0xffU);
        dram_[offset] = bval;

        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.mem_access = true;
        result.mem_write = true;
        result.mem_addr = addr;
        result.mem_size = 1;
        result.mem_wdata = bval;
        result.mem_wstrb = static_cast<std::uint8_t>(1U << (addr & 3U));
        pc_ += 4U;
        return result;
      } else {
        return fail_illegal();
      }
    }

    case kOpcodeJalr: { // jalr
      if (rd >= 16 || rs1 >= 16 || funct3 != 0b000) {
        return fail_illegal();
      }
      const std::int32_t imm = sext12(inst >> 20U);
      const std::uint32_t old_rs1 = regs_[rs1];
      const std::uint32_t raw_target = old_rs1 + static_cast<std::uint32_t>(imm);
      const std::uint32_t target = raw_target & 0xfffffffeU;

      if ((target & 0x2U) != 0) {
        // bit 1 is 1: instruction address misaligned!
        in_fault_ = true;
        fault_cause_ = static_cast<std::uint8_t>(FaultCause::instruction_misaligned);
        fault_pc_ = pc_;
        result.faulted = true;
        result.fault_cause = fault_cause_;
        result.fault_pc = fault_pc_;
        result.fault_inst_valid = true;
        result.fault_inst = inst;
        return result;
      }

      const std::uint32_t link = pc_ + 4U;
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = target;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = link;
      if (rd != 0) {
        regs_[rd] = link;
      }
      pc_ = target;
      return result;
    }

    default:
      return fail_illegal();
  }
}

}  // namespace dc_sim
