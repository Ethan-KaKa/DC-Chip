#include "sdb.h"

#include "disasm.h"
#include "numeric.h"

#include <iomanip>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace dc_sim {
namespace {

std::string hex_value(std::uint64_t value, int width) {
  std::ostringstream output;
  output << "0x" << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(width) << value;
  return output.str();
}

void print_help(std::ostream &output) {
  output << "help                 Show this help\n"
         << "q                    Quit the debugger\n"
         << "c                    Continue execution\n"
         << "si [N]               Step N committed instructions (default 1)\n"
         << "sc [N]               Step N cycles (default 1)\n"
         << "b <pc>               Set an execution-before breakpoint\n"
         << "d <id>               Delete a breakpoint\n"
         << "info r               Show registers and current instruction\n"
         << "info b               Show breakpoints\n";
#ifdef CONFIG_DC_SIM_WAVE
  output << "info wave            Show waveform state\n"
         << "wave on              Resume waveform recording\n"
         << "wave off             Pause waveform recording\n";
#endif
}

void print_state(const ArchitecturalState &state, std::ostream &output) {
  output << "state pc=" << hex_value(state.fetch_pc, 8)
         << " inst=" << hex_value(state.fetch_inst, 8) << " asm=\""
         << disassemble(state.fetch_inst) << '"';
  for (std::size_t index = 0; index < state.registers.size(); ++index) {
    output << " x" << index << '=' << hex_value(state.registers[index], 8);
  }
  output << " cycles=" << state.cycles << " commits=" << state.commits
         << " time=" << state.time << '\n';
}

void print_commit(const StepEvent &event, std::ostream &output) {
  output << "commit pc=" << hex_value(event.commit_pc, 8)
         << " inst=" << hex_value(event.commit_inst, 8) << " asm=\""
         << disassemble(event.commit_inst) << "\"\n";
}

std::string stop_text(const RunResult &result) {
  switch (result.reason) {
    case StopReason::cycles_complete:
      return "cycles complete";
    case StopReason::commits_complete:
      return "commits complete";
    case StopReason::program_exit:
      return "program exit (code " + std::to_string(result.event.guest_exit_code) + ")";
    case StopReason::fault:
      return fault_cause_string(result.event.fault_cause);
    case StopReason::timeout:
      return "timeout";
    case StopReason::monitor_failure:
      return "execution monitor failure";
    case StopReason::breakpoint:
      return "breakpoint";
    case StopReason::quit:
      return "quit";
  }
  return "unknown";
}

void print_terminal_error(const RunResult &result, std::ostream &errors) {
  if (result.reason == StopReason::fault) {
    if (result.event.fault_inst_valid) {
      errors << "error: " << fault_cause_string(result.event.fault_cause)
             << " at pc=" << hex_value(result.event.fault_pc, 8)
             << " inst=" << hex_value(result.event.fault_inst, 8) << '\n';
    } else {
      errors << "error: " << fault_cause_string(result.event.fault_cause)
             << " at pc=" << hex_value(result.event.fault_pc, 8) << '\n';
    }
  } else if (result.reason == StopReason::program_exit) {
    if (result.event.guest_exit_code != 0) {
      errors << "error: guest exit code: " << result.event.guest_exit_code << '\n';
    }
  } else if (result.reason == StopReason::timeout) {
    errors << "error: timeout after " << result.state.cycles
           << " cycles and " << result.state.commits << " commits\n";
  }
}

bool parse_positive(std::string_view text, std::string_view type,
                    std::uint64_t *value, std::ostream &errors) {
  if (!parse_unsigned(text, value) || *value == 0) {
    errors << "error: invalid positive " << type << " '" << text << "'\n";
    return false;
  }
  return true;
}

class Debugger {
 public:
  Debugger(Simulation &simulation, std::uint64_t max_cycles,
           std::istream &input, std::ostream &output, std::ostream &errors,
           const StepObserver &observer)
      : simulation_(simulation),
        max_cycles_(max_cycles),
        input_(input),
        output_(output),
        errors_(errors),
        observer_(observer) {}

  RunResult run() {
    std::string line;
    while (true) {
      output_ << "(dc-sdb) " << std::flush;
      if (!std::getline(input_, line)) {
        return quit_result();
      }

      const std::vector<std::string> words = split(line);
      if (words.empty()) {
        continue;
      }
      const std::string &command = words.front();
      if (command == "help") {
        if (!require_size(words, 1, "help")) {
          continue;
        }
        print_help(output_);
      } else if (command == "q") {
        if (!require_size(words, 1, "q")) {
          continue;
        }
        return quit_result();
      } else if (command == "c") {
        if (!require_size(words, 1, "c")) {
          continue;
        }
        const std::optional<RunResult> result = execute(RunTarget::none, 0);
        if (result.has_value()) {
          return *result;
        }
      } else if (command == "si" || command == "sc") {
        if (words.size() > 2) {
          usage(command + " [N]");
          continue;
        }
        std::uint64_t count = 1;
        if (words.size() == 2 &&
            !parse_positive(words[1], "step count", &count, errors_)) {
          continue;
        }
        const RunTarget target = command == "si" ? RunTarget::commits
                                                 : RunTarget::cycles;
        const std::optional<RunResult> result = execute(target, count);
        if (result.has_value()) {
          return *result;
        }
      } else if (command == "b") {
        set_breakpoint(words);
      } else if (command == "d") {
        delete_breakpoint(words);
      } else if (command == "info") {
        show_info(words);
#ifdef CONFIG_DC_SIM_WAVE
      } else if (command == "wave") {
        set_wave(words);
#endif
      } else {
        errors_ << "error: unknown command '" << command << "'\n";
      }
    }
  }

 private:
  static std::vector<std::string> split(const std::string &line) {
    std::istringstream input(line);
    std::vector<std::string> words;
    std::string word;
    while (input >> word) {
      words.push_back(word);
    }
    return words;
  }

  RunResult quit_result() const {
    return {StopReason::quit, {}, simulation_.snapshot()};
  }

  void usage(const std::string &syntax) {
    errors_ << "error: usage: " << syntax << '\n';
  }

  bool require_size(const std::vector<std::string> &words,
                    std::size_t expected, const std::string &syntax) {
    if (words.size() == expected) {
      return true;
    }
    usage(syntax);
    return false;
  }

  std::set<std::uint32_t> active_breakpoints() const {
    std::set<std::uint32_t> result;
    for (const auto &[pc, id] : breakpoint_ids_) {
      static_cast<void>(id);
      if (!suppressed_pc_.has_value() || pc != *suppressed_pc_) {
        result.insert(pc);
      }
    }
    return result;
  }

  std::optional<RunResult> execute(RunTarget target, std::uint64_t count) {
    const ArchitecturalState start = simulation_.snapshot();
    RunResult result;
    while (true) {
      result = simulation_.run_until(RunTarget::cycles, 1, max_cycles_,
                                     active_breakpoints(), observer_);
      if (result.reason == StopReason::breakpoint) {
        const auto found = breakpoint_ids_.find(result.state.fetch_pc);
        if (found == breakpoint_ids_.end()) {
          errors_ << "error: internal breakpoint lookup failed\n";
          return RunResult{StopReason::quit, {}, result.state};
        }
        suppressed_pc_ = result.state.fetch_pc;
        output_ << "stopped: breakpoint id=" << found->second << '\n';
        print_state(result.state, output_);
        return std::nullopt;
      }

      if (result.event.committed && suppressed_pc_.has_value() &&
          result.event.commit_pc == *suppressed_pc_) {
        suppressed_pc_.reset();
      }

      if (result.reason == StopReason::program_exit ||
          result.reason == StopReason::fault ||
          result.reason == StopReason::timeout ||
          result.reason == StopReason::monitor_failure) {
        output_ << "stopped: " << stop_text(result) << '\n';
        print_state(result.state, output_);
        print_terminal_error(result, errors_);
        return result;
      }

      bool complete = false;
      if (target == RunTarget::cycles) {
        complete = result.state.cycles - start.cycles >= count;
      } else if (target == RunTarget::commits) {
        complete = result.state.commits - start.commits >= count;
      }
      if (complete) {
        const StopReason reason = target == RunTarget::cycles
                                      ? StopReason::cycles_complete
                                      : StopReason::commits_complete;
        output_ << "stopped: " << (reason == StopReason::cycles_complete ? "cycles complete" : "commits complete") << '\n';
        if (result.event.committed) {
          print_commit(result.event, output_);
        }
        print_state(result.state, output_);
        break;
      }
    }
    return std::nullopt;
  }

  void set_breakpoint(const std::vector<std::string> &words) {
    if (!require_size(words, 2, "b <pc>")) {
      return;
    }
    std::uint64_t parsed = 0;
    if (!parse_unsigned(words[1], &parsed)) {
      errors_ << "error: invalid pc '" << words[1] << "'\n";
      return;
    }
    if (parsed > 0xffffffffULL) {
      errors_ << "error: pc '" << words[1] << "' is outside 0..0xffffffff\n";
      return;
    }
    if ((parsed & 3ULL) != 0) {
      errors_ << "error: pc '" << words[1] << "' is not 4-byte aligned\n";
      return;
    }
    const std::uint32_t pc = static_cast<std::uint32_t>(parsed);
    const auto existing = breakpoint_ids_.find(pc);
    if (existing != breakpoint_ids_.end()) {
      output_ << "breakpoint id=" << existing->second
              << " already set at pc=" << hex_value(pc, 8) << '\n';
      return;
    }
    const std::uint64_t id = next_breakpoint_id_++;
    breakpoints_.emplace(id, pc);
    breakpoint_ids_.emplace(pc, id);
    output_ << "breakpoint id=" << id << " set at pc=" << hex_value(pc, 8)
            << '\n';
  }

  void delete_breakpoint(const std::vector<std::string> &words) {
    if (!require_size(words, 2, "d <id>")) {
      return;
    }
    std::uint64_t id = 0;
    if (!parse_positive(words[1], "breakpoint id", &id, errors_)) {
      return;
    }
    const auto found = breakpoints_.find(id);
    if (found == breakpoints_.end()) {
      errors_ << "error: breakpoint id=" << id << " not found\n";
      return;
    }
    const std::uint32_t pc = found->second;
    breakpoint_ids_.erase(pc);
    breakpoints_.erase(found);
    if (suppressed_pc_.has_value() && *suppressed_pc_ == pc) {
      suppressed_pc_.reset();
    }
    output_ << "breakpoint id=" << id << " deleted\n";
  }

  void show_info(const std::vector<std::string> &words) {
    if (words.size() != 2) {
      usage("info r|b"
#ifdef CONFIG_DC_SIM_WAVE
            "|wave"
#endif
      );
      return;
    }
    if (words[1] == "r") {
      print_state(simulation_.snapshot(), output_);
      return;
    }
    if (words[1] == "b") {
      if (breakpoints_.empty()) {
        output_ << "no breakpoints\n";
      } else {
        for (const auto &[id, pc] : breakpoints_) {
          output_ << "breakpoint id=" << id << " pc=" << hex_value(pc, 8)
                  << '\n';
        }
      }
      return;
    }
#ifdef CONFIG_DC_SIM_WAVE
    if (words[1] == "wave") {
      print_wave();
      return;
    }
#endif
    errors_ << "error: unknown info target '" << words[1] << "'\n";
  }

#ifdef CONFIG_DC_SIM_WAVE
  void print_wave() {
    output_ << "wave=" << (simulation_.wave_enabled() ? "on" : "off")
            << " path=" << simulation_.wave_path()
            << " time=" << simulation_.snapshot().time << '\n';
  }

  void set_wave(const std::vector<std::string> &words) {
    if (!require_size(words, 2, "wave on|off")) {
      return;
    }
    if (words[1] != "on" && words[1] != "off") {
      usage("wave on|off");
      return;
    }
    simulation_.set_wave_enabled(words[1] == "on");
    print_wave();
  }
#endif

  Simulation &simulation_;
  std::uint64_t max_cycles_;
  std::istream &input_;
  std::ostream &output_;
  std::ostream &errors_;
  const StepObserver &observer_;
  std::map<std::uint64_t, std::uint32_t> breakpoints_;
  std::unordered_map<std::uint32_t, std::uint64_t> breakpoint_ids_;
  std::optional<std::uint32_t> suppressed_pc_;
  std::uint64_t next_breakpoint_id_ = 1;
};

}  // namespace

RunResult run_sdb(Simulation &simulation, std::uint64_t max_cycles,
                  std::istream &input, std::ostream &output,
                  std::ostream &errors, const StepObserver &observer) {
  return Debugger(simulation, max_cycles, input, output, errors, observer).run();
}

}  // namespace dc_sim
