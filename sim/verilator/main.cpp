#include "memory.h"
#include "numeric.h"
#include "simulation.h"
#ifdef CONFIG_DC_SIM_SDB
#include "sdb.h"
#endif
#ifdef CONFIG_DC_SIM_DIFFTEST
#include "disasm.h"
#include "difftest.h"
#include "dynamic_ref_backend.h"
#include "reference_model.h"
#endif

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>

namespace {

constexpr int kSuccess = 0;
constexpr int kInputError = 1;
constexpr int kFault = 2;
constexpr int kTimeout = 3;
constexpr int kStateMismatch = 4;
constexpr int kGuestFailure = 5;
constexpr int kUserQuit = 6;

struct Options {
  std::string inst_image_path;
  std::string data_image_path;
  std::string diff_ref_so_path;
  dc_sim::ImageFormat format = dc_sim::ImageFormat::kAuto;
  std::optional<std::uint64_t> steps;
  std::optional<std::uint64_t> max_cycles;
  bool trace = false;
  bool sdb_off = false;
  bool nvboard_off = false;
  bool wave_off = false;
  bool test_dispatch = false;
  bool has_expectation = false;
  std::array<std::optional<std::uint32_t>, 16> expected_registers;
  std::optional<std::uint32_t> expected_pc;
};

void print_usage(std::ostream &output) {
  output
      << "Usage: Vsim_top [--image <path> | --image-inst <path>] [options]\n"
      << "  --image <path>              Instruction image (.hex or .bin)\n"
      << "  --image-inst <path>         Instruction image (.hex or .bin, alias for --image)\n"
      << "  --image-data <path>         Data image (.bin or .hex, loaded to DRAM)\n"
      << "  --format <auto|hex|bin>     Force image format (default: auto)\n"
      << "  --steps <positive-u64>      Commits to execute (default: run until tohost/fault)\n"
      << "  --max-cycles <positive-u64> Execution cycles (default: 100000)\n"
      << "  --trace                     Print one line per committed instruction\n"
      << "  --expect <name=value>       Check x0..x15 or pc\n"
      << "  --sdb-off                   Disable configured interactive SDB\n"
      << "  --nvboard-off               Disable configured NVBoard runtime\n"
      << "  --wave-off                  Disable initial VCD creation/recording\n"
      << "  --diff-ref-so <path>        Path to external reference shared library (.so)\n"
      << "  --help                      Show this help (must be the only option)\n";
}


bool take_value(int argc, char **argv, int *index, std::string_view option,
                std::string_view *value, std::string *error) {
  if (*index + 1 >= argc) {
    *error = "missing value for " + std::string(option);
    return false;
  }
  ++(*index);
  *value = argv[*index];
  return true;
}

bool parse_expectation(std::string_view text, Options *options,
                       std::string *error) {
  const std::size_t equals = text.find('=');
  if (equals == std::string_view::npos || equals == 0 ||
      equals + 1 == text.size() || text.find('=', equals + 1) !=
                                         std::string_view::npos) {
    *error = "invalid --expect value '" + std::string(text) + "'";
    return false;
  }

  const std::string_view name = text.substr(0, equals);
  const std::string_view value_text = text.substr(equals + 1);
  std::uint64_t value = 0;
  if (!dc_sim::parse_unsigned(value_text, &value)) {
    *error = "invalid numeric value in --expect '" + std::string(text) +
             "'";
    return false;
  }

  if (name == "pc") {
    if (options->expected_pc.has_value()) {
      *error = "duplicate expectation for pc";
      return false;
    }
    if (value > 0xffffffffULL) {
      *error = "pc expectation is outside 0x00000000..0xffffffff";
      return false;
    }
    options->expected_pc = static_cast<std::uint32_t>(value);
    return true;
  }

  if (name.size() >= 2 && name[0] == 'x') {
    std::uint64_t reg_idx = 0;
    if (dc_sim::parse_unsigned(name.substr(1), &reg_idx) && reg_idx < 16) {
      if (options->expected_registers[reg_idx].has_value()) {
        *error = "duplicate expectation for " + std::string(name);
        return false;
      }
      if (value > 0xffffffffULL) {
        *error = std::string(name) + " expectation is outside 0x00000000..0xffffffff";
        return false;
      }
      options->expected_registers[reg_idx] = static_cast<std::uint32_t>(value);
      return true;
    }
  }

  *error = "unknown expectation name '" + std::string(name) + "'";
  return false;
}

bool parse_options(int argc, char **argv, Options *options,
                   std::string *error) {
  bool saw_inst_image = false;
  bool saw_data_image = false;
  bool saw_format = false;
  bool saw_steps = false;
  bool saw_max_cycles = false;
  bool saw_sdb_off = false;
  bool saw_nvboard_off = false;
  bool saw_wave_off = false;
  bool saw_test_dispatch = false;

  for (int index = 1; index < argc; ++index) {
    const std::string_view argument = argv[index];
    std::string_view value;

    if (argument == "--help") {
      *error = "--help must be the only argument";
      return false;
    }
    if (argument == "--image" || argument == "--image-inst") {
      if (saw_inst_image) {
        *error = "duplicate option " + std::string(argument);
        return false;
      }
      if (!take_value(argc, argv, &index, argument, &value, error)) {
        return false;
      }
      if (value.empty()) {
        *error = "empty value for " + std::string(argument);
        return false;
      }
      options->inst_image_path = value;
      saw_inst_image = true;
      continue;
    }
    if (argument == "--image-data") {
      if (saw_data_image) {
        *error = "duplicate option --image-data";
        return false;
      }
      if (!take_value(argc, argv, &index, argument, &value, error)) {
        return false;
      }
      if (value.empty()) {
        *error = "empty value for --image-data";
        return false;
      }
      options->data_image_path = value;
      saw_data_image = true;
      continue;
    }
    if (argument == "--format") {
      if (saw_format) {
        *error = "duplicate option --format";
        return false;
      }
      if (!take_value(argc, argv, &index, argument, &value, error)) {
        return false;
      }
      if (value == "auto") {
        options->format = dc_sim::ImageFormat::kAuto;
      } else if (value == "hex") {
        options->format = dc_sim::ImageFormat::kHex;
      } else if (value == "bin") {
        options->format = dc_sim::ImageFormat::kBin;
      } else {
        *error = "invalid format '" + std::string(value) + "'; expected auto, hex, or bin";
        return false;
      }
      saw_format = true;
      continue;
    }
    if (argument == "--steps" || argument == "--max-cycles") {
      const bool is_steps = argument == "--steps";
      bool &seen = is_steps ? saw_steps : saw_max_cycles;
      if (seen) {
        *error = "duplicate option " + std::string(argument);
        return false;
      }
      if (!take_value(argc, argv, &index, argument, &value, error)) {
        return false;
      }
      std::uint64_t parsed = 0;
      if (!dc_sim::parse_unsigned(value, &parsed) || parsed == 0) {
        *error = "invalid positive integer for " + std::string(argument) +
                 ": '" + std::string(value) + "'";
        return false;
      }
      if (is_steps) {
        options->steps = parsed;
      } else {
        options->max_cycles = parsed;
      }
      seen = true;
      continue;
    }
    if (argument == "--trace") {
      if (options->trace) {
        *error = "duplicate option --trace";
        return false;
      }
      options->trace = true;
      continue;
    }
    if (argument == "--expect") {
      if (!take_value(argc, argv, &index, argument, &value, error) ||
          !parse_expectation(value, options, error)) {
        return false;
      }
      options->has_expectation = true;
      continue;
    }
    if (argument == "--sdb-off" || argument == "--nvboard-off" ||
        argument == "--wave-off") {
      bool *seen = nullptr;
      bool *option = nullptr;
      if (argument == "--sdb-off") {
        seen = &saw_sdb_off;
        option = &options->sdb_off;
      } else if (argument == "--nvboard-off") {
        seen = &saw_nvboard_off;
        option = &options->nvboard_off;
      } else {
        seen = &saw_wave_off;
        option = &options->wave_off;
      }
      if (*seen) {
        *error = "duplicate option " + std::string(argument);
        return false;
      }
      *seen = true;
      *option = true;
      continue;
    }
    if (argument == "--test-dispatch") {
      if (saw_test_dispatch) {
        *error = "duplicate option --test-dispatch";
        return false;
      }
      options->test_dispatch = true;
      saw_test_dispatch = true;
      continue;
    }
    if (argument == "--diff-ref-so") {
      if (!take_value(argc, argv, &index, argument, &value, error)) {
        return false;
      }
      options->diff_ref_so_path = std::string(value);
      continue;
    }

    *error = "unknown argument '" + std::string(argument) + "'";
    return false;
  }

  if (!saw_inst_image) {
    *error = "missing required option --image";
    return false;
  }
  return true;
}


std::string hex_value(std::uint64_t value, int width) {
  std::ostringstream output;
  output << "0x" << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(width) << value;
  return output.str();
}

void print_state_summary(const dc_sim::ArchitecturalState &state) {
  std::cout << "summary commits=" << state.commits
            << " cycles=" << state.cycles
            << " pc=" << hex_value(state.fetch_pc, 8);
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    std::cout << " x" << index << "="
              << hex_value(state.registers[index], 8);
  }
  std::cout << '\n';
}

void print_trace(const dc_sim::StepEvent &event,
                 const dc_sim::ArchitecturalState &state) {
  std::cout << "cycle=" << state.cycles << " commit=" << state.commits
            << " pc=" << hex_value(event.commit_pc, 8)
            << " inst=" << hex_value(event.commit_inst, 8);
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    std::cout << " x" << index << "="
              << hex_value(state.registers[index], 8);
  }
  std::cout << '\n';
}

bool check_expectations(const Options &options,
                        const dc_sim::ArchitecturalState &state) {
  bool matches = true;
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    if (options.expected_registers[index].has_value() &&
        state.registers[index] != *options.expected_registers[index]) {
      std::cerr << "error: x" << index << " expected "
                << hex_value(*options.expected_registers[index], 8)
                << " but got " << hex_value(state.registers[index], 8)
                << '\n';
      matches = false;
    }
  }
  if (options.expected_pc.has_value() &&
      state.fetch_pc != *options.expected_pc) {
    std::cerr << "error: pc expected " << hex_value(*options.expected_pc, 8)
              << " but got " << hex_value(state.fetch_pc, 8) << '\n';
    matches = false;
  }
  return matches;
}

#ifdef CONFIG_DC_SIM_DIFFTEST
void print_difftest_mismatch(const dc_sim::DifftestMismatch &mismatch) {
  std::cerr << "error: difftest mismatch\n"
            << "  field : " << mismatch.field << '\n'
            << "  DUT   : " << hex_value(mismatch.dut_value, 8) << '\n'
            << "  REF   : " << hex_value(mismatch.ref_value, 8) << '\n'
            << "  pc    : " << hex_value(mismatch.pc, 8) << '\n'
            << "  inst  : " << hex_value(mismatch.inst, 8) << " asm=\""
            << dc_sim::disassemble(mismatch.inst) << "\"\n";

  if (!mismatch.has_register_snapshot) {
    return;
  }

  std::cerr << "  DUT registers:\n    ";
  for (std::size_t index = 0; index < mismatch.dut_registers.size(); ++index) {
    if ((index % 4U) != 0U) {
      std::cerr << ' ';
    }
    std::cerr << "x" << index << '=' << hex_value(mismatch.dut_registers[index], 8);
    if ((index % 4U) == 3U && index + 1U < mismatch.dut_registers.size()) {
      std::cerr << "\n    ";
    }
  }
  std::cerr << '\n';
}
#endif

}  // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::string_view(argv[1]) == "--help") {
    print_usage(std::cout);
    return kSuccess;
  }

  Options options;
  std::string error;
  if (!parse_options(argc, argv, &options, &error)) {
    std::cerr << "error: " << error << '\n';
    print_usage(std::cerr);
    return kInputError;
  }
#ifdef CONFIG_DC_SIM_SDB
  if (!options.sdb_off) {
    if (options.steps.has_value()) {
      std::cerr << "error: option --steps requires --sdb-off when SDB is enabled\n";
      return kInputError;
    }
    if (options.trace) {
      std::cerr << "error: option --trace requires --sdb-off when SDB is enabled\n";
      return kInputError;
    }
    if (options.has_expectation) {
      std::cerr << "error: option --expect requires --sdb-off when SDB is enabled\n";
      return kInputError;
    }
  }
#endif
  dc_sim::reset_memory();
  if (!dc_sim::load_image(options.inst_image_path, dc_sim::MemoryRegion::kIrom, options.format, &error)) {
    std::cerr << "error: " << error << '\n';
    return kInputError;
  }
  if (!options.data_image_path.empty()) {
    if (!dc_sim::load_image(options.data_image_path, dc_sim::MemoryRegion::kDram, options.format, &error)) {
      std::cerr << "error: " << error << '\n';
      return kInputError;
    }
  }


#ifdef CONFIG_DC_SIM_NVBOARD
  std::uint64_t max_cycles = options.nvboard_off ? 20000000U : 1000000000ULL;
#else
  std::uint64_t max_cycles = 20000000U;
#endif
  if (options.max_cycles.has_value()) {
    max_cycles = *options.max_cycles;
  }

  std::unique_ptr<dc_sim::Simulation> simulation;
  try {
    simulation = std::make_unique<dc_sim::Simulation>(
        argc, argv, !options.nvboard_off, !options.wave_off);
    simulation->reset();
  } catch (const std::exception &exception) {
    std::cerr << "error: " << exception.what() << '\n';
    return kInputError;
  }
  bool stopped_on_program_exit = false;
  std::uint32_t final_guest_exit_code = 0;

#ifdef CONFIG_DC_SIM_DIFFTEST
  std::unique_ptr<dc_sim::IRefBackend> ref_backend;
  std::string ref_so = options.diff_ref_so_path;
  if (ref_so.empty()) {
    const char *env_so = std::getenv("DIFF_REF_SO");
    if (env_so != nullptr && env_so[0] != '\0') {
      ref_so = env_so;
    }
  }

  if (!ref_so.empty()) {
    try {
      ref_backend = std::make_unique<dc_sim::DynamicRefBackend>(ref_so);
    } catch (const std::exception &e) {
      std::cerr << "error: failed to load dynamic reference model: " << e.what() << '\n';
      return kInputError;
    }
  } else {
    ref_backend = std::make_unique<dc_sim::ReferenceModel>();
  }

  dc_sim::Difftest difftest(*simulation, *ref_backend);
  difftest.sync_memory();
  dc_sim::DifftestMismatch mismatch;
  const dc_sim::StepObserver observer = [&](const dc_sim::RunResult &result) {
    return difftest.compare_result(result, &mismatch);
  };
#else
  const dc_sim::StepObserver observer;
#endif

#ifdef CONFIG_DC_SIM_SDB
  if (!options.sdb_off) {
    const dc_sim::RunResult result = dc_sim::run_sdb(
        *simulation, max_cycles, std::cin, std::cout, std::cerr, observer);
    if (result.reason == dc_sim::StopReason::monitor_failure) {
#ifdef CONFIG_DC_SIM_DIFFTEST
      print_difftest_mismatch(mismatch);
#endif
      return kStateMismatch;
    }
    if (result.reason == dc_sim::StopReason::fault) {
      return kFault;
    }
    if (result.reason == dc_sim::StopReason::program_exit) {
      return (result.event.guest_exit_code == 0) ? kSuccess : kGuestFailure;
    }
    if (result.reason == dc_sim::StopReason::timeout) {
      return kTimeout;
    }
    if (result.reason == dc_sim::StopReason::quit && options.test_dispatch) {
      return kUserQuit;
    }
    return kSuccess;
  }
#endif

  const std::uint64_t max_steps = options.steps.value_or(std::numeric_limits<std::uint64_t>::max());
  for (std::uint64_t step = 0; step < max_steps; ++step) {
    dc_sim::RunResult result;
    result = simulation->run_until(dc_sim::RunTarget::commits, 1,
                                   max_cycles, {}, observer);
    if (result.reason == dc_sim::StopReason::monitor_failure) {
#ifdef CONFIG_DC_SIM_DIFFTEST
      print_difftest_mismatch(mismatch);
#endif
      return kStateMismatch;
    }
    if (result.reason == dc_sim::StopReason::commits_complete) {
      if (options.trace) {
        print_trace(result.event, result.state);
      }
      if (options.steps.has_value() && step + 1 == *options.steps) {
        break;
      }
      continue;
    }
    if (result.reason == dc_sim::StopReason::program_exit) {
      if (options.trace && result.event.committed) {
        print_trace(result.event, result.state);
      }
      stopped_on_program_exit = true;
      final_guest_exit_code = result.event.guest_exit_code;
      break;
    }
    if (result.reason == dc_sim::StopReason::fault) {
      if (result.event.fault_inst_valid) {
        std::cerr << "error: " << dc_sim::fault_cause_string(result.event.fault_cause)
                  << " at pc=" << hex_value(result.event.fault_pc, 8)
                  << " inst=" << hex_value(result.event.fault_inst, 8) << '\n';
      } else {
        std::cerr << "error: " << dc_sim::fault_cause_string(result.event.fault_cause)
                  << " at pc=" << hex_value(result.event.fault_pc, 8) << '\n';
      }
      return kFault;
    }
    if (result.reason == dc_sim::StopReason::timeout) {
      std::cerr << "error: timeout after " << result.state.cycles
                << " cycles and " << result.state.commits << " commits\n";
      return kTimeout;
    }
  }

  const dc_sim::ArchitecturalState final_state = simulation->snapshot();
  print_state_summary(final_state);
  if (!check_expectations(options, final_state)) {
    return kStateMismatch;
  }
  if (stopped_on_program_exit) {
    if (final_guest_exit_code != 0) {
      std::cerr << "error: guest exit code: " << final_guest_exit_code << '\n';
      return kGuestFailure;
    }
    return kSuccess;
  }
  return kSuccess;
}
