`default_nettype none
`timescale 1ns / 1ps

module tb_periph_interconnect;

  logic        clk;
  logic        rst;

  // Upstream slave
  logic        s_req_valid;
  logic        s_req_ready;
  logic [31:0] s_req_addr;
  logic        s_req_write;
  logic [1:0]  s_req_size;
  logic [31:0] s_req_wdata;
  logic [3:0]  s_req_wstrb;
  logic        s_rsp_valid;
  logic        s_rsp_ready;
  logic [31:0] s_rsp_rdata;
  logic        s_rsp_error;

  // UART
  logic        uart_req_valid, uart_req_ready;
  logic [31:0] uart_req_addr;
  logic        uart_req_write;
  logic [1:0]  uart_req_size;
  logic [31:0] uart_req_wdata;
  logic [3:0]  uart_req_wstrb;
  logic        uart_rsp_valid, uart_rsp_ready;
  logic [31:0] uart_rsp_rdata;
  logic        uart_rsp_error;

  // LED
  logic        led_req_valid, led_req_ready;
  logic [31:0] led_req_addr;
  logic        led_req_write;
  logic [1:0]  led_req_size;
  logic [31:0] led_req_wdata;
  logic [3:0]  led_req_wstrb;
  logic        led_rsp_valid, led_rsp_ready;
  logic [31:0] led_rsp_rdata;
  logic        led_rsp_error;

  periph_interconnect #(
    .UART_BASE (32'h1000_0000),
    .LED_BASE  (32'h1000_0100)
  ) u_dut (
    .clk             (clk),
    .rst             (rst),
    .s_req_valid     (s_req_valid),
    .s_req_ready     (s_req_ready),
    .s_req_addr      (s_req_addr),
    .s_req_write     (s_req_write),
    .s_req_size      (s_req_size),
    .s_req_wdata     (s_req_wdata),
    .s_req_wstrb     (s_req_wstrb),
    .s_rsp_valid     (s_rsp_valid),
    .s_rsp_ready     (s_rsp_ready),
    .s_rsp_rdata     (s_rsp_rdata),
    .s_rsp_error     (s_rsp_error),
    .uart_req_valid  (uart_req_valid),
    .uart_req_ready  (uart_req_ready),
    .uart_req_addr   (uart_req_addr),
    .uart_req_write  (uart_req_write),
    .uart_req_size   (uart_req_size),
    .uart_req_wdata  (uart_req_wdata),
    .uart_req_wstrb  (uart_req_wstrb),
    .uart_rsp_valid  (uart_rsp_valid),
    .uart_rsp_ready  (uart_rsp_ready),
    .uart_rsp_rdata  (uart_rsp_rdata),
    .uart_rsp_error  (uart_rsp_error),
    .led_req_valid   (led_req_valid),
    .led_req_ready   (led_req_ready),
    .led_req_addr    (led_req_addr),
    .led_req_write   (led_req_write),
    .led_req_size    (led_req_size),
    .led_req_wdata   (led_req_wdata),
    .led_req_wstrb   (led_req_wstrb),
    .led_rsp_valid   (led_rsp_valid),
    .led_rsp_ready   (led_rsp_ready),
    .led_rsp_rdata   (led_rsp_rdata),
    .led_rsp_error   (led_rsp_error)
  );

  initial begin : clk_gen
    clk = 0;
    forever #5 clk = ~clk;
  end

  task automatic step_cycle();
    @(posedge clk);
    #1;
  endtask

  // Simple responders
  always_ff @(posedge clk) begin
    if (rst) begin
      uart_req_ready <= 1'b1;
      uart_rsp_valid <= 1'b0;
      uart_rsp_rdata <= 32'd0;
      uart_rsp_error <= 1'b0;

      led_req_ready  <= 1'b1;
      led_rsp_valid  <= 1'b0;
      led_rsp_rdata  <= 32'd0;
      led_rsp_error  <= 1'b0;
    end else begin
      if (uart_req_valid && uart_req_ready) begin
        uart_rsp_valid <= 1'b1;
        uart_rsp_rdata <= 32'h1111_2222;
        uart_rsp_error <= 1'b0;
      end else if (uart_rsp_valid && uart_rsp_ready) begin
        uart_rsp_valid <= 1'b0;
      end

      if (led_req_valid && led_req_ready) begin
        led_rsp_valid <= 1'b1;
        led_rsp_rdata <= 32'h3333_4444;
        led_rsp_error <= 1'b0;
      end else if (led_rsp_valid && led_rsp_ready) begin
        led_rsp_valid <= 1'b0;
      end
    end
  end

  initial begin
    rst         = 1'b1;
    s_req_valid = 1'b0;
    s_req_addr  = 32'd0;
    s_req_write = 1'b0;
    s_req_size  = 2'd0;
    s_req_wdata = 32'd0;
    s_req_wstrb = 4'd0;
    s_rsp_ready = 1'b0;

    repeat (4) step_cycle();
    rst = 1'b0;
    repeat (2) step_cycle();

    // 1. Access UART (0x1000_0000)
    s_req_valid = 1'b1;
    s_req_addr  = 32'h1000_0000;
    s_rsp_ready = 1'b1;
    while (!s_req_ready) step_cycle();
    step_cycle();
    s_req_valid = 1'b0;

    while (!s_rsp_valid) step_cycle();
    if (s_rsp_rdata !== 32'h1111_2222 || s_rsp_error !== 1'b0) begin
      $display("tb_periph_interconnect FAIL: UART routing mismatch");
      $finish(1);
    end
    step_cycle();
    s_rsp_ready = 1'b0;
    step_cycle();

    // 2. Access LED (0x1000_0100)
    s_req_valid = 1'b1;
    s_req_addr  = 32'h1000_0100;
    s_rsp_ready = 1'b1;
    while (!s_req_ready) step_cycle();
    step_cycle();
    s_req_valid = 1'b0;

    while (!s_rsp_valid) step_cycle();
    if (s_rsp_rdata !== 32'h3333_4444 || s_rsp_error !== 1'b0) begin
      $display("tb_periph_interconnect FAIL: LED routing mismatch");
      $finish(1);
    end
    step_cycle();
    s_rsp_ready = 1'b0;
    step_cycle();

    // 3. Access Unmapped (0x1000_0200) -> expect error
    s_req_valid = 1'b1;
    s_req_addr  = 32'h1000_0200;
    s_rsp_ready = 1'b1;
    while (!s_req_ready) step_cycle();
    step_cycle();
    s_req_valid = 1'b0;

    while (!s_rsp_valid) step_cycle();
    if (s_rsp_error !== 1'b1) begin
      $display("tb_periph_interconnect FAIL: Unmapped address should produce error");
      $finish(1);
    end
    step_cycle();
    s_rsp_ready = 1'b0;
    step_cycle();

    $display("tb_periph_interconnect: PASS");
    $finish(0);
  end

endmodule

`default_nettype wire
