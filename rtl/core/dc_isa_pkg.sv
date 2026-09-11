`default_nettype none

package dc_isa_pkg;
  localparam int unsigned XLEN           = 32;
  localparam int unsigned INST_WIDTH     = 32;
  localparam int unsigned DATA_WIDTH     = XLEN;
  localparam int unsigned REG_COUNT      = 16;
  localparam int unsigned REG_ADDR_WIDTH = 4;
  localparam int unsigned PC_WIDTH       = XLEN;

  localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
  localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
  localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
  localparam logic [6:0] OPCODE_OP     = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
  localparam logic [6:0] OPCODE_JALR   = 7'b1100111;

  localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
  localparam logic [2:0] FUNCT3_LB_SB   = 3'b000;
  localparam logic [2:0] FUNCT3_LW_SW   = 3'b010;
  localparam logic [2:0] FUNCT3_LBU     = 3'b100;
  localparam logic [6:0] FUNCT7_ADD     = 7'b0000000;

  typedef enum logic [0:0] {
    ALU_ADD = 1'b0
  } alu_op_e;

  typedef enum logic [2:0] {
    WB_NONE = 3'd0,
    WB_ALU  = 3'd1,
    WB_UIMM = 3'd2,
    WB_LOAD = 3'd3,
    WB_PC4  = 3'd4
  } writeback_sel_e;

  typedef enum logic [2:0] {
    MEM_NONE = 3'd0,
    MEM_LW   = 3'd1,
    MEM_LBU  = 3'd2,
    MEM_SW   = 3'd3,
    MEM_SB   = 3'd4
  } mem_op_e;

  typedef enum logic [2:0] {
    FAULT_NONE                    = 3'd0,
    FAULT_ILLEGAL_INSTRUCTION     = 3'd1,
    FAULT_INSTRUCTION_ACCESS      = 3'd2,
    FAULT_INSTRUCTION_MISALIGNED  = 3'd3,
    FAULT_LOAD_MISALIGNED         = 3'd4,
    FAULT_LOAD_ACCESS             = 3'd5,
    FAULT_STORE_MISALIGNED        = 3'd6,
    FAULT_STORE_ACCESS            = 3'd7
  } fault_cause_e;
endpackage

`default_nettype wire
