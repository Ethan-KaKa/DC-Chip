`default_nettype none

module soc_periph_subsystem #(
  parameter bit ASYNC_CDC = 1'b0
) (
  input logic clk_cpu, rst_cpu, clk_periph, rst_periph,
  input logic req_valid,
  output logic req_ready,
  input logic [31:0] req_addr,
  input logic req_write,
  input logic [1:0] req_size,
  input logic [31:0] req_wdata,
  input logic [3:0] req_wstrb,
  output logic rsp_valid,
  input logic rsp_ready,
  output logic [31:0] rsp_rdata,
  output logic rsp_error,
  output logic [15:0] o_led,
  output logic o_uart_tx,
  input logic i_uart_rx,
  input logic [20:0] i_button,
  output logic [7:0] o_seg0, o_seg1, o_seg2, o_seg3,
  output logic [7:0] o_seg4, o_seg5, o_seg6, o_seg7
);
  logic bus_req_valid, bus_req_ready, bus_req_write;
  logic [31:0] bus_req_addr, bus_req_wdata;
  logic [1:0] bus_req_size;
  logic [3:0] bus_req_wstrb;
  logic bus_rsp_valid, bus_rsp_ready, bus_rsp_error;
  logic [31:0] bus_rsp_rdata;

  logic uart_req_valid, uart_req_ready, uart_req_write;
  logic [31:0] uart_req_addr, uart_req_wdata, uart_rsp_rdata;
  logic [1:0] uart_req_size;
  logic [3:0] uart_req_wstrb;
  logic uart_rsp_valid, uart_rsp_ready, uart_rsp_error;
  logic led_req_valid, led_req_ready, led_req_write;
  logic [31:0] led_req_addr, led_req_wdata, led_rsp_rdata;
  logic [1:0] led_req_size;
  logic [3:0] led_req_wstrb;
  logic led_rsp_valid, led_rsp_ready, led_rsp_error;
  logic buttons_req_valid, buttons_req_ready, buttons_req_write;
  logic [31:0] buttons_req_addr, buttons_req_wdata, buttons_rsp_rdata;
  logic [1:0] buttons_req_size;
  logic [3:0] buttons_req_wstrb;
  logic buttons_rsp_valid, buttons_rsp_ready, buttons_rsp_error;
  logic seg7_req_valid, seg7_req_ready, seg7_req_write;
  logic [31:0] seg7_req_addr, seg7_req_wdata, seg7_rsp_rdata;
  logic [1:0] seg7_req_size;
  logic [3:0] seg7_req_wstrb;
  logic seg7_rsp_valid, seg7_rsp_ready, seg7_rsp_error;

  mmio_cdc_bridge #(.ASYNC_CDC(ASYNC_CDC)) u_cdc_bridge (
    .clk_cpu, .rst_cpu,
    .cpu_req_valid(req_valid), .cpu_req_ready(req_ready),
    .cpu_req_addr(req_addr), .cpu_req_write(req_write),
    .cpu_req_size(req_size), .cpu_req_wdata(req_wdata),
    .cpu_req_wstrb(req_wstrb), .cpu_rsp_valid(rsp_valid),
    .cpu_rsp_ready(rsp_ready), .cpu_rsp_rdata(rsp_rdata),
    .cpu_rsp_error(rsp_error), .clk_periph, .rst_periph,
    .periph_req_valid(bus_req_valid), .periph_req_ready(bus_req_ready),
    .periph_req_addr(bus_req_addr), .periph_req_write(bus_req_write),
    .periph_req_size(bus_req_size), .periph_req_wdata(bus_req_wdata),
    .periph_req_wstrb(bus_req_wstrb), .periph_rsp_valid(bus_rsp_valid),
    .periph_rsp_ready(bus_rsp_ready), .periph_rsp_rdata(bus_rsp_rdata),
    .periph_rsp_error(bus_rsp_error)
  );

  periph_interconnect u_periph_interconnect (
    .clk(clk_periph), .rst(rst_periph),
    .s_req_valid(bus_req_valid), .s_req_ready(bus_req_ready),
    .s_req_addr(bus_req_addr), .s_req_write(bus_req_write),
    .s_req_size(bus_req_size), .s_req_wdata(bus_req_wdata),
    .s_req_wstrb(bus_req_wstrb), .s_rsp_valid(bus_rsp_valid),
    .s_rsp_ready(bus_rsp_ready), .s_rsp_rdata(bus_rsp_rdata),
    .s_rsp_error(bus_rsp_error),
    .uart_req_valid, .uart_req_ready, .uart_req_addr, .uart_req_write,
    .uart_req_size, .uart_req_wdata, .uart_req_wstrb,
    .uart_rsp_valid, .uart_rsp_ready, .uart_rsp_rdata, .uart_rsp_error,
    .led_req_valid, .led_req_ready, .led_req_addr, .led_req_write,
    .led_req_size, .led_req_wdata, .led_req_wstrb,
    .led_rsp_valid, .led_rsp_ready, .led_rsp_rdata, .led_rsp_error,
    .buttons_req_valid, .buttons_req_ready, .buttons_req_addr,
    .buttons_req_write, .buttons_req_size, .buttons_req_wdata,
    .buttons_req_wstrb, .buttons_rsp_valid, .buttons_rsp_ready,
    .buttons_rsp_rdata, .buttons_rsp_error,
    .seg7_req_valid, .seg7_req_ready, .seg7_req_addr, .seg7_req_write,
    .seg7_req_size, .seg7_req_wdata, .seg7_req_wstrb,
    .seg7_rsp_valid, .seg7_rsp_ready, .seg7_rsp_rdata, .seg7_rsp_error
  );

  uart_controller #(
    .ADDR_BASE(dc_soc_addr_pkg::UART_BASE), .BAUD_DIV(432), .FIFO_DEPTH(16)
  ) u_uart_controller (
    .clk(clk_periph), .rst(rst_periph), .req_valid(uart_req_valid),
    .req_ready(uart_req_ready), .req_addr(uart_req_addr),
    .req_write(uart_req_write), .req_size(uart_req_size),
    .req_wdata(uart_req_wdata), .req_wstrb(uart_req_wstrb),
    .rsp_valid(uart_rsp_valid), .rsp_ready(uart_rsp_ready),
    .rsp_rdata(uart_rsp_rdata), .rsp_error(uart_rsp_error),
    .o_uart_tx, .i_uart_rx
  );

  led_controller #(.ADDR_BASE(dc_soc_addr_pkg::LED_BASE)) u_led_controller (
    .clk(clk_periph), .rst(rst_periph), .req_valid(led_req_valid),
    .req_ready(led_req_ready), .req_addr(led_req_addr),
    .req_write(led_req_write), .req_size(led_req_size),
    .req_wdata(led_req_wdata), .req_wstrb(led_req_wstrb),
    .rsp_valid(led_rsp_valid), .rsp_ready(led_rsp_ready),
    .rsp_rdata(led_rsp_rdata), .rsp_error(led_rsp_error), .o_led
  );

  buttons_controller #(
    .ADDR_BASE(dc_soc_addr_pkg::BUTTONS_BASE), .WIDTH(21), .DEBOUNCE_CYCLES(0)
  ) u_buttons_controller (
    .clk(clk_periph), .rst(rst_periph), .req_valid(buttons_req_valid),
    .req_ready(buttons_req_ready), .req_addr(buttons_req_addr),
    .req_write(buttons_req_write), .req_size(buttons_req_size),
    .req_wdata(buttons_req_wdata), .req_wstrb(buttons_req_wstrb),
    .rsp_valid(buttons_rsp_valid), .rsp_ready(buttons_rsp_ready),
    .rsp_rdata(buttons_rsp_rdata), .rsp_error(buttons_rsp_error), .i_button
  );

  seg7_controller #(.ADDR_BASE(dc_soc_addr_pkg::SEG7_BASE)) u_seg7_controller (
    .clk(clk_periph), .rst(rst_periph), .req_valid(seg7_req_valid),
    .req_ready(seg7_req_ready), .req_addr(seg7_req_addr),
    .req_write(seg7_req_write), .req_size(seg7_req_size),
    .req_wdata(seg7_req_wdata), .req_wstrb(seg7_req_wstrb),
    .rsp_valid(seg7_rsp_valid), .rsp_ready(seg7_rsp_ready),
    .rsp_rdata(seg7_rsp_rdata), .rsp_error(seg7_rsp_error),
    .o_seg0, .o_seg1, .o_seg2, .o_seg3, .o_seg4, .o_seg5, .o_seg6, .o_seg7
  );
endmodule

`default_nettype wire
