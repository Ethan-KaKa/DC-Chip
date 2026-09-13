`default_nettype none

module periph_interconnect #(
  parameter logic [31:0] UART_BASE = 32'h1000_0000,
  parameter logic [31:0] LED_BASE  = 32'h1000_0100,
  parameter logic [31:0] BUTTONS_BASE = 32'h1000_0200
) (
  input  logic        clk,
  input  logic        rst,

  // Upstream slave interface (from CDC bridge / CPU)
  input  logic        s_req_valid,
  output logic        s_req_ready,
  input  logic [31:0] s_req_addr,
  input  logic        s_req_write,
  input  logic [1:0]  s_req_size,
  input  logic [31:0] s_req_wdata,
  input  logic [3:0]  s_req_wstrb,
  output logic        s_rsp_valid,
  input  logic        s_rsp_ready,
  output logic [31:0] s_rsp_rdata,
  output logic        s_rsp_error,

  // Downstream master: UART
  output logic        uart_req_valid,
  input  logic        uart_req_ready,
  output logic [31:0] uart_req_addr,
  output logic        uart_req_write,
  output logic [1:0]  uart_req_size,
  output logic [31:0] uart_req_wdata,
  output logic [3:0]  uart_req_wstrb,
  input  logic        uart_rsp_valid,
  output logic        uart_rsp_ready,
  input  logic [31:0] uart_rsp_rdata,
  input  logic        uart_rsp_error,

  // Downstream master: LED
  output logic        led_req_valid,
  input  logic        led_req_ready,
  output logic [31:0] led_req_addr,
  output logic        led_req_write,
  output logic [1:0]  led_req_size,
  output logic [31:0] led_req_wdata,
  output logic [3:0]  led_req_wstrb,
  input  logic        led_rsp_valid,
  output logic        led_rsp_ready,
  input  logic [31:0] led_rsp_rdata,
  input  logic        led_rsp_error,

  // Downstream master: Buttons
  output logic        buttons_req_valid,
  input  logic        buttons_req_ready,
  output logic [31:0] buttons_req_addr,
  output logic        buttons_req_write,
  output logic [1:0]  buttons_req_size,
  output logic [31:0] buttons_req_wdata,
  output logic [3:0]  buttons_req_wstrb,
  input  logic        buttons_rsp_valid,
  output logic        buttons_rsp_ready,
  input  logic [31:0] buttons_rsp_rdata,
  input  logic        buttons_rsp_error
);

  typedef enum logic [2:0] {
    TARGET_IDLE    = 3'b000,
    TARGET_UART    = 3'b001,
    TARGET_LED     = 3'b010,
    TARGET_BUTTONS = 3'b011,
    TARGET_ERROR   = 3'b111
  } target_t;

  typedef enum logic [1:0] {
    STATE_IDLE     = 2'b00,
    STATE_WAIT_RSP = 2'b01,
    STATE_ERR_RSP  = 2'b10
  } state_t;

  state_t  state_q;
  target_t target_q;
  target_t target_comb;

  // Address decoding for peripheral space (0x1000_xxxx)
  wire is_uart = (s_req_addr[31:8] == UART_BASE[31:8]);
  wire is_led  = (s_req_addr[31:8] == LED_BASE[31:8]);
  wire is_buttons = (s_req_addr[31:8] == BUTTONS_BASE[31:8]);

  assign target_comb = target_t'(is_uart ? TARGET_UART :
                                 is_led  ? TARGET_LED  :
                                 is_buttons ? TARGET_BUTTONS :
                                 TARGET_ERROR);

  // Request pass-through
  assign uart_req_addr  = s_req_addr;
  assign uart_req_write = s_req_write;
  assign uart_req_size  = s_req_size;
  assign uart_req_wdata = s_req_wdata;
  assign uart_req_wstrb = s_req_wstrb;

  assign led_req_addr   = s_req_addr;
  assign led_req_write  = s_req_write;
  assign led_req_size   = s_req_size;
  assign led_req_wdata  = s_req_wdata;
  assign led_req_wstrb  = s_req_wstrb;

  assign buttons_req_addr  = s_req_addr;
  assign buttons_req_write = s_req_write;
  assign buttons_req_size  = s_req_size;
  assign buttons_req_wdata = s_req_wdata;
  assign buttons_req_wstrb = s_req_wstrb;

  // Request control
  wire req_active = !rst && (state_q == STATE_IDLE) && s_req_valid;
  assign uart_req_valid = req_active && (target_comb == TARGET_UART);
  assign led_req_valid  = req_active && (target_comb == TARGET_LED);
  assign buttons_req_valid = req_active && (target_comb == TARGET_BUTTONS);
  assign s_req_ready    = req_active && (
                            (target_comb == TARGET_UART  && uart_req_ready) ||
                            (target_comb == TARGET_LED   && led_req_ready)  ||
                            (target_comb == TARGET_BUTTONS && buttons_req_ready) ||
                            (target_comb == TARGET_ERROR)
                          );

  // Response control
  assign s_rsp_valid  = !rst && (
                          ((state_q == STATE_WAIT_RSP) && (
                            (target_q == TARGET_UART && uart_rsp_valid) ||
                            (target_q == TARGET_LED  && led_rsp_valid) ||
                            (target_q == TARGET_BUTTONS && buttons_rsp_valid)
                          )) ||
                          (state_q == STATE_ERR_RSP)
                        );
  assign s_rsp_rdata  = (state_q == STATE_WAIT_RSP && target_q == TARGET_UART) ? uart_rsp_rdata :
                        (state_q == STATE_WAIT_RSP && target_q == TARGET_LED)  ? led_rsp_rdata  :
                        (state_q == STATE_WAIT_RSP && target_q == TARGET_BUTTONS) ? buttons_rsp_rdata : 32'd0;
  assign s_rsp_error  = (state_q == STATE_ERR_RSP) ? 1'b1 :
                        (state_q == STATE_WAIT_RSP && target_q == TARGET_UART) ? uart_rsp_error :
                        (state_q == STATE_WAIT_RSP && target_q == TARGET_LED)  ? led_rsp_error  :
                        (state_q == STATE_WAIT_RSP && target_q == TARGET_BUTTONS) ? buttons_rsp_error : 1'b0;

  assign uart_rsp_ready = !rst && (state_q == STATE_WAIT_RSP) && (target_q == TARGET_UART) && s_rsp_ready;
  assign led_rsp_ready  = !rst && (state_q == STATE_WAIT_RSP) && (target_q == TARGET_LED)  && s_rsp_ready;
  assign buttons_rsp_ready = !rst && (state_q == STATE_WAIT_RSP) && (target_q == TARGET_BUTTONS) && s_rsp_ready;

  // State machine
  always_ff @(posedge clk) begin
    if (rst) begin
      state_q  <= STATE_IDLE;
      target_q <= TARGET_IDLE;
    end else begin
      case (state_q)
        STATE_IDLE: begin
          if (s_req_valid) begin
            case (target_comb)
              TARGET_UART: begin
                if (uart_req_ready) begin
                  state_q  <= STATE_WAIT_RSP;
                  target_q <= TARGET_UART;
                end
              end
              TARGET_LED: begin
                if (led_req_ready) begin
                  state_q  <= STATE_WAIT_RSP;
                  target_q <= TARGET_LED;
                end
              end
              TARGET_BUTTONS: begin
                if (buttons_req_ready) begin
                  state_q  <= STATE_WAIT_RSP;
                  target_q <= TARGET_BUTTONS;
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
          if (s_rsp_valid && s_rsp_ready) begin
            state_q  <= STATE_IDLE;
            target_q <= TARGET_IDLE;
          end
        end

        STATE_ERR_RSP: begin
          if (s_rsp_ready) begin
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
