`default_nettype none

module alu (
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0] lhs_i,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0] rhs_i,
  input  dc_isa_pkg::alu_op_e                op_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0] result_o
);
  always_comb begin
    result_o = '0;

    case (op_i)
      dc_isa_pkg::ALU_ADD:  result_o = lhs_i + rhs_i;
      dc_isa_pkg::ALU_SUB:  result_o = lhs_i - rhs_i;
      dc_isa_pkg::ALU_SLL:  result_o = lhs_i << rhs_i[4:0];
      dc_isa_pkg::ALU_SLT:  result_o = {31'd0, $signed(lhs_i) < $signed(rhs_i)};
      dc_isa_pkg::ALU_SLTU: result_o = {31'd0, lhs_i < rhs_i};
      dc_isa_pkg::ALU_XOR:  result_o = lhs_i ^ rhs_i;
      dc_isa_pkg::ALU_SRL:  result_o = lhs_i >> rhs_i[4:0];
      dc_isa_pkg::ALU_SRA:  result_o = $signed(lhs_i) >>> rhs_i[4:0];
      dc_isa_pkg::ALU_OR:   result_o = lhs_i | rhs_i;
      dc_isa_pkg::ALU_AND:  result_o = lhs_i & rhs_i;
      default:              result_o = '0;
    endcase
  end
endmodule

`default_nettype wire
