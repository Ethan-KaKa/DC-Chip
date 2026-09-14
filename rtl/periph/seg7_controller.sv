`default_nettype none

// Eight-digit hexadecimal seven-segment display controller.
// Each output is {a, b, c, d, e, f, g, dp}; a low level lights a segment.
module seg7_controller #(
  parameter logic [31:0] ADDR_BASE = 32'h1000_0300
) (
  input  logic        clk,
  input  logic        rst,

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

  output logic [7:0]  o_seg0,
  output logic [7:0]  o_seg1,
  output logic [7:0]  o_seg2,
  output logic [7:0]  o_seg3,
  output logic [7:0]  o_seg4,
  output logic [7:0]  o_seg5,
  output logic [7:0]  o_seg6,
  output logic [7:0]  o_seg7
);

  logic [31:0] seg_reg_q;
  logic        rsp_valid_q;
  logic [31:0] rsp_rdata_q;
  logic        rsp_error_q;
  logic        req_fire;
  logic        rsp_fire;
  logic        addr_match;

  function automatic logic [7:0] hex_to_segments(input logic [3:0] nibble);
    begin
      case (nibble)
        4'h0:   hex_to_segments = 8'b0000_0011;
        4'h1:   hex_to_segments = 8'b1001_1111;
        4'h2:   hex_to_segments = 8'b0010_0101;
        4'h3:   hex_to_segments = 8'b0000_1101;
        4'h4:   hex_to_segments = 8'b1001_1001;
        4'h5:   hex_to_segments = 8'b0100_1001;
        4'h6:   hex_to_segments = 8'b0100_0001;
        4'h7:   hex_to_segments = 8'b0001_1111;
        4'h8:   hex_to_segments = 8'b0000_0001;
        4'h9:   hex_to_segments = 8'b0000_1001;
        4'ha:   hex_to_segments = 8'b0001_0001;
        4'hb:   hex_to_segments = 8'b1100_0001;
        4'hc:   hex_to_segments = 8'b0110_0011;
        4'hd:   hex_to_segments = 8'b1000_0101;
        4'he:   hex_to_segments = 8'b0110_0001;
        default: hex_to_segments = 8'b0111_0001;
      endcase
    end
  endfunction

  assign req_ready = !rst && !rsp_valid_q;
  assign req_fire = req_valid && req_ready;
  assign rsp_fire = rsp_valid_q && rsp_ready;
  assign rsp_valid = rsp_valid_q;
  assign rsp_rdata = rsp_rdata_q;
  assign rsp_error = rsp_error_q;
  assign addr_match = (req_addr[31:2] == ADDR_BASE[31:2]);

  assign o_seg0 = hex_to_segments(seg_reg_q[3:0]);
  assign o_seg1 = hex_to_segments(seg_reg_q[7:4]);
  assign o_seg2 = hex_to_segments(seg_reg_q[11:8]);
  assign o_seg3 = hex_to_segments(seg_reg_q[15:12]);
  assign o_seg4 = hex_to_segments(seg_reg_q[19:16]);
  assign o_seg5 = hex_to_segments(seg_reg_q[23:20]);
  assign o_seg6 = hex_to_segments(seg_reg_q[27:24]);
  assign o_seg7 = hex_to_segments(seg_reg_q[31:28]);

  always_ff @(posedge clk) begin
    if (rst) begin
      seg_reg_q   <= 32'd0;
      rsp_valid_q <= 1'b0;
      rsp_rdata_q <= 32'd0;
      rsp_error_q <= 1'b0;
    end else begin
      if (req_fire) begin
        rsp_valid_q <= 1'b1;
        if (addr_match) begin
          rsp_error_q <= 1'b0;
          if (req_write) begin
            if (req_wstrb[0]) seg_reg_q[7:0]   <= req_wdata[7:0];
            if (req_wstrb[1]) seg_reg_q[15:8]  <= req_wdata[15:8];
            if (req_wstrb[2]) seg_reg_q[23:16] <= req_wdata[23:16];
            if (req_wstrb[3]) seg_reg_q[31:24] <= req_wdata[31:24];
            rsp_rdata_q <= 32'd0;
          end else begin
            rsp_rdata_q <= seg_reg_q;
          end
        end else begin
          rsp_error_q <= 1'b1;
          rsp_rdata_q <= 32'd0;
        end
      end else if (rsp_fire) begin
        rsp_valid_q <= 1'b0;
        rsp_rdata_q <= 32'd0;
        rsp_error_q <= 1'b0;
      end
    end
  end

  logic _unused;
  assign _unused = &{1'b0, req_size, req_addr[1:0], 1'b0};

endmodule

`default_nettype wire
