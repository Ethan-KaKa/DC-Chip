`timescale 1ns/1ps
`default_nettype none

module tb_decoder;
  logic [31:0] inst;
  logic [3:0]  rd_addr;
  logic [3:0]  rs1_addr;
  logic [3:0]  rs2_addr;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_u;
  dc_isa_pkg::alu_op_e        alu_op;
  dc_isa_pkg::writeback_sel_e writeback_sel;
  dc_isa_pkg::mem_op_e        mem_op;
  logic                       jalr;
  logic                       legal;

  decoder dut (
    .inst_i         (inst),
    .rd_addr_o      (rd_addr),
    .rs1_addr_o     (rs1_addr),
    .rs2_addr_o     (rs2_addr),
    .imm_i_o        (imm_i),
    .imm_s_o        (imm_s),
    .imm_u_o        (imm_u),
    .alu_op_o       (alu_op),
    .writeback_sel_o(writeback_sel),
    .mem_op_o       (mem_op),
    .jalr_o         (jalr),
    .legal_o        (legal)
  );

  task automatic check_decode(
    input logic [31:0] test_inst,
    input logic [2:0]  expected_writeback,
    input logic [2:0]  expected_mem_op,
    input logic        expected_jalr,
    input logic        expected_legal
  );
    logic [31:0] expected_imm_i;
    logic [31:0] expected_imm_s;
    logic [31:0] expected_imm_u;
    begin
      expected_imm_i = {{20{test_inst[31]}}, test_inst[31:20]};
      expected_imm_s = {{20{test_inst[31]}}, test_inst[31:25],
                        test_inst[11:7]};
      expected_imm_u = {test_inst[31:12], 12'b0};
      inst = test_inst;
      #1;
      if ((rd_addr !== test_inst[10:7]) ||
          (rs1_addr !== test_inst[18:15]) ||
          (rs2_addr !== test_inst[23:20]) ||
          (imm_i !== expected_imm_i) || (imm_s !== expected_imm_s) ||
          (imm_u !== expected_imm_u) ||
          (alu_op !== dc_isa_pkg::ALU_ADD) ||
          (writeback_sel !== expected_writeback) ||
          (mem_op !== expected_mem_op) || (jalr !== expected_jalr) ||
          (legal !== expected_legal)) begin
        $fatal(1,
               {"tb_decoder: inst=%h expected wb=%0d mem=%0d ",
                "jalr=%b legal=%b; actual rd=%0d rs1=%0d rs2=%0d ",
                "imm_i=%h imm_s=%h imm_u=%h alu=%0d wb=%0d mem=%0d ",
                "jalr=%b legal=%b"},
               test_inst, expected_writeback, expected_mem_op,
               expected_jalr, expected_legal, rd_addr, rs1_addr,
               rs2_addr, imm_i, imm_s, imm_u, alu_op, writeback_sel,
               mem_op, jalr, legal);
      end
    end
  endtask

  task automatic check_illegal(input logic [31:0] test_inst);
    begin
      check_decode(test_inst, dc_isa_pkg::WB_NONE,
                   dc_isa_pkg::MEM_NONE, 1'b0, 1'b0);
    end
  endtask

  integer funct3_value;
  integer funct7_value;
  integer opcode_value;
  integer register_value;

  initial begin
    inst = 32'h00000000;

    check_decode(32'h002081b3, dc_isa_pkg::WB_ALU,
                 dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
    check_decode(32'hfff08193, dc_isa_pkg::WB_ALU,
                 dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
    check_decode(32'h123451b7, dc_isa_pkg::WB_UIMM,
                 dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
    check_decode(32'h0040a183, dc_isa_pkg::WB_LOAD,
                 dc_isa_pkg::MEM_LW, 1'b0, 1'b1);
    check_decode(32'h0010c183, dc_isa_pkg::WB_LOAD,
                 dc_isa_pkg::MEM_LBU, 1'b0, 1'b1);
    check_decode(32'h0020a223, dc_isa_pkg::WB_NONE,
                 dc_isa_pkg::MEM_SW, 1'b0, 1'b1);
    check_decode(32'h002080a3, dc_isa_pkg::WB_NONE,
                 dc_isa_pkg::MEM_SB, 1'b0, 1'b1);
    check_decode(32'h008082e7, dc_isa_pkg::WB_PC4,
                 dc_isa_pkg::MEM_NONE, 1'b1, 1'b1);

    for (register_value = 0; register_value < 16;
         register_value = register_value + 1) begin
      check_decode({7'd0, register_value[4:0], register_value[4:0], 3'b000,
                    register_value[4:0], dc_isa_pkg::OPCODE_OP},
                   dc_isa_pkg::WB_ALU, dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
      check_decode({12'h800, register_value[4:0], 3'b000,
                    register_value[4:0], dc_isa_pkg::OPCODE_OP_IMM},
                   dc_isa_pkg::WB_ALU, dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
      check_decode({20'habcde, register_value[4:0], dc_isa_pkg::OPCODE_LUI},
                   dc_isa_pkg::WB_UIMM, dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
      check_decode({12'd0, register_value[4:0], 3'b010,
                    register_value[4:0], dc_isa_pkg::OPCODE_LOAD},
                   dc_isa_pkg::WB_LOAD, dc_isa_pkg::MEM_LW, 1'b0, 1'b1);
      check_decode({12'd0, register_value[4:0], 3'b100,
                    register_value[4:0], dc_isa_pkg::OPCODE_LOAD},
                   dc_isa_pkg::WB_LOAD, dc_isa_pkg::MEM_LBU, 1'b0, 1'b1);
      check_decode({7'd0, register_value[4:0], register_value[4:0], 3'b010,
                    5'd0, dc_isa_pkg::OPCODE_STORE},
                   dc_isa_pkg::WB_NONE, dc_isa_pkg::MEM_SW, 1'b0, 1'b1);
      check_decode({7'd0, register_value[4:0], register_value[4:0], 3'b000,
                    5'd0, dc_isa_pkg::OPCODE_STORE},
                   dc_isa_pkg::WB_NONE, dc_isa_pkg::MEM_SB, 1'b0, 1'b1);
      check_decode({12'd0, register_value[4:0], 3'b000,
                    register_value[4:0], dc_isa_pkg::OPCODE_JALR},
                   dc_isa_pkg::WB_PC4, dc_isa_pkg::MEM_NONE, 1'b1, 1'b1);
    end

    check_decode(32'h80008193, dc_isa_pkg::WB_ALU,
                 dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);
    if (imm_i !== 32'hfffff800) begin
      $fatal(1, "tb_decoder: I-immediate -2048 decoded as %h", imm_i);
    end
    check_decode(32'h7e20afa3, dc_isa_pkg::WB_NONE,
                 dc_isa_pkg::MEM_SW, 1'b0, 1'b1);
    if (imm_s !== 32'h000007ff) begin
      $fatal(1, "tb_decoder: S-immediate 2047 decoded as %h", imm_s);
    end

    // LUI does not use the bit positions occupied by rs1/rs2 in other formats.
    check_decode(32'hfffff7b7, dc_isa_pkg::WB_UIMM,
                 dc_isa_pkg::MEM_NONE, 1'b0, 1'b1);

    // Every actually used register field rejects x16--x31 independently.
    check_illegal(32'h00208833);  // add rd=x16
    check_illegal(32'h002800b3);  // add rs1=x16
    check_illegal(32'h010080b3);  // add rs2=x16
    check_illegal(32'h00008813);  // addi rd=x16
    check_illegal(32'h00080093);  // addi rs1=x16
    check_illegal(32'h0000a803);  // lw rd=x16
    check_illegal(32'h00082083);  // lw rs1=x16
    check_illegal(32'h0000c803);  // lbu rd=x16
    check_illegal(32'h00084083);  // lbu rs1=x16
    check_illegal(32'h0100a023);  // sw rs2=x16
    check_illegal(32'h00282023);  // sw rs1=x16
    check_illegal(32'h01008023);  // sb rs2=x16
    check_illegal(32'h00280023);  // sb rs1=x16
    check_illegal(32'h00008867);  // jalr rd=x16
    check_illegal(32'h000800e7);  // jalr rs1=x16
    check_illegal(32'h00000837);  // lui rd=x16

    // ADD is the only accepted OP funct3/funct7 combination.
    for (funct3_value = 0; funct3_value < 8;
         funct3_value = funct3_value + 1) begin
      for (funct7_value = 0; funct7_value < 128;
           funct7_value = funct7_value + 1) begin
        if ((funct3_value != 0) || (funct7_value != 0)) begin
          check_illegal({funct7_value[6:0], 5'd2, 5'd1,
                         funct3_value[2:0], 5'd3,
                         dc_isa_pkg::OPCODE_OP});
        end
      end
    end

    // Only assigned funct3 values are accepted for the other opcode groups.
    for (funct3_value = 0; funct3_value < 8;
         funct3_value = funct3_value + 1) begin
      if (funct3_value != 0) begin
        check_illegal({12'd0, 5'd1, funct3_value[2:0], 5'd3,
                       dc_isa_pkg::OPCODE_OP_IMM});
        check_illegal({12'd0, 5'd1, funct3_value[2:0], 5'd3,
                       dc_isa_pkg::OPCODE_JALR});
      end
      if ((funct3_value != 2) && (funct3_value != 4)) begin
        check_illegal({12'd0, 5'd1, funct3_value[2:0], 5'd3,
                       dc_isa_pkg::OPCODE_LOAD});
      end
      if ((funct3_value != 0) && (funct3_value != 2)) begin
        check_illegal({7'd0, 5'd2, 5'd1, funct3_value[2:0], 5'd0,
                       dc_isa_pkg::OPCODE_STORE});
      end
    end

    for (opcode_value = 0; opcode_value < 128;
         opcode_value = opcode_value + 1) begin
      if ((opcode_value != dc_isa_pkg::OPCODE_LOAD) &&
          (opcode_value != dc_isa_pkg::OPCODE_OP_IMM) &&
          (opcode_value != dc_isa_pkg::OPCODE_STORE) &&
          (opcode_value != dc_isa_pkg::OPCODE_OP) &&
          (opcode_value != dc_isa_pkg::OPCODE_LUI) &&
          (opcode_value != dc_isa_pkg::OPCODE_JALR)) begin
        check_illegal({25'd0, opcode_value[6:0]});
      end
    end

    inst = 32'b0000000_00010_00001_000_00011_0x10011;
    #1;
    if ((legal !== 1'b0) || (writeback_sel !== dc_isa_pkg::WB_NONE) ||
        (mem_op !== dc_isa_pkg::MEM_NONE) || (jalr !== 1'b0)) begin
      $fatal(1, "tb_decoder: X opcode did not select safe controls");
    end
    inst = 32'b0000000_00010_00001_0z0_00011_0110011;
    #1;
    if ((legal !== 1'b0) || (writeback_sel !== dc_isa_pkg::WB_NONE) ||
        (mem_op !== dc_isa_pkg::MEM_NONE) || (jalr !== 1'b0)) begin
      $fatal(1, "tb_decoder: Z funct3 did not select safe controls");
    end
    inst = 32'b000000x_00010_00001_000_00011_0110011;
    #1;
    if ((legal !== 1'b0) || (writeback_sel !== dc_isa_pkg::WB_NONE) ||
        (mem_op !== dc_isa_pkg::MEM_NONE) || (jalr !== 1'b0)) begin
      $fatal(1, "tb_decoder: X funct7 did not select safe controls");
    end
    inst = 32'b0000000_00010_00001_000_00011_011011x;
    #1;
    if ((legal !== 1'b0) || (writeback_sel !== dc_isa_pkg::WB_NONE) ||
        (mem_op !== dc_isa_pkg::MEM_NONE) || (jalr !== 1'b0)) begin
      $fatal(1, "tb_decoder: X LUI immediate did not select safe controls");
    end
    inst = 32'b0000000_00010_00001_000_00011_0010011;
    inst[31] = 1'bz;
    #1;
    if ((legal !== 1'b0) || (writeback_sel !== dc_isa_pkg::WB_NONE) ||
        (mem_op !== dc_isa_pkg::MEM_NONE) || (jalr !== 1'b0)) begin
      $fatal(1, "tb_decoder: Z I-immediate did not select safe controls");
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
