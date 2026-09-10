`default_nettype none

module regfile (
  input  logic                                      clk_i,
  input  logic                                      rst_i,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0]    raddr_a_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]        rdata_a_o,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0]    raddr_b_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]        rdata_b_o,
  input  logic                                      we_i,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0]    waddr_i,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0]        wdata_i,
  output logic [dc_isa_pkg::REG_COUNT*dc_isa_pkg::DATA_WIDTH-1:0]
                                                     debug_regs_o
);
  logic [dc_isa_pkg::DATA_WIDTH-1:0]
      regs_q [0:dc_isa_pkg::REG_COUNT-1];

  assign rdata_a_o = regs_q[raddr_a_i];
  assign rdata_b_o = regs_q[raddr_b_i];
  assign debug_regs_o = {regs_q[3], regs_q[2], regs_q[1], regs_q[0]};

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      regs_q[0] <= '0;
      regs_q[1] <= '0;
      regs_q[2] <= '0;
      regs_q[3] <= '0;
    end else if (we_i) begin
      regs_q[waddr_i] <= wdata_i;
    end
  end
endmodule

`default_nettype wire
