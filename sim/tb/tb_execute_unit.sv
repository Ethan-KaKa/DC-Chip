`timescale 1ns/1ps
`default_nettype none

module tb_execute_unit;
  dc_isa_pkg::decode_info_t decode;
  logic [31:0] pc, rs1, rs2;
  logic [31:0] result, next_pc;
  logic branch_taken, control_misaligned;

  execute_unit dut (
    .decode_i(decode), .pc_i(pc), .rs1_data_i(rs1), .rs2_data_i(rs2),
    .result_o(result), .next_pc_o(next_pc),
    .branch_taken_o(branch_taken),
    .control_misaligned_o(control_misaligned)
  );

  task automatic init_decode;
    begin
      decode = '0;
      decode.alu_op = dc_isa_pkg::ALU_ADD;
      decode.operand_a_sel = dc_isa_pkg::OPERAND_A_ZERO;
      decode.operand_b_sel = dc_isa_pkg::OPERAND_B_RS2;
      decode.writeback_sel = dc_isa_pkg::WB_ALU;
      decode.branch_op = dc_isa_pkg::BRANCH_NONE;
      decode.control_flow = dc_isa_pkg::CONTROL_NONE;
      pc = 32'h100;
      rs1 = 32'd7;
      rs2 = 32'd3;
    end
  endtask

  task automatic expect_branch(
    input dc_isa_pkg::branch_op_e op,
    input logic [31:0] lhs,
    input logic [31:0] rhs,
    input logic expected
  );
    begin
      decode.branch_op = op;
      decode.control_flow = dc_isa_pkg::CONTROL_BRANCH;
      decode.imm = 32'd8;
      rs1 = lhs;
      rs2 = rhs;
      #1;
      if ((branch_taken !== expected) ||
          (next_pc !== (expected ? pc + 32'd8 : pc + 32'd4)) ||
          control_misaligned) $fatal(1, "tb_execute_unit: branch %0d", op);
    end
  endtask

  initial begin
    init_decode();
    decode.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
    decode.operand_b_sel = dc_isa_pkg::OPERAND_B_RS2;
    #1;
    if (result !== 32'd10) $fatal(1, "tb_execute_unit: rs1/rs2 add");

    decode.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
    decode.imm = 32'hffff_fffc;
    #1;
    if (result !== 32'd3) $fatal(1, "tb_execute_unit: immediate add");

    decode.operand_a_sel = dc_isa_pkg::OPERAND_A_ZERO;
    decode.imm = 32'h1234_5000;
    #1;
    if (result !== 32'h1234_5000) $fatal(1, "tb_execute_unit: LUI path");

    decode.operand_a_sel = dc_isa_pkg::OPERAND_A_PC;
    #1;
    if (result !== 32'h1234_5100) $fatal(1, "tb_execute_unit: AUIPC path");

    decode.writeback_sel = dc_isa_pkg::WB_PC4;
    #1;
    if (result !== 32'h104) $fatal(1, "tb_execute_unit: PC+4 writeback");

    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BEQ,  5, 5, 1'b1);
    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BNE,  5, 4, 1'b1);
    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BLT,  32'hffff_ffff, 1, 1'b1);
    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BGE,  1, 32'hffff_ffff, 1'b1);
    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BLTU, 1, 32'hffff_ffff, 1'b1);
    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BGEU, 32'hffff_ffff, 1, 1'b1);
    init_decode(); expect_branch(dc_isa_pkg::BRANCH_BEQ,  5, 4, 1'b0);
    init_decode();
    decode.branch_op = dc_isa_pkg::BRANCH_BEQ;
    decode.control_flow = dc_isa_pkg::CONTROL_BRANCH;
    decode.imm = 32'd2;
    rs1 = 1;
    rs2 = 1;
    #1;
    if (!control_misaligned) $fatal(1, "tb_execute_unit: taken branch alignment");
    rs2 = 2;
    #1;
    if (control_misaligned || next_pc !== pc + 32'd4)
      $fatal(1, "tb_execute_unit: untaken branch alignment");

    init_decode();
    decode.control_flow = dc_isa_pkg::CONTROL_JAL;
    decode.imm = 32'd12;
    #1;
    if ((next_pc !== 32'h10c) || control_misaligned) $fatal(1, "tb_execute_unit: JAL");
    decode.imm = 32'd6;
    #1;
    if (!control_misaligned) $fatal(1, "tb_execute_unit: JAL alignment");

    init_decode();
    decode.control_flow = dc_isa_pkg::CONTROL_JALR;
    decode.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
    decode.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
    decode.imm = 0;
    rs1 = 7;
    #1;
    if ((next_pc !== 6) || !control_misaligned) $fatal(1, "tb_execute_unit: JALR clear bit zero");
    rs1 = 5;
    #1;
    if ((next_pc !== 4) || control_misaligned) $fatal(1, "tb_execute_unit: JALR aligned");

    $display("tb_execute_unit: PASS");
  end
endmodule

`default_nettype wire
