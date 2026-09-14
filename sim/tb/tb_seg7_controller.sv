`default_nettype none
`timescale 1ns / 1ps

module tb_seg7_controller;
  logic clk;
  logic rst;
  logic req_valid;
  logic req_ready;
  logic [31:0] req_addr;
  logic req_write;
  logic [1:0] req_size;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid;
  logic rsp_ready;
  logic [31:0] rsp_rdata;
  logic rsp_error;
  logic [7:0] o_seg0, o_seg1, o_seg2, o_seg3;
  logic [7:0] o_seg4, o_seg5, o_seg6, o_seg7;

  seg7_controller u_dut (
    .clk, .rst, .req_valid, .req_ready, .req_addr, .req_write, .req_size,
    .req_wdata, .req_wstrb, .rsp_valid, .rsp_ready, .rsp_rdata, .rsp_error,
    .o_seg0, .o_seg1, .o_seg2, .o_seg3, .o_seg4, .o_seg5, .o_seg6, .o_seg7
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic transact(
    input logic write,
    input logic [31:0] addr,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    output logic [31:0] rdata,
    output logic error
  );
    begin
      @(negedge clk);
      req_valid = 1'b1;
      req_addr = addr;
      req_write = write;
      req_size = 2'd2;
      req_wdata = wdata;
      req_wstrb = wstrb;
      rsp_ready = 1'b1;
      while (!req_ready) @(posedge clk);
      @(posedge clk);
      #1;
      req_valid = 1'b0;
      while (!rsp_valid) @(posedge clk);
      rdata = rsp_rdata;
      error = rsp_error;
      @(posedge clk);
      #1;
    end
  endtask

  logic [31:0] rdata;
  logic error;
  initial begin
    rst = 1'b1;
    req_valid = 1'b0;
    req_addr = '0;
    req_write = 1'b0;
    req_size = '0;
    req_wdata = '0;
    req_wstrb = '0;
    rsp_ready = 1'b0;

    repeat (3) @(posedge clk);
    #1;
    if ({o_seg7, o_seg6, o_seg5, o_seg4, o_seg3, o_seg2, o_seg1, o_seg0}
        !== {8{8'b0000_0011}}) begin
      $display("tb_seg7_controller FAIL: reset glyphs are not all zero");
      $finish(1);
    end
    rst = 1'b0;

    transact(1'b1, 32'h1000_0300, 32'hfedc_ba98, 4'b1111, rdata, error);
    if (error || {o_seg7, o_seg6, o_seg5, o_seg4, o_seg3, o_seg2, o_seg1, o_seg0}
                 !== {8'h71, 8'h61, 8'h85, 8'h63, 8'hc1, 8'h11, 8'h09, 8'h01}) begin
      $display("tb_seg7_controller FAIL: hexadecimal glyph decode mismatch");
      $finish(1);
    end

    transact(1'b0, 32'h1000_0300, 32'd0, 4'd0, rdata, error);
    if (error || rdata !== 32'hfedc_ba98) begin
      $display("tb_seg7_controller FAIL: readback mismatch: %h err=%b", rdata, error);
      $finish(1);
    end

    transact(1'b1, 32'h1000_0300, 32'h00ab_0000, 4'b0100, rdata, error);
    transact(1'b0, 32'h1000_0300, 32'd0, 4'd0, rdata, error);
    if (error || rdata !== 32'hfeab_ba98 || o_seg4 !== 8'h11 || o_seg5 !== 8'hc1) begin
      $display("tb_seg7_controller FAIL: byte lane update mismatch: %h", rdata);
      $finish(1);
    end

    transact(1'b1, 32'h1000_0304, 32'h1234_5678, 4'b1111, rdata, error);
    if (!error) begin
      $display("tb_seg7_controller FAIL: unmapped access should fail");
      $finish(1);
    end

    // Response payload must remain stable until the consumer accepts it.
    @(negedge clk);
    req_valid = 1'b1;
    req_addr = 32'h1000_0300;
    req_write = 1'b0;
    req_wdata = '0;
    req_wstrb = '0;
    rsp_ready = 1'b0;
    @(posedge clk);
    #1;
    req_valid = 1'b0;
    repeat (2) begin
      @(posedge clk);
      #1;
      if (!rsp_valid || rsp_rdata !== 32'hfeab_ba98 || rsp_error) begin
        $display("tb_seg7_controller FAIL: response did not hold under backpressure");
        $finish(1);
      end
    end
    rsp_ready = 1'b1;
    @(posedge clk);
    #1;
    if (rsp_valid) begin
      $display("tb_seg7_controller FAIL: response did not clear after handshake");
      $finish(1);
    end

    $display("tb_seg7_controller: PASS");
    $finish(0);
  end
endmodule

`default_nettype wire
