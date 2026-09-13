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
#ifdef CONFIG_DC_SIM_NVBOARD
#include <nvboard.h>
void nvboard_bind_all_pins(Vsim_top *top);
#endif
#include <iostream>
#include <stdexcept>

namespace dc_sim {

class Simulation::Impl {
 public:
  Impl(int argc, char **argv, bool enable_nvboard, bool enable_wave)
      : context(std::make_unique<VerilatedContext>())
#ifdef CONFIG_DC_SIM_WAVE
        , wave_dump_enabled(enable_wave)
#endif
#ifdef CONFIG_DC_SIM_NVBOARD
        , nvboard_enabled(enable_nvboard)
#endif
  {
#ifndef CONFIG_DC_SIM_NVBOARD
    static_cast<void>(enable_nvboard);
#endif
#ifndef CONFIG_DC_SIM_WAVE
    static_cast<void>(enable_wave);
#endif
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
    wave_file_path = resolve_wave_path();
    if (wave_dump_enabled) {
      open_wave();
    }
#endif
    top->eval();
#ifdef CONFIG_DC_SIM_WAVE
    if (tracer != nullptr) {
      tracer->dump(context->time());
    }
#endif
#ifdef CONFIG_DC_SIM_NVBOARD
    if (nvboard_enabled) {
      nvboard_bind_all_pins(top.get());
      nvboard_init();
    }
#endif
  }

  ~Impl() {
#ifdef CONFIG_DC_SIM_NVBOARD
    if (nvboard_enabled) {
      nvboard_quit();
    }
#endif
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
    for (std::size_t index = 0; index < state.registers.size(); ++index) {
      top->debug_reg_addr = static_cast<uint8_t>(index);
      top->eval();
      state.registers[index] = top->debug_reg_data;
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
    if (wave_dump_enabled && tracer != nullptr) {
      tracer->dump(context->time());
    }
#endif
#ifdef CONFIG_DC_SIM_NVBOARD
    if (nvboard_enabled && clock_level == 0) {
      nvboard_update();
    }
#endif
  }

#ifdef CONFIG_DC_SIM_WAVE
  void open_wave() {
    if (tracer != nullptr) {
      return;
    }
    tracer = std::make_unique<VerilatedVcdC>();
    top->trace(tracer.get(), 99);
    tracer->open(wave_file_path.c_str());
    if (!tracer->isOpen()) {
      tracer.reset();
      throw std::runtime_error("failed to open VCD waveform: " +
                               wave_file_path);
    }
  }

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
#ifdef CONFIG_DC_SIM_NVBOARD
  bool nvboard_enabled = true;
#endif
};

const char *fault_cause_string(std::uint8_t cause) {
  switch (static_cast<FaultCause>(cause)) {
    case FaultCause::illegal_instruction:
      return "illegal instruction";
    case FaultCause::instruction_access:
      return "instruction access fault";
    case FaultCause::instruction_misaligned:
      return "instruction address misaligned";
    case FaultCause::load_misaligned:
      return "load address misaligned";
    case FaultCause::load_access:
      return "load access fault";
    case FaultCause::store_misaligned:
      return "store address misaligned";
    case FaultCause::store_access:
      return "store access fault";
    case FaultCause::none:
    default:
      return "none";
  }
}

Simulation::Simulation() : Simulation(0, nullptr, true, true) {}

Simulation::Simulation(int argc, char **argv, bool enable_nvboard,
                       bool enable_wave)
    : impl_(std::make_unique<Impl>(argc, argv, enable_nvboard, enable_wave)) {
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

  const bool was_fault = impl_->top->fault_valid != 0;

  impl_->advance_half_cycle(1);
  ++impl_->cycles;

  StepEvent event;
  event.committed = impl_->top->trace_valid != 0;
  if (event.committed) {
    ++impl_->commits;
    event.commit_pc = impl_->top->trace_pc;
    event.commit_inst = impl_->top->trace_inst;
    event.is_skip_ref = (impl_->top->is_skip_ref != 0);
  }
  event.tohost_exit = impl_->top->tohost_exit != 0;
  event.guest_exit_code = impl_->top->guest_exit_code;

  const bool is_fault = impl_->top->fault_valid != 0;
  event.entered_fault = !was_fault && is_fault;
  if (is_fault) {
    event.fault_cause = static_cast<std::uint8_t>(impl_->top->fault_cause);
    event.fault_pc = impl_->top->fault_pc;
    event.fault_inst_valid = impl_->top->fault_inst_valid != 0;
    event.fault_inst = impl_->top->fault_inst;
  }

  impl_->advance_half_cycle(0);
  return event;
}

RunResult Simulation::step_instruction(std::uint64_t max_cycles) {
  return run_until(RunTarget::commits, 1, max_cycles, {});
}

RunResult Simulation::run_until(
    RunTarget target, std::uint64_t count, std::uint64_t max_cycles,
    const std::set<std::uint32_t> &breakpoints,
    const StepObserver &observer) {
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

    StopReason observed_reason = StopReason::cycles_complete;
    if (event.tohost_exit) {
      observed_reason = StopReason::program_exit;
    } else if (event.entered_fault || impl_->top->fault_valid != 0) {
      observed_reason = StopReason::fault;
    } else if (target == RunTarget::commits &&
               impl_->commits - start_commits >= count) {
      observed_reason = StopReason::commits_complete;
    }

    if (observer && (event.committed || observed_reason == StopReason::fault)) {
      const RunResult observed{observed_reason, event, snapshot()};
      if (!observer(observed)) {
        return {StopReason::monitor_failure, event, observed.state};
      }
    }

    // Priority 1: tohost program exit
    if (event.tohost_exit) {
      return {StopReason::program_exit, event, snapshot()};
    }

    // Priority 2: fault
    if (event.entered_fault || impl_->top->fault_valid != 0) {
      return {StopReason::fault, event, snapshot()};
    }

    // Priority 3: commits target reached
    if (target == RunTarget::commits &&
        impl_->commits - start_commits >= count) {
      return {StopReason::commits_complete, event, snapshot()};
    }

    // Priority 4: timeout
    if (impl_->cycles >= max_cycles) {
      return {StopReason::timeout, event, snapshot()};
    }

    // Priority 5: cycles target reached
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
  if (enabled && impl_->tracer == nullptr) {
    impl_->open_wave();
    impl_->tracer->dump(impl_->context->time());
  }
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

extern "C" {

void sim_uart_putc(std::uint8_t data) {
  std::cout.put(static_cast<char>(data));
  std::cout.flush();
}

}
