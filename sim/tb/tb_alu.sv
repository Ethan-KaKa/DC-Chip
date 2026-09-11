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

  task automatic check_op(
    input dc_isa_pkg::alu_op_e test_op,
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs,
    input logic [31:0] expected
  );
    begin
      op  = test_op;
      lhs = test_lhs;
      rhs = test_rhs;
      #1;
      if (result !== expected) begin
        $fatal(1,
               "tb_alu: op=%d lhs=%h rhs=%h expected=%h actual=%h",
               test_op, test_lhs, test_rhs, expected, result);
      end
    end
  endtask

  initial begin
    lhs = '0;
    rhs = '0;
    op  = dc_isa_pkg::ALU_ADD;

    // ADD
    check_op(dc_isa_pkg::ALU_ADD, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
    check_op(dc_isa_pkg::ALU_ADD, 32'h1234_5678, 32'h1111_1111, 32'h2345_6789);
    check_op(dc_isa_pkg::ALU_ADD, 32'hffff_ffff, 32'h0000_0001, 32'h0000_0000);

    // SUB
    check_op(dc_isa_pkg::ALU_SUB, 32'h0000_0005, 32'h0000_0003, 32'h0000_0002);
    check_op(dc_isa_pkg::ALU_SUB, 32'h0000_0000, 32'h0000_0001, 32'hffff_ffff);

    // SLL
    check_op(dc_isa_pkg::ALU_SLL, 32'h0000_0001, 32'h0000_0004, 32'h0000_0010);
    check_op(dc_isa_pkg::ALU_SLL, 32'h0000_0001, 32'h0000_0024, 32'h0000_0010); // shift amount mod 32

    // SLT (signed)
    check_op(dc_isa_pkg::ALU_SLT, 32'hffff_ffff, 32'h0000_0001, 32'h0000_0001); // -1 < 1 is true
    check_op(dc_isa_pkg::ALU_SLT, 32'h0000_0001, 32'hffff_ffff, 32'h0000_0000); // 1 < -1 is false
    check_op(dc_isa_pkg::ALU_SLT, 32'h7fff_ffff, 32'h8000_0000, 32'h0000_0000); // max pos < min neg is false

    // SLTU (unsigned)
    check_op(dc_isa_pkg::ALU_SLTU, 32'h0000_0001, 32'hffff_ffff, 32'h0000_0001); // 1 < 0xffffffff is true
    check_op(dc_isa_pkg::ALU_SLTU, 32'hffff_ffff, 32'h0000_0001, 32'h0000_0000);

    // XOR
    check_op(dc_isa_pkg::ALU_XOR, 32'h1234_5678, 32'hffff_ffff, 32'hedcb_a987);

    // SRL (logical shift right)
    check_op(dc_isa_pkg::ALU_SRL, 32'h8000_0000, 32'h0000_0004, 32'h0800_0000);

    // SRA (arithmetic shift right)
    check_op(dc_isa_pkg::ALU_SRA, 32'h8000_0000, 32'h0000_0004, 32'hf800_0000);
    check_op(dc_isa_pkg::ALU_SRA, 32'h7000_0000, 32'h0000_0004, 32'h0700_0000);

    // OR
    check_op(dc_isa_pkg::ALU_OR, 32'h1234_0000, 32'h0000_5678, 32'h1234_5678);

    // AND
    check_op(dc_isa_pkg::ALU_AND, 32'hffff_ffff, 32'h1234_5678, 32'h1234_5678);

    op = dc_isa_pkg::alu_op_e'(4'b1111);
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
