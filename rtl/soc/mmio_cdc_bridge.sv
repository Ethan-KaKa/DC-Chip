`default_nettype none

module mmio_cdc_bridge #(
  parameter bit ASYNC_CDC = 1'b0
) (
  // CPU clock domain
  input  logic        clk_cpu,
  input  logic        rst_cpu,

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

  // Peripheral clock domain (fixed 50MHz)
  input  logic        clk_periph,
  input  logic        rst_periph,

  output logic        periph_req_valid,
  input  logic        periph_req_ready,
  output logic [31:0] periph_req_addr,
  output logic        periph_req_write,
  output logic [1:0]  periph_req_size,
  output logic [31:0] periph_req_wdata,
  output logic [3:0]  periph_req_wstrb,

  input  logic        periph_rsp_valid,
  output logic        periph_rsp_ready,
  input  logic [31:0] periph_rsp_rdata,
  input  logic        periph_rsp_error
);

  localparam logic [1:0] CPU_IDLE      = 2'b00;
  localparam logic [1:0] CPU_WAIT_RSP  = 2'b01;
  localparam logic [1:0] CPU_RSP_READY = 2'b10;

  localparam logic [1:0] PERIPH_IDLE     = 2'b00;
  localparam logic [1:0] PERIPH_WAIT_REQ = 2'b01;
  localparam logic [1:0] PERIPH_WAIT_RSP = 2'b10;

  generate
    if (!ASYNC_CDC) begin : gen_sync
      // Direct synchronous pass-through for simulation and same-clock modes
      assign periph_req_valid = cpu_req_valid;
      assign cpu_req_ready    = periph_req_ready;
      assign periph_req_addr  = cpu_req_addr;
      assign periph_req_write = cpu_req_write;
      assign periph_req_size  = cpu_req_size;
      assign periph_req_wdata = cpu_req_wdata;
      assign periph_req_wstrb = cpu_req_wstrb;

      assign cpu_rsp_valid    = periph_rsp_valid;
      assign periph_rsp_ready = cpu_rsp_ready;
      assign cpu_rsp_rdata    = periph_rsp_rdata;
      assign cpu_rsp_error    = periph_rsp_error;

      // Clean unused tie-offs
      logic _unused_clk;
      assign _unused_clk = &{1'b0, clk_cpu, rst_cpu, clk_periph, rst_periph, 1'b0};

    end else begin : gen_async
      // -----------------------------------------------------------------------
      // Asynchronous CDC Bridge (for FPGA with tunable CPU clock & fixed 50MHz periph)
      // -----------------------------------------------------------------------

      // CPU domain registers
      logic [1:0]  cpu_state_q;
      logic        req_toggle_cpu_q;
      logic        rsp_toggle_cpu_q;
      logic [31:0] req_addr_q;
      logic        req_write_q;
      logic [1:0]  req_size_q;
      logic [31:0] req_wdata_q;
      logic [3:0]  req_wstrb_q;

      logic        cpu_rsp_valid_q;
      logic [31:0] cpu_rsp_rdata_q;
      logic        cpu_rsp_error_q;

      assign cpu_req_ready = (cpu_state_q == CPU_IDLE) && !rst_cpu;
      assign cpu_rsp_valid = cpu_rsp_valid_q;
      assign cpu_rsp_rdata = cpu_rsp_rdata_q;
      assign cpu_rsp_error = cpu_rsp_error_q;

      // Peripheral domain registers
      logic [1:0]  periph_state_q;
      logic        req_toggle_periph_q;
      logic        rsp_toggle_periph_q;
      logic [31:0] rsp_rdata_periph_q;
      logic        rsp_error_periph_q;

      logic        periph_req_valid_q;
      logic        periph_rsp_ready_q;

      assign periph_req_valid = periph_req_valid_q;
      assign periph_req_addr  = req_addr_q;
      assign periph_req_write = req_write_q;
      assign periph_req_size  = req_size_q;
      assign periph_req_wdata = req_wdata_q;
      assign periph_req_wstrb = req_wstrb_q;
      assign periph_rsp_ready = periph_rsp_ready_q;

      // Synchronizers: periph -> cpu
      logic rsp_toggle_p2c_sync1_q, rsp_toggle_p2c_sync2_q;
      always_ff @(posedge clk_cpu) begin
        if (rst_cpu) begin
          rsp_toggle_p2c_sync1_q <= 1'b0;
          rsp_toggle_p2c_sync2_q <= 1'b0;
        end else begin
          rsp_toggle_p2c_sync1_q <= rsp_toggle_periph_q;
          rsp_toggle_p2c_sync2_q <= rsp_toggle_p2c_sync1_q;
        end
      end

      // Synchronizers: cpu -> periph
      logic req_toggle_c2p_sync1_q, req_toggle_c2p_sync2_q;
      always_ff @(posedge clk_periph) begin
        if (rst_periph) begin
          req_toggle_c2p_sync1_q <= 1'b0;
          req_toggle_c2p_sync2_q <= 1'b0;
        end else begin
          req_toggle_c2p_sync1_q <= req_toggle_cpu_q;
          req_toggle_c2p_sync2_q <= req_toggle_c2p_sync1_q;
        end
      end

      // CPU domain state machine
      always_ff @(posedge clk_cpu) begin
        if (rst_cpu) begin
          cpu_state_q      <= CPU_IDLE;
          req_toggle_cpu_q <= 1'b0;
          rsp_toggle_cpu_q <= 1'b0;
          req_addr_q       <= 32'd0;
          req_write_q      <= 1'b0;
          req_size_q       <= 2'd0;
          req_wdata_q      <= 32'd0;
          req_wstrb_q      <= 4'd0;
          cpu_rsp_valid_q  <= 1'b0;
          cpu_rsp_rdata_q  <= 32'd0;
          cpu_rsp_error_q  <= 1'b0;
        end else begin
          case (cpu_state_q)
            CPU_IDLE: begin
              if (cpu_req_valid && cpu_req_ready) begin
                req_addr_q       <= cpu_req_addr;
                req_write_q      <= cpu_req_write;
                req_size_q       <= cpu_req_size;
                req_wdata_q      <= cpu_req_wdata;
                req_wstrb_q      <= cpu_req_wstrb;
                req_toggle_cpu_q <= ~req_toggle_cpu_q;
                cpu_state_q      <= CPU_WAIT_RSP;
              end
            end

            CPU_WAIT_RSP: begin
              if (rsp_toggle_p2c_sync2_q != rsp_toggle_cpu_q) begin
                rsp_toggle_cpu_q <= rsp_toggle_p2c_sync2_q;
                cpu_rsp_rdata_q  <= rsp_rdata_periph_q;
                cpu_rsp_error_q  <= rsp_error_periph_q;
                cpu_rsp_valid_q  <= 1'b1;
                cpu_state_q      <= CPU_RSP_READY;
              end
            end

            CPU_RSP_READY: begin
              if (cpu_rsp_ready) begin
                cpu_rsp_valid_q <= 1'b0;
                cpu_state_q     <= CPU_IDLE;
              end
            end

            default: begin
              cpu_state_q <= CPU_IDLE;
            end
          endcase
        end
      end

      // Peripheral domain state machine
      always_ff @(posedge clk_periph) begin
        if (rst_periph) begin
          periph_state_q      <= PERIPH_IDLE;
          req_toggle_periph_q <= 1'b0;
          rsp_toggle_periph_q <= 1'b0;
          rsp_rdata_periph_q  <= 32'd0;
          rsp_error_periph_q  <= 1'b0;
          periph_req_valid_q  <= 1'b0;
          periph_rsp_ready_q  <= 1'b0;
        end else begin
          case (periph_state_q)
            PERIPH_IDLE: begin
              periph_rsp_ready_q <= 1'b0;
              if (req_toggle_c2p_sync2_q != req_toggle_periph_q) begin
                req_toggle_periph_q <= req_toggle_c2p_sync2_q;
                periph_req_valid_q  <= 1'b1;
                periph_state_q      <= PERIPH_WAIT_REQ;
              end
            end

            PERIPH_WAIT_REQ: begin
              if (periph_req_ready) begin
                periph_req_valid_q <= 1'b0;
                periph_rsp_ready_q <= 1'b1;
                periph_state_q     <= PERIPH_WAIT_RSP;
              end
            end

            PERIPH_WAIT_RSP: begin
              if (periph_rsp_valid) begin
                rsp_rdata_periph_q  <= periph_rsp_rdata;
                rsp_error_periph_q  <= periph_rsp_error;
                rsp_toggle_periph_q <= ~rsp_toggle_periph_q;
                periph_rsp_ready_q  <= 1'b0;
                periph_state_q      <= PERIPH_IDLE;
              end
            end

            default: begin
              periph_state_q <= PERIPH_IDLE;
            end
          endcase
        end
      end

    end
  endgenerate

endmodule

`default_nettype wire
