`default_nettype none
`timescale 1ns / 1ps

module tb_soc_interconnect;

  logic        clk;
  logic        rst;

  // CPU
  logic        cpu_req_valid;
  logic        cpu_req_ready;
  logic [31:0] cpu_req_addr;
  logic        cpu_req_write;
  logic [1:0]  cpu_req_size;
  logic [31:0] cpu_req_wdata;
  logic [3:0]  cpu_req_wstrb;
  logic        cpu_rsp_valid;
  logic        cpu_rsp_ready;
  logic [31:0] cpu_rsp_rdata;
  logic        cpu_rsp_error;

  // DRAM
  logic        dram_req_valid;
  logic        dram_req_ready;
  logic [31:0] dram_req_addr;
  logic        dram_req_write;
  logic [1:0]  dram_req_size;
  logic [31:0] dram_req_wdata;
  logic [3:0]  dram_req_wstrb;
  logic        dram_rsp_valid;
  logic        dram_rsp_ready;
  logic [31:0] dram_rsp_rdata;
  logic        dram_rsp_error;

  // MMIO
  logic        mmio_req_valid;
  logic        mmio_req_ready;
  logic [31:0] mmio_req_addr;
  logic        mmio_req_write;
  logic [1:0]  mmio_req_size;
  logic [31:0] mmio_req_wdata;
  logic [3:0]  mmio_req_wstrb;
  logic        mmio_rsp_valid;
  logic        mmio_rsp_ready;
  logic [31:0] mmio_rsp_rdata;
  logic        mmio_rsp_error;

  soc_interconnect u_dut (
    .clk            (clk),
    .rst            (rst),
    .cpu_req_valid  (cpu_req_valid),
    .cpu_req_ready  (cpu_req_ready),
    .cpu_req_addr   (cpu_req_addr),
    .cpu_req_write  (cpu_req_write),
    .cpu_req_size   (cpu_req_size),
    .cpu_req_wdata  (cpu_req_wdata),
    .cpu_req_wstrb  (cpu_req_wstrb),
    .cpu_rsp_valid  (cpu_rsp_valid),
    .cpu_rsp_ready  (cpu_rsp_ready),
    .cpu_rsp_rdata  (cpu_rsp_rdata),
    .cpu_rsp_error  (cpu_rsp_error),
    .dram_req_valid (dram_req_valid),
    .dram_req_ready (dram_req_ready),
    .dram_req_addr  (dram_req_addr),
    .dram_req_write (dram_req_write),
    .dram_req_size  (dram_req_size),
    .dram_req_wdata (dram_req_wdata),
    .dram_req_wstrb (dram_req_wstrb),
    .dram_rsp_valid (dram_rsp_valid),
    .dram_rsp_ready (dram_rsp_ready),
    .dram_rsp_rdata (dram_rsp_rdata),
    .dram_rsp_error (dram_rsp_error),
    .mmio_req_valid (mmio_req_valid),
    .mmio_req_ready (mmio_req_ready),
    .mmio_req_addr  (mmio_req_addr),
    .mmio_req_write (mmio_req_write),
    .mmio_req_size  (mmio_req_size),
    .mmio_req_wdata (mmio_req_wdata),
    .mmio_req_wstrb (mmio_req_wstrb),
    .mmio_rsp_valid (mmio_rsp_valid),
    .mmio_rsp_ready (mmio_rsp_ready),
    .mmio_rsp_rdata (mmio_rsp_rdata),
    .mmio_rsp_error (mmio_rsp_error)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  task step_cycle;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  // Mock DRAM responder (1 cycle latency)
  always_ff @(posedge clk) begin
    if (rst) begin
      dram_rsp_valid <= 1'b0;
      dram_rsp_rdata <= 32'd0;
      dram_rsp_error <= 1'b0;
    end else begin
      if (dram_req_valid && dram_req_ready) begin
        dram_rsp_valid <= 1'b1;
        dram_rsp_rdata <= dram_req_addr + 32'h0100;
        dram_rsp_error <= 1'b0;
      end else if (dram_rsp_valid && dram_rsp_ready) begin
        dram_rsp_valid <= 1'b0;
      end
    end
  end
  assign dram_req_ready = !dram_rsp_valid;

  // Mock MMIO responder (1 cycle latency)
  always_ff @(posedge clk) begin
    if (rst) begin
      mmio_rsp_valid <= 1'b0;
      mmio_rsp_rdata <= 32'd0;
      mmio_rsp_error <= 1'b0;
    end else begin
      if (mmio_req_valid && mmio_req_ready) begin
        mmio_rsp_valid <= 1'b1;
        mmio_rsp_rdata <= 32'hcafe_0000 | (mmio_req_addr & 32'hffff);
        mmio_rsp_error <= 1'b0;
      end else if (mmio_rsp_valid && mmio_rsp_ready) begin
        mmio_rsp_valid <= 1'b0;
      end
    end
  end
  assign mmio_req_ready = !mmio_rsp_valid;

  initial begin
    cpu_req_valid = 0;
    cpu_req_addr  = 0;
    cpu_req_write = 0;
    cpu_req_size  = 0;
    cpu_req_wdata = 0;
    cpu_req_wstrb = 0;
    cpu_rsp_ready = 0;

    // Reset
    rst = 1;
    step_cycle();
    step_cycle();
    rst = 0;
    step_cycle();

    // 1. Route to DRAM: 0x2000_0004
    cpu_req_valid <= 1'b1;
    cpu_req_addr  <= 32'h2000_0004;
    cpu_req_write <= 1'b0;
    cpu_rsp_ready <= 1'b1;

    while (!cpu_req_ready) step_cycle();
    if (!dram_req_valid || mmio_req_valid) begin
      $display("tb_soc_interconnect: FAIL - dram route failed");
      $finish(1);
    end
    step_cycle();
    cpu_req_valid <= 1'b0;

    while (!cpu_rsp_valid) step_cycle();
    if (cpu_rsp_rdata !== 32'h2000_0104 || cpu_rsp_error) begin
      $display("tb_soc_interconnect: FAIL - dram data mismatch: %h err=%b", cpu_rsp_rdata, cpu_rsp_error);
      $finish(1);
    end
    step_cycle();

    // 2. Route to Tohost: 0xffff_fff0
    cpu_req_valid <= 1'b1;
    cpu_req_addr  <= 32'hffff_fff0;
    cpu_req_write <= 1'b1;
    cpu_rsp_ready <= 1'b1;

    while (!cpu_req_ready) step_cycle();
    if (!dram_req_valid || mmio_req_valid) begin
      $display("tb_soc_interconnect: FAIL - tohost route failed");
      $finish(1);
    end
    step_cycle();
    cpu_req_valid <= 1'b0;

    while (!cpu_rsp_valid) step_cycle();
    step_cycle();

    // 3. Route to MMIO: 0x1000_0100
    cpu_req_valid <= 1'b1;
    cpu_req_addr  <= 32'h1000_0100;
    cpu_req_write <= 1'b0;
    cpu_rsp_ready <= 1'b1;

    while (!cpu_req_ready) step_cycle();
    if (dram_req_valid || !mmio_req_valid) begin
      $display("tb_soc_interconnect: FAIL - mmio route failed");
      $finish(1);
    end
    step_cycle();
    cpu_req_valid <= 1'b0;

    while (!cpu_rsp_valid) step_cycle();
    if (cpu_rsp_rdata !== 32'hcafe_0100 || cpu_rsp_error) begin
      $display("tb_soc_interconnect: FAIL - mmio data mismatch: %h err=%b", cpu_rsp_rdata, cpu_rsp_error);
      $finish(1);
    end
    step_cycle();

    // 4. Route to unmapped address: 0x3000_0000
    cpu_req_valid <= 1'b1;
    cpu_req_addr  <= 32'h3000_0000;
    cpu_req_write <= 1'b0;
    cpu_rsp_ready <= 1'b1;

    while (!cpu_req_ready) step_cycle();
    if (dram_req_valid || mmio_req_valid) begin
      $display("tb_soc_interconnect: FAIL - unmapped should not trigger slaves");
      $finish(1);
    end
    step_cycle();
    cpu_req_valid <= 1'b0;

    while (!cpu_rsp_valid) step_cycle();
    if (!cpu_rsp_error) begin
      $display("tb_soc_interconnect: FAIL - unmapped should assert cpu_rsp_error");
      $finish(1);
    end
    step_cycle();

    $display("tb_soc_interconnect: PASS");
    $finish(0);
  end

endmodule

`default_nettype wire
