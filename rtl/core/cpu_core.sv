`default_nettype none

module cpu_core #(
  parameter logic [dc_isa_pkg::PC_WIDTH-1:0] RESET_PC = '0
) (
  input  logic                                   clk,
  input  logic                                   rst,
  output logic                                   imem_req_valid,
  input  logic                                   imem_req_ready,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]       imem_req_addr,
  input  logic                                   imem_rsp_valid,
  output logic                                   imem_rsp_ready,
  input  logic [dc_isa_pkg::INST_WIDTH-1:0]     imem_rsp_rdata,
  input  logic                                   imem_rsp_error,
  output logic                                   dmem_req_valid,
  input  logic                                   dmem_req_ready,
  output logic [dc_isa_pkg::XLEN-1:0]           dmem_req_addr,
  output logic                                   dmem_req_write,
  output logic [1:0]                             dmem_req_size,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]     dmem_req_wdata,
  output logic [3:0]                             dmem_req_wstrb,
  input  logic                                   dmem_rsp_valid,
  output logic                                   dmem_rsp_ready,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0]     dmem_rsp_rdata,
  input  logic                                   dmem_rsp_error,
  input  logic                                   dmem_rsp_skip_ref,
  output logic                                   trace_valid,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]       trace_pc,
  output logic [dc_isa_pkg::INST_WIDTH-1:0]     trace_inst,
  output logic                                   trace_skip_ref,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] debug_reg_addr,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]     debug_reg_data,
  output logic                                   fault_valid,
  output dc_isa_pkg::fault_cause_e               fault_cause,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]       fault_pc,
  output logic                                   fault_inst_valid,
  output logic [dc_isa_pkg::INST_WIDTH-1:0]     fault_inst
);
  typedef enum logic [1:0] {
    STATE_FETCH_REQ,
    STATE_FETCH_WAIT,
    STATE_LSU_WAIT,
    STATE_FAULT
  } state_e;

  state_e state_q;
  logic [dc_isa_pkg::PC_WIDTH-1:0] pc_q;
  dc_isa_pkg::decode_info_t decode;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] rs1_data, rs2_data;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] execute_result;
  logic [dc_isa_pkg::PC_WIDTH-1:0] execute_next_pc;
  /* verilator lint_off UNUSEDSIGNAL */
  logic branch_taken;
  /* verilator lint_on UNUSEDSIGNAL */
  logic control_misaligned;
  logic regfile_we;
  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] regfile_waddr;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] regfile_wdata;
  logic fetch_rsp_fire;
  logic imem_rsp_ok;
  logic fetch_commit;

  dc_isa_pkg::lsu_issue_t lsu_issue;
  dc_isa_pkg::lsu_completion_t lsu_completion;
  logic lsu_issue_valid, lsu_issue_ready, lsu_issue_misaligned;
  dc_isa_pkg::fault_cause_e lsu_issue_fault_cause;

  decoder u_decoder (
    .inst_i   (imem_rsp_rdata),
    .decode_o (decode)
  );

  regfile u_regfile (
    .clk_i            (clk),
    .rst_i            (rst),
    .raddr_a_i        (decode.rs1),
    .rdata_a_o        (rs1_data),
    .raddr_b_i        (decode.rs2),
    .rdata_b_o        (rs2_data),
    .we_i             (regfile_we),
    .waddr_i          (regfile_waddr),
    .wdata_i          (regfile_wdata),
    .debug_reg_addr_i (debug_reg_addr),
    .debug_reg_data_o (debug_reg_data)
  );

  execute_unit u_execute (
    .decode_i              (decode),
    .pc_i                  (pc_q),
    .rs1_data_i            (rs1_data),
    .rs2_data_i            (rs2_data),
    .result_o              (execute_result),
    .next_pc_o             (execute_next_pc),
    .branch_taken_o        (branch_taken),
    .control_misaligned_o  (control_misaligned)
  );

  always_comb begin
    lsu_issue = '0;
    lsu_issue.pc = pc_q;
    lsu_issue.inst = imem_rsp_rdata;
    lsu_issue.rd = decode.rd;
    lsu_issue.addr = execute_result;
    lsu_issue.store_data = rs2_data;
    lsu_issue.mem_op = decode.mem_op;
  end

  load_store_unit u_lsu (
    .clk_i                 (clk),
    .rst_i                 (rst),
    .issue_valid_i         (lsu_issue_valid),
    .issue_ready_o         (lsu_issue_ready),
    .issue_i               (lsu_issue),
    .issue_misaligned_o    (lsu_issue_misaligned),
    .issue_fault_cause_o   (lsu_issue_fault_cause),
    .completion_o          (lsu_completion),
    .dmem_req_valid_o      (dmem_req_valid),
    .dmem_req_ready_i      (dmem_req_ready),
    .dmem_req_addr_o       (dmem_req_addr),
    .dmem_req_write_o      (dmem_req_write),
    .dmem_req_size_o       (dmem_req_size),
    .dmem_req_wdata_o      (dmem_req_wdata),
    .dmem_req_wstrb_o      (dmem_req_wstrb),
    .dmem_rsp_valid_i      (dmem_rsp_valid),
    .dmem_rsp_ready_o      (dmem_rsp_ready),
    .dmem_rsp_rdata_i      (dmem_rsp_rdata),
    .dmem_rsp_error_i      (dmem_rsp_error),
    .dmem_rsp_skip_ref_i   (dmem_rsp_skip_ref)
  );

  always_comb begin
    imem_req_valid = 1'b0;
    imem_req_addr = pc_q;
    imem_rsp_ready = 1'b0;
    if (!rst) begin
      case (state_q)
        STATE_FETCH_REQ: begin
          imem_req_valid = 1'b1;
          imem_rsp_ready = imem_req_ready;
        end
        STATE_FETCH_WAIT: imem_rsp_ready = 1'b1;
        default: begin end
      endcase
    end
  end

  assign fetch_rsp_fire = imem_rsp_valid && imem_rsp_ready;
  assign imem_rsp_ok = (imem_rsp_error === 1'b0);
  assign lsu_issue_valid = fetch_rsp_fire && imem_rsp_ok && decode.legal &&
                           lsu_issue_ready &&
                           (decode.mem_op != dc_isa_pkg::MEM_NONE) &&
                           !lsu_issue_misaligned;
  assign fetch_commit = fetch_rsp_fire && imem_rsp_ok && decode.legal &&
                        (decode.mem_op == dc_isa_pkg::MEM_NONE) &&
                        !control_misaligned;

  always_comb begin
    regfile_we = 1'b0;
    regfile_waddr = '0;
    regfile_wdata = '0;
    if (fetch_commit && (decode.writeback_sel != dc_isa_pkg::WB_NONE)) begin
      regfile_we = 1'b1;
      regfile_waddr = decode.rd;
      regfile_wdata = execute_result;
    end else if ((state_q == STATE_LSU_WAIT) && lsu_completion.valid &&
                 !lsu_completion.error && lsu_completion.writeback_en) begin
      regfile_we = 1'b1;
      regfile_waddr = lsu_completion.rd;
      regfile_wdata = lsu_completion.writeback_data;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= STATE_FETCH_REQ;
      pc_q <= RESET_PC;
      trace_valid <= 1'b0;
      trace_pc <= '0;
      trace_inst <= '0;
      trace_skip_ref <= 1'b0;
      fault_valid <= 1'b0;
      fault_cause <= dc_isa_pkg::FAULT_NONE;
      fault_pc <= '0;
      fault_inst_valid <= 1'b0;
      fault_inst <= '0;
    end else begin
      trace_valid <= 1'b0;
      trace_skip_ref <= 1'b0;
      case (state_q)
        STATE_FETCH_REQ, STATE_FETCH_WAIT: begin
          if (fetch_rsp_fire) begin
            if (!imem_rsp_ok) begin
              state_q <= STATE_FAULT;
              fault_valid <= 1'b1;
              fault_cause <= dc_isa_pkg::FAULT_INSTRUCTION_ACCESS;
              fault_pc <= pc_q;
              fault_inst_valid <= 1'b0;
              fault_inst <= '0;
            end else if (!decode.legal) begin
              state_q <= STATE_FAULT;
              fault_valid <= 1'b1;
              fault_cause <= dc_isa_pkg::FAULT_ILLEGAL_INSTRUCTION;
              fault_pc <= pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst <= imem_rsp_rdata;
            end else if ((decode.mem_op != dc_isa_pkg::MEM_NONE) &&
                         lsu_issue_misaligned) begin
              state_q <= STATE_FAULT;
              fault_valid <= 1'b1;
              fault_cause <= lsu_issue_fault_cause;
              fault_pc <= pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst <= imem_rsp_rdata;
            end else if (control_misaligned) begin
              state_q <= STATE_FAULT;
              fault_valid <= 1'b1;
              fault_cause <= dc_isa_pkg::FAULT_INSTRUCTION_MISALIGNED;
              fault_pc <= pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst <= imem_rsp_rdata;
            end else if (decode.mem_op != dc_isa_pkg::MEM_NONE) begin
              state_q <= STATE_LSU_WAIT;
            end else begin
              state_q <= STATE_FETCH_REQ;
              pc_q <= execute_next_pc;
              trace_valid <= 1'b1;
              trace_pc <= pc_q;
              trace_inst <= imem_rsp_rdata;
            end
          end else if ((state_q == STATE_FETCH_REQ) && imem_req_ready) begin
            state_q <= STATE_FETCH_WAIT;
          end
        end
        STATE_LSU_WAIT: if (lsu_completion.valid) begin
          if (lsu_completion.error) begin
            state_q <= STATE_FAULT;
            fault_valid <= 1'b1;
            fault_cause <= lsu_completion.fault_cause;
            fault_pc <= lsu_completion.pc;
            fault_inst_valid <= 1'b1;
            fault_inst <= lsu_completion.inst;
          end else begin
            state_q <= STATE_FETCH_REQ;
            pc_q <= lsu_completion.pc + 32'd4;
            trace_valid <= 1'b1;
            trace_pc <= lsu_completion.pc;
            trace_inst <= lsu_completion.inst;
            trace_skip_ref <= lsu_completion.skip_ref;
          end
        end
        STATE_FAULT: state_q <= STATE_FAULT;
        default: begin
          state_q <= STATE_FAULT;
          fault_valid <= 1'b1;
          fault_cause <= dc_isa_pkg::FAULT_ILLEGAL_INSTRUCTION;
          fault_pc <= pc_q;
          fault_inst_valid <= 1'b0;
          fault_inst <= '0;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
