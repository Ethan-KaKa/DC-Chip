`default_nettype none

package dc_isa_pkg;
  localparam int unsigned INST_WIDTH     = 16;
  localparam int unsigned DATA_WIDTH     = 16;
  localparam int unsigned REG_ADDR_WIDTH = 2;
  localparam int unsigned REG_COUNT      = 4;
  localparam int unsigned PC_WIDTH       = 8;

  typedef enum logic [3:0] {
    OPC_MOVI = 4'h0,
    OPC_MOV  = 4'h1,
    OPC_ADDI = 4'h2,
    OPC_ADD  = 4'h3,
    OPC_SUB  = 4'h4,
    OPC_AND  = 4'h5,
    OPC_OR   = 4'h6,
    OPC_JUMP = 4'h7
  } opcode_e;

  typedef enum logic [2:0] {
    ALU_PASS_B = 3'd0,
    ALU_ADD    = 3'd1,
    ALU_SUB    = 3'd2,
    ALU_AND    = 3'd3,
    ALU_OR     = 3'd4
  } alu_op_e;
endpackage

`default_nettype wire
