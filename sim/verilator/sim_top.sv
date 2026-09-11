`default_nettype none

module sim_top (
  input  logic        clk,
  input  logic        rst,

  // Trace and architectural visibility
  output logic        trace_valid,
  output logic [31:0] trace_pc,
  output logic [31:0] trace_inst,
  input  logic [3:0]  debug_reg_addr,
  output logic [31:0] debug_reg_data,

  // Structured fault
  output logic        fault_valid,
  output logic [2:0]  fault_cause,
  output logic [31:0] fault_pc,
  output logic        fault_inst_valid,
  output logic [31:0] fault_inst,

  // Simulation control (tohost)
  output logic        tohost_exit,
  output logic [31:0] guest_exit_code,

  // Current fetch state for debug/SDB
  output logic [31:0] fetch_pc,
  output logic [31:0] fetch_inst
);

  logic        imem_req_valid;
  logic        imem_req_ready;
  logic [31:0] imem_req_addr;
  logic        imem_rsp_valid;
  logic        imem_rsp_ready;
  logic [31:0] imem_rsp_rdata;
  logic        imem_rsp_error;

  logic        dmem_req_valid;
  logic        dmem_req_ready;
  logic [31:0] dmem_req_addr;
  logic        dmem_req_write;
  logic [1:0]  dmem_req_size;
  logic [31:0] dmem_req_wdata;
  logic [3:0]  dmem_req_wstrb;
  logic        dmem_rsp_valid;
  logic        dmem_rsp_ready;
  logic [31:0] dmem_rsp_rdata;
  logic        dmem_rsp_error;

  cpu_core u_cpu_core (
    .clk              (clk),
    .rst              (rst),
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_rdata   (imem_rsp_rdata),
    .imem_rsp_error   (imem_rsp_error),
    .dmem_req_valid   (dmem_req_valid),
    .dmem_req_ready   (dmem_req_ready),
    .dmem_req_addr    (dmem_req_addr),
    .dmem_req_write   (dmem_req_write),
    .dmem_req_size    (dmem_req_size),
    .dmem_req_wdata   (dmem_req_wdata),
    .dmem_req_wstrb   (dmem_req_wstrb),
    .dmem_rsp_valid   (dmem_rsp_valid),
    .dmem_rsp_ready   (dmem_rsp_ready),
    .dmem_rsp_rdata   (dmem_rsp_rdata),
    .dmem_rsp_error   (dmem_rsp_error),
    .trace_valid      (trace_valid),
    .trace_pc         (trace_pc),
    .trace_inst       (trace_inst),
    .debug_reg_addr   (debug_reg_addr),
    .debug_reg_data   (debug_reg_data),
    .fault_valid      (fault_valid),
    .fault_cause      (fault_cause),
    .fault_pc         (fault_pc),
    .fault_inst_valid (fault_inst_valid),
    .fault_inst       (fault_inst)
  );

  sim_mem u_sim_mem (
    .clk              (clk),
    .rst              (rst),
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_rdata   (imem_rsp_rdata),
    .imem_rsp_error   (imem_rsp_error),
    .dmem_req_valid   (dmem_req_valid),
    .dmem_req_ready   (dmem_req_ready),
    .dmem_req_addr    (dmem_req_addr),
    .dmem_req_write   (dmem_req_write),
    .dmem_req_size    (dmem_req_size),
    .dmem_req_wdata   (dmem_req_wdata),
    .dmem_req_wstrb   (dmem_req_wstrb),
    .dmem_rsp_valid   (dmem_rsp_valid),
    .dmem_rsp_ready   (dmem_rsp_ready),
    .dmem_rsp_rdata   (dmem_rsp_rdata),
    .dmem_rsp_error   (dmem_rsp_error),
    .tohost_exit      (tohost_exit),
    .guest_exit_code  (guest_exit_code)
  );

  assign fetch_pc = fault_valid ? fault_pc : imem_req_addr;
  assign fetch_inst = (fault_valid && fault_inst_valid) ? fault_inst : imem_rsp_rdata;

endmodule

`default_nettype wire
