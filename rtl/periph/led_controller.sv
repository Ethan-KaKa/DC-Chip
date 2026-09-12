`default_nettype none

module led_controller #(
  parameter logic [31:0] ADDR_BASE = 32'h1000_0100
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

  // Peripheral output pins
  output logic [15:0] o_led
);

  logic [15:0] led_reg_q;
  logic        rsp_valid_q;
  logic [31:0] rsp_rdata_q;
  logic        rsp_error_q;

  logic req_fire;
  logic rsp_fire;
  logic addr_match;

  assign req_ready = !rst && !rsp_valid_q;
  assign req_fire  = req_valid && req_ready;
  assign rsp_fire  = rsp_valid_q && rsp_ready;

  assign rsp_valid = rsp_valid_q;
  assign rsp_rdata = rsp_rdata_q;
  assign rsp_error = rsp_error_q;
  assign o_led     = led_reg_q;

  assign addr_match = (req_addr[31:2] == ADDR_BASE[31:2]);

  always_ff @(posedge clk) begin
    if (rst) begin
      led_reg_q   <= 16'h0000;
      rsp_valid_q <= 1'b0;
      rsp_rdata_q <= 32'd0;
      rsp_error_q <= 1'b0;
    end else begin
      if (req_fire) begin
        rsp_valid_q <= 1'b1;
        if (addr_match) begin
          rsp_error_q <= 1'b0;
          if (req_write) begin
            if (req_wstrb[0]) led_reg_q[7:0]  <= req_wdata[7:0];
            if (req_wstrb[1]) led_reg_q[15:8] <= req_wdata[15:8];
            rsp_rdata_q <= 32'd0;
          end else begin
            rsp_rdata_q <= {16'h0000, led_reg_q};
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
    end
  end

  // Clean lint tie-off for unused inputs
  logic _unused;
  assign _unused = &{1'b0, req_size, req_wdata[31:16], req_wstrb[3:2], req_addr[1:0], 1'b0};

endmodule

`default_nettype wire
