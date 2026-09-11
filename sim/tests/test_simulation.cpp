#include "memory.h"
#include "simulation.h"

#include <array>
#include <cstdint>
#include <exception>
#include <functional>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using dc_sim::ArchitecturalState;
using dc_sim::RunTarget;
using dc_sim::Simulation;
using dc_sim::StopReason;

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string image_path(const std::string &fixture_dir,
                       const std::string &name) {
  return fixture_dir + "/" + name;
}

void load_image(const std::string &fixture_dir, const std::string &name) {
  std::string error;
  require(dc_sim::load_hex_image(image_path(fixture_dir, name), &error),
          error);
}

void expect_logic_error(const std::function<void()> &operation,
                        const std::string &message) {
  bool caught = false;
  try {
    operation();
  } catch (const std::logic_error &) {
    caught = true;
  }
  require(caught, message);
}

void test_reset_and_cycle(const std::string &fixture_dir) {
  load_image(fixture_dir, "isa_smoke.hex");
  Simulation simulation;
  simulation.reset();

  const ArchitecturalState reset_state = simulation.snapshot();
  require(reset_state.cycles == 0, "reset counted an execution cycle");
  require(reset_state.commits == 0, "reset counted a commit");
  require(reset_state.fetch_pc == 0, "reset PC is not 0x00000000");
  require(reset_state.fetch_inst == 0x00200093,
          "reset fetch instruction is not the first image word");
  require(reset_state.registers == std::array<std::uint32_t, 16>{},
          "reset registers are not zero");
  require(reset_state.time == 4, "two reset cycles did not advance time by 4");

  const dc_sim::StepEvent event = simulation.step_cycle();
  const ArchitecturalState state = simulation.snapshot();
  require(event.committed, "first execution cycle did not commit");
  require(event.commit_pc == 0 && event.commit_inst == 0x00200093,
          "first commit identity mismatch");
  require(!event.entered_fault, "legal first instruction reported an error event");
  require(state.cycles == 1 && state.commits == 1,
          "one cycle did not increment cycle and commit counts once");
  require(state.fetch_pc == 4 && state.registers[1] == 2,
          "first instruction architectural result mismatch");
  require(state.time == 6, "one execution cycle did not advance time by 2");
}

void test_instruction_steps(const std::string &fixture_dir) {
  load_image(fixture_dir, "jump_loop.hex");
  Simulation simulation;
  simulation.reset();

  std::vector<std::uint32_t> pcs;
  for (int step = 0; step < 5; ++step) {
    const dc_sim::RunResult result = simulation.step_instruction(10);
    require(result.reason == StopReason::commits_complete,
            "jump loop instruction step did not complete");
    require(result.event.committed,
            "completed instruction step has no commit event");
    pcs.push_back(result.event.commit_pc);
  }
  require(pcs == std::vector<std::uint32_t>({0x0, 0x4, 0x8, 0xc, 0x4}),
          "jump loop commit PC sequence mismatch");
  const ArchitecturalState state = simulation.snapshot();
  require(state.cycles == 5 && state.commits == 5,
          "jump loop final counts mismatch");
  require(state.fetch_pc == 0x8 && state.registers[1] == 3,
          "jump loop final architectural state mismatch");
}

void test_run_targets_and_breakpoint(const std::string &fixture_dir) {
  load_image(fixture_dir, "jump_loop.hex");
  Simulation cycle_simulation;
  cycle_simulation.reset();
  const dc_sim::RunResult cycle_result = cycle_simulation.run_until(
      RunTarget::cycles, 2, 10, {});
  require(cycle_result.reason == StopReason::cycles_complete,
          "cycle run target did not complete");
  require(cycle_result.state.cycles == 2 &&
              cycle_result.state.commits == 2,
          "cycle run target counts mismatch");
  const dc_sim::RunResult relative_cycle_result = cycle_simulation.run_until(
      RunTarget::cycles, 2, 10, {});
  require(relative_cycle_result.reason == StopReason::cycles_complete &&
              relative_cycle_result.state.cycles == 4,
          "cycle run target was not relative to the call start");

  load_image(fixture_dir, "jump_loop.hex");
  Simulation commit_simulation;
  commit_simulation.reset();
  const dc_sim::RunResult commit_result = commit_simulation.run_until(
      RunTarget::commits, 2, 10, {});
  require(commit_result.reason == StopReason::commits_complete,
          "commit run target did not complete");
  require(commit_result.state.cycles == 2 &&
              commit_result.state.commits == 2,
          "commit run target counts mismatch");
  const dc_sim::RunResult relative_commit_result =
      commit_simulation.run_until(RunTarget::commits, 2, 10, {});
  require(relative_commit_result.reason == StopReason::commits_complete &&
              relative_commit_result.state.commits == 4,
          "commit run target was not relative to the call start");

  load_image(fixture_dir, "jump_loop.hex");
  Simulation breakpoint_simulation;
  breakpoint_simulation.reset();
  const dc_sim::RunResult breakpoint_result =
      breakpoint_simulation.run_until(RunTarget::none, 0, 10, {0});
  require(breakpoint_result.reason == StopReason::breakpoint,
          "execution-before breakpoint did not stop");
  require(breakpoint_result.state.cycles == 0 &&
              breakpoint_result.state.commits == 0,
          "execution-before breakpoint advanced the simulation");

  load_image(fixture_dir, "jump_loop.hex");
  Simulation priority_simulation;
  priority_simulation.reset();
  require(priority_simulation.run_until(RunTarget::cycles, 1, 10, {}).reason ==
              StopReason::cycles_complete,
          "priority setup cycle did not complete");
  const dc_sim::RunResult limit_before_breakpoint =
      priority_simulation.run_until(RunTarget::none, 0, 1, {4});
  require(limit_before_breakpoint.reason == StopReason::timeout &&
              limit_before_breakpoint.state.cycles == 1,
          "pre-execution global limit did not precede breakpoint");
}

void test_fault_and_tohost(const std::string &fixture_dir) {
  load_image(fixture_dir, "illegal_reserved.hex");
  Simulation illegal_simulation;
  illegal_simulation.reset();
  const dc_sim::RunResult illegal_result =
      illegal_simulation.step_instruction(10);
  require(illegal_result.reason == StopReason::fault,
          "reserved opcode was not reported as fault");
  require(illegal_result.event.entered_fault &&
          illegal_result.event.fault_cause == 1,
          "reserved opcode fault cause mismatch");

  load_image(fixture_dir, "guest_fail.hex");
  Simulation guest_simulation;
  guest_simulation.reset();
  const dc_sim::RunResult guest_result =
      guest_simulation.run_until(RunTarget::none, 0, 100, {});
  require(guest_result.reason == StopReason::program_exit,
          "guest_fail did not stop on program exit");
  require(guest_result.event.tohost_exit &&
          guest_result.event.guest_exit_code == 42,
          "guest_fail exit code mismatch");
}

void test_timeout_and_completion_priority(const std::string &fixture_dir) {
  load_image(fixture_dir, "jump_loop.hex");
  Simulation timeout_simulation;
  timeout_simulation.reset();
  const dc_sim::RunResult timeout_result = timeout_simulation.run_until(
      RunTarget::commits, 5, 2, {});
  require(timeout_result.reason == StopReason::timeout,
          "global two-cycle limit did not time out");
  require(timeout_result.state.cycles == 2 &&
              timeout_result.state.commits == 2,
          "timeout counts mismatch");

  load_image(fixture_dir, "jump_loop.hex");
  Simulation cycle_timeout_simulation;
  cycle_timeout_simulation.reset();
  const dc_sim::RunResult cycle_timeout_result =
      cycle_timeout_simulation.run_until(RunTarget::cycles, 2, 2, {});
  require(cycle_timeout_result.reason == StopReason::timeout,
          "global cycle limit did not precede cycle target completion");
}

void test_misuse(const std::string &fixture_dir) {
  load_image(fixture_dir, "jump_loop.hex");
  Simulation simulation;
  expect_logic_error([&simulation] { simulation.step_cycle(); },
                     "step_cycle before reset did not fail");
  expect_logic_error(
      [&simulation] {
        simulation.run_until(RunTarget::commits, 1, 2, {});
      },
      "run_until before reset did not fail");
  simulation.reset();
  expect_logic_error([&simulation] { simulation.reset(); },
                     "repeated reset did not fail");
}

#ifdef CONFIG_DC_SIM_WAVE
void require_same_state(const ArchitecturalState &actual,
                        const ArchitecturalState &expected) {
  require(actual.fetch_pc == expected.fetch_pc,
          "wave pause changed the final PC");
  require(actual.fetch_inst == expected.fetch_inst,
          "wave pause changed the final instruction");
  require(actual.registers == expected.registers,
          "wave pause changed the final registers");
  require(actual.cycles == expected.cycles,
          "wave pause changed the cycle count");
  require(actual.commits == expected.commits,
          "wave pause changed the commit count");
  require(actual.time == expected.time,
          "wave pause changed the simulation time");
}

void test_wave_control(const std::string &fixture_dir) {
  load_image(fixture_dir, "jump_loop.hex");
  ArchitecturalState reference_state;
  StopReason reference_reason = StopReason::quit;
  {
    Simulation reference;
    reference.reset();
    const dc_sim::RunResult result =
        reference.run_until(RunTarget::cycles, 4, 10, {});
    reference_reason = result.reason;
    reference_state = result.state;
  }

  load_image(fixture_dir, "jump_loop.hex");
  Simulation paused;
  require(paused.wave_enabled(), "wave recording did not start enabled");
  require(!paused.wave_path().empty() &&
              paused.wave_path().size() >= std::string("dump.vcd").size() &&
              paused.wave_path().compare(
                  paused.wave_path().size() - std::string("dump.vcd").size(),
                  std::string("dump.vcd").size(), "dump.vcd") == 0,
          "wave path does not end in dump.vcd");
  paused.reset();
  require(paused.run_until(RunTarget::cycles, 1, 10, {}).reason ==
              StopReason::cycles_complete,
          "wave pause setup cycle did not complete");
  paused.set_wave_enabled(false);
  require(!paused.wave_enabled(), "wave recording did not pause");
  require(paused.run_until(RunTarget::cycles, 2, 10, {}).reason ==
              StopReason::cycles_complete,
          "cycles while wave recording was paused did not complete");
  paused.set_wave_enabled(true);
  require(paused.wave_enabled(), "wave recording did not resume");
  const dc_sim::RunResult paused_result =
      paused.run_until(RunTarget::cycles, 1, 10, {});
  require(paused_result.reason == reference_reason,
          "wave pause changed the final stop reason");
  require_same_state(paused_result.state, reference_state);
}
#endif

}  // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "test_simulation: FAIL expected fixture directory\n";
    return 1;
  }

  try {
    const std::string fixture_dir = argv[1];
    test_reset_and_cycle(fixture_dir);
    test_instruction_steps(fixture_dir);
    test_run_targets_and_breakpoint(fixture_dir);
    test_fault_and_tohost(fixture_dir);
    test_timeout_and_completion_priority(fixture_dir);
    test_misuse(fixture_dir);
#ifdef CONFIG_DC_SIM_WAVE
    test_wave_control(fixture_dir);
#endif
  } catch (const std::exception &error) {
    std::cerr << "test_simulation: FAIL " << error.what() << '\n';
    return 1;
  }

  std::cout << "test_simulation: PASS\n";
  return 0;
}
