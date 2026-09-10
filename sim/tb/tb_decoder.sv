`timescale 1ns/1ps
`default_nettype none

module tb_decoder;
  logic [15:0] inst;
  logic [1:0]  rd_addr;
  logic [1:0]  rs_addr;
  logic [15:0] imm;
  dc_isa_pkg::alu_op_e alu_op;
  logic alu_src_imm;
  logic reg_write;
  logic jump;
  logic legal;

  decoder dut (
    .inst_i        (inst),
    .rd_addr_o     (rd_addr),
    .rs_addr_o     (rs_addr),
    .imm_o         (imm),
    .alu_op_o      (alu_op),
    .alu_src_imm_o (alu_src_imm),
    .reg_write_o   (reg_write),
    .jump_o        (jump),
    .legal_o       (legal)
  );

  task automatic check_decode(
    input logic [15:0] test_inst,
    input logic [1:0]  expected_rd,
    input logic [1:0]  expected_rs,
    input logic [15:0] expected_imm,
    input logic [2:0]  expected_alu_op,
    input logic        expected_alu_src_imm,
    input logic        expected_reg_write,
    input logic        expected_jump,
    input logic        expected_legal
  );
    begin
      inst = test_inst;
      #1;
      if ((rd_addr !== expected_rd) ||
          (rs_addr !== expected_rs) ||
          (imm !== expected_imm) ||
          (alu_op !== expected_alu_op) ||
          (alu_src_imm !== expected_alu_src_imm) ||
          (reg_write !== expected_reg_write) ||
          (jump !== expected_jump) ||
          (legal !== expected_legal)) begin
        $fatal(1,
               {"tb_decoder: inst=%h expected rd=%b rs=%b imm=%h ",
                "alu=%b src_imm=%b write=%b jump=%b legal=%b; ",
                "actual rd=%b rs=%b imm=%h alu=%b src_imm=%b ",
                "write=%b jump=%b legal=%b"},
               test_inst,
               expected_rd, expected_rs, expected_imm, expected_alu_op,
               expected_alu_src_imm, expected_reg_write, expected_jump,
               expected_legal, rd_addr, rs_addr, imm, alu_op,
               alu_src_imm, reg_write, jump, legal);
      end
    end
  endtask

  task automatic check_safe_illegal(input logic [15:0] test_inst);
    begin
      check_decode(test_inst,
                   test_inst[11:10],
                   test_inst[9:8],
                   {8'h00, test_inst[7:0]},
                   dc_isa_pkg::ALU_PASS_B,
                   1'b0,
                   1'b0,
                   1'b0,
                   1'b0);
    end
  endtask

  integer opcode;

  initial begin
    inst = 16'h0000;

    check_decode(16'h0402, 2'b01, 2'b00, 16'h0002,
                 dc_isa_pkg::ALU_PASS_B, 1'b1, 1'b1, 1'b0, 1'b1);
    check_decode(16'h1900, 2'b10, 2'b01, 16'h0000,
                 dc_isa_pkg::ALU_PASS_B, 1'b0, 1'b1, 1'b0, 1'b1);
    check_decode(16'h2408, 2'b01, 2'b00, 16'h0008,
                 dc_isa_pkg::ALU_ADD, 1'b1, 1'b1, 1'b0, 1'b1);
    check_decode(16'h3600, 2'b01, 2'b10, 16'h0000,
                 dc_isa_pkg::ALU_ADD, 1'b0, 1'b1, 1'b0, 1'b1);
    check_decode(16'h4600, 2'b01, 2'b10, 16'h0000,
                 dc_isa_pkg::ALU_SUB, 1'b0, 1'b1, 1'b0, 1'b1);
    check_decode(16'h5600, 2'b01, 2'b10, 16'h0000,
                 dc_isa_pkg::ALU_AND, 1'b0, 1'b1, 1'b0, 1'b1);
    check_decode(16'h6600, 2'b01, 2'b10, 16'h0000,
                 dc_isa_pkg::ALU_OR, 1'b0, 1'b1, 1'b0, 1'b1);
    check_decode(16'h7008, 2'b00, 2'b00, 16'h0008,
                 dc_isa_pkg::ALU_PASS_B, 1'b0, 1'b0, 1'b1, 1'b1);

    check_safe_illegal(16'h0101);
    check_safe_illegal(16'h2201);
    check_safe_illegal(16'h1101);
    check_safe_illegal(16'h3101);
    check_safe_illegal(16'h4101);
    check_safe_illegal(16'h5101);
    check_safe_illegal(16'h6101);
    check_safe_illegal(16'h7401);
    check_safe_illegal(16'h7101);

    for (opcode = 8; opcode <= 15; opcode = opcode + 1) begin
      check_safe_illegal({opcode[3:0], 4'ha, 8'h5a});
    end

    check_safe_illegal(16'b0x00_01_00_10100101);
    check_safe_illegal(16'b0z00_10_00_01011010);
    check_safe_illegal(16'b0000_11_0x_11110000);
    check_safe_illegal(16'b0010_10_0z_00001111);
    check_safe_illegal(16'b0001_01_10_000x0000);
    check_safe_illegal(16'b0110_10_01_000z0000);
    check_safe_illegal(16'b0111_0x_00_00111100);
    check_safe_illegal(16'b0111_00_0z_11000011);

    $display("tb_decoder: PASS");
    disable timeout_block;
  end

  initial begin : timeout_block
    #1000;
    $fatal(1, "tb_decoder: timeout");
  end
endmodule

`default_nettype wire
