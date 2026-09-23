`default_nettype none

module load_store_unit (
  input  logic                              clk_i,
  input  logic                              rst_i,
  input  logic                              issue_valid_i,
  output logic                              issue_ready_o,
  input  dc_isa_pkg::lsu_issue_t            issue_i,
  output logic                              issue_misaligned_o,
  output dc_isa_pkg::fault_cause_e          issue_fault_cause_o,
  output dc_isa_pkg::lsu_completion_t       completion_o,

  output logic                              dmem_req_valid_o,
  input  logic                              dmem_req_ready_i,
  output logic [dc_isa_pkg::XLEN-1:0]       dmem_req_addr_o,
  output logic                              dmem_req_write_o,
  output logic [1:0]                        dmem_req_size_o,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0] dmem_req_wdata_o,
  output logic [3:0]                        dmem_req_wstrb_o,
  input  logic                              dmem_rsp_valid_i,
  output logic                              dmem_rsp_ready_o,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0] dmem_rsp_rdata_i,
  input  logic                              dmem_rsp_error_i,
  input  logic                              dmem_rsp_skip_ref_i
);
  typedef enum logic [1:0] {LSU_IDLE, LSU_REQUEST, LSU_WAIT} lsu_state_e;
  lsu_state_e state_q;
  dc_isa_pkg::lsu_issue_t issue_q;
  logic rsp_fire;
  logic [7:0] load_byte;
  logic [15:0] load_half;

  assign issue_ready_o = (state_q == LSU_IDLE) && !rst_i;
  assign issue_misaligned_o = dc_isa_pkg::mem_is_misaligned(issue_i.mem_op,
                                                            issue_i.addr[1:0]);
  always_comb begin
    if (dc_isa_pkg::mem_is_load(issue_i.mem_op))
      issue_fault_cause_o = dc_isa_pkg::FAULT_LOAD_MISALIGNED;
    else issue_fault_cause_o = dc_isa_pkg::FAULT_STORE_MISALIGNED;
  end

  always_comb begin
    dmem_req_valid_o = 1'b0;
    dmem_rsp_ready_o = 1'b0;
    if (!rst_i) begin
      if (state_q == LSU_REQUEST) begin
        dmem_req_valid_o = 1'b1;
        dmem_rsp_ready_o = dmem_req_ready_i;
      end else if (state_q == LSU_WAIT) begin
        dmem_rsp_ready_o = 1'b1;
      end
    end
  end

  assign dmem_req_addr_o = issue_q.addr;
  assign dmem_req_write_o = dc_isa_pkg::mem_is_store(issue_q.mem_op);
  assign dmem_req_size_o = dc_isa_pkg::mem_size(issue_q.mem_op);

  always_comb begin
    dmem_req_wdata_o = '0;
    dmem_req_wstrb_o = '0;
    case (issue_q.mem_op)
      dc_isa_pkg::MEM_SW: begin
        dmem_req_wdata_o = issue_q.store_data;
        dmem_req_wstrb_o = 4'b1111;
      end
      dc_isa_pkg::MEM_SH: begin
        dmem_req_wdata_o = {16'd0, issue_q.store_data[15:0]} <<
                           (issue_q.addr[1] * 16);
        dmem_req_wstrb_o = 4'b0011 << (issue_q.addr[1] * 2);
      end
      dc_isa_pkg::MEM_SB: begin
        dmem_req_wdata_o = {24'd0, issue_q.store_data[7:0]} <<
                           (issue_q.addr[1:0] * 8);
        dmem_req_wstrb_o = 4'b0001 << issue_q.addr[1:0];
      end
      default: begin end
    endcase
  end

  assign rsp_fire = dmem_rsp_valid_i && dmem_rsp_ready_o;
  always_comb begin
    case (issue_q.addr[1:0])
      2'd0: load_byte = dmem_rsp_rdata_i[7:0];
      2'd1: load_byte = dmem_rsp_rdata_i[15:8];
      2'd2: load_byte = dmem_rsp_rdata_i[23:16];
      default: load_byte = dmem_rsp_rdata_i[31:24];
    endcase
    load_half = issue_q.addr[1] ? dmem_rsp_rdata_i[31:16]
                                : dmem_rsp_rdata_i[15:0];
  end

  always_comb begin
    completion_o = '0;
    completion_o.valid = rsp_fire;
    completion_o.error = (dmem_rsp_error_i !== 1'b0);
    if (dc_isa_pkg::mem_is_load(issue_q.mem_op))
      completion_o.fault_cause = dc_isa_pkg::FAULT_LOAD_ACCESS;
    else completion_o.fault_cause = dc_isa_pkg::FAULT_STORE_ACCESS;
    completion_o.pc = issue_q.pc;
    completion_o.inst = issue_q.inst;
    completion_o.rd = issue_q.rd;
    completion_o.writeback_en = dc_isa_pkg::mem_is_load(issue_q.mem_op);
    completion_o.skip_ref = dmem_rsp_skip_ref_i;
    case (issue_q.mem_op)
      dc_isa_pkg::MEM_LB:  completion_o.writeback_data = {{24{load_byte[7]}}, load_byte};
      dc_isa_pkg::MEM_LBU: completion_o.writeback_data = {24'd0, load_byte};
      dc_isa_pkg::MEM_LH:  completion_o.writeback_data = {{16{load_half[15]}}, load_half};
      dc_isa_pkg::MEM_LHU: completion_o.writeback_data = {16'd0, load_half};
      dc_isa_pkg::MEM_LW:  completion_o.writeback_data = dmem_rsp_rdata_i;
      default: begin end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q <= LSU_IDLE;
      issue_q <= '0;
    end else begin
      case (state_q)
        LSU_IDLE: if (issue_valid_i && issue_ready_o && !issue_misaligned_o) begin
          issue_q <= issue_i;
          state_q <= LSU_REQUEST;
        end
        LSU_REQUEST: begin
          if (rsp_fire) state_q <= LSU_IDLE;
          else if (dmem_req_ready_i) state_q <= LSU_WAIT;
        end
        LSU_WAIT: if (rsp_fire) state_q <= LSU_IDLE;
        default: state_q <= LSU_IDLE;
      endcase
    end
  end
endmodule

`default_nettype wire
