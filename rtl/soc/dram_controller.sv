`default_nettype none

module dram_controller #(
  parameter logic [31:0] DRAM_BASE    = dc_soc_addr_pkg::DRAM_BASE,
  parameter int unsigned DRAM_BYTES   = dc_soc_addr_pkg::DRAM_BYTES,
  parameter logic [31:0] TOHOST_ADDR  = dc_soc_addr_pkg::TOHOST_ADDR,
  parameter bit          ENABLE_TOHOST = 1'b1
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  input  logic        req_write,
  input  logic [1:0]  req_size,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata,
  output logic        rsp_error,
  output logic [13:0] dram_addr,
  output logic [31:0] dram_wdata,
  output logic [3:0]  dram_wstrb,
  input  logic [31:0] dram_rdata,
  output logic        tohost_exit,
  output logic [31:0] guest_exit_code
);
  logic rsp_valid_q;
  logic rsp_error_q;
  logic pending_dram_q;
  logic pending_write_q;
  logic pending_tohost_q;
  logic [13:0] pending_word_addr_q;
  logic [31:0] pending_wdata_q;
  logic [3:0] pending_wstrb_q;

  logic in_dram;
  logic aligned;
  logic legal_tohost;
  logic request_dram;
  logic request_tohost;
  logic request_error;
  logic req_fire;
  logic rsp_fire;

  /* verilator lint_off UNSIGNED */
  assign in_dram = (req_addr >= DRAM_BASE) &&
                   (req_addr < (DRAM_BASE + 32'(DRAM_BYTES)));
  /* verilator lint_on UNSIGNED */
  assign aligned = (req_size == 2'b00) ||
                   ((req_size == 2'b01) && !req_addr[0]) ||
                   ((req_size == 2'b10) && (req_addr[1:0] == 2'b00));
  assign legal_tohost = ENABLE_TOHOST && (req_addr == TOHOST_ADDR) &&
                        req_write && (req_size == 2'b10) &&
                        (req_wstrb == 4'b1111);
  assign request_dram = in_dram && aligned;
  assign request_tohost = legal_tohost;
  assign request_error = !(request_dram || request_tohost);

  assign req_ready = !rst && !rsp_valid_q;
  assign req_fire = req_valid && req_ready;
  assign rsp_fire = rsp_valid_q && rsp_ready;
  assign rsp_valid = !rst && rsp_valid_q;
  assign rsp_error = rsp_error_q;
  assign rsp_rdata = (pending_dram_q && !rsp_error_q) ? dram_rdata : 32'd0;

  assign dram_addr = req_fire ? (req_addr[15:2] - DRAM_BASE[15:2]) : pending_word_addr_q;
  assign dram_wdata = pending_wdata_q;
  assign dram_wstrb = {4{rsp_fire && pending_dram_q && pending_write_q && !rsp_error_q}} &
                      pending_wstrb_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_valid_q        <= 1'b0;
      rsp_error_q        <= 1'b0;
      pending_dram_q     <= 1'b0;
      pending_write_q    <= 1'b0;
      pending_tohost_q   <= 1'b0;
      pending_word_addr_q <= 14'd0;
      pending_wdata_q    <= 32'd0;
      pending_wstrb_q    <= 4'd0;
      tohost_exit        <= 1'b0;
      guest_exit_code    <= 32'd0;
    end else begin
      if (rsp_fire && pending_tohost_q && !rsp_error_q) begin
        tohost_exit     <= 1'b1;
        guest_exit_code <= pending_wdata_q;
      end

      if (req_fire) begin
        rsp_valid_q         <= 1'b1;
        rsp_error_q         <= request_error;
        pending_dram_q      <= request_dram;
        pending_write_q     <= req_write;
        pending_tohost_q    <= request_tohost;
        pending_word_addr_q <= req_addr[15:2] - DRAM_BASE[15:2];
        pending_wdata_q     <= req_wdata;
        pending_wstrb_q     <= req_wstrb;
      end else if (rsp_fire) begin
        rsp_valid_q      <= 1'b0;
        rsp_error_q      <= 1'b0;
        pending_dram_q   <= 1'b0;
        pending_write_q  <= 1'b0;
        pending_tohost_q <= 1'b0;
        pending_wstrb_q  <= 4'd0;
      end
    end
  end
endmodule

`default_nettype wire
