#ifndef DC_CHIP_SIM_VERILATOR_REFERENCE_MODEL_H_
#define DC_CHIP_SIM_VERILATOR_REFERENCE_MODEL_H_

#include "ref_backend.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace dc_sim {

using ReferenceStepResult = RefStepResult;

class ReferenceModel : public IRefBackend {
 public:
  ReferenceModel();
  ~ReferenceModel() override = default;

  void reset(std::uint32_t reset_pc = 0) override;

  // Memory initialization / sync
  void load_irom(const std::vector<std::uint32_t> &words) override;
  void load_from_sim_memory() override;
  void write_dram_byte(std::uint32_t addr, std::uint8_t byte_val);
  void write_dram_half(std::uint32_t addr, std::uint16_t half_val);
  void write_dram_word(std::uint32_t addr, std::uint32_t word_val);
  std::uint8_t read_dram_byte(std::uint32_t addr) const;
  std::uint16_t read_dram_half(std::uint32_t addr) const;
  std::uint32_t read_dram_word(std::uint32_t addr) const;

  // State queries and modification
  std::uint32_t pc() const override { return pc_; }
  void set_pc(std::uint32_t val) override { pc_ = val; }
  std::uint32_t reg(std::size_t index) const override {
    return (index < 16) ? regs_[index] : 0U;
  }
  void set_reg(std::size_t index, std::uint32_t val) override {
    if (index > 0 && index < 16) {
      regs_[index] = val;
    }
  }
  const std::array<std::uint32_t, 16> &regs() const override { return regs_; }
  bool in_fault() const override { return in_fault_; }
  std::uint8_t fault_cause() const override { return fault_cause_; }
  std::uint32_t fault_pc() const override { return fault_pc_; }
  std::uint16_t led() const { return led_reg_; }

  // Skip instruction with DUT synchronization
  void skip_instruction(std::uint32_t rd, std::uint32_t dut_rd_val,
                        std::uint32_t next_pc) override {
    if (rd > 0 && rd < 16) {
      regs_[rd] = dut_rd_val;
    }
    pc_ = next_pc;
  }

  // Step single instruction
  ReferenceStepResult step() override;
  const char *name() const override { return "internal"; }

 private:
  std::uint32_t pc_ = 0;
  std::array<std::uint32_t, 16> regs_{};
  std::array<std::uint32_t, 16384> irom_{};    // 64 KiB = 16384 words
  std::array<std::uint8_t, 65536> dram_{};     // 64 KiB
  std::uint16_t led_reg_ = 0;

  bool in_fault_ = false;
  std::uint8_t fault_cause_ = 0;
  std::uint32_t fault_pc_ = 0;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_REFERENCE_MODEL_H_
