#ifndef DC_CHIP_SIM_VERILATOR_DYNAMIC_REF_BACKEND_H_
#define DC_CHIP_SIM_VERILATOR_DYNAMIC_REF_BACKEND_H_

#include "ref_backend.h"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace dc_sim {

class DynamicRefBackend : public IRefBackend {
 public:
  explicit DynamicRefBackend(const std::string &so_path);
  ~DynamicRefBackend() override;

  void reset(std::uint32_t reset_pc = 0) override;
  void load_irom(const std::vector<std::uint32_t> &words) override;
  void load_from_sim_memory() override;

  std::uint32_t pc() const override { return pc_; }
  void set_pc(std::uint32_t val) override;
  std::uint32_t reg(std::size_t index) const override {
    return (index < 16) ? regs_[index] : 0U;
  }
  void set_reg(std::size_t index, std::uint32_t val) override;
  const std::array<std::uint32_t, 16> &regs() const override { return regs_; }

  bool in_fault() const override { return in_fault_; }
  std::uint8_t fault_cause() const override { return fault_cause_; }
  std::uint32_t fault_pc() const override { return fault_pc_; }

  void skip_instruction(std::uint32_t rd, std::uint32_t dut_rd_val,
                        std::uint32_t next_pc) override;
  RefStepResult step() override;
  const char *name() const override { return backend_name_.c_str(); }

 private:
  void *handle_ = nullptr;
  std::string backend_name_;

  void (*ref_init_)(int port) = nullptr;
  void (*ref_memcpy_)(std::uint32_t addr, void *buf, std::size_t n, bool direction) = nullptr;
  void (*ref_regcpy_)(std::uint32_t *pc, std::uint32_t *regs, bool direction) = nullptr;
  void (*ref_exec_)(std::uint64_t n) = nullptr;
  void (*ref_raise_intr_)(std::uint64_t NO) = nullptr;

  std::uint32_t pc_ = 0;
  std::array<std::uint32_t, 16> regs_{};
  bool in_fault_ = false;
  std::uint8_t fault_cause_ = 0;
  std::uint32_t fault_pc_ = 0;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_DYNAMIC_REF_BACKEND_H_
