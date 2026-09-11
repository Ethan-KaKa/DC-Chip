#ifndef DC_CHIP_SIM_VERILATOR_REFERENCE_MODEL_H_
#define DC_CHIP_SIM_VERILATOR_REFERENCE_MODEL_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace dc_sim {

struct ReferenceStepResult {
  bool committed = false;
  std::uint32_t commit_pc = 0;
  std::uint32_t commit_inst = 0;
  std::uint32_t next_pc = 0;

  // Register writeback
  bool reg_write = false;
  std::uint8_t reg_waddr = 0;
  std::uint32_t reg_wdata = 0;

  // Memory access
  bool mem_access = false;
  bool mem_write = false;
  std::uint32_t mem_addr = 0;
  std::uint8_t mem_size = 0;  // 1 (byte) or 4 (word)
  std::uint32_t mem_wdata = 0;
  std::uint8_t mem_wstrb = 0;

  // Program exit (tohost)
  bool tohost_exit = false;
  std::uint32_t guest_exit_code = 0;

  // Fault
  bool faulted = false;
  std::uint8_t fault_cause = 0;
  std::uint32_t fault_pc = 0;
  bool fault_inst_valid = false;
  std::uint32_t fault_inst = 0;
};

class ReferenceModel {
 public:
  ReferenceModel();

  void reset(std::uint32_t reset_pc = 0);

  // Memory initialization / sync
  void load_irom(const std::vector<std::uint32_t> &words);
  void load_from_sim_memory();
  void write_dram_byte(std::uint32_t addr, std::uint8_t byte_val);
  std::uint8_t read_dram_byte(std::uint32_t addr) const;
  std::uint32_t read_dram_word(std::uint32_t addr) const;

  // State queries
  std::uint32_t pc() const { return pc_; }
  std::uint32_t reg(std::size_t index) const {
    return (index < 16) ? regs_[index] : 0U;
  }
  const std::array<std::uint32_t, 16> &regs() const { return regs_; }
  bool in_fault() const { return in_fault_; }
  std::uint8_t fault_cause() const { return fault_cause_; }
  std::uint32_t fault_pc() const { return fault_pc_; }

  // Step single instruction
  ReferenceStepResult step();

 private:
  std::uint32_t pc_ = 0;
  std::array<std::uint32_t, 16> regs_{};
  std::array<std::uint32_t, 256> irom_{};    // 1 KiB = 256 words
  std::array<std::uint8_t, 4096> dram_{};    // 4 KiB
  bool in_fault_ = false;
  std::uint8_t fault_cause_ = 0;
  std::uint32_t fault_pc_ = 0;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_REFERENCE_MODEL_H_
