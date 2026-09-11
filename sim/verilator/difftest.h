#ifndef DC_CHIP_SIM_VERILATOR_DIFFTEST_H_
#define DC_CHIP_SIM_VERILATOR_DIFFTEST_H_

#include "reference_model.h"
#include "simulation.h"

#include <cstdint>
#include <string>

namespace dc_sim {

struct DifftestMismatch {
  std::uint64_t cycle = 0;
  std::uint64_t commit = 0;
  std::string field;
  std::uint32_t dut_value = 0;
  std::uint32_t ref_value = 0;
  std::string message;
};

class Difftest {
 public:
  Difftest(Simulation &dut, ReferenceModel &ref);

  // Sync reference memory with simulation memory
  void sync_memory();

  // Run difftest step on single committed instruction or fault
  // Returns true if matched, false if mismatch occurred.
  bool step_and_compare(std::uint64_t max_cycles, DifftestMismatch *mismatch = nullptr);

  // Run until tohost exit, fault, or max commits
  bool run_difftest(std::uint64_t max_commits, std::uint64_t max_cycles,
                    DifftestMismatch *mismatch = nullptr);

  bool last_tohost_exit() const { return last_tohost_exit_; }

 private:
  Simulation &dut_;
  ReferenceModel &ref_;
  bool last_tohost_exit_ = false;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_DIFFTEST_H_
