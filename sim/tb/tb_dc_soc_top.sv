`default_nettype none
`timescale 1ns / 1ps

module tb_dc_soc_top;

  logic        clk;
  logic        rst;

  // IROM interface
  logic        imem_req_valid;
  logic        imem_req_ready;
  logic [31:0] imem_req_addr;
  logic        imem_rsp_valid;
  logic        imem_rsp_ready;
  logic [31:0] imem_rsp_rdata;
  logic        imem_rsp_error;

  // DRAM interface
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

  // Peripherals
  logic [15:0] o_led;
  logic        o_uart_tx;
  logic        i_uart_rx;
  logic [20:0] i_button;

  // Trace & Debug
  logic        trace_valid;
  logic [31:0] trace_pc;
  logic [31:0] trace_inst;
  logic        trace_skip_ref;
  logic [3:0]  debug_reg_addr;
  logic [31:0] debug_reg_data;
  logic        fault_valid;
  logic [2:0]  fault_cause;
  logic [31:0] fault_pc;
  logic        fault_inst_valid;
  logic [31:0] fault_inst;

  dc_soc_top u_soc (
    .clk              (clk),
    .rst              (rst),
    .clk_periph       (clk),
    .rst_periph       (rst),
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_rdata   (imem_rsp_rdata),
    .imem_rsp_error   (imem_rsp_error),
    .dram_req_valid   (dram_req_valid),
    .dram_req_ready   (dram_req_ready),
    .dram_req_addr    (dram_req_addr),
    .dram_req_write   (dram_req_write),
    .dram_req_size    (dram_req_size),
    .dram_req_wdata   (dram_req_wdata),
    .dram_req_wstrb   (dram_req_wstrb),
    .dram_rsp_valid   (dram_rsp_valid),
    .dram_rsp_ready   (dram_rsp_ready),
    .dram_rsp_rdata   (dram_rsp_rdata),
    .dram_rsp_error   (dram_rsp_error),
    .o_led            (o_led),
    .o_uart_tx        (o_uart_tx),
    .i_uart_rx        (i_uart_rx),
    .i_button         (i_button),
    .trace_valid      (trace_valid),
    .trace_pc         (trace_pc),
    .trace_inst       (trace_inst),
    .trace_skip_ref   (trace_skip_ref),
    .debug_reg_addr   (debug_reg_addr),
    .debug_reg_data   (debug_reg_data),
    .fault_valid      (fault_valid),
    .fault_cause      (fault_cause),
    .fault_pc         (fault_pc),
    .fault_inst_valid (fault_inst_valid),
    .fault_inst       (fault_inst)
  );

  initial begin : clk_block
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin : timeout_block
    #100000;
    $display("tb_dc_soc_top: TIMEOUT");
    $finish(1);
  end

  task automatic fetch_inst(
    input logic [31:0] expected_pc,
    input logic [31:0] inst
  );
    begin
      @(negedge clk);
      if (!imem_req_valid || imem_req_addr !== expected_pc) begin
        $display("tb_dc_soc_top: FAIL - imem req mismatch: valid=%b addr=%h expected=%h",
                 imem_req_valid, imem_req_addr, expected_pc);
        $finish(1);
      end
      imem_req_ready = 1'b1;
      imem_rsp_valid = 1'b1;
      imem_rsp_rdata = inst;
      imem_rsp_error = 1'b0;
      @(posedge clk);
      #1;
      imem_req_ready = 1'b0;
      imem_rsp_valid = 1'b0;
    end
  endtask

  task automatic dram_respond(
    input logic [31:0] rdata
  );
    begin
      @(negedge clk);
      if (!dram_req_valid) begin
        $display("tb_dc_soc_top: FAIL - expected dram_req_valid");
        $finish(1);
      end
      dram_req_ready = 1'b1;
      @(posedge clk);
      #1;
      dram_req_ready = 1'b0;
      @(negedge clk);
      dram_rsp_valid = 1'b1;
      dram_rsp_rdata = rdata;
      dram_rsp_error = 1'b0;
      @(posedge clk);
      #1;
      dram_rsp_valid = 1'b0;
    end
  endtask

  initial begin
    rst            = 1;
    imem_req_ready = 0;
    imem_rsp_valid = 0;
    imem_rsp_rdata = 0;
    imem_rsp_error = 0;
    dram_req_ready = 0;
    dram_rsp_valid = 0;
    dram_rsp_rdata = 0;
    dram_rsp_error = 0;
    debug_reg_addr = 0;
    i_uart_rx      = 1'b1;
    i_button       = 8'h00;

    repeat (3) @(posedge clk);
    #1;
    rst = 0;

    // 1. lui x1, 0x10000 (x1 = 0x1000_0000)
    fetch_inst(32'h0000_0000, 32'h100000b7);
    #1;
    if (!trace_valid || trace_pc !== 32'h0) begin
      $display("tb_dc_soc_top: FAIL - lui commit mismatch");
      $finish(1);
    end

    // 2. addi x2, x0, 0x123 (x2 = 0x0000_0123)
    fetch_inst(32'h0000_0004, 32'h12300113);
    #1;
    if (!trace_valid || trace_pc !== 32'h4) begin
      $display("tb_dc_soc_top: FAIL - addi commit mismatch");
      $finish(1);
    end

    // 3. sw x2, 256(x1) -> writes 0x123 to 0x1000_0100 (LED)
    fetch_inst(32'h0000_0008, 32'h1020a023);
    // The core enters DMEM_REQ, and internal interconnect routes to led_controller
    // Wait for store commit (2 cycles)
    @(posedge clk);
    @(posedge clk);
    #1;
    if (o_led !== 16'h0123) begin
      $display("tb_dc_soc_top: FAIL - LED output mismatch: expected 0x0123, got %h", o_led);
      $finish(1);
    end

    // 4. lw x3, 256(x1) -> reads back from LED 0x1000_0100
    fetch_inst(32'h0000_000c, 32'h1000a183);
    @(posedge clk);
    @(posedge clk);
    #1;
    debug_reg_addr = 4'd3;
    #1;
    if (debug_reg_data !== 32'h0000_0123) begin
      $display("tb_dc_soc_top: FAIL - LED readback mismatch: expected 0x123, got %h", debug_reg_data);
      $finish(1);
    end

    // 5. lui x4, 0x20000 (x4 = 0x2000_0000, DRAM base)
    fetch_inst(32'h0000_0010, 32'h20000237);

    // 6. sw x3, 0(x4) -> writes x3 to DRAM 0x2000_0000
    fetch_inst(32'h0000_0014, 32'h00322023);
    dram_respond(32'd0);

    // 7. lw x5, 0(x4) -> reads DRAM 0x2000_0000
    fetch_inst(32'h0000_0018, 32'h00022283);
    dram_respond(32'h0000_0123);
    #1;
    debug_reg_addr = 4'd5;
    #1;
    if (debug_reg_data !== 32'h0000_0123) begin
      $display("tb_dc_soc_top: FAIL - DRAM readback mismatch: expected 0x123, got %h", debug_reg_data);
      $finish(1);
    end

    // 8. lw x6, 8(x1) -> reads UART_STATUS 0x1000_0008 (expect tx_ready=1, rx_ready=0 -> 2)
    fetch_inst(32'h0000_001c, 32'h0080a303);
    @(posedge clk);
    @(posedge clk);
    #1;
    debug_reg_addr = 4'd6;
    #1;
    if (debug_reg_data !== 32'h0000_0002) begin
      $display("tb_dc_soc_top: FAIL - UART status mismatch: expected 0x2, got %h", debug_reg_data);
      $finish(1);
    end

    // 9. sw x2, 0(x1) -> writes x2 to UART_TX 0x1000_0000
    fetch_inst(32'h0000_0020, 32'h0020a023);
    @(posedge clk);
    @(posedge clk);
    #1;

    $display("tb_dc_soc_top: PASS");
    $finish(0);
  end

endmodule

`default_nettype wire
