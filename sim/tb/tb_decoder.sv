`timescale 1ns/1ps
`default_nettype none

module tb_decoder;
  logic [31:0] inst;
  logic [3:0]  rd_addr;
  logic [3:0]  rs1_addr;
  logic [3:0]  rs2_addr;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_b;
  logic [31:0] imm_u;
  logic [31:0] imm_j;
  dc_isa_pkg::alu_op_e        alu_op;
  dc_isa_pkg::writeback_sel_e writeback_sel;
  dc_isa_pkg::mem_op_e        mem_op;
  dc_isa_pkg::branch_op_e     branch_op;
  logic                       jal;
  logic                       jalr;
  logic                       legal;

  decoder dut (
    .inst_i         (inst),
    .rd_addr_o      (rd_addr),
    .rs1_addr_o     (rs1_addr),
    .rs2_addr_o     (rs2_addr),
    .imm_i_o        (imm_i),
    .imm_s_o        (imm_s),
    .imm_b_o        (imm_b),
    .imm_u_o        (imm_u),
    .imm_j_o        (imm_j),
    .alu_op_o       (alu_op),
    .writeback_sel_o(writeback_sel),
    .mem_op_o       (mem_op),
    .branch_op_o    (branch_op),
    .jal_o          (jal),
    .jalr_o         (jalr),
    .legal_o        (legal)
  );

  task automatic check_decode(
    input logic [31:0] test_inst,
    input dc_isa_pkg::writeback_sel_e expected_writeback,
    input dc_isa_pkg::mem_op_e        expected_mem_op,
    input dc_isa_pkg::branch_op_e     expected_branch_op,
    input logic                       expected_jal,
    input logic                       expected_jalr,
    input logic                       expected_legal
  );
    begin
      inst = test_inst;
      #1;
      if ((rd_addr !== test_inst[10:7]) ||
          (rs1_addr !== test_inst[18:15]) ||
          (rs2_addr !== test_inst[23:20]) ||
          (writeback_sel !== expected_writeback) ||
          (mem_op !== expected_mem_op) ||
          (branch_op !== expected_branch_op) ||
          (jal !== expected_jal) ||
          (jalr !== expected_jalr) ||
          (legal !== expected_legal)) begin
        $fatal(1,
               {"tb_decoder: inst=%h expected wb=%0d mem=%0d br=%0d jal=%b jalr=%b legal=%b; ",
                "actual rd=%0d rs1=%0d rs2=%0d wb=%0d mem=%0d br=%0d jal=%b jalr=%b legal=%b"},
               test_inst, expected_writeback, expected_mem_op, expected_branch_op,
               expected_jal, expected_jalr, expected_legal, rd_addr, rs1_addr,
               rs2_addr, writeback_sel, mem_op, branch_op, jal, jalr, legal);
      end
    end
  endtask

  task automatic check_illegal(input logic [31:0] test_inst);
    begin
      check_decode(test_inst, dc_isa_pkg::WB_NONE, dc_isa_pkg::MEM_NONE,
                   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b0);
    end
  endtask

  initial begin
    inst = 32'h00000000;

    // 1. Existing instructions
    check_decode(32'h002081b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // add
    check_decode(32'hfff08193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // addi
    check_decode(32'h123451b7, dc_isa_pkg::WB_UIMM,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // lui
    check_decode(32'h0040a183, dc_isa_pkg::WB_LOAD,  dc_isa_pkg::MEM_LW,   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // lw
    check_decode(32'h0010c183, dc_isa_pkg::WB_LOAD,  dc_isa_pkg::MEM_LBU,  dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // lbu
    check_decode(32'h0020a223, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_SW,   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sw
    check_decode(32'h002080a3, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_SB,   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sb
    check_decode(32'h008082e7, dc_isa_pkg::WB_PC4,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b1, 1'b1); // jalr

    // 2. New RV32E instructions
    check_decode(32'h00000117, dc_isa_pkg::WB_AUIPC, dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // auipc
    check_decode(32'h000000ef, dc_isa_pkg::WB_PC4,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b1, 1'b0, 1'b1); // jal
    check_decode(32'h00208063, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_BEQ,  1'b0, 1'b0, 1'b1); // beq
    check_decode(32'h00209063, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_BNE,  1'b0, 1'b0, 1'b1); // bne
    check_decode(32'h0020c063, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_BLT,  1'b0, 1'b0, 1'b1); // blt
    check_decode(32'h0020d063, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_BGE,  1'b0, 1'b0, 1'b1); // bge
    check_decode(32'h0020e063, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_BLTU, 1'b0, 1'b0, 1'b1); // bltu
    check_decode(32'h0020f063, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_BGEU, 1'b0, 1'b0, 1'b1); // bgeu

    check_decode(32'h00008103, dc_isa_pkg::WB_LOAD,  dc_isa_pkg::MEM_LB,   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // lb
    check_decode(32'h00009103, dc_isa_pkg::WB_LOAD,  dc_isa_pkg::MEM_LH,   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // lh
    check_decode(32'h0000d103, dc_isa_pkg::WB_LOAD,  dc_isa_pkg::MEM_LHU,  dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // lhu
    check_decode(32'h00209023, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_SH,   dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sh

    check_decode(32'h402081b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sub
    check_decode(32'h002091b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sll
    check_decode(32'h0020a1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // slt
    check_decode(32'h0020b1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sltu
    check_decode(32'h0020c1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // xor
    check_decode(32'h0020d1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // srl
    check_decode(32'h4020d1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sra
    check_decode(32'h0020e1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // or
    check_decode(32'h0020f1b3, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // and

    check_decode(32'h00109193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // slli
    check_decode(32'h0010d193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // srli
    check_decode(32'h4010d193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // srai
    check_decode(32'h0010a193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // slti
    check_decode(32'h0010b193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // sltiu
    check_decode(32'h0010c193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // xori
    check_decode(32'h0010e193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // ori
    check_decode(32'h0010f193, dc_isa_pkg::WB_ALU,   dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // andi
    check_decode(32'h0000000f, dc_isa_pkg::WB_NONE,  dc_isa_pkg::MEM_NONE, dc_isa_pkg::BRANCH_NONE, 1'b0, 1'b0, 1'b1); // fence

    // 3. Register boundary rejection for x16..x31
    check_illegal(32'h00208833);  // add rd=x16
    check_illegal(32'h002800b3);  // add rs1=x16
    check_illegal(32'h010080b3);  // add rs2=x16
    check_illegal(32'h00008813);  // addi rd=x16
    check_illegal(32'h00080093);  // addi rs1=x16
    check_illegal(32'h0000a803);  // lw rd=x16
    check_illegal(32'h00082083);  // lw rs1=x16
    check_illegal(32'h0100a023);  // sw rs2=x16
    check_illegal(32'h00282023);  // sw rs1=x16
    check_illegal(32'h000008ef);  // jal rd=x16
    check_illegal(32'h00000817);  // auipc rd=x16
    check_illegal(32'h01008063);  // beq rs2=x16
    check_illegal(32'h00280063);  // beq rs1=x16

    // 4. Unknown/X/Z testing
    inst = 32'b0000000_00010_00001_000_00011_0x10011;
    #1;
    if ((legal !== 1'b0) || (writeback_sel !== dc_isa_pkg::WB_NONE) ||
        (mem_op !== dc_isa_pkg::MEM_NONE) || (jalr !== 1'b0) || (jal !== 1'b0)) begin
      $fatal(1, "tb_decoder: X opcode did not select safe controls");
    end

    $display("tb_decoder: PASS");
    disable timeout_block;
  end

  initial begin : timeout_block
    #100000;
    $fatal(1, "tb_decoder: timeout");
  end
endmodule

`default_nettype wire
