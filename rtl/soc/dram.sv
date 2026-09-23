`default_nettype none

module dram (
  input  logic        clka,
  input  logic [13:0] addra,
  input  logic [31:0] dina,
  input  logic [3:0]  wea,
  output logic [31:0] douta
);
`ifndef SYNTHESIS
  import "DPI-C" function void sim_dram_read(
    input int unsigned addr,
    output int unsigned data
  );
  import "DPI-C" function void sim_dram_write(
    input int unsigned addr,
    input int unsigned data,
    input int unsigned wstrb
  );

  always_ff @(posedge clka) begin
    sim_dram_read({16'd0, addra, 2'b00} + dc_soc_addr_pkg::DRAM_BASE, douta);
    if (|wea) begin
      sim_dram_write({16'd0, addra, 2'b00} + dc_soc_addr_pkg::DRAM_BASE,
                     dina, {28'd0, wea});
    end
  end
`else
  always_ff @(posedge clka) douta <= 32'd0;
`endif
endmodule

`default_nettype wire
