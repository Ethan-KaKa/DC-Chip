`timescale 1ns/1ps
`default_nettype none

module tb_alu;
  logic [15:0] lhs;
  logic [15:0] rhs;
  logic [2:0]  op;
  logic [15:0] result;

  alu dut (
    .lhs_i    (lhs),
    .rhs_i    (rhs),
    .op_i     (op),
    .result_o (result)
  );

  task automatic check_result(
    input logic [2:0]  test_op,
    input logic [15:0] test_lhs,
    input logic [15:0] test_rhs,
    input logic [15:0] expected
  );
    begin
      op  = test_op;
      lhs = test_lhs;
      rhs = test_rhs;
      #1;
      if (result !== expected) begin
        $fatal(1,
               "tb_alu: op=%b lhs=%h rhs=%h expected=%h actual=%h",
               test_op, test_lhs, test_rhs, expected, result);
      end
    end
  endtask

  initial begin
    lhs = 16'h0000;
    rhs = 16'h0000;
    op  = 3'b000;

    check_result(dc_isa_pkg::ALU_PASS_B, 16'h1234, 16'h0000, 16'h0000);
    check_result(dc_isa_pkg::ALU_PASS_B, 16'h0000, 16'hffff, 16'hffff);
    check_result(dc_isa_pkg::ALU_PASS_B, 16'h5555, 16'haaaa, 16'haaaa);

    check_result(dc_isa_pkg::ALU_ADD, 16'h1234, 16'h4321, 16'h5555);
    check_result(dc_isa_pkg::ALU_ADD, 16'hffff, 16'h0001, 16'h0000);
    check_result(dc_isa_pkg::ALU_SUB, 16'h1234, 16'h0234, 16'h1000);
    check_result(dc_isa_pkg::ALU_SUB, 16'h0000, 16'h0001, 16'hffff);

    check_result(dc_isa_pkg::ALU_AND, 16'h0000, 16'hffff, 16'h0000);
    check_result(dc_isa_pkg::ALU_AND, 16'hffff, 16'hffff, 16'hffff);
    check_result(dc_isa_pkg::ALU_AND, 16'haaaa, 16'h5555, 16'h0000);
    check_result(dc_isa_pkg::ALU_OR, 16'h0000, 16'h0000, 16'h0000);
    check_result(dc_isa_pkg::ALU_OR, 16'hffff, 16'h0000, 16'hffff);
    check_result(dc_isa_pkg::ALU_OR, 16'haaaa, 16'h5555, 16'hffff);

    check_result(3'b101, 16'hffff, 16'hffff, 16'h0000);
    check_result(3'b110, 16'hffff, 16'hffff, 16'h0000);
    check_result(3'b111, 16'hffff, 16'hffff, 16'h0000);
    check_result(3'b0x1, 16'hffff, 16'hffff, 16'h0000);
    check_result(3'b1z0, 16'hffff, 16'hffff, 16'h0000);

    $display("tb_alu: PASS");
    disable timeout_block;
  end

  initial begin : timeout_block
    #1000;
    $fatal(1, "tb_alu: timeout");
  end
endmodule

`default_nettype wire
