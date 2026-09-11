`default_nettype none

module cpu_core #(
  parameter logic [dc_isa_pkg::PC_WIDTH-1:0] RESET_PC = '0
) (
  input  logic                                  clk,
  input  logic                                  rst,

  output logic                                  imem_req_valid,
  input  logic                                  imem_req_ready,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]      imem_req_addr,
  input  logic                                  imem_rsp_valid,
  output logic                                  imem_rsp_ready,
  input  logic [dc_isa_pkg::INST_WIDTH-1:0]    imem_rsp_rdata,
  input  logic                                  imem_rsp_error,

  output logic                                  dmem_req_valid,
  input  logic                                  dmem_req_ready,
  output logic [dc_isa_pkg::XLEN-1:0]          dmem_req_addr,
  output logic                                  dmem_req_write,
  output logic [1:0]                            dmem_req_size,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]    dmem_req_wdata,
  output logic [3:0]                            dmem_req_wstrb,
  input  logic                                  dmem_rsp_valid,
  output logic                                  dmem_rsp_ready,
  input  logic [dc_isa_pkg::DATA_WIDTH-1:0]    dmem_rsp_rdata,
  input  logic                                  dmem_rsp_error,

  output logic                                  trace_valid,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]      trace_pc,
  output logic [dc_isa_pkg::INST_WIDTH-1:0]    trace_inst,
  input  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] debug_reg_addr,
  output logic [dc_isa_pkg::DATA_WIDTH-1:0]    debug_reg_data,

  output logic                                  fault_valid,
  output dc_isa_pkg::fault_cause_e              fault_cause,
  output logic [dc_isa_pkg::PC_WIDTH-1:0]      fault_pc,
  output logic                                  fault_inst_valid,
  output logic [dc_isa_pkg::INST_WIDTH-1:0]    fault_inst
);
  localparam logic [1:0] MEM_SIZE_BYTE = 2'b00;
  localparam logic [1:0] MEM_SIZE_HALF = 2'b01;
  localparam logic [1:0] MEM_SIZE_WORD = 2'b10;

  typedef enum logic [2:0] {
    STATE_FETCH_REQ,
    STATE_FETCH_WAIT,
    STATE_DMEM_REQ,
    STATE_DMEM_WAIT,
    STATE_FAULT
  } state_e;

  state_e state_q;

  logic [dc_isa_pkg::PC_WIDTH-1:0] pc_q;

  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rd_addr;
  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rs1_addr;
  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] rs2_addr;
  logic [dc_isa_pkg::XLEN-1:0]           imm_i;
  logic [dc_isa_pkg::XLEN-1:0]           imm_s;
  logic [dc_isa_pkg::XLEN-1:0]           imm_b;
  logic [dc_isa_pkg::XLEN-1:0]           imm_u;
  logic [dc_isa_pkg::XLEN-1:0]           imm_j;
  dc_isa_pkg::alu_op_e                   alu_op;
  dc_isa_pkg::writeback_sel_e            writeback_sel;
  dc_isa_pkg::mem_op_e                   mem_op;
  dc_isa_pkg::branch_op_e                branch_op;
  logic                                  jal;
  logic                                  jalr;
  logic                                  legal;

  logic [dc_isa_pkg::DATA_WIDTH-1:0] rs1_data;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] rs2_data;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] alu_rhs;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] alu_result;
  logic                              regfile_we;
  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] regfile_waddr;
  logic [dc_isa_pkg::DATA_WIDTH-1:0] regfile_wdata;

  logic [dc_isa_pkg::XLEN-1:0] effective_addr;
  logic [dc_isa_pkg::XLEN-1:0] jal_target;
  logic [dc_isa_pkg::XLEN-1:0] jalr_target;
  logic [dc_isa_pkg::XLEN-1:0] branch_target;
  logic                        branch_taken;
  logic                        mem_is_load;
  logic                        mem_is_store;
  logic                        mem_is_word;
  logic                        mem_is_half;
  logic                        mem_misaligned;
  logic                        jal_misaligned;
  logic                        jalr_misaligned;
  logic                        branch_misaligned;

  logic [dc_isa_pkg::PC_WIDTH-1:0]       mem_pc_q;
  logic [dc_isa_pkg::INST_WIDTH-1:0]     mem_inst_q;
  dc_isa_pkg::mem_op_e                   mem_op_q;
  logic [dc_isa_pkg::REG_ADDR_WIDTH-1:0] mem_rd_q;
  logic [dc_isa_pkg::XLEN-1:0]           mem_addr_q;
  logic                                   mem_write_q;
  logic [1:0]                             mem_size_q;
  logic [dc_isa_pkg::DATA_WIDTH-1:0]     mem_wdata_q;
  logic [3:0]                             mem_wstrb_q;

  logic fetch_rsp_fire;
  logic dmem_rsp_fire;
  logic imem_rsp_ok;
  logic dmem_rsp_ok;
  logic fetch_commit;
  logic load_commit;

  decoder u_decoder (
    .inst_i          (imem_rsp_rdata),
    .rd_addr_o       (rd_addr),
    .rs1_addr_o      (rs1_addr),
    .rs2_addr_o      (rs2_addr),
    .imm_i_o         (imm_i),
    .imm_s_o         (imm_s),
    .imm_b_o         (imm_b),
    .imm_u_o         (imm_u),
    .imm_j_o         (imm_j),
    .alu_op_o        (alu_op),
    .writeback_sel_o (writeback_sel),
    .mem_op_o        (mem_op),
    .branch_op_o     (branch_op),
    .jal_o           (jal),
    .jalr_o          (jalr),
    .legal_o         (legal)
  );

  assign alu_rhs = mem_is_store ? imm_s
                 : ((imem_rsp_rdata[6:0] == dc_isa_pkg::OPCODE_OP)
                    ? rs2_data : imm_i);

  alu u_alu (
    .lhs_i    (rs1_data),
    .rhs_i    (alu_rhs),
    .op_i     (alu_op),
    .result_o (alu_result)
  );

  regfile u_regfile (
    .clk_i            (clk),
    .rst_i            (rst),
    .raddr_a_i        (rs1_addr),
    .rdata_a_o        (rs1_data),
    .raddr_b_i        (rs2_addr),
    .rdata_b_o        (rs2_data),
    .we_i             (regfile_we),
    .waddr_i          (regfile_waddr),
    .wdata_i          (regfile_wdata),
    .debug_reg_addr_i (debug_reg_addr),
    .debug_reg_data_o (debug_reg_data)
  );

  always_comb begin
    branch_taken = 1'b0;
    case (branch_op)
      dc_isa_pkg::BRANCH_BEQ:  branch_taken = (rs1_data == rs2_data);
      dc_isa_pkg::BRANCH_BNE:  branch_taken = (rs1_data != rs2_data);
      dc_isa_pkg::BRANCH_BLT:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));
      dc_isa_pkg::BRANCH_BGE:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
      dc_isa_pkg::BRANCH_BLTU: branch_taken = (rs1_data < rs2_data);
      dc_isa_pkg::BRANCH_BGEU: branch_taken = (rs1_data >= rs2_data);
      default:                 branch_taken = 1'b0;
    endcase
  end

  assign mem_is_load = (mem_op == dc_isa_pkg::MEM_LW) ||
                       (mem_op == dc_isa_pkg::MEM_LH) ||
                       (mem_op == dc_isa_pkg::MEM_LHU) ||
                       (mem_op == dc_isa_pkg::MEM_LB) ||
                       (mem_op == dc_isa_pkg::MEM_LBU);
  assign mem_is_store = (mem_op == dc_isa_pkg::MEM_SW) ||
                        (mem_op == dc_isa_pkg::MEM_SH) ||
                        (mem_op == dc_isa_pkg::MEM_SB);
  assign mem_is_word = (mem_op == dc_isa_pkg::MEM_LW) ||
                       (mem_op == dc_isa_pkg::MEM_SW);
  assign mem_is_half = (mem_op == dc_isa_pkg::MEM_LH) ||
                       (mem_op == dc_isa_pkg::MEM_LHU) ||
                       (mem_op == dc_isa_pkg::MEM_SH);
  assign effective_addr = alu_result;
  assign mem_misaligned = (mem_is_word && (effective_addr[1:0] != 2'b00)) ||
                          (mem_is_half && (effective_addr[0] != 1'b0));

  assign jal_target        = pc_q + imm_j;
  assign jal_misaligned    = jal && (jal_target[1:0] != 2'b00);

  assign jalr_target       = alu_result & 32'hffff_fffe;
  assign jalr_misaligned   = jalr && (jalr_target[1:0] != 2'b00);

  assign branch_target     = pc_q + imm_b;
  assign branch_misaligned = (branch_op != dc_isa_pkg::BRANCH_NONE) &&
                             branch_taken && (branch_target[1:0] != 2'b00);

  always_comb begin
    imem_req_valid = 1'b0;
    imem_req_addr  = pc_q;
    imem_rsp_ready = 1'b0;

    dmem_req_valid = 1'b0;
    dmem_req_addr  = mem_addr_q;
    dmem_req_write = mem_write_q;
    dmem_req_size  = mem_size_q;
    dmem_req_wdata = mem_wdata_q;
    dmem_req_wstrb = mem_wstrb_q;
    dmem_rsp_ready = 1'b0;

    if (!rst) begin
      case (state_q)
        STATE_FETCH_REQ: begin
          imem_req_valid = 1'b1;
          imem_rsp_ready = imem_req_ready;
        end
        STATE_FETCH_WAIT: begin
          imem_rsp_ready = 1'b1;
        end
        STATE_DMEM_REQ: begin
          dmem_req_valid = 1'b1;
          dmem_rsp_ready = dmem_req_ready;
        end
        STATE_DMEM_WAIT: begin
          dmem_rsp_ready = 1'b1;
        end
        default: begin
        end
      endcase
    end
  end

  assign fetch_rsp_fire = imem_rsp_valid && imem_rsp_ready;
  assign dmem_rsp_fire  = dmem_rsp_valid && dmem_rsp_ready;
  assign imem_rsp_ok    = (imem_rsp_error === 1'b0);
  assign dmem_rsp_ok    = (dmem_rsp_error === 1'b0);

  assign fetch_commit = fetch_rsp_fire && imem_rsp_ok && legal &&
                        (mem_op == dc_isa_pkg::MEM_NONE) &&
                        !jal_misaligned && !jalr_misaligned && !branch_misaligned;
  assign load_commit = dmem_rsp_fire && dmem_rsp_ok &&
                       ((mem_op_q == dc_isa_pkg::MEM_LW) ||
                        (mem_op_q == dc_isa_pkg::MEM_LH) ||
                        (mem_op_q == dc_isa_pkg::MEM_LHU) ||
                        (mem_op_q == dc_isa_pkg::MEM_LB) ||
                        (mem_op_q == dc_isa_pkg::MEM_LBU));

  always_comb begin
    regfile_we    = 1'b0;
    regfile_waddr = '0;
    regfile_wdata = '0;

    if (fetch_commit && (writeback_sel != dc_isa_pkg::WB_NONE)) begin
      regfile_we    = 1'b1;
      regfile_waddr = rd_addr;
      case (writeback_sel)
        dc_isa_pkg::WB_ALU:   regfile_wdata = alu_result;
        dc_isa_pkg::WB_UIMM:  regfile_wdata = imm_u;
        dc_isa_pkg::WB_AUIPC: regfile_wdata = pc_q + imm_u;
        dc_isa_pkg::WB_PC4:   regfile_wdata = pc_q + 32'd4;
        default:              regfile_wdata = '0;
      endcase
    end else if (load_commit) begin
      regfile_we    = 1'b1;
      regfile_waddr = mem_rd_q;
      case (mem_op_q)
        dc_isa_pkg::MEM_LB: begin
          case (mem_addr_q[1:0])
            2'd0: regfile_wdata = {{24{dmem_rsp_rdata[7]}},  dmem_rsp_rdata[7:0]};
            2'd1: regfile_wdata = {{24{dmem_rsp_rdata[15]}}, dmem_rsp_rdata[15:8]};
            2'd2: regfile_wdata = {{24{dmem_rsp_rdata[23]}}, dmem_rsp_rdata[23:16]};
            2'd3: regfile_wdata = {{24{dmem_rsp_rdata[31]}}, dmem_rsp_rdata[31:24]};
            default: regfile_wdata = '0;
          endcase
        end
        dc_isa_pkg::MEM_LBU: begin
          case (mem_addr_q[1:0])
            2'd0: regfile_wdata = {24'd0, dmem_rsp_rdata[7:0]};
            2'd1: regfile_wdata = {24'd0, dmem_rsp_rdata[15:8]};
            2'd2: regfile_wdata = {24'd0, dmem_rsp_rdata[23:16]};
            2'd3: regfile_wdata = {24'd0, dmem_rsp_rdata[31:24]};
            default: regfile_wdata = '0;
          endcase
        end
        dc_isa_pkg::MEM_LH: begin
          if (mem_addr_q[1] == 1'b0) begin
            regfile_wdata = {{16{dmem_rsp_rdata[15]}}, dmem_rsp_rdata[15:0]};
          end else begin
            regfile_wdata = {{16{dmem_rsp_rdata[31]}}, dmem_rsp_rdata[31:16]};
          end
        end
        dc_isa_pkg::MEM_LHU: begin
          if (mem_addr_q[1] == 1'b0) begin
            regfile_wdata = {16'd0, dmem_rsp_rdata[15:0]};
          end else begin
            regfile_wdata = {16'd0, dmem_rsp_rdata[31:16]};
          end
        end
        dc_isa_pkg::MEM_LW: begin
          regfile_wdata = dmem_rsp_rdata;
        end
        default: regfile_wdata = '0;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q          <= STATE_FETCH_REQ;
      pc_q             <= RESET_PC;
      mem_pc_q         <= '0;
      mem_inst_q       <= '0;
      mem_op_q         <= dc_isa_pkg::MEM_NONE;
      mem_rd_q         <= '0;
      mem_addr_q       <= '0;
      mem_write_q      <= 1'b0;
      mem_size_q       <= MEM_SIZE_BYTE;
      mem_wdata_q      <= '0;
      mem_wstrb_q      <= '0;
      trace_valid      <= 1'b0;
      trace_pc         <= '0;
      trace_inst       <= '0;
      fault_valid      <= 1'b0;
      fault_cause      <= dc_isa_pkg::FAULT_NONE;
      fault_pc         <= '0;
      fault_inst_valid <= 1'b0;
      fault_inst       <= '0;
    end else begin
      trace_valid <= 1'b0;

      case (state_q)
        STATE_FETCH_REQ, STATE_FETCH_WAIT: begin
          if (fetch_rsp_fire) begin
            if (!imem_rsp_ok) begin
              state_q          <= STATE_FAULT;
              fault_valid      <= 1'b1;
              fault_cause      <= dc_isa_pkg::FAULT_INSTRUCTION_ACCESS;
              fault_pc         <= pc_q;
              fault_inst_valid <= 1'b0;
              fault_inst       <= '0;
            end else if (!legal) begin
              state_q          <= STATE_FAULT;
              fault_valid      <= 1'b1;
              fault_cause      <= dc_isa_pkg::FAULT_ILLEGAL_INSTRUCTION;
              fault_pc         <= pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst       <= imem_rsp_rdata;
            end else if ((mem_op != dc_isa_pkg::MEM_NONE) && mem_misaligned) begin
              state_q          <= STATE_FAULT;
              fault_valid      <= 1'b1;
              if (mem_is_load) begin
                fault_cause <= dc_isa_pkg::FAULT_LOAD_MISALIGNED;
              end else begin
                fault_cause <= dc_isa_pkg::FAULT_STORE_MISALIGNED;
              end
              fault_pc         <= pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst       <= imem_rsp_rdata;
            end else if (jal_misaligned || jalr_misaligned || branch_misaligned) begin
              state_q          <= STATE_FAULT;
              fault_valid      <= 1'b1;
              fault_cause      <= dc_isa_pkg::FAULT_INSTRUCTION_MISALIGNED;
              fault_pc         <= pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst       <= imem_rsp_rdata;
            end else if (mem_op != dc_isa_pkg::MEM_NONE) begin
              state_q     <= STATE_DMEM_REQ;
              mem_pc_q    <= pc_q;
              mem_inst_q  <= imem_rsp_rdata;
              mem_op_q    <= mem_op;
              mem_rd_q    <= rd_addr;
              mem_addr_q  <= effective_addr;
              mem_write_q <= mem_is_store;
              mem_size_q  <= mem_is_word ? MEM_SIZE_WORD
                           : mem_is_half ? MEM_SIZE_HALF
                           : MEM_SIZE_BYTE;
              if (mem_op == dc_isa_pkg::MEM_SW) begin
                mem_wdata_q <= rs2_data;
                mem_wstrb_q <= 4'b1111;
              end else if (mem_op == dc_isa_pkg::MEM_SH) begin
                if (effective_addr[1] == 1'b0) begin
                  mem_wdata_q <= {16'd0, rs2_data[15:0]};
                  mem_wstrb_q <= 4'b0011;
                end else begin
                  mem_wdata_q <= {rs2_data[15:0], 16'd0};
                  mem_wstrb_q <= 4'b1100;
                end
              end else if (mem_op == dc_isa_pkg::MEM_SB) begin
                case (effective_addr[1:0])
                  2'd0: begin
                    mem_wdata_q <= {24'd0, rs2_data[7:0]};
                    mem_wstrb_q <= 4'b0001;
                  end
                  2'd1: begin
                    mem_wdata_q <= {16'd0, rs2_data[7:0], 8'd0};
                    mem_wstrb_q <= 4'b0010;
                  end
                  2'd2: begin
                    mem_wdata_q <= {8'd0, rs2_data[7:0], 16'd0};
                    mem_wstrb_q <= 4'b0100;
                  end
                  2'd3: begin
                    mem_wdata_q <= {rs2_data[7:0], 24'd0};
                    mem_wstrb_q <= 4'b1000;
                  end
                  default: begin
                    mem_wdata_q <= '0;
                    mem_wstrb_q <= '0;
                  end
                endcase
              end else begin
                mem_wdata_q <= '0;
                mem_wstrb_q <= '0;
              end
            end else begin
              state_q     <= STATE_FETCH_REQ;
              if (jalr) begin
                pc_q <= jalr_target;
              end else if (jal) begin
                pc_q <= jal_target;
              end else if ((branch_op != dc_isa_pkg::BRANCH_NONE) && branch_taken) begin
                pc_q <= branch_target;
              end else begin
                pc_q <= pc_q + 32'd4;
              end
              trace_valid <= 1'b1;
              trace_pc    <= pc_q;
              trace_inst  <= imem_rsp_rdata;
            end
          end else if ((state_q == STATE_FETCH_REQ) && imem_req_ready) begin
            state_q <= STATE_FETCH_WAIT;
          end
        end

        STATE_DMEM_REQ, STATE_DMEM_WAIT: begin
          if (dmem_rsp_fire) begin
            if (!dmem_rsp_ok) begin
              state_q          <= STATE_FAULT;
              fault_valid      <= 1'b1;
              if ((mem_op_q == dc_isa_pkg::MEM_LW) ||
                  (mem_op_q == dc_isa_pkg::MEM_LH) ||
                  (mem_op_q == dc_isa_pkg::MEM_LHU) ||
                  (mem_op_q == dc_isa_pkg::MEM_LB) ||
                  (mem_op_q == dc_isa_pkg::MEM_LBU)) begin
                fault_cause <= dc_isa_pkg::FAULT_LOAD_ACCESS;
              end else begin
                fault_cause <= dc_isa_pkg::FAULT_STORE_ACCESS;
              end
              fault_pc         <= mem_pc_q;
              fault_inst_valid <= 1'b1;
              fault_inst       <= mem_inst_q;
            end else begin
              state_q     <= STATE_FETCH_REQ;
              pc_q        <= mem_pc_q + 32'd4;
              trace_valid <= 1'b1;
              trace_pc    <= mem_pc_q;
              trace_inst  <= mem_inst_q;
            end
          end else if ((state_q == STATE_DMEM_REQ) && dmem_req_ready) begin
            state_q <= STATE_DMEM_WAIT;
          end
        end

        STATE_FAULT: begin
          state_q <= STATE_FAULT;
        end

        default: begin
          state_q          <= STATE_FAULT;
          fault_valid      <= 1'b1;
          fault_cause      <= dc_isa_pkg::FAULT_ILLEGAL_INSTRUCTION;
          fault_pc         <= pc_q;
          fault_inst_valid <= 1'b0;
          fault_inst       <= '0;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
