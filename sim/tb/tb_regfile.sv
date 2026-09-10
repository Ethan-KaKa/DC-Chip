`timescale 1ns/1ps
`default_nettype none

module tb_regfile;
  logic        clk;
  logic        rst;
  logic [1:0]  raddr_a;
  logic [15:0] rdata_a;
  logic [1:0]  raddr_b;
  logic [15:0] rdata_b;
  logic        we;
  logic [1:0]  waddr;
  logic [15:0] wdata;
  logic [63:0] debug_regs;

  regfile dut (
    .clk_i        (clk),
    .rst_i        (rst),
    .raddr_a_i    (raddr_a),
    .rdata_a_o    (rdata_a),
    .raddr_b_i    (raddr_b),
    .rdata_b_o    (rdata_b),
    .we_i         (we),
    .waddr_i      (waddr),
    .wdata_i      (wdata),
    .debug_regs_o (debug_regs)
  );

  initial begin : clock_block
    forever #5 clk = ~clk;
  end

  task automatic check_debug(input logic [63:0] expected);
    begin
      if (debug_regs !== expected) begin
        $fatal(1,
               "tb_regfile: expected debug=%h actual=%h",
               expected, debug_regs);
      end
    end
  endtask

  task automatic check_reads(
    input logic [1:0]  addr_a,
    input logic [15:0] expected_a,
    input logic [1:0]  addr_b,
    input logic [15:0] expected_b
  );
    begin
      raddr_a = addr_a;
      raddr_b = addr_b;
      #1;
      if ((rdata_a !== expected_a) || (rdata_b !== expected_b)) begin
        $fatal(1,
               {"tb_regfile: read a[%0d] expected=%h actual=%h; ",
                "b[%0d] expected=%h actual=%h"},
               addr_a, expected_a, rdata_a,
               addr_b, expected_b, rdata_b);
      end
    end
  endtask

  task automatic write_and_check(
    input logic [1:0]  addr,
    input logic [15:0] old_value,
    input logic [15:0] new_value,
    input logic [63:0] expected_debug
  );
    begin
      @(negedge clk);
      raddr_a = addr;
      raddr_b = addr;
      waddr   = addr;
      wdata   = new_value;
      we      = 1'b1;
      #1;
      if ((rdata_a !== old_value) || (rdata_b !== old_value)) begin
        $fatal(1,
               "tb_regfile: R%0d changed before write edge",
               addr);
      end
      @(posedge clk);
      #1;
      if ((rdata_a !== new_value) || (rdata_b !== new_value)) begin
        $fatal(1,
               "tb_regfile: R%0d did not change after write edge",
               addr);
      end
      check_debug(expected_debug);
      we = 1'b0;
    end
  endtask

  initial begin
    clk     = 1'b0;
    rst     = 1'b1;
    raddr_a = 2'd0;
    raddr_b = 2'd3;
    we      = 1'b0;
    waddr   = 2'd0;
    wdata   = 16'h0000;

    repeat (2) begin
      @(posedge clk);
      #1;
      check_reads(2'd0, 16'h0000, 2'd3, 16'h0000);
      check_debug(64'h0000_0000_0000_0000);
    end

    @(negedge clk);
    rst   = 1'b0;
    waddr = 2'd2;
    wdata = 16'hffff;
    we    = 1'b0;
    @(posedge clk);
    #1;
    check_debug(64'h0000_0000_0000_0000);

    write_and_check(2'd0, 16'h0000, 16'h1111,
                    64'h0000_0000_0000_1111);
    write_and_check(2'd1, 16'h0000, 16'h2222,
                    64'h0000_0000_2222_1111);
    write_and_check(2'd2, 16'h0000, 16'h3333,
                    64'h0000_3333_2222_1111);
    write_and_check(2'd3, 16'h0000, 16'h4444,
                    64'h4444_3333_2222_1111);

    check_reads(2'd0, 16'h1111, 2'd3, 16'h4444);
    check_reads(2'd1, 16'h2222, 2'd2, 16'h3333);

    @(negedge clk);
    rst   = 1'b1;
    we    = 1'b1;
    waddr = 2'd1;
    wdata = 16'hffff;
    @(posedge clk);
    #1;
    check_reads(2'd1, 16'h0000, 2'd2, 16'h0000);
    check_debug(64'h0000_0000_0000_0000);

    $display("tb_regfile: PASS");
    disable clock_block;
    disable timeout_block;
  end

  initial begin : timeout_block
    #2000;
    $fatal(1, "tb_regfile: timeout");
  end
endmodule

`default_nettype wire
