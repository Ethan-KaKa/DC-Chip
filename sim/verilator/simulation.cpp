#include "simulation.h"

#include "Vsim_top.h"
#include "memory.h"
#include "verilated.h"
#ifdef CONFIG_DC_SIM_WAVE
#include "verilated_vcd_c.h"
#endif

#ifdef CONFIG_DC_SIM_WAVE
#include <filesystem>
#include <system_error>
#endif
#include <stdexcept>

namespace dc_sim {

class Simulation::Impl {
 public:
  Impl(int argc, char **argv)
      : context(std::make_unique<VerilatedContext>()) {
    if (argc > 0) {
      context->commandArgs(argc, argv);
    }
    top = std::make_unique<Vsim_top>(context.get());
    top->clk = 0;
    top->rst = 1;
  }

  void initialize() {
#ifdef CONFIG_DC_SIM_WAVE
    context->traceEverOn(true);
    tracer = std::make_unique<VerilatedVcdC>();
    top->trace(tracer.get(), 99);
    wave_file_path = resolve_wave_path();
    tracer->open(wave_file_path.c_str());
    if (!tracer->isOpen()) {
      throw std::runtime_error("failed to open VCD waveform: " +
                               wave_file_path);
    }
#endif
    top->eval();
#ifdef CONFIG_DC_SIM_WAVE
    tracer->dump(context->time());
#endif
  }

  ~Impl() {
#ifdef CONFIG_DC_SIM_WAVE
    if (tracer != nullptr) {
      tracer->flush();
      tracer->close();
    }
#endif
    if (top != nullptr) {
      top->final();
    }
  }

  ArchitecturalState snapshot() const {
    ArchitecturalState state;
    state.fetch_pc = top->fetch_pc;
    state.fetch_inst = top->fetch_inst;
    const std::uint64_t packed = top->debug_regs;
    for (std::size_t index = 0; index < state.registers.size(); ++index) {
      state.registers[index] = static_cast<std::uint16_t>(
          (packed >> (index * 16U)) & 0xffffU);
    }
    state.cycles = cycles;
    state.commits = commits;
    state.time = context->time();
    return state;
  }

  void advance_half_cycle(std::uint8_t clock_level) {
    context->timeInc(1);
    top->clk = clock_level;
    top->eval();
#ifdef CONFIG_DC_SIM_WAVE
    if (wave_dump_enabled) {
      tracer->dump(context->time());
    }
#endif
  }

#ifdef CONFIG_DC_SIM_WAVE
  static std::string resolve_wave_path() {
    std::error_code error;
    const std::filesystem::path executable =
        std::filesystem::read_symlink("/proc/self/exe", error);
    if (error || executable.empty()) {
      throw std::runtime_error(
          "failed to resolve simulator executable via /proc/self/exe");
    }

    const std::filesystem::path simulator_dir = executable.parent_path();
    const std::string directory_name = simulator_dir.filename().string();
    if (directory_name.rfind("verilator", 0) != 0 ||
        simulator_dir.parent_path().empty()) {
      throw std::runtime_error(
          "simulator executable is not under <BUILD_DIR>/verilator*: " +
          executable.string());
    }
    return (simulator_dir.parent_path() / "dump.vcd").string();
  }
#endif

  std::unique_ptr<VerilatedContext> context;
  std::unique_ptr<Vsim_top> top;
#ifdef CONFIG_DC_SIM_WAVE
  std::unique_ptr<VerilatedVcdC> tracer;
  std::string wave_file_path;
  bool wave_dump_enabled = true;
#endif
  std::uint64_t cycles = 0;
  std::uint64_t commits = 0;
  bool reset_done = false;
};

Simulation::Simulation() : Simulation(0, nullptr) {}

Simulation::Simulation(int argc, char **argv)
    : impl_(std::make_unique<Impl>(argc, argv)) {
  impl_->initialize();
}

Simulation::~Simulation() = default;

void Simulation::reset() {
  if (impl_->reset_done) {
    throw std::logic_error("Simulation::reset() may only be called once");
  }

  impl_->top->clk = 0;
  impl_->top->rst = 1;
  impl_->top->eval();
  for (int reset_cycle = 0; reset_cycle < 2; ++reset_cycle) {
    impl_->advance_half_cycle(1);
    impl_->advance_half_cycle(0);
  }
  impl_->top->rst = 0;
  impl_->top->eval();
  clear_fetch_status();
  impl_->reset_done = true;
}

StepEvent Simulation::step_cycle() {
  if (!impl_->reset_done) {
    throw std::logic_error(
        "Simulation::step_cycle() requires reset() first");
  }

  const bool was_illegal = impl_->top->illegal_inst != 0;
  const std::uint8_t executed_pc = impl_->top->fetch_pc;

  impl_->advance_half_cycle(1);
  ++impl_->cycles;

  StepEvent event;
  event.committed = impl_->top->trace_valid != 0;
  if (event.committed) {
    ++impl_->commits;
    event.commit_pc = impl_->top->trace_pc;
    event.commit_inst = impl_->top->trace_inst;
  }
  event.entered_illegal = !was_illegal && impl_->top->illegal_inst != 0;
  event.executed_out_of_bounds_fetch =
      event.entered_illegal && fetch_out_of_bounds() &&
      first_oob_address() == executed_pc;

  impl_->advance_half_cycle(0);
  return event;
}

RunResult Simulation::step_instruction(std::uint64_t max_cycles) {
  return run_until(RunTarget::commits, 1, max_cycles, {});
}

RunResult Simulation::run_until(
    RunTarget target, std::uint64_t count, std::uint64_t max_cycles,
    const std::set<std::uint8_t> &breakpoints) {
  if (!impl_->reset_done) {
    throw std::logic_error(
        "Simulation::run_until() requires reset() first");
  }
  if (target != RunTarget::none && count == 0) {
    throw std::invalid_argument(
        "Simulation::run_until() target count must be positive");
  }

  const std::uint64_t start_cycles = impl_->cycles;
  const std::uint64_t start_commits = impl_->commits;
  while (true) {
    if (impl_->cycles >= max_cycles) {
      return {StopReason::timeout, {}, snapshot()};
    }
    if (breakpoints.find(impl_->top->fetch_pc) != breakpoints.end()) {
      return {StopReason::breakpoint, {}, snapshot()};
    }

    const StepEvent event = step_cycle();
    if (target == RunTarget::commits &&
        impl_->commits - start_commits >= count) {
      return {StopReason::commits_complete, event, snapshot()};
    }
    if (event.entered_illegal) {
      const StopReason reason = event.executed_out_of_bounds_fetch
                                    ? StopReason::out_of_bounds_fetch
                                    : StopReason::illegal_instruction;
      return {reason, event, snapshot()};
    }
    if (impl_->cycles >= max_cycles) {
      return {StopReason::timeout, event, snapshot()};
    }
    if (target == RunTarget::cycles &&
        impl_->cycles - start_cycles >= count) {
      return {StopReason::cycles_complete, event, snapshot()};
    }
  }
}

ArchitecturalState Simulation::snapshot() const {
  if (!impl_->reset_done) {
    throw std::logic_error("Simulation::snapshot() requires reset() first");
  }
  return impl_->snapshot();
}

#ifdef CONFIG_DC_SIM_WAVE
void Simulation::set_wave_enabled(bool enabled) {
  impl_->wave_dump_enabled = enabled;
}

bool Simulation::wave_enabled() const {
  return impl_->wave_dump_enabled;
}

const std::string &Simulation::wave_path() const {
  return impl_->wave_file_path;
}
#endif

}  // namespace dc_sim
