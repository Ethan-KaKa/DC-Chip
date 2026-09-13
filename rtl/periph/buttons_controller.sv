`default_nettype none

module buttons_controller #(
  parameter logic [31:0] ADDR_BASE        = 32'h1000_0200,
  parameter int unsigned WIDTH            = 8,
  parameter int unsigned DEBOUNCE_CYCLES = 0
) (
  input  logic             clk,
  input  logic             rst,
  input  logic             req_valid,
  output logic             req_ready,
  input  logic [31:0]      req_addr,
  input  logic             req_write,
  input  logic [1:0]       req_size,
  input  logic [31:0]      req_wdata,
  input  logic [3:0]       req_wstrb,
  output logic             rsp_valid,
  input  logic             rsp_ready,
  output logic [31:0]      rsp_rdata,
  output logic             rsp_error,
  input  logic [WIDTH-1:0] i_button
);

  localparam int unsigned COUNT_BITS = (DEBOUNCE_CYCLES < 2) ? 1 :
                                       $clog2(DEBOUNCE_CYCLES + 1);

  logic [WIDTH-1:0] button_sync1_q;
  logic [WIDTH-1:0] button_sync2_q;
  logic [WIDTH-1:0] button_state_q;
  logic        rsp_valid_q;
  logic [31:0] rsp_rdata_q;
  logic        rsp_error_q;
  logic        req_fire;
  logic        rsp_fire;
  logic        addr_match;

  assign req_ready = !rst && !rsp_valid_q;
  assign req_fire  = req_valid && req_ready;
  assign rsp_fire  = rsp_valid_q && rsp_ready;
  assign rsp_valid = rsp_valid_q;
  assign rsp_rdata = rsp_rdata_q;
  assign rsp_error = rsp_error_q;
  assign addr_match = (req_addr[31:2] == ADDR_BASE[31:2]);

  generate
    if (DEBOUNCE_CYCLES == 0) begin : gen_no_debounce
      always_ff @(posedge clk) begin
        if (rst) begin
          button_sync1_q <= '0;
          button_sync2_q <= '0;
          button_state_q <= '0;
        end else begin
          button_sync1_q <= i_button;
          button_sync2_q <= button_sync1_q;
          button_state_q <= button_sync2_q;
        end
      end
    end else begin : gen_debounce
      localparam logic [COUNT_BITS-1:0] DEBOUNCE_LIMIT = DEBOUNCE_CYCLES - 1;
      logic [COUNT_BITS-1:0] debounce_count_q [0:WIDTH-1];
      always_ff @(posedge clk) begin : input_filter
        integer index;
        if (rst) begin
          button_sync1_q <= '0;
          button_sync2_q <= '0;
          button_state_q <= '0;
          for (index = 0; index < WIDTH; index = index + 1) begin
            debounce_count_q[index] <= '0;
          end
        end else begin
          button_sync1_q <= i_button;
          button_sync2_q <= button_sync1_q;
          for (index = 0; index < WIDTH; index = index + 1) begin
            if (button_sync2_q[index] == button_state_q[index]) begin
              debounce_count_q[index] <= '0;
            end else if (debounce_count_q[index] >= DEBOUNCE_LIMIT) begin
              button_state_q[index]    <= button_sync2_q[index];
              debounce_count_q[index] <= '0;
            end else begin
              debounce_count_q[index] <= debounce_count_q[index] + 1'b1;
            end
          end
        end
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_valid_q <= 1'b0;
      rsp_rdata_q <= 32'd0;
      rsp_error_q <= 1'b0;
    end else begin
      if (req_fire) begin
        rsp_valid_q <= 1'b1;
        if (addr_match && !req_write) begin
          rsp_error_q <= 1'b0;
          rsp_rdata_q <= {{(32-WIDTH){1'b0}}, button_state_q};
        end else begin
          rsp_error_q <= 1'b1;
          rsp_rdata_q <= 32'd0;
        end
      end else if (rsp_fire) begin
        rsp_valid_q <= 1'b0;
        rsp_error_q <= 1'b0;
        rsp_rdata_q <= 32'd0;
      end
    end
  end

  logic _unused;
  assign _unused = &{1'b0, req_addr[1:0], req_size, req_wdata, req_wstrb};

endmodule

`default_nettype wire
