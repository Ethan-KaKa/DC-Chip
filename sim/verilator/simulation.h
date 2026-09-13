#ifndef DC_CHIP_SIM_VERILATOR_SIMULATION_H_
#define DC_CHIP_SIM_VERILATOR_SIMULATION_H_

#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <set>
#ifdef CONFIG_DC_SIM_WAVE
#include <string>
#endif

namespace dc_sim {

enum class FaultCause : std::uint8_t {
  none = 0,
  illegal_instruction = 1,
  instruction_access = 2,
  instruction_misaligned = 3,
  load_misaligned = 4,
  load_access = 5,
  store_misaligned = 6,
  store_access = 7,
};

const char *fault_cause_string(std::uint8_t cause);

struct ArchitecturalState {
  std::uint32_t fetch_pc = 0;
  std::uint32_t fetch_inst = 0;
  std::array<std::uint32_t, 16> registers{};
  std::uint64_t cycles = 0;
  std::uint64_t commits = 0;
  std::uint64_t time = 0;
};

struct StepEvent {
  bool committed = false;
  std::uint32_t commit_pc = 0;
  std::uint32_t commit_inst = 0;
  bool is_skip_ref = false;
  bool tohost_exit = false;
  std::uint32_t guest_exit_code = 0;
  bool entered_fault = false;
  std::uint8_t fault_cause = 0;
  std::uint32_t fault_pc = 0;
  bool fault_inst_valid = false;
  std::uint32_t fault_inst = 0;
};

enum class StopReason {
  cycles_complete,
  commits_complete,
  breakpoint,
  fault,
  program_exit,
  timeout,
  monitor_failure,
  quit,
};

enum class RunTarget {
  none,
  cycles,
  commits,
};

struct RunResult {
  StopReason reason = StopReason::quit;
  StepEvent event{};
  ArchitecturalState state{};
};

using StepObserver = std::function<bool(const RunResult &)>;

class Simulation {
 public:
  Simulation();
  Simulation(int argc, char **argv, bool enable_nvboard = true,
             bool enable_wave = true);
  ~Simulation();

  Simulation(const Simulation &) = delete;
  Simulation &operator=(const Simulation &) = delete;
  Simulation(Simulation &&) = delete;
  Simulation &operator=(Simulation &&) = delete;

  void reset();
  StepEvent step_cycle();
  RunResult step_instruction(std::uint64_t max_cycles);
  RunResult run_until(RunTarget target, std::uint64_t count,
                      std::uint64_t max_cycles,
                      const std::set<std::uint32_t> &breakpoints = {},
                      const StepObserver &observer = {});
  ArchitecturalState snapshot() const;

#ifdef CONFIG_DC_SIM_WAVE
  void set_wave_enabled(bool enabled);
  bool wave_enabled() const;
  const std::string &wave_path() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_SIMULATION_H_
