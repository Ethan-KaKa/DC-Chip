`timescale 1ns/1ps
`default_nettype none

module tb_alu;
  logic [31:0] lhs;
  logic [31:0] rhs;
  dc_isa_pkg::alu_op_e op;
  logic [31:0] result;

  alu dut (
    .lhs_i    (lhs),
    .rhs_i    (rhs),
    .op_i     (op),
    .result_o (result)
  );

  task automatic check_add(
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs,
    input logic [31:0] expected
  );
    begin
      op  = dc_isa_pkg::ALU_ADD;
      lhs = test_lhs;
      rhs = test_rhs;
      #1;
      if (result !== expected) begin
        $fatal(1,
               "tb_alu: lhs=%h rhs=%h expected=%h actual=%h",
               test_lhs, test_rhs, expected, result);
      end
    end
  endtask

  initial begin
    lhs = '0;
    rhs = '0;
    op  = dc_isa_pkg::ALU_ADD;

    check_add(32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
    check_add(32'h1234_5678, 32'h1111_1111, 32'h2345_6789);
    check_add(32'hffff_ffff, 32'h0000_0001, 32'h0000_0000);
    check_add(32'h7fff_ffff, 32'h0000_0001, 32'h8000_0000);
    check_add(32'h8000_0000, 32'hffff_ffff, 32'h7fff_ffff);
    check_add(32'hffff_f800, 32'h0000_0800, 32'h0000_0000);

    op = dc_isa_pkg::alu_op_e'(1'bx);
    #1;
    if (result !== 32'h0000_0000) begin
      $fatal(1, "tb_alu: unknown operation did not select safe zero");
    end

    $display("tb_alu: PASS");
    disable timeout_block;
  end

  initial begin : timeout_block
    #1000;
    $fatal(1, "tb_alu: timeout");
  end
endmodule

`default_nettype wire
