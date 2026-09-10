`default_nettype none

module cpu_core (
  input  logic                                  clk,
  input  logic                                  rst,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]      imem_addr,
  input  logic [dc_isa_pkg::INST_WIDTH-1:0]    imem_rdata,
  output logic                                  trace_valid,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]      trace_pc,
  output logic [dc_isa_pkg::INST_WIDTH-1:0]    trace_inst,
  output logic [dc_isa_pkg::REG_COUNT*dc_isa_pkg::DATA_WIDTH-1:0]
                                                 debug_regs,
  output logic                                  illegal_inst
);
  logic [dc_isa_pkg::PC_WIDTH-1:0] pc_q;
  logic [dc_isa_pkg::PC_WIDTH-1:0] pc_next;

  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rd_addr;
  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rs_addr;
  logic [dc_isa_pkg::DATA_WIDTH-1:0]     imm;
  dc_isa_pkg::alu_op_e                   alu_op;
  logic                                  alu_src_imm;
  logic                                  reg_write;
  logic                                  jump;
  logic                                  legal;

  logic [dc_isa_pkg::DATA_WIDTH-1:0] rd_data;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] rs_data;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] alu_rhs;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] alu_result;
  logic                              regfile_we;
  logic                              illegal_q;

  assign imem_addr   = pc_q;
  assign illegal_inst = illegal_q;
  assign alu_rhs     = alu_src_imm ? imm : rs_data;
  assign pc_next     = jump ? imm[dc_isa_pkg::PC_WIDTH-1:0]
                            : pc_q + 8'd1;
  assign regfile_we  = legal && reg_write && !illegal_q && !rst;

  decoder u_decoder (
    .inst_i        (imem_rdata),
    .rd_addr_o     (rd_addr),
    .rs_addr_o     (rs_addr),
    .imm_o         (imm),
    .alu_op_o      (alu_op),
    .alu_src_imm_o (alu_src_imm),
    .reg_write_o   (reg_write),
    .jump_o        (jump),
    .legal_o       (legal)
  );

  regfile u_regfile (
    .clk_i        (clk),
    .rst_i        (rst),
    .raddr_a_i    (rd_addr),
    .rdata_a_o    (rd_data),
    .raddr_b_i    (rs_addr),
    .rdata_b_o    (rs_data),
    .we_i         (regfile_we),
    .waddr_i      (rd_addr),
    .wdata_i      (alu_result),
    .debug_regs_o (debug_regs)
  );

  alu u_alu (
    .lhs_i    (rd_data),
    .rhs_i    (alu_rhs),
    .op_i     (alu_op),
    .result_o (alu_result)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      pc_q        <= '0;
      trace_valid <= 1'b0;
      trace_pc    <= '0;
      trace_inst  <= '0;
      illegal_q   <= 1'b0;
    end else begin
      trace_valid <= 1'b0;

      if (illegal_q) begin
        illegal_q <= 1'b1;
      end else if (!legal) begin
        illegal_q <= 1'b1;
      end else begin
        pc_q        <= pc_next;
        trace_valid <= 1'b1;
        trace_pc    <= pc_q;
        trace_inst  <= imem_rdata;
      end
    end
  end
endmodule

`default_nettype wire
