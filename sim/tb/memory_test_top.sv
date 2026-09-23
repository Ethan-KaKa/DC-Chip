`default_nettype none

module memory_test_top (
  input  logic        clk,
  input  logic        rst,
  input  logic        imem_req_valid,
  output logic        imem_req_ready,
  input  logic [31:0] imem_req_addr,
  output logic        imem_rsp_valid,
  input  logic        imem_rsp_ready,
  output logic [31:0] imem_rsp_rdata,
  output logic        imem_rsp_error,
  input  logic        dmem_req_valid,
  output logic        dmem_req_ready,
  input  logic [31:0] dmem_req_addr,
  input  logic        dmem_req_write,
  input  logic [1:0]  dmem_req_size,
  input  logic [31:0] dmem_req_wdata,
  input  logic [3:0]  dmem_req_wstrb,
  output logic        dmem_rsp_valid,
  input  logic        dmem_rsp_ready,
  output logic [31:0] dmem_rsp_rdata,
  output logic        dmem_rsp_error,
  output logic        tohost_exit,
  output logic [31:0] guest_exit_code
);
  logic [13:0] irom_addr;
  logic [31:0] irom_rdata;
  logic [13:0] dram_addr;
  logic [31:0] dram_wdata;
  logic [3:0] dram_wstrb;
  logic [31:0] dram_rdata;

  irom_controller u_irom_controller (
    .rst, .req_valid(imem_req_valid), .req_ready(imem_req_ready),
    .req_addr(imem_req_addr), .rsp_valid(imem_rsp_valid),
    .rsp_ready(imem_rsp_ready), .rsp_rdata(imem_rsp_rdata),
    .rsp_error(imem_rsp_error), .irom_addr, .irom_rdata
  );
  irom u_irom (.clk, .a(irom_addr), .spo(irom_rdata));

  dram_controller u_dram_controller (
    .clk, .rst, .req_valid(dmem_req_valid), .req_ready(dmem_req_ready),
    .req_addr(dmem_req_addr), .req_write(dmem_req_write),
    .req_size(dmem_req_size), .req_wdata(dmem_req_wdata),
    .req_wstrb(dmem_req_wstrb), .rsp_valid(dmem_rsp_valid),
    .rsp_ready(dmem_rsp_ready), .rsp_rdata(dmem_rsp_rdata),
    .rsp_error(dmem_rsp_error), .dram_addr, .dram_wdata, .dram_wstrb,
    .dram_rdata, .tohost_exit, .guest_exit_code
  );
  dram u_dram (
    .clka(clk), .addra(dram_addr), .dina(dram_wdata),
    .wea(dram_wstrb), .douta(dram_rdata)
  );
endmodule

`default_nettype wire
