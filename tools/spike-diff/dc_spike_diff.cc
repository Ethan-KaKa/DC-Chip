#include <sys/syscall.h>
#include <unistd.h>
#include "config.h"

#include "riscv/cfg.h"
#include "riscv/mmu.h"
#include "riscv/processor.h"
#include "riscv/sim.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>

#define DIFFTEST_TO_REF true
#define DIFFTEST_TO_DUT false

#define DC_NR_GPR 16
#define DC_IROM_BASE 0x00000000ULL
#define DC_IROM_SIZE 0x00010000ULL  // 64 KiB
#define DC_DRAM_BASE 0x20000000ULL
#define DC_DRAM_SIZE 0x00010000ULL  // 64 KiB

static sim_t *s = nullptr;
static processor_t *p = nullptr;
static state_t *state = nullptr;

static std::vector<std::pair<reg_t, abstract_mem_t*>> spike_mems;
static std::vector<device_factory_sargs_t> spike_plugin_devices;
static std::vector<std::string> spike_htif_args;
static debug_module_config_t spike_dm_config = {
  .progbufsize = 2,
  .max_sba_data_width = 0,
  .require_authentication = false,
  .abstract_rti = 0,
  .support_hasel = true,
  .support_abstract_csr_access = true,
  .support_abstract_fpr_access = false,
  .support_haltgroups = true,
  .support_impebreak = true
};

static cfg_t spike_cfg;

extern "C" {

void difftest_memcpy(uint32_t addr, void *buf, size_t n, bool direction) {
  if (spike_mems.empty()) return;
  uint8_t *ptr = static_cast<uint8_t*>(buf);
  for (auto &pair : spike_mems) {
    reg_t base = pair.first;
    reg_t size = pair.second->size();
    if (addr >= base && addr < base + size) {
      size_t offset = addr - base;
      size_t count = std::min(n, size_t(size - offset));
      if (direction == DIFFTEST_TO_REF) {
        pair.second->store(offset, count, ptr);
      } else {
        pair.second->load(offset, count, ptr);
      }
      if (count < n) {
        difftest_memcpy(addr + count, ptr + count, n - count, direction);
      }
      return;
    }
  }
}

void difftest_regcpy(uint32_t *pc, uint32_t *regs, bool direction) {
  if (state == nullptr) return;
  if (direction == DIFFTEST_TO_REF) {
    if (regs != nullptr) {
      for (int i = 0; i < DC_NR_GPR; ++i) {
        state->XPR.write(i, static_cast<reg_t>(regs[i]));
      }
    }
    if (pc != nullptr) {
      state->pc = static_cast<reg_t>(*pc);
    }
  } else {
    if (regs != nullptr) {
      for (int i = 0; i < DC_NR_GPR; ++i) {
        regs[i] = static_cast<uint32_t>(state->XPR[i]);
      }
    }
    if (pc != nullptr) {
      *pc = static_cast<uint32_t>(state->pc);
    }
  }
}

void difftest_exec(uint64_t n) {
  if (p == nullptr) return;
  p->step(n);
}

void difftest_raise_intr(uint64_t NO) {
  (void)NO;
}

void difftest_init(int port) {
  (void)port;
  if (s != nullptr) {
    p->reset();
    state = p->get_state();
    state->pc = DC_IROM_BASE;
    uint32_t zero = 0;
    difftest_memcpy(0xfffffff0, &zero, 4, DIFFTEST_TO_REF);
    return;
  }
  spike_htif_args.push_back("");

  spike_cfg.isa = "RV32E";
  spike_cfg.priv = "M";
  spike_cfg.mem_layout = {
    mem_cfg_t(DC_IROM_BASE, DC_IROM_SIZE),
    mem_cfg_t(DC_DRAM_BASE, DC_DRAM_SIZE),
    mem_cfg_t(0xfffff000ULL, 0x00001000ULL)
  };
  spike_cfg.start_pc.set_global(DC_IROM_BASE);
  spike_cfg.hartids = {0};

  spike_mems.clear();
  for (const auto &mc : spike_cfg.mem_layout) {
    spike_mems.push_back({mc.get_base(), new mem_t(mc.get_size())});
  }

  s = new sim_t(&spike_cfg, false,
                spike_mems, spike_plugin_devices,
                false /* dtb_discovery */,
                spike_htif_args,
                spike_dm_config, nullptr,
                false, nullptr,
                false,
                nullptr,
                std::nullopt);

  p = s->get_core(0);
  state = p->get_state();
  state->pc = DC_IROM_BASE;
}

}
