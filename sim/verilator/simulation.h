#ifndef DC_CHIP_SIM_VERILATOR_SIMULATION_H_
#define DC_CHIP_SIM_VERILATOR_SIMULATION_H_

#include <array>
#include <cstdint>
#include <memory>
#include <set>
#ifdef CONFIG_DC_SIM_WAVE
#include <string>
#endif

namespace dc_sim {

struct ArchitecturalState {
  std::uint8_t fetch_pc = 0;
  std::uint16_t fetch_inst = 0;
  std::array<std::uint16_t, 4> registers{};
  std::uint64_t cycles = 0;
  std::uint64_t commits = 0;
  std::uint64_t time = 0;
};

struct StepEvent {
  bool committed = false;
  std::uint8_t commit_pc = 0;
  std::uint16_t commit_inst = 0;
  bool entered_illegal = false;
  bool executed_out_of_bounds_fetch = false;
};

enum class StopReason {
  cycles_complete,
  commits_complete,
  breakpoint,
  illegal_instruction,
  out_of_bounds_fetch,
  timeout,
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

class Simulation {
 public:
  Simulation();
  Simulation(int argc, char **argv);
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
                      const std::set<std::uint8_t> &breakpoints = {});
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
