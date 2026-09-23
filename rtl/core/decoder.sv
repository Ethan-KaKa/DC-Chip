`default_nettype none

module decoder (
  input  logic [dc_isa_pkg::INST_WIDTH-1:0] inst_i,
  output dc_isa_pkg::decode_info_t          decode_o
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  logic rd_valid, rs1_valid, rs2_valid;

  assign opcode = inst_i[6:0];
  assign funct3 = inst_i[14:12];
  assign funct7 = inst_i[31:25];
  assign imm_i = {{20{inst_i[31]}}, inst_i[31:20]};
  assign imm_s = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
  assign imm_b = {{20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
  assign imm_u = {inst_i[31:12], 12'b0};
  assign imm_j = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
  assign rd_valid  = (inst_i[11] == 1'b0);
  assign rs1_valid = (inst_i[19] == 1'b0);
  assign rs2_valid = (inst_i[24] == 1'b0);

  always_comb begin
    decode_o = '0;
    decode_o.rd = inst_i[10:7];
    decode_o.rs1 = inst_i[18:15];
    decode_o.rs2 = inst_i[23:20];
    decode_o.alu_op = dc_isa_pkg::ALU_ADD;
    decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_ZERO;
    decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_RS2;
    decode_o.writeback_sel = dc_isa_pkg::WB_NONE;
    decode_o.mem_op = dc_isa_pkg::MEM_NONE;
    decode_o.branch_op = dc_isa_pkg::BRANCH_NONE;
    decode_o.control_flow = dc_isa_pkg::CONTROL_NONE;

    case (^inst_i)
      1'b0, 1'b1: case (opcode)
        dc_isa_pkg::OPCODE_LUI: if (rd_valid) begin
          decode_o.imm = imm_u;
          decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
          decode_o.writeback_sel = dc_isa_pkg::WB_ALU;
          decode_o.legal = 1'b1;
        end
        dc_isa_pkg::OPCODE_AUIPC: if (rd_valid) begin
          decode_o.imm = imm_u;
          decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_PC;
          decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
          decode_o.writeback_sel = dc_isa_pkg::WB_ALU;
          decode_o.legal = 1'b1;
        end
        dc_isa_pkg::OPCODE_JAL: if (rd_valid) begin
          decode_o.imm = imm_j;
          decode_o.writeback_sel = dc_isa_pkg::WB_PC4;
          decode_o.control_flow = dc_isa_pkg::CONTROL_JAL;
          decode_o.legal = 1'b1;
        end
        dc_isa_pkg::OPCODE_JALR: if ((funct3 == 3'b000) && rd_valid && rs1_valid) begin
          decode_o.imm = imm_i;
          decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
          decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
          decode_o.writeback_sel = dc_isa_pkg::WB_PC4;
          decode_o.control_flow = dc_isa_pkg::CONTROL_JALR;
          decode_o.legal = 1'b1;
        end
        dc_isa_pkg::OPCODE_BRANCH: if (rs1_valid && rs2_valid) begin
          decode_o.imm = imm_b;
          decode_o.control_flow = dc_isa_pkg::CONTROL_BRANCH;
          case (funct3)
            dc_isa_pkg::FUNCT3_BEQ:  begin decode_o.branch_op = dc_isa_pkg::BRANCH_BEQ;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_BNE:  begin decode_o.branch_op = dc_isa_pkg::BRANCH_BNE;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_BLT:  begin decode_o.branch_op = dc_isa_pkg::BRANCH_BLT;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_BGE:  begin decode_o.branch_op = dc_isa_pkg::BRANCH_BGE;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_BLTU: begin decode_o.branch_op = dc_isa_pkg::BRANCH_BLTU; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_BGEU: begin decode_o.branch_op = dc_isa_pkg::BRANCH_BGEU; decode_o.legal = 1'b1; end
            default: begin end
          endcase
        end
        dc_isa_pkg::OPCODE_LOAD: if (rd_valid && rs1_valid) begin
          decode_o.imm = imm_i;
          decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
          decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
          decode_o.writeback_sel = dc_isa_pkg::WB_LOAD;
          case (funct3)
            dc_isa_pkg::FUNCT3_LB_SB: begin decode_o.mem_op = dc_isa_pkg::MEM_LB;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_LH_SH: begin decode_o.mem_op = dc_isa_pkg::MEM_LH;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_LW_SW: begin decode_o.mem_op = dc_isa_pkg::MEM_LW;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_LBU:   begin decode_o.mem_op = dc_isa_pkg::MEM_LBU; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_LHU:   begin decode_o.mem_op = dc_isa_pkg::MEM_LHU; decode_o.legal = 1'b1; end
            default: begin end
          endcase
        end
        dc_isa_pkg::OPCODE_STORE: if (rs1_valid && rs2_valid) begin
          decode_o.imm = imm_s;
          decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
          decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
          case (funct3)
            dc_isa_pkg::FUNCT3_LB_SB: begin decode_o.mem_op = dc_isa_pkg::MEM_SB; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_LH_SH: begin decode_o.mem_op = dc_isa_pkg::MEM_SH; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_LW_SW: begin decode_o.mem_op = dc_isa_pkg::MEM_SW; decode_o.legal = 1'b1; end
            default: begin end
          endcase
        end
        dc_isa_pkg::OPCODE_OP_IMM: if (rd_valid && rs1_valid) begin
          decode_o.imm = imm_i;
          decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
          decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_IMM;
          decode_o.writeback_sel = dc_isa_pkg::WB_ALU;
          case (funct3)
            dc_isa_pkg::FUNCT3_ADD_SUB: begin decode_o.alu_op = dc_isa_pkg::ALU_ADD;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SLT:     begin decode_o.alu_op = dc_isa_pkg::ALU_SLT;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SLTU:    begin decode_o.alu_op = dc_isa_pkg::ALU_SLTU; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_XOR:     begin decode_o.alu_op = dc_isa_pkg::ALU_XOR;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_OR:      begin decode_o.alu_op = dc_isa_pkg::ALU_OR;   decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_AND:     begin decode_o.alu_op = dc_isa_pkg::ALU_AND;  decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SLL: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_SLL; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SRL_SRA: begin
              if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_SRL; decode_o.legal = 1'b1; end
              else if (funct7 == dc_isa_pkg::FUNCT7_ALT) begin decode_o.alu_op = dc_isa_pkg::ALU_SRA; decode_o.legal = 1'b1; end
            end
            default: begin end
          endcase
        end
        dc_isa_pkg::OPCODE_OP: if (rd_valid && rs1_valid && rs2_valid) begin
          decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_RS1;
          decode_o.writeback_sel = dc_isa_pkg::WB_ALU;
          case (funct3)
            dc_isa_pkg::FUNCT3_ADD_SUB: begin
              if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_ADD; decode_o.legal = 1'b1; end
              else if (funct7 == dc_isa_pkg::FUNCT7_ALT) begin decode_o.alu_op = dc_isa_pkg::ALU_SUB; decode_o.legal = 1'b1; end
            end
            dc_isa_pkg::FUNCT3_SLL: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_SLL; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SLT: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_SLT; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SLTU: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_SLTU; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_XOR: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_XOR; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_SRL_SRA: begin
              if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_SRL; decode_o.legal = 1'b1; end
              else if (funct7 == dc_isa_pkg::FUNCT7_ALT) begin decode_o.alu_op = dc_isa_pkg::ALU_SRA; decode_o.legal = 1'b1; end
            end
            dc_isa_pkg::FUNCT3_OR: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_OR; decode_o.legal = 1'b1; end
            dc_isa_pkg::FUNCT3_AND: if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin decode_o.alu_op = dc_isa_pkg::ALU_AND; decode_o.legal = 1'b1; end
            default: begin end
          endcase
        end
        dc_isa_pkg::OPCODE_MISC_MEM: if (funct3 == 3'b000) decode_o.legal = 1'b1;
        default: begin end
      endcase
      default: begin end
    endcase

    if (!decode_o.legal) begin
      decode_o.imm = '0;
      decode_o.alu_op = dc_isa_pkg::ALU_ADD;
      decode_o.operand_a_sel = dc_isa_pkg::OPERAND_A_ZERO;
      decode_o.operand_b_sel = dc_isa_pkg::OPERAND_B_RS2;
      decode_o.writeback_sel = dc_isa_pkg::WB_NONE;
      decode_o.mem_op = dc_isa_pkg::MEM_NONE;
      decode_o.branch_op = dc_isa_pkg::BRANCH_NONE;
      decode_o.control_flow = dc_isa_pkg::CONTROL_NONE;
    end
  end
endmodule

`default_nettype wire
