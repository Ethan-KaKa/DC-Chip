`default_nettype none

module decoder (
  input  logic [dc_isa_pkg::INST_WIDTH-1:0]     inst_i,
  output logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rd_addr_o,
  output logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rs1_addr_o,
  output logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rs2_addr_o,
  output logic [dc_isa_pkg::XLEN-1:0]           imm_i_o,
  output logic [dc_isa_pkg::XLEN-1:0]           imm_s_o,
  output logic [dc_isa_pkg::XLEN-1:0]           imm_b_o,
  output logic [dc_isa_pkg::XLEN-1:0]           imm_u_o,
  output logic [dc_isa_pkg::XLEN-1:0]           imm_j_o,
  output dc_isa_pkg::alu_op_e                   alu_op_o,
  output dc_isa_pkg::writeback_sel_e            writeback_sel_o,
  output dc_isa_pkg::mem_op_e                   mem_op_o,
  output dc_isa_pkg::branch_op_e                branch_op_o,
  output logic                                  jal_o,
  output logic                                  jalr_o,
  output logic                                  legal_o
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic       rd_valid;
  logic       rs1_valid;
  logic       rs2_valid;

  assign opcode = inst_i[6:0];
  assign funct3 = inst_i[14:12];
  assign funct7 = inst_i[31:25];

  assign rd_addr_o  = inst_i[10:7];
  assign rs1_addr_o = inst_i[18:15];
  assign rs2_addr_o = inst_i[23:20];

  assign imm_i_o = {{20{inst_i[31]}}, inst_i[31:20]};
  assign imm_s_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
  assign imm_b_o = {{20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
  assign imm_u_o = {inst_i[31:12], 12'b0};
  assign imm_j_o = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};

  // RV32E only supports x0..x15 (bit 4 must be 0)
  assign rd_valid  = (inst_i[11] == 1'b0);
  assign rs1_valid = (inst_i[19] == 1'b0);
  assign rs2_valid = (inst_i[24] == 1'b0);

  always_comb begin
    alu_op_o        = dc_isa_pkg::ALU_ADD;
    writeback_sel_o = dc_isa_pkg::WB_NONE;
    mem_op_o        = dc_isa_pkg::MEM_NONE;
    branch_op_o     = dc_isa_pkg::BRANCH_NONE;
    jal_o           = 1'b0;
    jalr_o          = 1'b0;
    legal_o         = 1'b0;

    case (^inst_i)
      1'b0, 1'b1: begin
        case (opcode)
          dc_isa_pkg::OPCODE_LUI: begin
            if (rd_valid) begin
              writeback_sel_o = dc_isa_pkg::WB_UIMM;
              legal_o         = 1'b1;
            end
          end

          dc_isa_pkg::OPCODE_AUIPC: begin
            if (rd_valid) begin
              writeback_sel_o = dc_isa_pkg::WB_AUIPC;
              legal_o         = 1'b1;
            end
          end

          dc_isa_pkg::OPCODE_JAL: begin
            if (rd_valid) begin
              writeback_sel_o = dc_isa_pkg::WB_PC4;
              jal_o           = 1'b1;
              legal_o         = 1'b1;
            end
          end

          dc_isa_pkg::OPCODE_JALR: begin
            if ((funct3 == dc_isa_pkg::FUNCT3_ADD_SUB) && rd_valid && rs1_valid) begin
              writeback_sel_o = dc_isa_pkg::WB_PC4;
              jalr_o          = 1'b1;
              legal_o         = 1'b1;
            end
          end

          dc_isa_pkg::OPCODE_BRANCH: begin
            if (rs1_valid && rs2_valid) begin
              case (funct3)
                dc_isa_pkg::FUNCT3_BEQ:  begin branch_op_o = dc_isa_pkg::BRANCH_BEQ;  legal_o = 1'b1; end
                dc_isa_pkg::FUNCT3_BNE:  begin branch_op_o = dc_isa_pkg::BRANCH_BNE;  legal_o = 1'b1; end
                dc_isa_pkg::FUNCT3_BLT:  begin branch_op_o = dc_isa_pkg::BRANCH_BLT;  legal_o = 1'b1; end
                dc_isa_pkg::FUNCT3_BGE:  begin branch_op_o = dc_isa_pkg::BRANCH_BGE;  legal_o = 1'b1; end
                dc_isa_pkg::FUNCT3_BLTU: begin branch_op_o = dc_isa_pkg::BRANCH_BLTU; legal_o = 1'b1; end
                dc_isa_pkg::FUNCT3_BGEU: begin branch_op_o = dc_isa_pkg::BRANCH_BGEU; legal_o = 1'b1; end
                default: begin end
              endcase
            end
          end

          dc_isa_pkg::OPCODE_LOAD: begin
            if (rd_valid && rs1_valid) begin
              case (funct3)
                dc_isa_pkg::FUNCT3_LB_SB: begin
                  writeback_sel_o = dc_isa_pkg::WB_LOAD;
                  mem_op_o        = dc_isa_pkg::MEM_LB;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_LH_SH: begin
                  writeback_sel_o = dc_isa_pkg::WB_LOAD;
                  mem_op_o        = dc_isa_pkg::MEM_LH;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_LW_SW: begin
                  writeback_sel_o = dc_isa_pkg::WB_LOAD;
                  mem_op_o        = dc_isa_pkg::MEM_LW;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_LBU: begin
                  writeback_sel_o = dc_isa_pkg::WB_LOAD;
                  mem_op_o        = dc_isa_pkg::MEM_LBU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_LHU: begin
                  writeback_sel_o = dc_isa_pkg::WB_LOAD;
                  mem_op_o        = dc_isa_pkg::MEM_LHU;
                  legal_o         = 1'b1;
                end
                default: begin end
              endcase
            end
          end

          dc_isa_pkg::OPCODE_STORE: begin
            if (rs1_valid && rs2_valid) begin
              case (funct3)
                dc_isa_pkg::FUNCT3_LB_SB: begin
                  mem_op_o = dc_isa_pkg::MEM_SB;
                  legal_o  = 1'b1;
                end
                dc_isa_pkg::FUNCT3_LH_SH: begin
                  mem_op_o = dc_isa_pkg::MEM_SH;
                  legal_o  = 1'b1;
                end
                dc_isa_pkg::FUNCT3_LW_SW: begin
                  mem_op_o = dc_isa_pkg::MEM_SW;
                  legal_o  = 1'b1;
                end
                default: begin end
              endcase
            end
          end

          dc_isa_pkg::OPCODE_OP_IMM: begin
            if (rd_valid && rs1_valid) begin
              case (funct3)
                dc_isa_pkg::FUNCT3_ADD_SUB: begin
                  alu_op_o        = dc_isa_pkg::ALU_ADD;
                  writeback_sel_o = dc_isa_pkg::WB_ALU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_SLT: begin
                  alu_op_o        = dc_isa_pkg::ALU_SLT;
                  writeback_sel_o = dc_isa_pkg::WB_ALU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_SLTU: begin
                  alu_op_o        = dc_isa_pkg::ALU_SLTU;
                  writeback_sel_o = dc_isa_pkg::WB_ALU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_XOR: begin
                  alu_op_o        = dc_isa_pkg::ALU_XOR;
                  writeback_sel_o = dc_isa_pkg::WB_ALU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_OR: begin
                  alu_op_o        = dc_isa_pkg::ALU_OR;
                  writeback_sel_o = dc_isa_pkg::WB_ALU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_AND: begin
                  alu_op_o        = dc_isa_pkg::ALU_AND;
                  writeback_sel_o = dc_isa_pkg::WB_ALU;
                  legal_o         = 1'b1;
                end
                dc_isa_pkg::FUNCT3_SLL: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SLL;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_SRL_SRA: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SRL;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end else if (funct7 == dc_isa_pkg::FUNCT7_ALT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SRA;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                default: begin end
              endcase
            end
          end

          dc_isa_pkg::OPCODE_OP: begin
            if (rd_valid && rs1_valid && rs2_valid) begin
              case (funct3)
                dc_isa_pkg::FUNCT3_ADD_SUB: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_ADD;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end else if (funct7 == dc_isa_pkg::FUNCT7_ALT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SUB;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_SLL: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SLL;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_SLT: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SLT;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_SLTU: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SLTU;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_XOR: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_XOR;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_SRL_SRA: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SRL;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end else if (funct7 == dc_isa_pkg::FUNCT7_ALT) begin
                    alu_op_o        = dc_isa_pkg::ALU_SRA;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_OR: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_OR;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                dc_isa_pkg::FUNCT3_AND: begin
                  if (funct7 == dc_isa_pkg::FUNCT7_DEFAULT) begin
                    alu_op_o        = dc_isa_pkg::ALU_AND;
                    writeback_sel_o = dc_isa_pkg::WB_ALU;
                    legal_o         = 1'b1;
                  end
                end
                default: begin end
              endcase
            end
          end

          dc_isa_pkg::OPCODE_MISC_MEM: begin
            // FENCE: Treated as NOP in single-core unprivileged environment
            if (funct3 == 3'b000) begin
              legal_o = 1'b1;
            end
          end

          default: begin end
        endcase
      end
      default: begin end
    endcase
  end
endmodule

`default_nettype wire
