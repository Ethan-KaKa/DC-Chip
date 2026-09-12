`default_nettype none
`timescale 1ns / 1ps

module tb_uart_controller;

  localparam int unsigned BAUD_DIV   = 8;
  localparam int unsigned FIFO_DEPTH = 4;
  localparam logic [31:0] ADDR_BASE  = 32'h1000_0000;

  logic        clk;
  logic        rst;

  logic        req_valid;
  logic        req_ready;
  logic [31:0] req_addr;
  logic        req_write;
  logic [1:0]  req_size;
  logic [31:0] req_wdata;
  logic [3:0]  req_wstrb;

  logic        rsp_valid;
  logic        rsp_ready;
  logic [31:0] rsp_rdata;
  logic        rsp_error;

  logic        o_uart_tx;
  logic        i_uart_rx;

  uart_controller #(
    .ADDR_BASE  (ADDR_BASE),
    .BAUD_DIV   (BAUD_DIV),
    .FIFO_DEPTH (FIFO_DEPTH)
  ) u_dut (
    .clk       (clk),
    .rst       (rst),
    .req_valid (req_valid),
    .req_ready (req_ready),
    .req_addr  (req_addr),
    .req_write (req_write),
    .req_size  (req_size),
    .req_wdata (req_wdata),
    .req_wstrb (req_wstrb),
    .rsp_valid (rsp_valid),
    .rsp_ready (rsp_ready),
    .rsp_rdata (rsp_rdata),
    .rsp_error (rsp_error),
    .o_uart_tx (o_uart_tx),
    .i_uart_rx (i_uart_rx)
  );

  // Clock generation: 10ns period (100 MHz in sim testbench)
  initial begin : clk_gen
    clk = 0;
    forever #5 clk = ~clk;
  end

  task automatic step_cycle();
    @(posedge clk);
    #1;
  endtask

  task automatic bus_write(input [31:0] addr, input [31:0] data, input [3:0] strb, output logic err);
    req_valid = 1'b1;
    req_addr  = addr;
    req_write = 1'b1;
    req_size  = 2'b10;
    req_wdata = data;
    req_wstrb = strb;
    rsp_ready = 1'b1;

    while (!req_ready) begin
      step_cycle();
    end
    step_cycle();
    req_valid = 1'b0;

    while (!rsp_valid) begin
      step_cycle();
    end
    err = rsp_error;
    step_cycle();
    rsp_ready = 1'b0;
  endtask

  task automatic bus_read(input [31:0] addr, output [31:0] data, output logic err);
    req_valid = 1'b1;
    req_addr  = addr;
    req_write = 1'b0;
    req_size  = 2'b10;
    req_wdata = 32'd0;
    req_wstrb = 4'h0;
    rsp_ready = 1'b1;

    while (!req_ready) begin
      step_cycle();
    end
    step_cycle();
    req_valid = 1'b0;

    while (!rsp_valid) begin
      step_cycle();
    end
    data = rsp_rdata;
    err  = rsp_error;
    step_cycle();
    rsp_ready = 1'b0;
  endtask

  task automatic send_rx_byte(input [7:0] byte_val);
    // start bit
    i_uart_rx = 1'b0;
    repeat (BAUD_DIV) step_cycle();
    // 8 data bits (LSB first)
    for (int i = 0; i < 8; i++) begin
      i_uart_rx = byte_val[i];
      repeat (BAUD_DIV) step_cycle();
    end
    // stop bit
    i_uart_rx = 1'b1;
    repeat (BAUD_DIV) step_cycle();
  endtask

  logic err_flag;
  logic [31:0] rdata;

  initial begin
    // Init
    rst       = 1'b1;
    req_valid = 1'b0;
    req_addr  = 32'd0;
    req_write = 1'b0;
    req_size  = 2'b00;
    req_wdata = 32'd0;
    req_wstrb = 4'd0;
    rsp_ready = 1'b0;
    i_uart_rx = 1'b1;

    repeat (4) step_cycle();
    rst = 1'b0;
    repeat (2) step_cycle();

    // 1. Check initial state
    if (o_uart_tx !== 1'b1) begin
      $display("tb_uart_controller FAIL: o_uart_tx should be 1 at reset");
      $finish(1);
    end

    // Read STATUS register: expect tx_ready=1 (bit 1), rx_ready=0 (bit 0)
    bus_read(32'h1000_0008, rdata, err_flag);
    if (err_flag || (rdata[1:0] !== 2'b10)) begin
      $display("tb_uart_controller FAIL: initial status expected 0x02, got 0x%08x err=%b", rdata, err_flag);
      $finish(1);
    end

    // 2. Test TX Transmission: send byte 0x55 (01010101b)
    bus_write(32'h1000_0000, 32'h0000_0055, 4'h1, err_flag);
    if (err_flag) begin
      $display("tb_uart_controller FAIL: write TX failed with error");
      $finish(1);
    end

    // Wait for start bit
    while (o_uart_tx !== 1'b0) begin
      step_cycle();
    end

    // Sample each bit at mid-baud: start bit
    repeat (BAUD_DIV / 2) step_cycle();
    if (o_uart_tx !== 1'b0) begin
      $display("tb_uart_controller FAIL: start bit mismatch");
      $finish(1);
    end

    // 8 data bits for 0x55: LSB first is 1, 0, 1, 0, 1, 0, 1, 0
    for (int i = 0; i < 8; i++) begin
      repeat (BAUD_DIV) step_cycle();
      if (o_uart_tx !== ((i % 2 == 0) ? 1'b1 : 1'b0)) begin
        $display("tb_uart_controller FAIL: data bit %0d mismatch, got %b", i, o_uart_tx);
        $finish(1);
      end
    end

    // Stop bit
    repeat (BAUD_DIV) step_cycle();
    if (o_uart_tx !== 1'b1) begin
      $display("tb_uart_controller FAIL: stop bit mismatch, got %b", o_uart_tx);
      $finish(1);
    end

    // Return to idle
    repeat (BAUD_DIV) step_cycle();
    if (o_uart_tx !== 1'b1) begin
      $display("tb_uart_controller FAIL: idle bit mismatch, got %b", o_uart_tx);
      $finish(1);
    end

    // 3. Test RX Receiver: receive byte 0xA5
    send_rx_byte(8'hA5);
    repeat (4) step_cycle();

    // Check status: rx_ready should be 1
    bus_read(32'h1000_0008, rdata, err_flag);
    if (err_flag || (rdata[0] !== 1'b1)) begin
      $display("tb_uart_controller FAIL: rx_ready should be 1, got 0x%08x", rdata);
      $finish(1);
    end

    // Read RX DATA: expect 0xA5
    bus_read(32'h1000_0004, rdata, err_flag);
    if (err_flag || (rdata[7:0] !== 8'hA5)) begin
      $display("tb_uart_controller FAIL: rx_data expected 0xA5, got 0x%08x", rdata);
      $finish(1);
    end

    // After reading, rx_ready should be cleared to 0
    bus_read(32'h1000_0008, rdata, err_flag);
    if (err_flag || (rdata[0] !== 1'b0)) begin
      $display("tb_uart_controller FAIL: rx_ready should clear to 0, got 0x%08x", rdata);
      $finish(1);
    end

    // 4. Test Error paths: write to read-only RX_DATA (0x1000_0004)
    bus_write(32'h1000_0004, 32'h1234, 4'hf, err_flag);
    if (!err_flag) begin
      $display("tb_uart_controller FAIL: write to RX_DATA should produce error");
      $finish(1);
    end

    // Read from unmapped offset within controller
    bus_read(32'h1000_000c, rdata, err_flag);
    if (!err_flag) begin
      $display("tb_uart_controller FAIL: read from offset 0x0C should produce error");
      $finish(1);
    end

    $display("tb_uart_controller: PASS");
    $finish(0);
  end

endmodule

`default_nettype wire
