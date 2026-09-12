`default_nettype none

module soc_interconnect #(
  parameter logic [31:0] DRAM_BASE   = 32'h2000_0000,
  parameter int unsigned DRAM_BYTES  = 65536,
  parameter logic [31:0] MMIO_BASE   = 32'h1000_0000,
  parameter int unsigned MMIO_BYTES  = 65536,
  parameter logic [31:0] TOHOST_ADDR = 32'hffff_fff0
) (
  input  logic        clk,
  input  logic        rst,

  // CPU master interface (LSU dmem)
  input  logic        cpu_req_valid,
  output logic        cpu_req_ready,
  input  logic [31:0] cpu_req_addr,
  input  logic        cpu_req_write,
  input  logic [1:0]  cpu_req_size,
  input  logic [31:0] cpu_req_wdata,
  input  logic [3:0]  cpu_req_wstrb,
  output logic        cpu_rsp_valid,
  input  logic        cpu_rsp_ready,
  output logic [31:0] cpu_rsp_rdata,
  output logic        cpu_rsp_error,
  output logic        cpu_rsp_skip_ref,

  // DRAM / Memory slave interface
  output logic        dram_req_valid,
  input  logic        dram_req_ready,
  output logic [31:0] dram_req_addr,
  output logic        dram_req_write,
  output logic [1:0]  dram_req_size,
  output logic [31:0] dram_req_wdata,
  output logic [3:0]  dram_req_wstrb,
  input  logic        dram_rsp_valid,
  output logic        dram_rsp_ready,
  input  logic [31:0] dram_rsp_rdata,
  input  logic        dram_rsp_error,

  // MMIO peripheral slave interface
  output logic        mmio_req_valid,
  input  logic        mmio_req_ready,
  output logic [31:0] mmio_req_addr,
  output logic        mmio_req_write,
  output logic [1:0]  mmio_req_size,
  output logic [31:0] mmio_req_wdata,
  output logic [3:0]  mmio_req_wstrb,
  input  logic        mmio_rsp_valid,
  output logic        mmio_rsp_ready,
  input  logic [31:0] mmio_rsp_rdata,
  input  logic        mmio_rsp_error
);

  typedef enum logic [1:0] {
    TARGET_IDLE  = 2'b00,
    TARGET_DRAM  = 2'b01,
    TARGET_MMIO  = 2'b10,
    TARGET_ERROR = 2'b11
  } target_t;

  typedef enum logic [1:0] {
    STATE_IDLE     = 2'b00,
    STATE_WAIT_RSP = 2'b01,
    STATE_ERR_RSP  = 2'b10
  } state_t;

  state_t  state_q;
  target_t target_q;
  target_t target_comb;

  /* verilator lint_off UNSIGNED */
  assign target_comb = target_t'(((cpu_req_addr >= DRAM_BASE && cpu_req_addr < (DRAM_BASE + 32'(DRAM_BYTES))) ||
                                  (cpu_req_addr == TOHOST_ADDR)) ? TARGET_DRAM :
                                 (cpu_req_addr >= MMIO_BASE && cpu_req_addr < (MMIO_BASE + 32'(MMIO_BYTES))) ? TARGET_MMIO :
                                 TARGET_ERROR);
  /* verilator lint_on UNSIGNED */

  // Request pass-through signals
  assign dram_req_addr  = cpu_req_addr;
  assign dram_req_write = cpu_req_write;
  assign dram_req_size  = cpu_req_size;
  assign dram_req_wdata = cpu_req_wdata;
  assign dram_req_wstrb = cpu_req_wstrb;

  assign mmio_req_addr  = cpu_req_addr;
  assign mmio_req_write = cpu_req_write;
  assign mmio_req_size  = cpu_req_size;
  assign mmio_req_wdata = cpu_req_wdata;
  assign mmio_req_wstrb = cpu_req_wstrb;

  // Request channel
  wire req_active = !rst && (state_q == STATE_IDLE) && cpu_req_valid;
  assign dram_req_valid = req_active && (target_comb == TARGET_DRAM);
  assign mmio_req_valid = req_active && (target_comb == TARGET_MMIO);
  assign cpu_req_ready  = req_active && (
                            (target_comb == TARGET_DRAM  && dram_req_ready) ||
                            (target_comb == TARGET_MMIO  && mmio_req_ready) ||
                            (target_comb == TARGET_ERROR)
                          );

  // Response channel
  assign cpu_rsp_valid  = !rst && (
                            ((state_q == STATE_WAIT_RSP) && (
                              (target_q == TARGET_DRAM && dram_rsp_valid) ||
                              (target_q == TARGET_MMIO && mmio_rsp_valid)
                            )) ||
                            (state_q == STATE_ERR_RSP)
                          );
  assign cpu_rsp_rdata  = (state_q == STATE_WAIT_RSP && target_q == TARGET_DRAM) ? dram_rsp_rdata :
                          (state_q == STATE_WAIT_RSP && target_q == TARGET_MMIO) ? mmio_rsp_rdata : 32'd0;
  assign cpu_rsp_error  = (state_q == STATE_ERR_RSP) ? 1'b1 :
                          (state_q == STATE_WAIT_RSP && target_q == TARGET_DRAM) ? dram_rsp_error :
                          (state_q == STATE_WAIT_RSP && target_q == TARGET_MMIO) ? mmio_rsp_error : 1'b0;
  assign cpu_rsp_skip_ref = (state_q == STATE_WAIT_RSP && target_q == TARGET_MMIO);
  assign dram_rsp_ready = !rst && (state_q == STATE_WAIT_RSP) && (target_q == TARGET_DRAM) && cpu_rsp_ready;
  assign mmio_rsp_ready = !rst && (state_q == STATE_WAIT_RSP) && (target_q == TARGET_MMIO) && cpu_rsp_ready;

  // ---------------------------------------------------------------------------
  // Interconnect state register
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      state_q  <= STATE_IDLE;
      target_q <= TARGET_IDLE;
    end else begin
      case (state_q)
        STATE_IDLE: begin
          if (cpu_req_valid) begin
            case (target_comb)
              TARGET_DRAM: begin
                if (dram_req_ready) begin
                  state_q  <= STATE_WAIT_RSP;
                  target_q <= TARGET_DRAM;
                end
              end
              TARGET_MMIO: begin
                if (mmio_req_ready) begin
                  state_q  <= STATE_WAIT_RSP;
                  target_q <= TARGET_MMIO;
                end
              end
              TARGET_ERROR: begin
                state_q  <= STATE_ERR_RSP;
                target_q <= TARGET_ERROR;
              end
              default: begin
              end
            endcase
          end
        end

        STATE_WAIT_RSP: begin
          if (cpu_rsp_valid && cpu_rsp_ready) begin
            state_q  <= STATE_IDLE;
            target_q <= TARGET_IDLE;
          end
        end

        STATE_ERR_RSP: begin
          if (cpu_rsp_ready) begin
            state_q  <= STATE_IDLE;
            target_q <= TARGET_IDLE;
          end
        end

        default: begin
          state_q  <= STATE_IDLE;
          target_q <= TARGET_IDLE;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
