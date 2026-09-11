#include "memory.h"
#include "numeric.h"
#include "simulation.h"
#ifdef CONFIG_DC_SIM_SDB
#include "sdb.h"
#endif

#include <array>
#include <cstdint>
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
constexpr int kIllegalInstruction = 2;
constexpr int kTimeout = 3;
constexpr int kStateMismatch = 4;

struct Options {
  std::string image_path;
  std::optional<std::uint64_t> steps;
  std::optional<std::uint64_t> max_cycles;
  bool trace = false;
  bool batch = false;
  bool has_expectation = false;
  std::array<std::optional<std::uint16_t>, 4> expected_registers;
  std::optional<std::uint8_t> expected_pc;
};

void print_usage(std::ostream &output) {
  output
      << "Usage: Vsim_top --image <path> [options]\n"
      << "  --image <path>              HEX instruction image (required)\n"
      << "  --steps <positive-u64>      Commits to execute (default: image words)\n"
      << "  --max-cycles <positive-u64> Execution cycles (default: steps+4)\n"
      << "  --trace                     Print one line per committed instruction\n"
      << "  --expect <name=value>       Check r0, r1, r2, r3, or pc\n"
      << "  --batch                     Use non-interactive batch execution\n"
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
    if (value > std::numeric_limits<std::uint8_t>::max()) {
      *error = "pc expectation is outside 0x00..0xff";
      return false;
    }
    options->expected_pc = static_cast<std::uint8_t>(value);
    return true;
  }

  if (name.size() == 2 && name[0] == 'r' && name[1] >= '0' &&
      name[1] <= '3') {
    const std::size_t register_index =
        static_cast<std::size_t>(name[1] - '0');
    if (options->expected_registers[register_index].has_value()) {
      *error = "duplicate expectation for " + std::string(name);
      return false;
    }
    if (value > std::numeric_limits<std::uint16_t>::max()) {
      *error = std::string(name) + " expectation is outside 0x0000..0xffff";
      return false;
    }
    options->expected_registers[register_index] =
        static_cast<std::uint16_t>(value);
    return true;
  }

  *error = "unknown expectation name '" + std::string(name) + "'";
  return false;
}

bool parse_options(int argc, char **argv, Options *options,
                   std::string *error) {
  bool saw_image = false;
  bool saw_steps = false;
  bool saw_max_cycles = false;
  bool saw_batch = false;

  for (int index = 1; index < argc; ++index) {
    const std::string_view argument = argv[index];
    std::string_view value;

    if (argument == "--help") {
      *error = "--help must be the only argument";
      return false;
    }
    if (argument == "--image") {
      if (saw_image) {
        *error = "duplicate option --image";
        return false;
      }
      if (!take_value(argc, argv, &index, argument, &value, error)) {
        return false;
      }
      if (value.empty()) {
        *error = "empty value for --image";
        return false;
      }
      options->image_path = value;
      saw_image = true;
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
    if (argument == "--batch") {
      if (saw_batch) {
        *error = "duplicate option --batch";
        return false;
      }
      options->batch = true;
      saw_batch = true;
      continue;
    }

    *error = "unknown argument '" + std::string(argument) + "'";
    return false;
  }

  if (!saw_image) {
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
            << " pc=" << hex_value(state.fetch_pc, 2);
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    std::cout << " r" << index << "="
              << hex_value(state.registers[index], 4);
  }
  std::cout << '\n';
}

void print_trace(const dc_sim::StepEvent &event,
                 const dc_sim::ArchitecturalState &state) {
  std::cout << "cycle=" << state.cycles << " commit=" << state.commits
            << " pc=" << hex_value(event.commit_pc, 2)
            << " inst=" << hex_value(event.commit_inst, 4);
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    std::cout << " r" << index << "="
              << hex_value(state.registers[index], 4);
  }
  std::cout << '\n';
}

bool check_expectations(const Options &options,
                        const dc_sim::ArchitecturalState &state) {
  bool matches = true;
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    if (options.expected_registers[index].has_value() &&
        state.registers[index] != *options.expected_registers[index]) {
      std::cerr << "error: r" << index << " expected "
                << hex_value(*options.expected_registers[index], 4)
                << " but got " << hex_value(state.registers[index], 4)
                << '\n';
      matches = false;
    }
  }
  if (options.expected_pc.has_value() &&
      state.fetch_pc != *options.expected_pc) {
    std::cerr << "error: pc expected " << hex_value(*options.expected_pc, 2)
              << " but got " << hex_value(state.fetch_pc, 2) << '\n';
    matches = false;
  }
  return matches;
}

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
  if (!options.batch) {
    if (options.steps.has_value()) {
      std::cerr << "error: option --steps requires --batch when SDB is enabled\n";
      return kInputError;
    }
    if (options.trace) {
      std::cerr << "error: option --trace requires --batch when SDB is enabled\n";
      return kInputError;
    }
    if (options.has_expectation) {
      std::cerr << "error: option --expect requires --batch when SDB is enabled\n";
      return kInputError;
    }
  }
#endif
  if (!dc_sim::load_hex_image(options.image_path, &error)) {
    std::cerr << "error: " << error << '\n';
    return kInputError;
  }

  const std::uint64_t image_words = dc_sim::image_word_count();
  const std::uint64_t steps = options.steps.value_or(image_words);
  std::uint64_t max_cycles = 0;
  if (options.max_cycles.has_value()) {
    max_cycles = *options.max_cycles;
  } else {
    const std::uint64_t default_base =
#ifdef CONFIG_DC_SIM_SDB
        options.batch ? steps : image_words;
#else
        steps;
#endif
    if (default_base > std::numeric_limits<std::uint64_t>::max() - 4U) {
      std::cerr << "error: default --max-cycles overflows steps+4\n";
      return kInputError;
    }
    max_cycles = default_base + 4U;
  }

  std::unique_ptr<dc_sim::Simulation> simulation;
  try {
    simulation = std::make_unique<dc_sim::Simulation>(argc, argv);
    simulation->reset();
  } catch (const std::exception &exception) {
    std::cerr << "error: " << exception.what() << '\n';
    return kInputError;
  }
#ifdef CONFIG_DC_SIM_SDB
  if (!options.batch) {
    const dc_sim::RunResult result = dc_sim::run_sdb(
        *simulation, max_cycles, std::cin, std::cout, std::cerr);
    if (result.reason == dc_sim::StopReason::illegal_instruction ||
        result.reason == dc_sim::StopReason::out_of_bounds_fetch) {
      return kIllegalInstruction;
    }
    if (result.reason == dc_sim::StopReason::timeout) {
      return kTimeout;
    }
    return kSuccess;
  }
#endif
  for (std::uint64_t step = 0; step < steps; ++step) {
    const dc_sim::RunResult result =
        simulation->step_instruction(max_cycles);
    if (result.reason == dc_sim::StopReason::commits_complete) {
      if (options.trace) {
        print_trace(result.event, result.state);
      }
      continue;
    }
    if (result.reason == dc_sim::StopReason::illegal_instruction ||
        result.reason == dc_sim::StopReason::out_of_bounds_fetch) {
      if (result.reason == dc_sim::StopReason::out_of_bounds_fetch) {
        std::cerr << "error: executed out-of-bounds instruction fetch at pc=";
      } else {
        std::cerr << "error: illegal instruction at pc=";
      }
      std::cerr << hex_value(result.state.fetch_pc, 2) << " inst="
                << hex_value(result.state.fetch_inst, 4) << '\n';
      return kIllegalInstruction;
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
  return kSuccess;
}
