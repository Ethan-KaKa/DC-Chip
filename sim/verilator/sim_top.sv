`default_nettype none

module sim_top (
  input  logic        clk,
  input  logic        rst,
  output logic        trace_valid,
  output logic [7:0]  trace_pc,
  output logic [15:0] trace_inst,
  output logic [63:0] debug_regs,
  output logic        illegal_inst,
  output logic [7:0]  fetch_pc,
  output logic [15:0] fetch_inst
);
  import "DPI-C" function int unsigned sim_imem_read(
    input int unsigned word_addr
  );

  always_comb begin
    fetch_inst = 16'(sim_imem_read(32'(fetch_pc)));
  end

  cpu_core u_cpu_core (
    .clk          (clk),
    .rst          (rst),
    .imem_addr    (fetch_pc),
    .imem_rdata   (fetch_inst),
    .trace_valid  (trace_valid),
    .trace_pc     (trace_pc),
    .trace_inst   (trace_inst),
    .debug_regs   (debug_regs),
    .illegal_inst (illegal_inst)
  );
endmodule

`default_nettype wire
