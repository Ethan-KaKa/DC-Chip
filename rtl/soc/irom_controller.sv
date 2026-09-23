`default_nettype none

module irom_controller #(
  parameter logic [31:0] IROM_BASE  = dc_soc_addr_pkg::IROM_BASE,
  parameter int unsigned IROM_BYTES = dc_soc_addr_pkg::IROM_BYTES
) (
  input  logic        rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata,
  output logic        rsp_error,
  output logic [13:0] irom_addr,
  input  logic [31:0] irom_rdata
);
  logic request_legal;

  /* verilator lint_off UNSIGNED */
  assign request_legal = (req_addr >= IROM_BASE) &&
                         (req_addr < (IROM_BASE + 32'(IROM_BYTES))) &&
                         (req_addr[1:0] == 2'b00);
  /* verilator lint_on UNSIGNED */

  assign irom_addr = req_addr[15:2] - IROM_BASE[15:2];
  assign req_ready = !rst && req_valid;
  assign rsp_valid = !rst && req_valid;
  assign rsp_rdata = request_legal ? irom_rdata : 32'd0;
  assign rsp_error = !rst && req_valid && !request_legal;

  logic _unused;
  assign _unused = &{1'b0, rsp_ready, 1'b0};
endmodule

`default_nettype wire
