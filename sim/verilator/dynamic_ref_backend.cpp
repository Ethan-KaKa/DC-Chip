#include "dynamic_ref_backend.h"
#include "memory.h"

#include <dlfcn.h>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace dc_sim {

DynamicRefBackend::DynamicRefBackend(const std::string &so_path)
    : backend_name_("dynamic:" + so_path) {
  handle_ = dlopen(so_path.c_str(), RTLD_NOW | RTLD_GLOBAL);
  if (handle_ == nullptr) {
    throw std::runtime_error("DynamicRefBackend: failed to dlopen " + so_path +
                             ": " + dlerror());
  }

  ref_init_ = reinterpret_cast<void (*)(int)>(dlsym(handle_, "difftest_init"));
  ref_memcpy_ = reinterpret_cast<void (*)(std::uint32_t, void *, std::size_t, bool)>(
      dlsym(handle_, "difftest_memcpy"));
  ref_regcpy_ = reinterpret_cast<void (*)(std::uint32_t *, std::uint32_t *, bool)>(
      dlsym(handle_, "difftest_regcpy"));
  ref_exec_ = reinterpret_cast<void (*)(std::uint64_t)>(
      dlsym(handle_, "difftest_exec"));
  ref_raise_intr_ = reinterpret_cast<void (*)(std::uint64_t)>(
      dlsym(handle_, "difftest_raise_intr"));

  if (!ref_init_ || !ref_memcpy_ || !ref_regcpy_ || !ref_exec_) {
    dlclose(handle_);
    handle_ = nullptr;
    throw std::runtime_error("DynamicRefBackend: required symbols missing in " +
                             so_path);
  }

  reset(0);
}

DynamicRefBackend::~DynamicRefBackend() {
  // Keep handle loaded across test cases to preserve simulator static runtime
}

void DynamicRefBackend::reset(std::uint32_t reset_pc) {
  pc_ = reset_pc;
  regs_.fill(0);
  in_fault_ = false;
  fault_cause_ = 0;
  fault_pc_ = 0;

  if (ref_init_ != nullptr) {
    ref_init_(0);
  }
  if (ref_regcpy_ != nullptr) {
    ref_regcpy_(&pc_, regs_.data(), true /* DIFFTEST_TO_REF */);
  }
}

void DynamicRefBackend::load_irom(const std::vector<std::uint32_t> &words) {
  if (ref_memcpy_ == nullptr) return;
  std::vector<std::uint8_t> buf(kIromCapacityBytes, 0);
  const std::size_t count = std::min(words.size(), kIromCapacityWords);
  for (std::size_t i = 0; i < count; ++i) {
    const std::uint32_t w = words[i];
    buf[i * 4 + 0] = static_cast<std::uint8_t>(w & 0xffU);
    buf[i * 4 + 1] = static_cast<std::uint8_t>((w >> 8U) & 0xffU);
    buf[i * 4 + 2] = static_cast<std::uint8_t>((w >> 16U) & 0xffU);
    buf[i * 4 + 3] = static_cast<std::uint8_t>((w >> 24U) & 0xffU);
  }
  ref_memcpy_(kIromBase, buf.data(), buf.size(), true /* DIFFTEST_TO_REF */);
}

void DynamicRefBackend::load_from_sim_memory() {
  if (ref_memcpy_ == nullptr) return;

  std::vector<std::uint8_t> irom_buf(kIromCapacityBytes, 0);
  for (std::size_t i = 0; i < kIromCapacityWords; ++i) {
    const std::uint32_t w = ::dc_sim::read_irom_word(i);
    irom_buf[i * 4 + 0] = static_cast<std::uint8_t>(w & 0xffU);
    irom_buf[i * 4 + 1] = static_cast<std::uint8_t>((w >> 8U) & 0xffU);
    irom_buf[i * 4 + 2] = static_cast<std::uint8_t>((w >> 16U) & 0xffU);
    irom_buf[i * 4 + 3] = static_cast<std::uint8_t>((w >> 24U) & 0xffU);
  }
  ref_memcpy_(kIromBase, irom_buf.data(), irom_buf.size(), true);

  std::vector<std::uint8_t> dram_buf(kDramCapacityBytes, 0);
  for (std::size_t i = 0; i < kDramCapacityWords; ++i) {
    const std::uint32_t w = ::dc_sim::read_dram_word(i);
    dram_buf[i * 4 + 0] = static_cast<std::uint8_t>(w & 0xffU);
    dram_buf[i * 4 + 1] = static_cast<std::uint8_t>((w >> 8U) & 0xffU);
    dram_buf[i * 4 + 2] = static_cast<std::uint8_t>((w >> 16U) & 0xffU);
    dram_buf[i * 4 + 3] = static_cast<std::uint8_t>((w >> 24U) & 0xffU);
  }
  ref_memcpy_(kDramBase, dram_buf.data(), dram_buf.size(), true);
}

void DynamicRefBackend::set_pc(std::uint32_t val) {
  pc_ = val;
  if (ref_regcpy_ != nullptr) {
    ref_regcpy_(&pc_, regs_.data(), true);
  }
}

void DynamicRefBackend::set_reg(std::size_t index, std::uint32_t val) {
  if (index > 0 && index < 16) {
    regs_[index] = val;
    if (ref_regcpy_ != nullptr) {
      ref_regcpy_(&pc_, regs_.data(), true);
    }
  }
}

void DynamicRefBackend::skip_instruction(std::uint32_t rd, std::uint32_t dut_rd_val,
                                         std::uint32_t next_pc) {
  if (rd > 0 && rd < 16) {
    regs_[rd] = dut_rd_val;
  }
  pc_ = next_pc;
  if (ref_regcpy_ != nullptr) {
    ref_regcpy_(&pc_, regs_.data(), true /* DIFFTEST_TO_REF */);
  }
}

RefStepResult DynamicRefBackend::step() {
  RefStepResult res;
  const std::uint32_t current_pc = pc_;

  if (current_pc < kIromCapacityBytes) {
    res.commit_inst = ::dc_sim::read_irom_word(current_pc / 4);
  }

  if (ref_exec_ != nullptr) {
    ref_exec_(1);
  }
  if (ref_regcpy_ != nullptr) {
    ref_regcpy_(&pc_, regs_.data(), false /* DIFFTEST_TO_DUT */);
  }

  res.committed = true;
  res.commit_pc = current_pc;
  res.next_pc = pc_;
  return res;
}

}  // namespace dc_sim
