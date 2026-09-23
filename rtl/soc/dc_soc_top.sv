`default_nettype none

module dc_soc_top #(
  parameter bit ASYNC_CDC = 1'b0,
  parameter bit ENABLE_TOHOST = 1'b1
) (
  input logic clk, rst, clk_periph, rst_periph,
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
  output logic [31:0] fault_inst,
  output logic tohost_exit,
  output logic [31:0] guest_exit_code,
  output logic [31:0] debug_fetch_addr,
  output logic [31:0] debug_fetch_data
);
  logic imem_req_valid, imem_req_ready;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready, imem_rsp_error;
  logic [31:0] imem_rsp_rdata;
  logic dram_req_valid, dram_req_ready, dram_req_write;
  logic [31:0] dram_req_addr, dram_req_wdata, dram_rsp_rdata;
  logic [1:0] dram_req_size;
  logic [3:0] dram_req_wstrb;
  logic dram_rsp_valid, dram_rsp_ready, dram_rsp_error;
  logic [13:0] irom_addr, dram_addr;
  logic [31:0] irom_rdata, dram_wdata, dram_rdata;
  logic [3:0] dram_wstrb;

  dc_soc_subsystem #(.ASYNC_CDC(ASYNC_CDC)) u_subsystem (
    .clk, .rst, .clk_periph, .rst_periph,
    .imem_req_valid, .imem_req_ready, .imem_req_addr,
    .imem_rsp_valid, .imem_rsp_ready, .imem_rsp_rdata, .imem_rsp_error,
    .dram_req_valid, .dram_req_ready, .dram_req_addr, .dram_req_write,
    .dram_req_size, .dram_req_wdata, .dram_req_wstrb,
    .dram_rsp_valid, .dram_rsp_ready, .dram_rsp_rdata, .dram_rsp_error,
    .o_led, .o_uart_tx, .i_uart_rx, .i_button,
    .o_seg0, .o_seg1, .o_seg2, .o_seg3, .o_seg4, .o_seg5, .o_seg6, .o_seg7,
    .trace_valid, .trace_pc, .trace_inst, .trace_skip_ref,
    .debug_reg_addr, .debug_reg_data, .fault_valid, .fault_cause,
    .fault_pc, .fault_inst_valid, .fault_inst
  );

  irom_controller u_irom_controller (
    .rst, .req_valid(imem_req_valid), .req_ready(imem_req_ready),
    .req_addr(imem_req_addr), .rsp_valid(imem_rsp_valid),
    .rsp_ready(imem_rsp_ready), .rsp_rdata(imem_rsp_rdata),
    .rsp_error(imem_rsp_error), .irom_addr, .irom_rdata
  );
  irom u_irom (.clk, .a(irom_addr), .spo(irom_rdata));

  dram_controller #(.ENABLE_TOHOST(ENABLE_TOHOST)) u_dram_controller (
    .clk, .rst, .req_valid(dram_req_valid), .req_ready(dram_req_ready),
    .req_addr(dram_req_addr), .req_write(dram_req_write),
    .req_size(dram_req_size), .req_wdata(dram_req_wdata),
    .req_wstrb(dram_req_wstrb), .rsp_valid(dram_rsp_valid),
    .rsp_ready(dram_rsp_ready), .rsp_rdata(dram_rsp_rdata),
    .rsp_error(dram_rsp_error), .dram_addr, .dram_wdata, .dram_wstrb,
    .dram_rdata, .tohost_exit, .guest_exit_code
  );
  dram u_dram (
    .clka(clk), .addra(dram_addr), .dina(dram_wdata),
    .wea(dram_wstrb), .douta(dram_rdata)
  );

  assign debug_fetch_addr = fault_valid ? fault_pc : imem_req_addr;
  assign debug_fetch_data = (fault_valid && fault_inst_valid) ? fault_inst : imem_rsp_rdata;
endmodule

`default_nettype wire
