`default_nettype none

module execute_unit (
  /* verilator lint_off UNUSEDSIGNAL */
  input  dc_isa_pkg::decode_info_t             decode_i,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [dc_isa_pkg::PC_WIDTH-1:0]      pc_i,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0]    rs1_data_i,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0]    rs2_data_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]    result_o,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]      next_pc_o,
  output logic                                  branch_taken_o,
  output logic                                  control_misaligned_o
);
  logic [dc_isa_pkg::DATA_WIDTH-1:0] operand_a;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] operand_b;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] alu_result;
  logic [dc_isa_pkg::PC_WIDTH-1:0] control_target;

  always_comb begin
    case (decode_i.operand_a_sel)
      dc_isa_pkg::OPERAND_A_RS1: operand_a = rs1_data_i;
      dc_isa_pkg::OPERAND_A_PC:  operand_a = pc_i;
      default:                   operand_a = '0;
    endcase
    operand_b = (decode_i.operand_b_sel == dc_isa_pkg::OPERAND_B_IMM)
              ? decode_i.imm : rs2_data_i;
  end

  alu u_alu (
    .lhs_i    (operand_a),
    .rhs_i    (operand_b),
    .op_i     (decode_i.alu_op),
    .result_o (alu_result)
  );

  always_comb begin
    branch_taken_o = 1'b0;
    case (decode_i.branch_op)
      dc_isa_pkg::BRANCH_BEQ:  branch_taken_o = (rs1_data_i == rs2_data_i);
      dc_isa_pkg::BRANCH_BNE:  branch_taken_o = (rs1_data_i != rs2_data_i);
      dc_isa_pkg::BRANCH_BLT:  branch_taken_o = ($signed(rs1_data_i) < $signed(rs2_data_i));
      dc_isa_pkg::BRANCH_BGE:  branch_taken_o = ($signed(rs1_data_i) >= $signed(rs2_data_i));
      dc_isa_pkg::BRANCH_BLTU: branch_taken_o = (rs1_data_i < rs2_data_i);
      dc_isa_pkg::BRANCH_BGEU: branch_taken_o = (rs1_data_i >= rs2_data_i);
      default: begin end
    endcase
  end

  always_comb begin
    result_o = (decode_i.writeback_sel == dc_isa_pkg::WB_PC4)
             ? pc_i + 32'd4 : alu_result;
    next_pc_o = pc_i + 32'd4;
    control_target = pc_i + decode_i.imm;
    case (decode_i.control_flow)
      dc_isa_pkg::CONTROL_JAL: next_pc_o = control_target;
      dc_isa_pkg::CONTROL_JALR: begin
        control_target = alu_result & 32'hffff_fffe;
        next_pc_o = control_target;
      end
      dc_isa_pkg::CONTROL_BRANCH: begin
        if (branch_taken_o) next_pc_o = control_target;
      end
      default: begin end
    endcase
    control_misaligned_o = (decode_i.control_flow == dc_isa_pkg::CONTROL_JAL) ||
                           (decode_i.control_flow == dc_isa_pkg::CONTROL_JALR) ||
                           ((decode_i.control_flow == dc_isa_pkg::CONTROL_BRANCH) &&
                            branch_taken_o);
    control_misaligned_o = control_misaligned_o && (control_target[1:0] != 2'b00);
  end
endmodule

`default_nettype wire
