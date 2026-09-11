#include "difftest.h"

#include <iomanip>
#include <sstream>

namespace dc_sim {
namespace {

std::string hex8(std::uint32_t val) {
  std::ostringstream oss;
  oss << "0x" << std::hex << std::setfill('0') << std::setw(8) << val;
  return oss.str();
}

}  // namespace

Difftest::Difftest(Simulation &dut, ReferenceModel &ref)
    : dut_(dut), ref_(ref) {}

void Difftest::sync_memory() {
  ref_.load_from_sim_memory();
}

bool Difftest::step_and_compare(std::uint64_t max_cycles, DifftestMismatch *mismatch) {
  const RunResult dut_res = dut_.step_instruction(max_cycles);

  if (dut_res.reason == StopReason::timeout) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_res.state.cycles;
      mismatch->commit = dut_res.state.commits;
      mismatch->field = "timeout";
      mismatch->message = "DUT timed out before completing instruction step";
    }
    return false;
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

  // Compare tohost exit
  if (dut_res.event.tohost_exit != ref_res.tohost_exit) {
    if (mismatch != nullptr) {
      mismatch->cycle = dut_state.cycles;
      mismatch->commit = dut_state.commits;
      mismatch->field = "tohost_exit";
      mismatch->dut_value = dut_res.event.tohost_exit ? 1 : 0;
      mismatch->ref_value = ref_res.tohost_exit ? 1 : 0;
      mismatch->message = "tohost_exit flag mismatch";
    }
    return false;
  }

  if (dut_res.event.tohost_exit &&
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

bool Difftest::run_difftest(std::uint64_t max_commits, std::uint64_t max_cycles,
                            DifftestMismatch *mismatch) {
  sync_memory();
  for (std::uint64_t commit = 0; commit < max_commits; ++commit) {
    if (!step_and_compare(max_cycles, mismatch)) {
      return false;
    }
    if (dut_.snapshot().fetch_pc == ref_.pc() && ref_.in_fault()) {
      break;
    }
  }
  return true;
}

}  // namespace dc_sim
