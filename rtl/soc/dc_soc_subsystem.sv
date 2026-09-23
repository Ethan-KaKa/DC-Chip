`default_nettype none

module dc_soc_subsystem #(
  parameter bit ASYNC_CDC = 1'b0
) (
  input logic clk, rst, clk_periph, rst_periph,
  output logic imem_req_valid,
  input logic imem_req_ready,
  output logic [31:0] imem_req_addr,
  input logic imem_rsp_valid,
  output logic imem_rsp_ready,
  input logic [31:0] imem_rsp_rdata,
  input logic imem_rsp_error,
  output logic dram_req_valid,
  input logic dram_req_ready,
  output logic [31:0] dram_req_addr,
  output logic dram_req_write,
  output logic [1:0] dram_req_size,
  output logic [31:0] dram_req_wdata,
  output logic [3:0] dram_req_wstrb,
  input logic dram_rsp_valid,
  output logic dram_rsp_ready,
  input logic [31:0] dram_rsp_rdata,
  input logic dram_rsp_error,
  output logic [15:0] o_led,
  output logic o_uart_tx,
  input logic i_uart_rx,
  input logic [20:0] i_button,
  output logic [7:0] o_seg0, o_seg1, o_seg2, o_seg3,
  output logic [7:0] o_seg4, o_seg5, o_seg6, o_seg7,
  output logic trace_valid,
  output logic [31:0] trace_pc, trace_inst,
  output logic trace_skip_ref,
  input logic [3:0] debug_reg_addr,
  output logic [31:0] debug_reg_data,
  output logic fault_valid,
  output logic [2:0] fault_cause,
  output logic [31:0] fault_pc,
  output logic fault_inst_valid,
  output logic [31:0] fault_inst
);
  logic cpu_req_valid, cpu_req_ready, cpu_req_write;
  logic [31:0] cpu_req_addr, cpu_req_wdata;
  logic [1:0] cpu_req_size;
  logic [3:0] cpu_req_wstrb;
  logic cpu_rsp_valid, cpu_rsp_ready, cpu_rsp_error, cpu_rsp_skip_ref;
  logic [31:0] cpu_rsp_rdata;
  logic mmio_req_valid, mmio_req_ready, mmio_req_write;
  logic [31:0] mmio_req_addr, mmio_req_wdata;
  logic [1:0] mmio_req_size;
  logic [3:0] mmio_req_wstrb;
  logic mmio_rsp_valid, mmio_rsp_ready, mmio_rsp_error;
  logic [31:0] mmio_rsp_rdata;

  cpu_core u_cpu_core (
    .clk, .rst, .imem_req_valid, .imem_req_ready, .imem_req_addr,
    .imem_rsp_valid, .imem_rsp_ready, .imem_rsp_rdata, .imem_rsp_error,
    .dmem_req_valid(cpu_req_valid), .dmem_req_ready(cpu_req_ready),
    .dmem_req_addr(cpu_req_addr), .dmem_req_write(cpu_req_write),
    .dmem_req_size(cpu_req_size), .dmem_req_wdata(cpu_req_wdata),
    .dmem_req_wstrb(cpu_req_wstrb), .dmem_rsp_valid(cpu_rsp_valid),
    .dmem_rsp_ready(cpu_rsp_ready), .dmem_rsp_rdata(cpu_rsp_rdata),
    .dmem_rsp_error(cpu_rsp_error), .dmem_rsp_skip_ref(cpu_rsp_skip_ref),
    .trace_valid, .trace_pc, .trace_inst, .trace_skip_ref,
    .debug_reg_addr, .debug_reg_data, .fault_valid, .fault_cause,
    .fault_pc, .fault_inst_valid, .fault_inst
  );

  soc_interconnect u_interconnect (
    .clk, .rst, .cpu_req_valid, .cpu_req_ready, .cpu_req_addr,
    .cpu_req_write, .cpu_req_size, .cpu_req_wdata, .cpu_req_wstrb,
    .cpu_rsp_valid, .cpu_rsp_ready, .cpu_rsp_rdata, .cpu_rsp_error,
    .cpu_rsp_skip_ref, .dram_req_valid, .dram_req_ready, .dram_req_addr,
    .dram_req_write, .dram_req_size, .dram_req_wdata, .dram_req_wstrb,
    .dram_rsp_valid, .dram_rsp_ready, .dram_rsp_rdata, .dram_rsp_error,
    .mmio_req_valid, .mmio_req_ready, .mmio_req_addr, .mmio_req_write,
    .mmio_req_size, .mmio_req_wdata, .mmio_req_wstrb,
    .mmio_rsp_valid, .mmio_rsp_ready, .mmio_rsp_rdata, .mmio_rsp_error
  );

  soc_periph_subsystem #(.ASYNC_CDC(ASYNC_CDC)) u_periph_subsystem (
    .clk_cpu(clk), .rst_cpu(rst), .clk_periph, .rst_periph,
    .req_valid(mmio_req_valid), .req_ready(mmio_req_ready),
    .req_addr(mmio_req_addr), .req_write(mmio_req_write),
    .req_size(mmio_req_size), .req_wdata(mmio_req_wdata),
    .req_wstrb(mmio_req_wstrb), .rsp_valid(mmio_rsp_valid),
    .rsp_ready(mmio_rsp_ready), .rsp_rdata(mmio_rsp_rdata),
    .rsp_error(mmio_rsp_error), .o_led, .o_uart_tx, .i_uart_rx,
    .i_button, .o_seg0, .o_seg1, .o_seg2, .o_seg3,
    .o_seg4, .o_seg5, .o_seg6, .o_seg7
  );
endmodule

`default_nettype wire
