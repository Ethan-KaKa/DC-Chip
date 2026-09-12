#include "reference_model.h"

#include "memory.h"
#include "simulation.h"

namespace dc_sim {
namespace {

constexpr std::uint32_t kIromBytes = static_cast<std::uint32_t>(kIromCapacityBytes);
constexpr std::uint32_t kDramBytes = static_cast<std::uint32_t>(kDramCapacityBytes);

constexpr std::uint32_t kOpcodeLoad    = 0b0000011;
constexpr std::uint32_t kOpcodeMiscMem = 0b0001111; // fence
constexpr std::uint32_t kOpcodeOpImm   = 0b0010011;
constexpr std::uint32_t kOpcodeAuipc   = 0b0010111;
constexpr std::uint32_t kOpcodeStore   = 0b0100011;
constexpr std::uint32_t kOpcodeOp      = 0b0110011;
constexpr std::uint32_t kOpcodeLui     = 0b0110111;
constexpr std::uint32_t kOpcodeBranch  = 0b1100011;
constexpr std::uint32_t kOpcodeJalr    = 0b1100111;
constexpr std::uint32_t kOpcodeJal     = 0b1101111;

std::int32_t sext12(std::uint32_t val12) {
  const std::uint32_t sign = (val12 >> 11U) & 1U;
  return static_cast<std::int32_t>(sign ? (val12 | 0xfffff000U) : (val12 & 0x00000fffU));
}

std::int32_t sext_b(std::uint32_t inst) {
  const std::uint32_t imm = (((inst >> 31U) & 1U) << 12U) |
                            (((inst >> 7U) & 1U) << 11U) |
                            (((inst >> 25U) & 0x3fU) << 5U) |
                            (((inst >> 8U) & 0x0fU) << 1U);
  return static_cast<std::int32_t>((imm ^ 0x1000U) - 0x1000U);
}

std::int32_t sext_j(std::uint32_t inst) {
  const std::uint32_t imm = (((inst >> 31U) & 1U) << 20U) |
                            (((inst >> 12U) & 0xffU) << 12U) |
                            (((inst >> 20U) & 1U) << 11U) |
                            (((inst >> 21U) & 0x3ffU) << 1U);
  return static_cast<std::int32_t>((imm ^ 0x100000U) - 0x100000U);
}

}  // namespace

ReferenceModel::ReferenceModel() {
  reset(0);
}

void ReferenceModel::reset(std::uint32_t reset_pc) {
  pc_ = reset_pc;
  regs_.fill(0);
  dram_.fill(0);
  led_reg_ = 0;
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

void ReferenceModel::write_dram_half(std::uint32_t addr, std::uint16_t half_val) {
  if (addr >= kDramBase && addr + 2 <= kDramBase + kDramBytes && (addr & 1U) == 0) {
    const std::size_t offset = addr - kDramBase;
    dram_[offset + 0] = static_cast<std::uint8_t>(half_val & 0xffU);
    dram_[offset + 1] = static_cast<std::uint8_t>((half_val >> 8U) & 0xffU);
  }
}

void ReferenceModel::write_dram_word(std::uint32_t addr, std::uint32_t word_val) {
  if (addr >= kDramBase && addr + 4 <= kDramBase + kDramBytes && (addr & 3U) == 0) {
    const std::size_t offset = addr - kDramBase;
    dram_[offset + 0] = static_cast<std::uint8_t>(word_val & 0xffU);
    dram_[offset + 1] = static_cast<std::uint8_t>((word_val >> 8U) & 0xffU);
    dram_[offset + 2] = static_cast<std::uint8_t>((word_val >> 16U) & 0xffU);
    dram_[offset + 3] = static_cast<std::uint8_t>((word_val >> 24U) & 0xffU);
  }
}

std::uint8_t ReferenceModel::read_dram_byte(std::uint32_t addr) const {
  if (addr >= kDramBase && addr < kDramBase + kDramBytes) {
    return dram_[addr - kDramBase];
  }
  return 0;
}

std::uint16_t ReferenceModel::read_dram_half(std::uint32_t addr) const {
  if (addr >= kDramBase && addr + 2 <= kDramBase + kDramBytes && (addr & 1U) == 0) {
    const std::size_t offset = addr - kDramBase;
    return static_cast<std::uint16_t>(dram_[offset]) |
           static_cast<std::uint16_t>(static_cast<std::uint16_t>(dram_[offset + 1]) << 8U);
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
    return result;
  }

  const std::size_t inst_index = (pc_ - kIromBase) >> 2U;
  const std::uint32_t inst = irom_[inst_index];

  const std::uint32_t opcode = inst & 0x7fU;
  const std::uint32_t rd     = (inst >> 7U) & 0x1fU;
  const std::uint32_t funct3 = (inst >> 12U) & 0x07U;
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

  auto fail_misaligned_inst = [&]() {
    in_fault_ = true;
    fault_cause_ = static_cast<std::uint8_t>(FaultCause::instruction_misaligned);
    fault_pc_ = pc_;
    result.faulted = true;
    result.fault_cause = fault_cause_;
    result.fault_pc = fault_pc_;
    result.fault_inst_valid = true;
    result.fault_inst = inst;
    return result;
  };

  switch (opcode) {
    case kOpcodeLui: {
      if (rd >= 16) return fail_illegal();
      const std::uint32_t imm = inst & 0xfffff000U;
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = imm;
      if (rd != 0) regs_[rd] = imm;
      pc_ += 4U;
      return result;
    }

    case kOpcodeAuipc: {
      if (rd >= 16) return fail_illegal();
      const std::uint32_t imm = inst & 0xfffff000U;
      const std::uint32_t res = pc_ + imm;
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = res;
      if (rd != 0) regs_[rd] = res;
      pc_ += 4U;
      return result;
    }

    case kOpcodeJal: {
      if (rd >= 16) return fail_illegal();
      const std::int32_t imm = sext_j(inst);
      const std::uint32_t target = pc_ + static_cast<std::uint32_t>(imm);
      if ((target & 3U) != 0) return fail_misaligned_inst();
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = target;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = pc_ + 4U;
      if (rd != 0) regs_[rd] = pc_ + 4U;
      pc_ = target;
      return result;
    }

    case kOpcodeJalr: {
      if (rd >= 16 || rs1 >= 16 || funct3 != 0) return fail_illegal();
      const std::int32_t imm = sext12(inst >> 20U);
      const std::uint32_t target = (regs_[rs1] + static_cast<std::uint32_t>(imm)) & ~1U;
      if ((target & 3U) != 0) return fail_misaligned_inst();
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = target;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = pc_ + 4U;
      if (rd != 0) regs_[rd] = pc_ + 4U;
      pc_ = target;
      return result;
    }

    case kOpcodeBranch: {
      if (rs1 >= 16 || rs2 >= 16) return fail_illegal();
      bool take_branch = false;
      switch (funct3) {
        case 0: take_branch = (regs_[rs1] == regs_[rs2]); break; // beq
        case 1: take_branch = (regs_[rs1] != regs_[rs2]); break; // bne
        case 4: take_branch = (static_cast<std::int32_t>(regs_[rs1]) < static_cast<std::int32_t>(regs_[rs2])); break; // blt
        case 5: take_branch = (static_cast<std::int32_t>(regs_[rs1]) >= static_cast<std::int32_t>(regs_[rs2])); break; // bge
        case 6: take_branch = (regs_[rs1] < regs_[rs2]); break; // bltu
        case 7: take_branch = (regs_[rs1] >= regs_[rs2]); break; // bgeu
        default: return fail_illegal();
      }
      const std::int32_t imm = sext_b(inst);
      const std::uint32_t target = pc_ + static_cast<std::uint32_t>(imm);
      if (take_branch && ((target & 3U) != 0)) return fail_misaligned_inst();
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = take_branch ? target : pc_ + 4U;
      pc_ = result.next_pc;
      return result;
    }

    case kOpcodeOpImm: {
      if (rd >= 16 || rs1 >= 16) return fail_illegal();
      const std::int32_t imm = sext12(inst >> 20U);
      const std::uint32_t shamt = (inst >> 20U) & 0x1fU;
      std::uint32_t res = 0;

      switch (funct3) {
        case 0: res = regs_[rs1] + static_cast<std::uint32_t>(imm); break; // addi
        case 2: res = (static_cast<std::int32_t>(regs_[rs1]) < imm) ? 1U : 0U; break; // slti
        case 3: res = (regs_[rs1] < static_cast<std::uint32_t>(imm)) ? 1U : 0U; break; // sltiu
        case 4: res = regs_[rs1] ^ static_cast<std::uint32_t>(imm); break; // xori
        case 6: res = regs_[rs1] | static_cast<std::uint32_t>(imm); break; // ori
        case 7: res = regs_[rs1] & static_cast<std::uint32_t>(imm); break; // andi
        case 1: // slli
          if (funct7 != 0) return fail_illegal();
          res = regs_[rs1] << shamt;
          break;
        case 5: // srli / srai
          if (funct7 == 0) {
            res = regs_[rs1] >> shamt;
          } else if (funct7 == 0x20) {
            res = static_cast<std::uint32_t>(static_cast<std::int32_t>(regs_[rs1]) >> shamt);
          } else {
            return fail_illegal();
          }
          break;
        default: return fail_illegal();
      }

      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = res;
      if (rd != 0) regs_[rd] = res;
      pc_ += 4U;
      return result;
    }

    case kOpcodeOp: {
      if (rd >= 16 || rs1 >= 16 || rs2 >= 16) return fail_illegal();
      std::uint32_t res = 0;
      const std::uint32_t shamt = regs_[rs2] & 0x1fU;

      switch (funct3) {
        case 0:
          if (funct7 == 0) res = regs_[rs1] + regs_[rs2];
          else if (funct7 == 0x20) res = regs_[rs1] - regs_[rs2];
          else return fail_illegal();
          break;
        case 1:
          if (funct7 != 0) return fail_illegal();
          res = regs_[rs1] << shamt;
          break;
        case 2:
          if (funct7 != 0) return fail_illegal();
          res = (static_cast<std::int32_t>(regs_[rs1]) < static_cast<std::int32_t>(regs_[rs2])) ? 1U : 0U;
          break;
        case 3:
          if (funct7 != 0) return fail_illegal();
          res = (regs_[rs1] < regs_[rs2]) ? 1U : 0U;
          break;
        case 4:
          if (funct7 != 0) return fail_illegal();
          res = regs_[rs1] ^ regs_[rs2];
          break;
        case 5:
          if (funct7 == 0) res = regs_[rs1] >> shamt;
          else if (funct7 == 0x20) res = static_cast<std::uint32_t>(static_cast<std::int32_t>(regs_[rs1]) >> shamt);
          else return fail_illegal();
          break;
        case 6:
          if (funct7 != 0) return fail_illegal();
          res = regs_[rs1] | regs_[rs2];
          break;
        case 7:
          if (funct7 != 0) return fail_illegal();
          res = regs_[rs1] & regs_[rs2];
          break;
        default: return fail_illegal();
      }

      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      result.reg_write = (rd != 0);
      result.reg_waddr = static_cast<std::uint8_t>(rd);
      result.reg_wdata = res;
      if (rd != 0) regs_[rd] = res;
      pc_ += 4U;
      return result;
    }

    case kOpcodeLoad: {
      if (rd >= 16 || rs1 >= 16) return fail_illegal();
      const std::int32_t imm = sext12(inst >> 20U);
      const std::uint32_t addr = regs_[rs1] + static_cast<std::uint32_t>(imm);

      auto fail_load_misaligned = [&]() {
        in_fault_ = true;
        fault_cause_ = static_cast<std::uint8_t>(FaultCause::load_misaligned);
        fault_pc_ = pc_;
        result.faulted = true;
        result.fault_cause = fault_cause_;
        result.fault_pc = fault_pc_;
        result.fault_inst_valid = true;
        result.fault_inst = inst;
        return result;
      };

      auto fail_load_access = [&]() {
        in_fault_ = true;
        fault_cause_ = static_cast<std::uint8_t>(FaultCause::load_access);
        fault_pc_ = pc_;
        result.faulted = true;
        result.fault_cause = fault_cause_;
        result.fault_pc = fault_pc_;
        result.fault_inst_valid = true;
        result.fault_inst = inst;
        return result;
      };

      std::uint32_t rdata = 0;
      std::uint8_t access_size = 0;

      const bool is_dram = (addr >= kDramBase && addr < kDramBase + kDramBytes);
      const bool is_mmio = (addr >= kMmioBase && addr < kMmioBase + kMmioCapacityBytes);

      switch (funct3) {
        case 0: { // lb
          if (is_dram) {
            const std::uint8_t byte_val = read_dram_byte(addr);
            rdata = static_cast<std::uint32_t>(static_cast<std::int32_t>(static_cast<std::int8_t>(byte_val)));
          } else if (is_mmio && (addr == kMmioLedAddr || addr == kMmioLedAddr + 1U)) {
            const std::uint8_t byte_val = static_cast<std::uint8_t>((led_reg_ >> ((addr & 1U) * 8U)) & 0xffU);
            rdata = static_cast<std::uint32_t>(static_cast<std::int32_t>(static_cast<std::int8_t>(byte_val)));
          } else {
            return fail_load_access();
          }
          access_size = 1;
          break;
        }
        case 1: { // lh
          if ((addr & 1U) != 0) return fail_load_misaligned();
          if (is_dram && addr + 2U <= kDramBase + kDramBytes) {
            const std::uint16_t half_val = read_dram_half(addr);
            rdata = static_cast<std::uint32_t>(static_cast<std::int32_t>(static_cast<std::int16_t>(half_val)));
          } else if (is_mmio && addr == kMmioLedAddr) {
            rdata = static_cast<std::uint32_t>(static_cast<std::int32_t>(static_cast<std::int16_t>(led_reg_)));
          } else {
            return fail_load_access();
          }
          access_size = 2;
          break;
        }
        case 2: { // lw
          if ((addr & 3U) != 0) return fail_load_misaligned();
          if (is_dram && addr + 4U <= kDramBase + kDramBytes) {
            rdata = read_dram_word(addr);
          } else if (is_mmio && addr == kMmioLedAddr) {
            rdata = static_cast<std::uint32_t>(led_reg_);
          } else if (is_mmio && addr == kMmioUartStatusAddr) {
            rdata = 0x00000002U; // tx_ready = 1, rx_ready = 0
          } else if (is_mmio && (addr == kMmioUartRxAddr || addr == kMmioUartTxAddr)) {
            rdata = 0;
          } else {
            return fail_load_access();
          }
          access_size = 4;
          break;
        }
        case 4: { // lbu
          if (is_dram) {
            rdata = static_cast<std::uint32_t>(read_dram_byte(addr));
          } else if (is_mmio && (addr == kMmioLedAddr || addr == kMmioLedAddr + 1U)) {
            rdata = static_cast<std::uint32_t>((led_reg_ >> ((addr & 1U) * 8U)) & 0xffU);
          } else if (is_mmio && addr == kMmioUartStatusAddr) {
            rdata = 0x02U;
          } else if (is_mmio && (addr == kMmioUartRxAddr || addr == kMmioUartTxAddr)) {
            rdata = 0;
          } else {
            return fail_load_access();
          }
          access_size = 1;
          break;
        }
        case 5: { // lhu
          if ((addr & 1U) != 0) return fail_load_misaligned();
          if (is_dram && addr + 2U <= kDramBase + kDramBytes) {
            rdata = static_cast<std::uint32_t>(read_dram_half(addr));
          } else if (is_mmio && addr == kMmioLedAddr) {
            rdata = static_cast<std::uint32_t>(led_reg_);
          } else {
            return fail_load_access();
          }
          access_size = 2;
          break;
        }
        default: return fail_illegal();
      }

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
      result.mem_size = access_size;
      if (rd != 0) regs_[rd] = rdata;
      pc_ += 4U;
      return result;
    }

    case kOpcodeStore: {
      if (rs1 >= 16 || rs2 >= 16) return fail_illegal();
      const std::uint32_t imm_s_bits = ((inst >> 20U) & 0xfe0U) | ((inst >> 7U) & 0x1fU);
      const std::int32_t imm = sext12(imm_s_bits);
      const std::uint32_t addr = regs_[rs1] + static_cast<std::uint32_t>(imm);

      auto fail_store_misaligned = [&]() {
        in_fault_ = true;
        fault_cause_ = static_cast<std::uint8_t>(FaultCause::store_misaligned);
        fault_pc_ = pc_;
        result.faulted = true;
        result.fault_cause = fault_cause_;
        result.fault_pc = fault_pc_;
        result.fault_inst_valid = true;
        result.fault_inst = inst;
        return result;
      };

      auto fail_store_access = [&]() {
        in_fault_ = true;
        fault_cause_ = static_cast<std::uint8_t>(FaultCause::store_access);
        fault_pc_ = pc_;
        result.faulted = true;
        result.fault_cause = fault_cause_;
        result.fault_pc = fault_pc_;
        result.fault_inst_valid = true;
        result.fault_inst = inst;
        return result;
      };

      const bool is_dram = (addr >= kDramBase && addr < kDramBase + kDramBytes);
      const bool is_mmio = (addr >= kMmioBase && addr < kMmioBase + kMmioCapacityBytes);

      if (funct3 == 2) { // sw
        if (addr == kTohostAddr) {
          result.committed = true;
          result.commit_pc = pc_;
          result.commit_inst = inst;
          result.next_pc = pc_ + 4U;
          result.tohost_exit = true;
          result.guest_exit_code = regs_[rs2];
          pc_ += 4U;
          return result;
        }
        if ((addr & 3U) != 0) return fail_store_misaligned();
        if (is_dram && addr + 4U <= kDramBase + kDramBytes) {
          write_dram_word(addr, regs_[rs2]);
        } else if (is_mmio && addr == kMmioLedAddr) {
          led_reg_ = static_cast<std::uint16_t>(regs_[rs2] & 0xffffU);
        } else if (is_mmio && addr == kMmioUartTxAddr) {
          // Accepted MMIO UART TX write
        } else {
          return fail_store_access();
        }

        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.mem_access = true;
        result.mem_write = true;
        result.mem_addr = addr;
        result.mem_size = 4;
        result.mem_wdata = regs_[rs2];
        result.mem_wstrb = 0x0fU;
        pc_ += 4U;
        return result;
      } else if (funct3 == 1) { // sh
        if ((addr & 1U) != 0) return fail_store_misaligned();
        if (is_dram && addr + 2U <= kDramBase + kDramBytes) {
          write_dram_half(addr, static_cast<std::uint16_t>(regs_[rs2] & 0xffffU));
        } else if (is_mmio && addr == kMmioLedAddr) {
          led_reg_ = static_cast<std::uint16_t>(regs_[rs2] & 0xffffU);
        } else {
          return fail_store_access();
        }

        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.mem_access = true;
        result.mem_write = true;
        result.mem_addr = addr;
        result.mem_size = 2;
        result.mem_wdata = (addr & 2U) ? (regs_[rs2] << 16U) : (regs_[rs2] & 0xffffU);
        result.mem_wstrb = (addr & 2U) ? 0x0cU : 0x03U;
        pc_ += 4U;
        return result;
      } else if (funct3 == 0) { // sb
        if (is_dram) {
          write_dram_byte(addr, static_cast<std::uint8_t>(regs_[rs2] & 0xffU));
        } else if (is_mmio && addr == kMmioLedAddr) {
          led_reg_ = (led_reg_ & 0xff00U) | static_cast<std::uint16_t>(regs_[rs2] & 0xffU);
        } else if (is_mmio && addr == kMmioLedAddr + 1U) {
          led_reg_ = (led_reg_ & 0x00ffU) | static_cast<std::uint16_t>((regs_[rs2] & 0xffU) << 8U);
        } else if (is_mmio && addr == kMmioUartTxAddr) {
          // Accepted MMIO UART TX byte write
        } else {
          return fail_store_access();
        }

        const std::uint8_t lane = static_cast<std::uint8_t>(addr & 3U);
        result.committed = true;
        result.commit_pc = pc_;
        result.commit_inst = inst;
        result.next_pc = pc_ + 4U;
        result.mem_access = true;
        result.mem_write = true;
        result.mem_addr = addr;
        result.mem_size = 1;
        result.mem_wdata = (regs_[rs2] & 0xffU) << (lane * 8U);
        result.mem_wstrb = static_cast<std::uint8_t>(1U << lane);
        pc_ += 4U;
        return result;
      } else {
        return fail_illegal();
      }
    }

    case kOpcodeMiscMem: { // fence
      if (funct3 != 0) return fail_illegal();
      result.committed = true;
      result.commit_pc = pc_;
      result.commit_inst = inst;
      result.next_pc = pc_ + 4U;
      pc_ += 4U;
      return result;
    }

    default:
      return fail_illegal();
  }
}

}  // namespace dc_sim
