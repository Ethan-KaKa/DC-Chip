#ifndef DC_CHIP_SIM_VERILATOR_DIFFTEST_H_
#define DC_CHIP_SIM_VERILATOR_DIFFTEST_H_

#include "ref_backend.h"
#include "simulation.h"

#include <array>
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
  std::uint32_t pc = 0;
  std::uint32_t inst = 0;
  bool has_register_snapshot = false;
  std::array<std::uint32_t, 16> dut_registers{};
};

class Difftest {
 public:
  Difftest(Simulation &dut, IRefBackend &ref);

  // Sync reference memory with simulation memory
  void sync_memory();

  // Run difftest step on single committed instruction or fault
  // Returns true if matched, false if mismatch occurred.
  bool step_and_compare(std::uint64_t max_cycles, DifftestMismatch *mismatch = nullptr,
                        RunResult *out_dut_res = nullptr);

  // Compare a result produced by the shared execution loop. This advances the
  // reference model exactly once for a committed instruction or precise fault.
  bool compare_result(const RunResult &dut_res,
                      DifftestMismatch *mismatch = nullptr);

  // Run until tohost exit, fault, or max commits
  bool run_difftest(std::uint64_t max_commits, std::uint64_t max_cycles,
                    DifftestMismatch *mismatch = nullptr);

  bool last_tohost_exit() const { return last_tohost_exit_; }

 private:
  Simulation &dut_;
  IRefBackend &ref_;
  bool last_tohost_exit_ = false;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_DIFFTEST_H_
