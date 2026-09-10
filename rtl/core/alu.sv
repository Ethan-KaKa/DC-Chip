`default_nettype none

module alu (
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0] lhs_i,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0] rhs_i,
  input  dc_isa_pkg::alu_op_e                  op_i,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0] result_o
);
  localparam bit ISA_V01_CONFIG_VALID =
      (dc_isa_pkg::INST_WIDTH == 16) &&
      (dc_isa_pkg::DATA_WIDTH == 16) &&
      (dc_isa_pkg::REG_ADDR_WIDTH == 2) &&
      (dc_isa_pkg::REG_COUNT == 4) &&
      (dc_isa_pkg::PC_WIDTH == 8);

  always_comb begin
    result_o = 16'h0000;

    if (ISA_V01_CONFIG_VALID) begin
      case (op_i)
        dc_isa_pkg::ALU_PASS_B: result_o = rhs_i;
        dc_isa_pkg::ALU_ADD:    result_o = lhs_i + rhs_i;
        dc_isa_pkg::ALU_SUB:    result_o = lhs_i - rhs_i;
        dc_isa_pkg::ALU_AND:    result_o = lhs_i & rhs_i;
        dc_isa_pkg::ALU_OR:     result_o = lhs_i | rhs_i;
        default:                result_o = 16'h0000;
      endcase
    end
  end
endmodule

`default_nettype wire
