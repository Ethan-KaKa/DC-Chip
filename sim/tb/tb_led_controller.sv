`default_nettype none
`timescale 1ns / 1ps

module tb_led_controller;

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

  logic [15:0] o_led;

  led_controller u_dut (
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
    .o_led     (o_led)
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

  task write_reg(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0]  strb,
    input logic [1:0]  size,
    output logic       err
  );
    begin
      req_valid <= 1'b1;
      req_addr  <= addr;
      req_write <= 1'b1;
      req_wdata <= data;
      req_wstrb <= strb;
      req_size  <= size;
      rsp_ready <= 1'b1;

      while (!req_ready) step_cycle();
      step_cycle();
      req_valid <= 1'b0;

      while (!rsp_valid) step_cycle();
      err = rsp_error;
      step_cycle();
    end
  endtask

  task read_reg(
    input  logic [31:0] addr,
    input  logic [1:0]  size,
    output logic [31:0] data,
    output logic        err
  );
    begin
      req_valid <= 1'b1;
      req_addr  <= addr;
      req_write <= 1'b0;
      req_wdata <= 32'd0;
      req_wstrb <= 4'd0;
      req_size  <= size;
      rsp_ready <= 1'b1;

      while (!req_ready) step_cycle();
      step_cycle();
      req_valid <= 1'b0;

      while (!rsp_valid) step_cycle();
      data = rsp_rdata;
      err  = rsp_error;
      step_cycle();
    end
  endtask

  logic [31:0] rdata;
  logic        err;

  initial begin
    req_valid = 0;
    req_addr  = 0;
    req_write = 0;
    req_size  = 0;
    req_wdata = 0;
    req_wstrb = 0;
    rsp_ready = 0;

    // Reset
    rst = 1;
    step_cycle();
    step_cycle();
    rst = 0;
    step_cycle();

    // 1. Check reset state
    if (o_led !== 16'h0000) begin
      $display("tb_led_controller: FAIL - reset o_led mismatch: %h", o_led);
      $finish(1);
    end

    // 2. Word write 0xbeef
    write_reg(32'h1000_0100, 32'h0000_beef, 4'b1111, 2'b10, err);
    if (err || o_led !== 16'hbeef) begin
      $display("tb_led_controller: FAIL - word write failed: o_led=%h err=%b", o_led, err);
      $finish(1);
    end

    // 3. Word read
    read_reg(32'h1000_0100, 2'b10, rdata, err);
    if (err || rdata !== 32'h0000_beef) begin
      $display("tb_led_controller: FAIL - word read mismatch: rdata=%h err=%b", rdata, err);
      $finish(1);
    end

    // 4. Byte write byte 0: 0xaa
    write_reg(32'h1000_0100, 32'h0000_00aa, 4'b0001, 2'b00, err);
    if (err || o_led !== 16'hbeaa) begin
      $display("tb_led_controller: FAIL - byte 0 write mismatch: o_led=%h", o_led);
      $finish(1);
    end

    // 5. Byte write byte 1: 0x55
    write_reg(32'h1000_0100, 32'h0000_5500, 4'b0010, 2'b00, err);
    if (err || o_led !== 16'h55aa) begin
      $display("tb_led_controller: FAIL - byte 1 write mismatch: o_led=%h", o_led);
      $finish(1);
    end

    // 6. Unmapped address access
    write_reg(32'h1000_0104, 32'hffff_ffff, 4'b1111, 2'b10, err);
    if (!err || o_led !== 16'h55aa) begin
      $display("tb_led_controller: FAIL - unmapped write should fail: err=%b o_led=%h", err, o_led);
      $finish(1);
    end

    // 7. Backpressure hold test
    req_valid <= 1'b1;
    req_addr  <= 32'h1000_0100;
    req_write <= 1'b0;
    rsp_ready <= 1'b0; // do not accept response immediately
    step_cycle();
    req_valid <= 1'b0;

    // Response should arrive next cycle and hold
    step_cycle();
    if (!rsp_valid || rsp_rdata !== 32'h0000_55aa) begin
      $display("tb_led_controller: FAIL - rsp_valid should hold during backpressure");
      $finish(1);
    end
    step_cycle();
    if (!rsp_valid || rsp_rdata !== 32'h0000_55aa) begin
      $display("tb_led_controller: FAIL - rsp_valid did not hold on cycle 2");
      $finish(1);
    end
    // Now accept
    rsp_ready <= 1'b1;
    step_cycle();
    if (rsp_valid) begin
      $display("tb_led_controller: FAIL - rsp_valid did not clear after handshake");
      $finish(1);
    end

    $display("tb_led_controller: PASS");
    $finish(0);
  end

endmodule

`default_nettype wire
