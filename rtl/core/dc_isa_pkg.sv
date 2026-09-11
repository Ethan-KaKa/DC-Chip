`default_nettype none

package dc_isa_pkg;
  localparam int unsigned XLEN           = 32;
  localparam int unsigned INST_WIDTH     = 32;
  localparam int unsigned DATA_WIDTH     = XLEN;
  localparam int unsigned REG_COUNT      = 16;
  localparam int unsigned REG_ADDR_WIDTH = 4;
  localparam int unsigned PC_WIDTH       = XLEN;

  // Opcodes
  localparam logic [6:0] OPCODE_LOAD     = 7'b0000011;
  localparam logic [6:0] OPCODE_MISC_MEM = 7'b0001111; // fence
  localparam logic [6:0] OPCODE_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPCODE_STORE    = 7'b0100011;
  localparam logic [6:0] OPCODE_OP       = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI      = 7'b0110111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPCODE_JALR     = 7'b1100111;
  localparam logic [6:0] OPCODE_JAL      = 7'b1101111;

  // OP / OP_IMM funct3
  localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
  localparam logic [2:0] FUNCT3_SLL     = 3'b001;
  localparam logic [2:0] FUNCT3_SLT     = 3'b010;
  localparam logic [2:0] FUNCT3_SLTU    = 3'b011;
  localparam logic [2:0] FUNCT3_XOR     = 3'b100;
  localparam logic [2:0] FUNCT3_SRL_SRA = 3'b101;
  localparam logic [2:0] FUNCT3_OR      = 3'b110;
  localparam logic [2:0] FUNCT3_AND     = 3'b111;

  // BRANCH funct3
  localparam logic [2:0] FUNCT3_BEQ  = 3'b000;
  localparam logic [2:0] FUNCT3_BNE  = 3'b001;
  localparam logic [2:0] FUNCT3_BLT  = 3'b100;
  localparam logic [2:0] FUNCT3_BGE  = 3'b101;
  localparam logic [2:0] FUNCT3_BLTU = 3'b110;
  localparam logic [2:0] FUNCT3_BGEU = 3'b111;

  // LOAD / STORE funct3
  localparam logic [2:0] FUNCT3_LB_SB = 3'b000;
  localparam logic [2:0] FUNCT3_LH_SH = 3'b001;
  localparam logic [2:0] FUNCT3_LW_SW = 3'b010;
  localparam logic [2:0] FUNCT3_LBU   = 3'b100;
  localparam logic [2:0] FUNCT3_LHU   = 3'b101;

  // Funct7
  localparam logic [6:0] FUNCT7_DEFAULT = 7'b0000000;
  localparam logic [6:0] FUNCT7_ALT     = 7'b0100000; // SUB, SRA, SRAI

  typedef enum logic [3:0] {
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_SLL  = 4'd2,
    ALU_SLT  = 4'd3,
    ALU_SLTU = 4'd4,
    ALU_XOR  = 4'd5,
    ALU_SRL  = 4'd6,
    ALU_SRA  = 4'd7,
    ALU_OR   = 4'd8,
    ALU_AND  = 4'd9
  } alu_op_e;

  typedef enum logic [2:0] {
    WB_NONE  = 3'd0,
    WB_ALU   = 3'd1,
    WB_UIMM  = 3'd2,
    WB_LOAD  = 3'd3,
    WB_PC4   = 3'd4,
    WB_AUIPC = 3'd5
  } writeback_sel_e;

  typedef enum logic [3:0] {
    MEM_NONE = 4'd0,
    MEM_LW   = 4'd1,
    MEM_LBU  = 4'd2,
    MEM_SW   = 4'd3,
    MEM_SB   = 4'd4,
    MEM_LB   = 4'd5,
    MEM_LH   = 4'd6,
    MEM_LHU  = 4'd7,
    MEM_SH   = 4'd8
  } mem_op_e;

  typedef enum logic [2:0] {
    BRANCH_NONE = 3'd0,
    BRANCH_BEQ  = 3'd1,
    BRANCH_BNE  = 3'd2,
    BRANCH_BLT  = 3'd3,
    BRANCH_BGE  = 3'd4,
    BRANCH_BLTU = 3'd5,
    BRANCH_BGEU = 3'd6
  } branch_op_e;

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
