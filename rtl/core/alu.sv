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
      dc_isa_pkg::ALU_ADD: result_o = lhs_i + rhs_i;
      default:             result_o = '0;
    endcase
  end
endmodule

`default_nettype wire
