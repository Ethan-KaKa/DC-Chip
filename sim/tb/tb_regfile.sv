`timescale 1ns/1ps
`default_nettype none

module tb_regfile;
  logic        clk;
  logic        rst;
  logic [3:0]  raddr_a;
  logic [31:0] rdata_a;
  logic [3:0]  raddr_b;
  logic [31:0] rdata_b;
  logic        we;
  logic [3:0]  waddr;
  logic [31:0] wdata;
  logic [3:0]  debug_reg_addr;
  logic [31:0] debug_reg_data;
  integer      reg_index;

  regfile dut (
    .clk_i            (clk),
    .rst_i            (rst),
    .raddr_a_i        (raddr_a),
    .rdata_a_o        (rdata_a),
    .raddr_b_i        (raddr_b),
    .rdata_b_o        (rdata_b),
    .we_i             (we),
    .waddr_i          (waddr),
    .wdata_i          (wdata),
    .debug_reg_addr_i (debug_reg_addr),
    .debug_reg_data_o (debug_reg_data)
  );

  initial begin : clock_block
    forever #5 clk = ~clk;
  end

  task automatic check_read(
    input logic [3:0]  addr,
    input logic [31:0] expected
  );
    begin
      raddr_a       = addr;
      raddr_b       = addr;
      debug_reg_addr = addr;
      #1;
      if ((rdata_a !== expected) || (rdata_b !== expected) ||
          (debug_reg_data !== expected)) begin
        $fatal(1,
               {"tb_regfile: x%0d expected=%h actual a=%h b=%h ",
                "debug=%h"},
               addr, expected, rdata_a, rdata_b, debug_reg_data);
      end
    end
  endtask

  task automatic write_reg(
    input logic [3:0]  addr,
    input logic [31:0] old_value,
    input logic [31:0] new_value
  );
    begin
      @(negedge clk);
      raddr_a = addr;
      raddr_b = addr;
      debug_reg_addr = addr;
      waddr = addr;
      wdata = new_value;
      we    = 1'b1;
      #1;
      if ((rdata_a !== old_value) || (rdata_b !== old_value) ||
          (debug_reg_data !== old_value)) begin
        $fatal(1, "tb_regfile: x%0d changed before write edge", addr);
      end
      @(posedge clk);
      #1;
      check_read(addr, (addr == 4'd0) ? 32'd0 : new_value);
      we = 1'b0;
    end
  endtask

  initial begin
    clk            = 1'b0;
    rst            = 1'b1;
    raddr_a        = 4'd0;
    raddr_b        = 4'd15;
    we             = 1'b0;
    waddr          = 4'd0;
    wdata          = 32'd0;
    debug_reg_addr = 4'd0;

    repeat (2) @(posedge clk);
    #1;
    for (reg_index = 0; reg_index < 16; reg_index = reg_index + 1) begin
      check_read(reg_index[3:0], 32'd0);
    end

    @(negedge clk);
    rst = 1'b0;

    write_reg(4'd0, 32'd0, 32'hffff_ffff);
    for (reg_index = 1; reg_index < 16; reg_index = reg_index + 1) begin
      write_reg(reg_index[3:0], 32'd0,
                32'h1000_0000 + reg_index);
    end

    raddr_a = 4'd3;
    raddr_b = 4'd14;
    #1;
    if ((rdata_a !== 32'h1000_0003) ||
        (rdata_b !== 32'h1000_000e)) begin
      $fatal(1, "tb_regfile: independent read ports failed");
    end

    @(negedge clk);
    rst   = 1'b1;
    we    = 1'b1;
    waddr = 4'd7;
    wdata = 32'hdead_beef;
    @(posedge clk);
    #1;
    we = 1'b0;
    for (reg_index = 0; reg_index < 16; reg_index = reg_index + 1) begin
      check_read(reg_index[3:0], 32'd0);
    end

    $display("tb_regfile: PASS");
    disable clock_block;
    disable timeout_block;
  end

  initial begin : timeout_block
    #5000;
    $fatal(1, "tb_regfile: timeout");
  end
endmodule

`default_nettype wire
