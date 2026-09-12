`default_nettype none

module uart_controller #(
  parameter logic [31:0] ADDR_BASE  = 32'h1000_0000,
  parameter int unsigned BAUD_DIV   = 432,
  parameter int unsigned FIFO_DEPTH = 16
) (
  input  logic        clk,
  input  logic        rst,

  // Bus slave interface (valid/ready handshake)
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  input  logic        req_write,
  input  logic [1:0]  req_size,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,

  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata,
  output logic        rsp_error,

  // Physical serial pins
  output logic        o_uart_tx,
  input  logic        i_uart_rx
);

`ifdef VERILATOR
  import "DPI-C" function void sim_uart_putc(input byte data);
`endif

  localparam logic [3:0] OFFSET_TX_DATA = 4'h0;
  localparam logic [3:0] OFFSET_RX_DATA = 4'h4;
  localparam logic [3:0] OFFSET_STATUS  = 4'h8;

  // Handshake signals
  logic rsp_valid_q;
  logic [31:0] rsp_rdata_q;
  logic rsp_error_q;

  wire req_fire = req_valid && req_ready;
  wire rsp_fire = rsp_valid_q && rsp_ready;
  assign req_ready = !rst && !rsp_valid_q;

  assign rsp_valid = rsp_valid_q;
  assign rsp_rdata = rsp_rdata_q;
  assign rsp_error = rsp_error_q;

  wire addr_base_match = (req_addr[31:4] == ADDR_BASE[31:4]);
  wire [3:0] addr_offset = req_addr[3:0];

  wire is_tx_addr = addr_base_match && (addr_offset == OFFSET_TX_DATA);
  wire is_rx_addr = addr_base_match && (addr_offset == OFFSET_RX_DATA);
  wire is_st_addr = addr_base_match && (addr_offset == OFFSET_STATUS);
  wire addr_valid = is_tx_addr || is_rx_addr || is_st_addr;

  // ---------------------------------------------------------------------------
  // TX FIFO and Transmitter
  // ---------------------------------------------------------------------------
  localparam int unsigned PTR_BITS = (FIFO_DEPTH <= 2) ? 1 :
                                     (FIFO_DEPTH <= 4) ? 2 :
                                     (FIFO_DEPTH <= 8) ? 3 :
                                     (FIFO_DEPTH <= 16) ? 4 : 5;

  logic [7:0] fifo_mem [0:FIFO_DEPTH-1];
  logic [PTR_BITS-1:0] fifo_wptr_q;
  logic [PTR_BITS-1:0] fifo_rptr_q;
  logic [PTR_BITS:0]   fifo_count_q;

  wire fifo_full  = (fifo_count_q == FIFO_DEPTH[PTR_BITS:0]);
  wire fifo_empty = (fifo_count_q == '0);
  wire tx_ready   = !fifo_full;

  typedef enum logic [1:0] {
    TX_IDLE,
    TX_SENDING
  } tx_state_t;

  tx_state_t tx_state_q;
  logic [15:0] tx_baud_cnt_q;
  logic [3:0]  tx_bit_idx_q;
  logic [9:0]  tx_shift_q;
  logic        uart_tx_q;

  assign o_uart_tx = uart_tx_q;

  // ---------------------------------------------------------------------------
  // RX Synchronizer and Receiver
  // ---------------------------------------------------------------------------
  logic rx_sync1_q;
  logic rx_sync2_q;
  logic rx_ready_q;
  logic [7:0] rx_data_q;

  typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
  } rx_state_t;

  rx_state_t rx_state_q;
  logic [15:0] rx_baud_cnt_q;
  logic [2:0]  rx_bit_idx_q;
  logic [7:0]  rx_shift_q;

  // ---------------------------------------------------------------------------
  // Bus Handshake & Register Access
  // ---------------------------------------------------------------------------
  wire fifo_push = req_fire && req_write && is_tx_addr && !fifo_full;
  wire [7:0] fifo_wdata = req_wdata[7:0];

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_valid_q <= 1'b0;
      rsp_rdata_q <= 32'd0;
      rsp_error_q <= 1'b0;
      rx_ready_q  <= 1'b0;
      rx_data_q   <= 8'd0;
    end else begin
      if (req_fire) begin
        rsp_valid_q <= 1'b1;
        if (addr_valid) begin
          rsp_error_q <= 1'b0;
          if (req_write) begin
            if (is_tx_addr) begin
              `ifdef VERILATOR
                sim_uart_putc(req_wdata[7:0]);
              `endif
              rsp_rdata_q <= 32'd0;
            end else begin
              // Writing to RX_DATA or STATUS is read-only
              rsp_error_q <= 1'b1;
              rsp_rdata_q <= 32'd0;
            end
          end else begin // read
            if (is_tx_addr) begin
              rsp_rdata_q <= 32'd0;
            end else if (is_rx_addr) begin
              rsp_rdata_q <= {24'd0, rx_data_q};
              rx_ready_q  <= 1'b0; // clear on read
            end else begin // STATUS
              rsp_rdata_q <= {30'd0, tx_ready, rx_ready_q};
            end
          end
        end else begin
          rsp_error_q <= 1'b1;
          rsp_rdata_q <= 32'd0;
        end
      end else if (rsp_fire) begin
        rsp_valid_q <= 1'b0;
        rsp_error_q <= 1'b0;
        rsp_rdata_q <= 32'd0;
      end

      // Latch newly received RX byte
      if (rx_state_q == RX_STOP && rx_baud_cnt_q == 0 && rx_sync2_q == 1'b1) begin
        rx_data_q  <= rx_shift_q;
        rx_ready_q <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // TX FIFO & State Machine
  // ---------------------------------------------------------------------------
  logic fifo_pop;
  logic [7:0] tx_byte_to_send;

  assign tx_byte_to_send = fifo_mem[fifo_rptr_q];

  always_ff @(posedge clk) begin
    if (rst) begin
      fifo_wptr_q  <= '0;
      fifo_rptr_q  <= '0;
      fifo_count_q <= '0;
    end else begin
      if (fifo_push && !fifo_pop) begin
        fifo_mem[fifo_wptr_q] <= fifo_wdata;
        fifo_wptr_q           <= fifo_wptr_q + 1'b1;
        fifo_count_q          <= fifo_count_q + 1'b1;
      end else if (!fifo_push && fifo_pop) begin
        fifo_rptr_q  <= fifo_rptr_q + 1'b1;
        fifo_count_q <= fifo_count_q - 1'b1;
      end else if (fifo_push && fifo_pop) begin
        fifo_mem[fifo_wptr_q] <= fifo_wdata;
        fifo_wptr_q           <= fifo_wptr_q + 1'b1;
        fifo_rptr_q           <= fifo_rptr_q + 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      tx_state_q    <= TX_IDLE;
      tx_baud_cnt_q <= 16'd0;
      tx_bit_idx_q  <= 4'd0;
      tx_shift_q    <= 10'h3ff;
      uart_tx_q     <= 1'b1;
      fifo_pop      <= 1'b0;
    end else begin
      fifo_pop <= 1'b0;
      case (tx_state_q)
        TX_IDLE: begin
          uart_tx_q    <= 1'b1;
          tx_bit_idx_q <= 4'd0;
          if (!fifo_empty) begin
            fifo_pop      <= 1'b1;
            tx_shift_q    <= {1'b1, tx_byte_to_send, 1'b0}; // stop(1), data(8), start(0)
            tx_state_q    <= TX_SENDING;
            tx_baud_cnt_q <= 16'(BAUD_DIV - 1);
            uart_tx_q     <= 1'b0; // start bit
          end
        end

        TX_SENDING: begin
          if (tx_baud_cnt_q == 0) begin
            tx_baud_cnt_q <= 16'(BAUD_DIV - 1);
            if (tx_bit_idx_q == 4'd9) begin
              tx_state_q <= TX_IDLE;
              uart_tx_q  <= 1'b1;
            end else begin
              tx_bit_idx_q <= tx_bit_idx_q + 1'b1;
              uart_tx_q    <= tx_shift_q[tx_bit_idx_q + 1'b1];
            end
          end else begin
            tx_baud_cnt_q <= tx_baud_cnt_q - 1'b1;
          end
        end

        default: begin
          tx_state_q <= TX_IDLE;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // RX Synchronizer and State Machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      rx_sync1_q    <= 1'b1;
      rx_sync2_q    <= 1'b1;
      rx_state_q    <= RX_IDLE;
      rx_baud_cnt_q <= 16'd0;
      rx_bit_idx_q  <= 3'd0;
      rx_shift_q    <= 8'd0;
    end else begin
      rx_sync1_q <= i_uart_rx;
      rx_sync2_q <= rx_sync1_q;

      case (rx_state_q)
        RX_IDLE: begin
          if (!rx_sync2_q) begin // falling edge: start bit
            rx_state_q    <= RX_START;
            rx_baud_cnt_q <= 16'(BAUD_DIV / 2 - 1);
          end
        end

        RX_START: begin
          if (rx_baud_cnt_q == 0) begin
            if (!rx_sync2_q) begin
              rx_state_q    <= RX_DATA;
              rx_baud_cnt_q <= 16'(BAUD_DIV - 1);
              rx_bit_idx_q  <= 3'd0;
            end else begin
              rx_state_q <= RX_IDLE; // glitch
            end
          end else begin
            rx_baud_cnt_q <= rx_baud_cnt_q - 1'b1;
          end
        end

        RX_DATA: begin
          if (rx_baud_cnt_q == 0) begin
            rx_baud_cnt_q <= 16'(BAUD_DIV - 1);
            rx_shift_q[rx_bit_idx_q] <= rx_sync2_q;
            if (rx_bit_idx_q == 3'd7) begin
              rx_state_q <= RX_STOP;
            end else begin
              rx_bit_idx_q <= rx_bit_idx_q + 1'b1;
            end
          end else begin
            rx_baud_cnt_q <= rx_baud_cnt_q - 1'b1;
          end
        end

        RX_STOP: begin
          if (rx_baud_cnt_q == 0) begin
            rx_state_q <= RX_IDLE;
          end else begin
            rx_baud_cnt_q <= rx_baud_cnt_q - 1'b1;
          end
        end

        default: begin
          rx_state_q <= RX_IDLE;
        end
      endcase
    end
  end

  // Clean lint tie-off for unused inputs
  logic _unused;
  assign _unused = &{1'b0, req_size, req_wdata[31:8], req_wstrb, 1'b0};

endmodule

`default_nettype wire
