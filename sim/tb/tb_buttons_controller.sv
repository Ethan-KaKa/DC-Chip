`default_nettype none
`timescale 1ns / 1ps

module tb_buttons_controller;
  logic clk, rst;
  logic req_valid, req_ready;
  logic [31:0] req_addr;
  logic req_write;
  logic [1:0] req_size;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid, rsp_ready;
  logic [31:0] rsp_rdata;
  logic rsp_error;
  logic [20:0] i_button;

  buttons_controller u_dut (
    .clk(clk), .rst(rst), .req_valid(req_valid), .req_ready(req_ready),
    .req_addr(req_addr), .req_write(req_write), .req_size(req_size),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb), .rsp_valid(rsp_valid),
    .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata), .rsp_error(rsp_error),
    .i_button(i_button)
  );

  initial begin clk = 0; forever #5 clk = ~clk; end

  task automatic read_buttons(input logic [31:0] expected);
    begin
      req_valid = 1'b1;
      req_addr = 32'h1000_0200;
      req_write = 1'b0;
      while (!req_ready) @(posedge clk);
      @(posedge clk); #1;
      req_valid = 1'b0;
      while (!rsp_valid) @(posedge clk);
      if (rsp_error || rsp_rdata !== expected) begin
        $display("tb_buttons_controller FAIL: data=%h error=%b expected=%h", rsp_rdata, rsp_error, expected);
        $finish(1);
      end
      @(posedge clk); #1;
    end
  endtask

  initial begin
    rst = 1'b1;
    req_valid = 1'b0;
    req_addr = 0;
    req_write = 0;
    req_size = 2'b10;
    req_wdata = 0;
    req_wstrb = 0;
    rsp_ready = 1'b1;
    i_button = 21'h00000;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3) @(posedge clk);
    read_buttons(32'h0000_0000);

    i_button = 21'h0005a;
    repeat (3) @(posedge clk);
    read_buttons(32'h0000_005a);

    req_valid = 1'b1;
    req_addr = 32'h1000_0200;
    req_write = 1'b1;
    req_wdata = 32'hffff_ffff;
    while (!req_ready) @(posedge clk);
    @(posedge clk); #1;
    req_valid = 1'b0;
    while (!rsp_valid) @(posedge clk);
    if (!rsp_error) begin
      $display("tb_buttons_controller FAIL: write should return error");
      $finish(1);
    end

    $display("tb_buttons_controller: PASS");
    $finish(0);
  end
endmodule

`default_nettype wire
