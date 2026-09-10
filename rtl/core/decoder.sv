`default_nettype none

module decoder (
  input  logic [dc_isa_pkg::INST_WIDTH-1:0] inst_i,
  output logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rd_addr_o,
  output logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rs_addr_o,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]     imm_o,
  output dc_isa_pkg::alu_op_e                   alu_op_o,
  output logic                                  alu_src_imm_o,
  output logic                                  reg_write_o,
  output logic                                  jump_o,
  output logic                                  legal_o
);
  logic [3:0] opcode;
  logic [7:0] imm8;

  localparam bit ISA_V01_CONFIG_VALID =
      (dc_isa_pkg::INST_WIDTH == 16) &&
      (dc_isa_pkg::DATA_WIDTH == 16) &&
      (dc_isa_pkg::REG_ADDR_WIDTH == 2) &&
      (dc_isa_pkg::REG_COUNT == 4) &&
      (dc_isa_pkg::PC_WIDTH == 8);

  assign opcode    = inst_i[15:12];
  assign rd_addr_o = inst_i[11:10];
  assign rs_addr_o = inst_i[9:8];
  assign imm8      = inst_i[7:0];
  assign imm_o     = {8'h00, imm8};

  always_comb begin
    alu_op_o      = dc_isa_pkg::ALU_PASS_B;
    alu_src_imm_o = 1'b0;
    reg_write_o   = 1'b0;
    jump_o        = 1'b0;
    legal_o       = 1'b0;

    if (ISA_V01_CONFIG_VALID) begin
      case (opcode)
        dc_isa_pkg::OPC_MOVI: begin
          if (rs_addr_o == 2'b00) begin
            alu_src_imm_o = 1'b1;
            reg_write_o   = 1'b1;
            legal_o       = 1'b1;
          end
        end

        dc_isa_pkg::OPC_MOV: begin
          if (imm8 == 8'h00) begin
            reg_write_o = 1'b1;
            legal_o     = 1'b1;
          end
        end

        dc_isa_pkg::OPC_ADDI: begin
          if (rs_addr_o == 2'b00) begin
            alu_op_o      = dc_isa_pkg::ALU_ADD;
            alu_src_imm_o = 1'b1;
            reg_write_o   = 1'b1;
            legal_o       = 1'b1;
          end
        end

        dc_isa_pkg::OPC_ADD: begin
          if (imm8 == 8'h00) begin
            alu_op_o    = dc_isa_pkg::ALU_ADD;
            reg_write_o = 1'b1;
            legal_o     = 1'b1;
          end
        end

        dc_isa_pkg::OPC_SUB: begin
          if (imm8 == 8'h00) begin
            alu_op_o    = dc_isa_pkg::ALU_SUB;
            reg_write_o = 1'b1;
            legal_o     = 1'b1;
          end
        end

        dc_isa_pkg::OPC_AND: begin
          if (imm8 == 8'h00) begin
            alu_op_o    = dc_isa_pkg::ALU_AND;
            reg_write_o = 1'b1;
            legal_o     = 1'b1;
          end
        end

        dc_isa_pkg::OPC_OR: begin
          if (imm8 == 8'h00) begin
            alu_op_o    = dc_isa_pkg::ALU_OR;
            reg_write_o = 1'b1;
            legal_o     = 1'b1;
          end
        end

        dc_isa_pkg::OPC_JUMP: begin
          if ((rd_addr_o == 2'b00) && (rs_addr_o == 2'b00)) begin
            jump_o  = 1'b1;
            legal_o = 1'b1;
          end
        end

        default: begin
        end
      endcase
    end
  end
endmodule

`default_nettype wire
