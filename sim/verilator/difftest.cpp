#include "difftest.h"

#include <iomanip>
#include <iostream>
#include <sstream>

namespace dc_sim {
namespace {

std::string hex8(std::uint32_t val) {
  std::ostringstream oss;
  oss << "0x" << std::hex << std::setfill('0') << std::setw(8) << val;
  return oss.str();
}

}  // namespace

Difftest::Difftest(Simulation &dut, IRefBackend &ref)
    : dut_(dut), ref_(ref) {}

void Difftest::sync_memory() {
  ref_.load_from_sim_memory();
}

bool Difftest::step_and_compare(std::uint64_t max_cycles, DifftestMismatch *mismatch,
                                RunResult *out_dut_res) {
  const RunResult dut_res = dut_.step_instruction(max_cycles);
  if (out_dut_res != nullptr) {
    *out_dut_res = dut_res;
  }

  if (dut_res.reason == StopReason::timeout) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_res.state.cycles;
      mismatch->commit = dut_res.state.commits;
      mismatch->field = "timeout";
      mismatch->message = "DUT timed out before completing instruction step";
    }
    return false;
  }

  if (dut_res.event.is_skip_ref) {
    if (dut_res.event.commit_pc != ref_.pc()) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_res.state.cycles;
        mismatch->commit = dut_res.state.commits;
        mismatch->field = "commit_pc";
        mismatch->dut_value = dut_res.event.commit_pc;
        mismatch->ref_value = ref_.pc();
        mismatch->message = "commit_pc mismatch on skip_ref: DUT " + hex8(dut_res.event.commit_pc) +
                            " vs REF " + hex8(ref_.pc());
      }
      return false;
    }

    const std::uint32_t inst = dut_res.event.commit_inst;
    const std::uint32_t opcode = inst & 0x7fU;
    const std::uint32_t rd = (inst >> 7U) & 0x1fU;
    const ArchitecturalState &dut_state = dut_res.state;
    const std::uint32_t next_pc = dut_res.event.commit_pc + 4U;

    // Load instruction: opcode 0b0000011 (0x03)
    if (opcode == 0x03U) {
      ref_.skip_instruction(rd, dut_state.registers[rd], next_pc);
    } else {
      ref_.skip_instruction(0, 0, next_pc);
    }

    // Compare all 16 registers
    for (std::size_t i = 0; i < 16; ++i) {
      if (dut_state.registers[i] != ref_.reg(i)) {
        if (mismatch != nullptr) {
          mismatch->cycle = dut_state.cycles;
          mismatch->commit = dut_state.commits;
          mismatch->field = "x" + std::to_string(i);
          mismatch->dut_value = dut_state.registers[i];
          mismatch->ref_value = ref_.reg(i);
          mismatch->message = "Register x" + std::to_string(i) + " mismatch after skip_ref: DUT " +
                              hex8(dut_state.registers[i]) + " vs REF " + hex8(ref_.reg(i));
        }
        return false;
      }
    }

    // Compare next fetch PC
    if (dut_state.fetch_pc != next_pc) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_state.cycles;
        mismatch->commit = dut_state.commits;
        mismatch->field = "next_pc";
        mismatch->dut_value = dut_state.fetch_pc;
        mismatch->ref_value = next_pc;
        mismatch->message = "Next PC mismatch after skip_ref: DUT " + hex8(dut_state.fetch_pc) +
                            " vs REF " + hex8(next_pc);
      }
      return false;
    }

    last_tohost_exit_ = dut_res.event.tohost_exit;
    return true;
  }

  const ReferenceStepResult ref_res = ref_.step();

  if (dut_res.reason == StopReason::fault) {
    if (!ref_res.faulted) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_res.state.cycles;
        mismatch->commit = dut_res.state.commits;
        mismatch->field = "fault_occurrence";
        mismatch->dut_value = 1;
        mismatch->ref_value = 0;
        mismatch->message = "DUT faulted but reference model did not fault";
      }
      return false;
    }
    if (dut_res.event.fault_cause != ref_res.fault_cause) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_res.state.cycles;
        mismatch->commit = dut_res.state.commits;
        mismatch->field = "fault_cause";
        mismatch->dut_value = dut_res.event.fault_cause;
        mismatch->ref_value = ref_res.fault_cause;
        mismatch->message = "DUT fault_cause mismatch: " +
                            std::string(fault_cause_string(dut_res.event.fault_cause)) +
                            " vs REF " +
                            std::string(fault_cause_string(ref_res.fault_cause));
      }
      return false;
    }
    if (dut_res.event.fault_pc != ref_res.fault_pc) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_res.state.cycles;
        mismatch->commit = dut_res.state.commits;
        mismatch->field = "fault_pc";
        mismatch->dut_value = dut_res.event.fault_pc;
        mismatch->ref_value = ref_res.fault_pc;
        mismatch->message = "DUT fault_pc mismatch: " + hex8(dut_res.event.fault_pc) +
                            " vs REF " + hex8(ref_res.fault_pc);
      }
      return false;
    }
    return true;
  }

  // If not fault, both should have committed
  if (ref_res.faulted) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_res.state.cycles;
      mismatch->commit = dut_res.state.commits;
      mismatch->field = "fault_occurrence";
      mismatch->dut_value = 0;
      mismatch->ref_value = 1;
      mismatch->message = "Reference model faulted but DUT did not fault";
    }
    return false;
  }

  if (dut_res.event.commit_pc != ref_res.commit_pc) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_res.state.cycles;
      mismatch->commit = dut_res.state.commits;
      mismatch->field = "commit_pc";
      mismatch->dut_value = dut_res.event.commit_pc;
      mismatch->ref_value = ref_res.commit_pc;
      mismatch->message = "commit_pc mismatch: DUT " + hex8(dut_res.event.commit_pc) +
                          " vs REF " + hex8(ref_res.commit_pc);
    }
    return false;
  }

  if (dut_res.event.commit_inst != ref_res.commit_inst) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_res.state.cycles;
      mismatch->commit = dut_res.state.commits;
      mismatch->field = "commit_inst";
      mismatch->dut_value = dut_res.event.commit_inst;
      mismatch->ref_value = ref_res.commit_inst;
      mismatch->message = "commit_inst mismatch: DUT " + hex8(dut_res.event.commit_inst) +
                          " vs REF " + hex8(ref_res.commit_inst);
    }
    return false;
  }

  // Compare all 16 registers
  const ArchitecturalState &dut_state = dut_res.state;
  for (std::size_t i = 0; i < 16; ++i) {
    if (dut_state.registers[i] != ref_.reg(i)) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_state.cycles;
        mismatch->commit = dut_state.commits;
        mismatch->field = "x" + std::to_string(i);
        mismatch->dut_value = dut_state.registers[i];
        mismatch->ref_value = ref_.reg(i);
        mismatch->message = "Register x" + std::to_string(i) + " mismatch: DUT " +
                            hex8(dut_state.registers[i]) + " vs REF " + hex8(ref_.reg(i));
      }
      return false;
    }
  }

  // Check program exit (tohost) first: once program exits, verification terminates successfully
  if (dut_res.event.tohost_exit) {
    last_tohost_exit_ = true;
    if (ref_res.tohost_exit &&
        dut_res.event.guest_exit_code != ref_res.guest_exit_code) {
      if (mismatch != nullptr) {
        mismatch->cycle = dut_state.cycles;
        mismatch->commit = dut_state.commits;
        mismatch->field = "guest_exit_code";
        mismatch->dut_value = dut_res.event.guest_exit_code;
        mismatch->ref_value = ref_res.guest_exit_code;
        mismatch->message = "guest_exit_code mismatch: DUT " +
                            hex8(dut_res.event.guest_exit_code) + " vs REF " +
                            hex8(ref_res.guest_exit_code);
      }
      return false;
    }
    return true;
  }

  // Compare next fetch PC
  if (dut_state.fetch_pc != ref_res.next_pc) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_state.cycles;
      mismatch->commit = dut_state.commits;
      mismatch->field = "next_pc";
      mismatch->dut_value = dut_state.fetch_pc;
      mismatch->ref_value = ref_res.next_pc;
      mismatch->message = "Next PC mismatch: DUT " + hex8(dut_state.fetch_pc) +
                          " vs REF " + hex8(ref_res.next_pc);
    }
    return false;
  }

  last_tohost_exit_ = false;
  return true;
}

bool Difftest::run_difftest(std::uint64_t max_commits, std::uint64_t max_cycles,
                            DifftestMismatch *mismatch) {
  sync_memory();
  last_tohost_exit_ = false;
  for (std::uint64_t commit = 0; commit < max_commits; ++commit) {
    if (!step_and_compare(max_cycles, mismatch)) {
      return false;
    }
    if (dut_.snapshot().fetch_pc == ref_.pc() && ref_.in_fault()) {
      break;
    }
    if (last_tohost_exit_) {
      break;
    }
  }
  return true;
}

}  // namespace dc_sim
