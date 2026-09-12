`default_nettype none

module dc_soc_top #(
  parameter logic [31:0] DRAM_BASE   = 32'h2000_0000,
  parameter int unsigned DRAM_BYTES  = 65536,
  parameter logic [31:0] MMIO_BASE   = 32'h1000_0000,
  parameter int unsigned MMIO_BYTES  = 65536,
  parameter logic [31:0] TOHOST_ADDR = 32'hffff_fff0
) (
  input  logic        clk,
  input  logic        rst,

  // Instruction memory interface (to IROM / sim_mem)
  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_rsp_valid,
  output logic        imem_rsp_ready,
  input  logic [31:0] imem_rsp_rdata,
  input  logic        imem_rsp_error,

  // Data memory interface (to DRAM / sim_mem)
  output logic        dram_req_valid,
  input  logic        dram_req_ready,
  output logic [31:0] dram_req_addr,
  output logic        dram_req_write,
  output logic [1:0]  dram_req_size,
  output logic [31:0] dram_req_wdata,
  output logic [3:0]  dram_req_wstrb,
  input  logic        dram_rsp_valid,
  output logic        dram_rsp_ready,
  input  logic [31:0] dram_rsp_rdata,
  input  logic        dram_rsp_error,

  // Peripherals
  output logic [15:0] o_led,

  // Trace & Debug
  output logic        trace_valid,
  output logic [31:0] trace_pc,
  output logic [31:0] trace_inst,
  input  logic [3:0]  debug_reg_addr,
  output logic [31:0] debug_reg_data,
  output logic        fault_valid,
  output logic [2:0]  fault_cause,
  output logic [31:0] fault_pc,
  output logic        fault_inst_valid,
  output logic [31:0] fault_inst
);

  // Internal CPU DMEM bus
  logic        cpu_dmem_req_valid;
  logic        cpu_dmem_req_ready;
  logic [31:0] cpu_dmem_req_addr;
  logic        cpu_dmem_req_write;
  logic [1:0]  cpu_dmem_req_size;
  logic [31:0] cpu_dmem_req_wdata;
  logic [3:0]  cpu_dmem_req_wstrb;
  logic        cpu_dmem_rsp_valid;
  logic        cpu_dmem_rsp_ready;
  logic [31:0] cpu_dmem_rsp_rdata;
  logic        cpu_dmem_rsp_error;

  // Internal MMIO bus
  logic        mmio_req_valid;
  logic        mmio_req_ready;
  logic [31:0] mmio_req_addr;
  logic        mmio_req_write;
  logic [1:0]  mmio_req_size;
  logic [31:0] mmio_req_wdata;
  logic [3:0]  mmio_req_wstrb;
  logic        mmio_rsp_valid;
  logic        mmio_rsp_ready;
  logic [31:0] mmio_rsp_rdata;
  logic        mmio_rsp_error;

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
    .dmem_req_valid   (cpu_dmem_req_valid),
    .dmem_req_ready   (cpu_dmem_req_ready),
    .dmem_req_addr    (cpu_dmem_req_addr),
    .dmem_req_write   (cpu_dmem_req_write),
    .dmem_req_size    (cpu_dmem_req_size),
    .dmem_req_wdata   (cpu_dmem_req_wdata),
    .dmem_req_wstrb   (cpu_dmem_req_wstrb),
    .dmem_rsp_valid   (cpu_dmem_rsp_valid),
    .dmem_rsp_ready   (cpu_dmem_rsp_ready),
    .dmem_rsp_rdata   (cpu_dmem_rsp_rdata),
    .dmem_rsp_error   (cpu_dmem_rsp_error),
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

  soc_interconnect #(
    .DRAM_BASE   (DRAM_BASE),
    .DRAM_BYTES  (DRAM_BYTES),
    .MMIO_BASE   (MMIO_BASE),
    .MMIO_BYTES  (MMIO_BYTES),
    .TOHOST_ADDR (TOHOST_ADDR)
  ) u_interconnect (
    .clk             (clk),
    .rst             (rst),
    .cpu_req_valid   (cpu_dmem_req_valid),
    .cpu_req_ready   (cpu_dmem_req_ready),
    .cpu_req_addr    (cpu_dmem_req_addr),
    .cpu_req_write   (cpu_dmem_req_write),
    .cpu_req_size    (cpu_dmem_req_size),
    .cpu_req_wdata   (cpu_dmem_req_wdata),
    .cpu_req_wstrb   (cpu_dmem_req_wstrb),
    .cpu_rsp_valid   (cpu_dmem_rsp_valid),
    .cpu_rsp_ready   (cpu_dmem_rsp_ready),
    .cpu_rsp_rdata   (cpu_dmem_rsp_rdata),
    .cpu_rsp_error   (cpu_dmem_rsp_error),
    .dram_req_valid  (dram_req_valid),
    .dram_req_ready  (dram_req_ready),
    .dram_req_addr   (dram_req_addr),
    .dram_req_write  (dram_req_write),
    .dram_req_size   (dram_req_size),
    .dram_req_wdata  (dram_req_wdata),
    .dram_req_wstrb  (dram_req_wstrb),
    .dram_rsp_valid  (dram_rsp_valid),
    .dram_rsp_ready  (dram_rsp_ready),
    .dram_rsp_rdata  (dram_rsp_rdata),
    .dram_rsp_error  (dram_rsp_error),
    .mmio_req_valid  (mmio_req_valid),
    .mmio_req_ready  (mmio_req_ready),
    .mmio_req_addr   (mmio_req_addr),
    .mmio_req_write  (mmio_req_write),
    .mmio_req_size   (mmio_req_size),
    .mmio_req_wdata  (mmio_req_wdata),
    .mmio_req_wstrb  (mmio_req_wstrb),
    .mmio_rsp_valid  (mmio_rsp_valid),
    .mmio_rsp_ready  (mmio_rsp_ready),
    .mmio_rsp_rdata  (mmio_rsp_rdata),
    .mmio_rsp_error  (mmio_rsp_error)
  );

  led_controller u_led_controller (
    .clk       (clk),
    .rst       (rst),
    .req_valid (mmio_req_valid),
    .req_ready (mmio_req_ready),
    .req_addr  (mmio_req_addr),
    .req_write (mmio_req_write),
    .req_size  (mmio_req_size),
    .req_wdata (mmio_req_wdata),
    .req_wstrb (mmio_req_wstrb),
    .rsp_valid (mmio_rsp_valid),
    .rsp_ready (mmio_rsp_ready),
    .rsp_rdata (mmio_rsp_rdata),
    .rsp_error (mmio_rsp_error),
    .o_led     (o_led)
  );

endmodule

`default_nettype wire
