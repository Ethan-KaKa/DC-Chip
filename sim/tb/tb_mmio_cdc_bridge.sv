`default_nettype none
`timescale 1ns / 1ps

module tb_mmio_cdc_bridge;

  // Clocks: CPU 100MHz (10ns), Periph 50MHz (20ns)
  logic clk_cpu;
  logic rst_cpu;
  logic clk_periph;
  logic rst_periph;

  initial begin : clk_cpu_gen
    clk_cpu = 0;
    forever #5 clk_cpu = ~clk_cpu;
  end

  initial begin : clk_periph_gen
    clk_periph = 0;
    forever #10 clk_periph = ~clk_periph;
  end

  // DUT 1: Sync bridge (ASYNC_CDC = 0)
  logic        s_cpu_req_valid, s_cpu_req_ready;
  logic [31:0] s_cpu_req_addr;
  logic        s_cpu_req_write;
  logic [1:0]  s_cpu_req_size;
  logic [31:0] s_cpu_req_wdata;
  logic [3:0]  s_cpu_req_wstrb;
  logic        s_cpu_rsp_valid, s_cpu_rsp_ready;
  logic [31:0] s_cpu_rsp_rdata;
  logic        s_cpu_rsp_error;

  logic        s_periph_req_valid, s_periph_req_ready;
  logic [31:0] s_periph_req_addr;
  logic        s_periph_req_write;
  logic [1:0]  s_periph_req_size;
  logic [31:0] s_periph_req_wdata;
  logic [3:0]  s_periph_req_wstrb;
  logic        s_periph_rsp_valid, s_periph_rsp_ready;
  logic [31:0] s_periph_rsp_rdata;
  logic        s_periph_rsp_error;

  mmio_cdc_bridge #(.ASYNC_CDC(1'b0)) u_sync_bridge (
    .clk_cpu          (clk_cpu),
    .rst_cpu          (rst_cpu),
    .cpu_req_valid    (s_cpu_req_valid),
    .cpu_req_ready    (s_cpu_req_ready),
    .cpu_req_addr     (s_cpu_req_addr),
    .cpu_req_write    (s_cpu_req_write),
    .cpu_req_size     (s_cpu_req_size),
    .cpu_req_wdata    (s_cpu_req_wdata),
    .cpu_req_wstrb    (s_cpu_req_wstrb),
    .cpu_rsp_valid    (s_cpu_rsp_valid),
    .cpu_rsp_ready    (s_cpu_rsp_ready),
    .cpu_rsp_rdata    (s_cpu_rsp_rdata),
    .cpu_rsp_error    (s_cpu_rsp_error),
    .clk_periph       (clk_cpu),
    .rst_periph       (rst_cpu),
    .periph_req_valid (s_periph_req_valid),
    .periph_req_ready (s_periph_req_ready),
    .periph_req_addr  (s_periph_req_addr),
    .periph_req_write (s_periph_req_write),
    .periph_req_size  (s_periph_req_size),
    .periph_req_wdata (s_periph_req_wdata),
    .periph_req_wstrb (s_periph_req_wstrb),
    .periph_rsp_valid (s_periph_rsp_valid),
    .periph_rsp_ready (s_periph_rsp_ready),
    .periph_rsp_rdata (s_periph_rsp_rdata),
    .periph_rsp_error (s_periph_rsp_error)
  );

  // DUT 2: Async CDC bridge (ASYNC_CDC = 1)
  logic        a_cpu_req_valid, a_cpu_req_ready;
  logic [31:0] a_cpu_req_addr;
  logic        a_cpu_req_write;
  logic [1:0]  a_cpu_req_size;
  logic [31:0] a_cpu_req_wdata;
  logic [3:0]  a_cpu_req_wstrb;
  logic        a_cpu_rsp_valid, a_cpu_rsp_ready;
  logic [31:0] a_cpu_rsp_rdata;
  logic        a_cpu_rsp_error;

  logic        a_periph_req_valid, a_periph_req_ready;
  logic [31:0] a_periph_req_addr;
  logic        a_periph_req_write;
  logic [1:0]  a_periph_req_size;
  logic [31:0] a_periph_req_wdata;
  logic [3:0]  a_periph_req_wstrb;
  logic        a_periph_rsp_valid, a_periph_rsp_ready;
  logic [31:0] a_periph_rsp_rdata;
  logic        a_periph_rsp_error;

  mmio_cdc_bridge #(.ASYNC_CDC(1'b1)) u_async_bridge (
    .clk_cpu          (clk_cpu),
    .rst_cpu          (rst_cpu),
    .cpu_req_valid    (a_cpu_req_valid),
    .cpu_req_ready    (a_cpu_req_ready),
    .cpu_req_addr     (a_cpu_req_addr),
    .cpu_req_write    (a_cpu_req_write),
    .cpu_req_size     (a_cpu_req_size),
    .cpu_req_wdata    (a_cpu_req_wdata),
    .cpu_req_wstrb    (a_cpu_req_wstrb),
    .cpu_rsp_valid    (a_cpu_rsp_valid),
    .cpu_rsp_ready    (a_cpu_rsp_ready),
    .cpu_rsp_rdata    (a_cpu_rsp_rdata),
    .cpu_rsp_error    (a_cpu_rsp_error),
    .clk_periph       (clk_periph),
    .rst_periph       (rst_periph),
    .periph_req_valid (a_periph_req_valid),
    .periph_req_ready (a_periph_req_ready),
    .periph_req_addr  (a_periph_req_addr),
    .periph_req_write (a_periph_req_write),
    .periph_req_size  (a_periph_req_size),
    .periph_req_wdata (a_periph_req_wdata),
    .periph_req_wstrb (a_periph_req_wstrb),
    .periph_rsp_valid (a_periph_rsp_valid),
    .periph_rsp_ready (a_periph_rsp_ready),
    .periph_rsp_rdata (a_periph_rsp_rdata),
    .periph_rsp_error (a_periph_rsp_error)
  );

  // Periph responder for async bridge (50MHz domain)
  always_ff @(posedge clk_periph) begin
    if (rst_periph) begin
      a_periph_req_ready <= 1'b1;
      a_periph_rsp_valid <= 1'b0;
      a_periph_rsp_rdata <= 32'd0;
      a_periph_rsp_error <= 1'b0;
    end else begin
      if (a_periph_req_valid && a_periph_req_ready) begin
        a_periph_rsp_valid <= 1'b1;
        a_periph_rsp_rdata <= 32'hCAFE_BABE;
        a_periph_rsp_error <= 1'b0;
      end else if (a_periph_rsp_valid && a_periph_rsp_ready) begin
        a_periph_rsp_valid <= 1'b0;
      end
    end
  end

  initial begin
    rst_cpu    = 1'b1;
    rst_periph = 1'b1;
    s_cpu_req_valid = 1'b0;
    s_cpu_req_addr  = 32'd0;
    s_cpu_req_write = 1'b0;
    s_cpu_req_size  = 2'd0;
    s_cpu_req_wdata = 32'd0;
    s_cpu_req_wstrb = 4'd0;
    s_cpu_rsp_ready = 1'b0;
    s_periph_req_ready = 1'b1;
    s_periph_rsp_valid = 1'b0;
    s_periph_rsp_rdata = 32'd0;
    s_periph_rsp_error = 1'b0;

    a_cpu_req_valid = 1'b0;
    a_cpu_req_addr  = 32'd0;
    a_cpu_req_write = 1'b0;
    a_cpu_req_size  = 2'd0;
    a_cpu_req_wdata = 32'd0;
    a_cpu_req_wstrb = 4'd0;
    a_cpu_rsp_ready = 1'b0;

    #40;
    rst_cpu    = 1'b0;
    rst_periph = 1'b0;
    #20;

    // Test 1: Sync bridge pass-through
    s_cpu_req_valid = 1'b1;
    s_cpu_req_addr  = 32'h1000_0100;
    s_cpu_rsp_ready = 1'b1;
    #1;
    if (!s_periph_req_valid || s_periph_req_addr !== 32'h1000_0100) begin
      $display("tb_mmio_cdc_bridge FAIL: sync bridge pass-through mismatch");
      $finish(1);
    end
    s_cpu_req_valid = 1'b0;
    #20;

    // Test 2: Async CDC bridge (CPU 100MHz, Periph 50MHz)
    @(posedge clk_cpu);
    #1;
    a_cpu_req_valid = 1'b1;
    a_cpu_req_addr  = 32'h1000_0000;
    a_cpu_req_write = 1'b0;
    a_cpu_req_size  = 2'b10;
    a_cpu_rsp_ready = 1'b1;

    while (!a_cpu_req_ready) begin
      @(posedge clk_cpu); #1;
    end
    @(posedge clk_cpu); #1;
    a_cpu_req_valid = 1'b0;

    // Wait for response in CPU domain
    while (!a_cpu_rsp_valid) begin
      @(posedge clk_cpu); #1;
    end

    if (a_cpu_rsp_rdata !== 32'hCAFE_BABE || a_cpu_rsp_error !== 1'b0) begin
      $display("tb_mmio_cdc_bridge FAIL: async bridge response mismatch, got 0x%08x", a_cpu_rsp_rdata);
      $finish(1);
    end
    @(posedge clk_cpu); #1;
    a_cpu_rsp_ready = 1'b0;
    #40;

    $display("tb_mmio_cdc_bridge: PASS");
    $finish(0);
  end

endmodule

`default_nettype wire
