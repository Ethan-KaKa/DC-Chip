`default_nettype none

module irom (
  input  logic        clk,
  input  logic [13:0] a,
  output logic [31:0] spo
);
`ifndef SYNTHESIS
  import "DPI-C" function void sim_irom_read(
    input int unsigned addr,
    output int unsigned data
  );

  always_comb sim_irom_read({16'd0, a, 2'b00}, spo);
`else
  always_comb spo = 32'd0;
`endif

  logic _unused;
  assign _unused = clk;
endmodule

`default_nettype wire
