`default_nettype none

module regfile (
  input  logic                                   clk_i,
  input  logic                                   rst_i,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] raddr_a_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]     rdata_a_o,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] raddr_b_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]     rdata_b_o,
  input  logic                                   we_i,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] waddr_i,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0]     wdata_i,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] debug_reg_addr_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]     debug_reg_data_o
);
  logic [dc_isa_pkg::DATA_WIDTH-1:0]
      regs_q [0:dc_isa_pkg::REG_COUNT-1];
  integer reg_index;

  assign rdata_a_o = (raddr_a_i == '0) ? '0 : regs_q[raddr_a_i];
  assign rdata_b_o = (raddr_b_i == '0) ? '0 : regs_q[raddr_b_i];
  assign debug_reg_data_o = (debug_reg_addr_i == '0)
                          ? '0 : regs_q[debug_reg_addr_i];

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      for (reg_index = 0; reg_index < dc_isa_pkg::REG_COUNT;
           reg_index = reg_index + 1) begin
        regs_q[reg_index] <= '0;
      end
    end else if (we_i && (waddr_i != '0)) begin
      regs_q[waddr_i] <= wdata_i;
    end
  end
endmodule

`default_nettype wire
