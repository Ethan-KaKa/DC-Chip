#include "Vsim_top.h"
#include "memory.h"
#include "verilated.h"

#include <array>
#include <charconv>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>

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
      << "  --help                      Show this help (must be the only option)\n";
}

bool parse_unsigned(std::string_view text, std::uint64_t *value) {
  if (text.empty()) {
    return false;
  }

  int base = 10;
  if (text.size() >= 2 && text[0] == '0' &&
      (text[1] == 'x' || text[1] == 'X')) {
    base = 16;
    text.remove_prefix(2);
    if (text.empty()) {
      return false;
    }
  }

  for (char character : text) {
    const bool decimal_digit = character >= '0' && character <= '9';
    const bool lowercase_hex = character >= 'a' && character <= 'f';
    const bool uppercase_hex = character >= 'A' && character <= 'F';
    if (!decimal_digit &&
        (base != 16 || (!lowercase_hex && !uppercase_hex))) {
      return false;
    }
  }

  std::uint64_t parsed = 0;
  const auto result =
      std::from_chars(text.data(), text.data() + text.size(), parsed, base);
  if (result.ec != std::errc() || result.ptr != text.data() + text.size()) {
    return false;
  }
  *value = parsed;
  return true;
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
  if (!parse_unsigned(value_text, &value)) {
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
      if (!parse_unsigned(value, &parsed) || parsed == 0) {
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

std::array<std::uint16_t, 4> read_registers(const Vsim_top &top) {
  const std::uint64_t packed = top.debug_regs;
  std::array<std::uint16_t, 4> registers{};
  for (std::size_t index = 0; index < registers.size(); ++index) {
    registers[index] =
        static_cast<std::uint16_t>((packed >> (index * 16U)) & 0xffffU);
  }
  return registers;
}

void print_state_summary(std::uint64_t commits, std::uint64_t cycles,
                         const Vsim_top &top) {
  const auto registers = read_registers(top);
  std::cout << "summary commits=" << commits << " cycles=" << cycles
            << " pc=" << hex_value(top.fetch_pc, 2);
  for (std::size_t index = 0; index < registers.size(); ++index) {
    std::cout << " r" << index << "=" << hex_value(registers[index], 4);
  }
  std::cout << '\n';
}

void print_trace(std::uint64_t cycle, std::uint64_t commit,
                 const Vsim_top &top) {
  const auto registers = read_registers(top);
  std::cout << "cycle=" << cycle << " commit=" << commit
            << " pc=" << hex_value(top.trace_pc, 2)
            << " inst=" << hex_value(top.trace_inst, 4);
  for (std::size_t index = 0; index < registers.size(); ++index) {
    std::cout << " r" << index << "=" << hex_value(registers[index], 4);
  }
  std::cout << '\n';
}

bool check_expectations(const Options &options, const Vsim_top &top) {
  bool matches = true;
  const auto registers = read_registers(top);
  for (std::size_t index = 0; index < registers.size(); ++index) {
    if (options.expected_registers[index].has_value() &&
        registers[index] != *options.expected_registers[index]) {
      std::cerr << "error: r" << index << " expected "
                << hex_value(*options.expected_registers[index], 4)
                << " but got " << hex_value(registers[index], 4) << '\n';
      matches = false;
    }
  }
  if (options.expected_pc.has_value() &&
      top.fetch_pc != *options.expected_pc) {
    std::cerr << "error: pc expected " << hex_value(*options.expected_pc, 2)
              << " but got " << hex_value(top.fetch_pc, 2) << '\n';
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
  if (!dc_sim::load_hex_image(options.image_path, &error)) {
    std::cerr << "error: " << error << '\n';
    return kInputError;
  }

  const std::uint64_t steps =
      options.steps.value_or(dc_sim::image_word_count());
  std::uint64_t max_cycles = 0;
  if (options.max_cycles.has_value()) {
    max_cycles = *options.max_cycles;
  } else {
    if (steps > std::numeric_limits<std::uint64_t>::max() - 4U) {
      std::cerr << "error: default --max-cycles overflows steps+4\n";
      return kInputError;
    }
    max_cycles = steps + 4U;
  }

  auto context = std::make_unique<VerilatedContext>();
  context->commandArgs(argc, argv);
  auto top = std::make_unique<Vsim_top>(context.get());
  const auto finish = [&](int exit_code) {
    top->final();
    return exit_code;
  };

  top->clk = 0;
  top->rst = 1;
  top->eval();
  for (int reset_cycle = 0; reset_cycle < 2; ++reset_cycle) {
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
  }
  top->clk = 0;
  top->rst = 0;
  top->eval();
  dc_sim::clear_fetch_status();

  std::uint64_t commits = 0;
  std::uint64_t cycles = 0;
  while (true) {
    top->clk = 1;
    top->eval();
    ++cycles;

    if (top->trace_valid != 0) {
      ++commits;
      if (options.trace) {
        print_trace(cycles, commits, *top);
      }
    }

    if (commits == steps) {
      print_state_summary(commits, cycles, *top);
      if (!check_expectations(options, *top)) {
        return finish(kStateMismatch);
      }
      return finish(kSuccess);
    }

    if (top->illegal_inst != 0) {
      if (dc_sim::fetch_out_of_bounds() &&
          dc_sim::first_oob_address() == top->fetch_pc) {
        std::cerr << "error: executed out-of-bounds instruction fetch at pc="
                  << hex_value(top->fetch_pc, 2) << " inst="
                  << hex_value(top->fetch_inst, 4) << '\n';
      } else {
        std::cerr << "error: illegal instruction at pc="
                  << hex_value(top->fetch_pc, 2) << " inst="
                  << hex_value(top->fetch_inst, 4) << '\n';
      }
      return finish(kIllegalInstruction);
    }

    if (cycles == max_cycles) {
      std::cerr << "error: timeout after " << cycles << " cycles and "
                << commits << " commits\n";
      return finish(kTimeout);
    }

    top->clk = 0;
    top->eval();
  }
}
