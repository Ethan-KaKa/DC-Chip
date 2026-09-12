#ifndef DC_CHIP_SIM_VERILATOR_REF_BACKEND_H_
#define DC_CHIP_SIM_VERILATOR_REF_BACKEND_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace dc_sim {

struct RefStepResult {
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
  std::uint8_t mem_size = 0;  // 1 (byte), 2 (halfword), 4 (word)
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

using ReferenceStepResult = RefStepResult;

class IRefBackend {
 public:
  virtual ~IRefBackend() = default;

  virtual void reset(std::uint32_t reset_pc = 0) = 0;
  virtual void load_irom(const std::vector<std::uint32_t> &words) = 0;
  virtual void load_from_sim_memory() = 0;

  virtual std::uint32_t pc() const = 0;
  virtual void set_pc(std::uint32_t val) = 0;
  virtual std::uint32_t reg(std::size_t index) const = 0;
  virtual void set_reg(std::size_t index, std::uint32_t val) = 0;
  virtual const std::array<std::uint32_t, 16> &regs() const = 0;

  virtual bool in_fault() const = 0;
  virtual std::uint8_t fault_cause() const = 0;
  virtual std::uint32_t fault_pc() const = 0;

  virtual void skip_instruction(std::uint32_t rd, std::uint32_t dut_rd_val,
                                std::uint32_t next_pc) = 0;
  virtual RefStepResult step() = 0;
  virtual const char *name() const = 0;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_REF_BACKEND_H_
