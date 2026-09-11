#ifndef DC_CHIP_SIM_VERILATOR_SDB_H_
#define DC_CHIP_SIM_VERILATOR_SDB_H_

#include "simulation.h"

#include <cstdint>
#include <iosfwd>

namespace dc_sim {

RunResult run_sdb(Simulation &simulation, std::uint64_t max_cycles,
                  std::istream &input, std::ostream &output,
                  std::ostream &errors);

}  // namespace dc_sim

#endif  // DC_CHIP_SIM_VERILATOR_SDB_H_
