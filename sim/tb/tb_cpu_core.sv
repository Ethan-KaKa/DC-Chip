`timescale 1ns/1ps
`default_nettype none

module tb_cpu_core;
  logic        clk;
  logic        rst;
  logic [7:0]  imem_addr;
  logic [15:0] imem_rdata;
  logic        trace_valid;
  logic [7:0]  trace_pc;
  logic [15:0] trace_inst;
  logic [63:0] debug_regs;
  logic        illegal_inst;

  logic [15:0] rom [0:255];

  assign imem_rdata = rom[imem_addr];

  cpu_core dut (
    .clk          (clk),
    .rst          (rst),
    .imem_addr    (imem_addr),
    .imem_rdata   (imem_rdata),
    .trace_valid  (trace_valid),
    .trace_pc     (trace_pc),
    .trace_inst   (trace_inst),
    .debug_regs   (debug_regs),
    .illegal_inst (illegal_inst)
  );

  initial begin : clock_block
    forever #5 clk = ~clk;
  end

  task automatic fill_illegal;
    integer address;
    begin
      for (address = 0; address < 256; address = address + 1) begin
        rom[address] = 16'h8000;
      end
    end
  endtask

  task automatic check_reset_state;
    begin
      if ((imem_addr !== 8'h00) ||
          (debug_regs !== 64'h0000_0000_0000_0000) ||
          (trace_valid !== 1'b0) ||
          (trace_pc !== 8'h00) ||
          (trace_inst !== 16'h0000) ||
          (illegal_inst !== 1'b0)) begin
        $fatal(1,
               {"tb_cpu_core: reset state mismatch pc=%h regs=%h ",
                "trace=%b/%h/%h illegal=%b"},
               imem_addr, debug_regs, trace_valid, trace_pc,
               trace_inst, illegal_inst);
      end
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst = 1'b1;
      repeat (2) begin
        @(posedge clk);
        #1;
        check_reset_state();
      end
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task automatic check_commit(
    input logic [7:0]  expected_pc,
    input logic [15:0] expected_inst,
    input logic [63:0] expected_regs,
    input logic [7:0]  expected_next_pc
  );
    begin
      @(posedge clk);
      #1;
      if ((trace_valid !== 1'b1) ||
          (trace_pc !== expected_pc) ||
          (trace_inst !== expected_inst) ||
          (debug_regs !== expected_regs) ||
          (imem_addr !== expected_next_pc) ||
          (illegal_inst !== 1'b0)) begin
        $fatal(1,
               {"tb_cpu_core: commit mismatch expected trace=%h/%h ",
                "regs=%h next_pc=%h; actual trace=%b/%h/%h ",
                "regs=%h next_pc=%h illegal=%b"},
               expected_pc, expected_inst, expected_regs,
               expected_next_pc, trace_valid, trace_pc, trace_inst,
               debug_regs, imem_addr, illegal_inst);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    fill_illegal();

    rom[8'h00] = 16'h0402;
    rom[8'h01] = 16'h1900;
    rom[8'h02] = 16'h2408;
    rom[8'h03] = 16'h3600;
    rom[8'h04] = 16'h4600;
    rom[8'h05] = 16'h5600;
    rom[8'h06] = 16'h6600;
    rom[8'h07] = 16'h7008;

    repeat (2) begin
      @(posedge clk);
      #1;
      check_reset_state();
    end
    @(negedge clk);
    rst = 1'b0;

    check_commit(8'h00, 16'h0402, 64'h0000_0000_0002_0000, 8'h01);
    check_commit(8'h01, 16'h1900, 64'h0000_0002_0002_0000, 8'h02);
    check_commit(8'h02, 16'h2408, 64'h0000_0002_000a_0000, 8'h03);
    check_commit(8'h03, 16'h3600, 64'h0000_0002_000c_0000, 8'h04);
    check_commit(8'h04, 16'h4600, 64'h0000_0002_000a_0000, 8'h05);
    check_commit(8'h05, 16'h5600, 64'h0000_0002_0002_0000, 8'h06);
    check_commit(8'h06, 16'h6600, 64'h0000_0002_0002_0000, 8'h07);
    check_commit(8'h07, 16'h7008, 64'h0000_0002_0002_0000, 8'h08);

    fill_illegal();
    rom[8'h00] = 16'h0401;
    rom[8'h01] = 16'h2401;
    rom[8'h02] = 16'h7001;
    apply_reset();

    check_commit(8'h00, 16'h0401, 64'h0000_0000_0001_0000, 8'h01);
    check_commit(8'h01, 16'h2401, 64'h0000_0000_0002_0000, 8'h02);
    check_commit(8'h02, 16'h7001, 64'h0000_0000_0002_0000, 8'h01);
    check_commit(8'h01, 16'h2401, 64'h0000_0000_0003_0000, 8'h02);
    check_commit(8'h02, 16'h7001, 64'h0000_0000_0003_0000, 8'h01);

    fill_illegal();
    rom[8'h00] = 16'h70ff;
    rom[8'hff] = 16'h0ca5;
    apply_reset();

    check_commit(8'h00, 16'h70ff, 64'h0000_0000_0000_0000, 8'hff);
    check_commit(8'hff, 16'h0ca5, 64'h00a5_0000_0000_0000, 8'h00);

    fill_illegal();
    rom[8'h00] = 16'h0005;
    apply_reset();

    check_commit(8'h00, 16'h0005, 64'h0000_0000_0000_0005, 8'h01);
    @(posedge clk);
    #1;
    if ((trace_valid !== 1'b0) ||
        (trace_pc !== 8'h00) ||
        (trace_inst !== 16'h0005) ||
        (debug_regs !== 64'h0000_0000_0000_0005) ||
        (imem_addr !== 8'h01) ||
        (illegal_inst !== 1'b1)) begin
      $fatal(1, "tb_cpu_core: illegal instruction did not freeze state");
    end

    rom[8'h01] = 16'h2001;
    repeat (2) begin
      @(posedge clk);
      #1;
      if ((trace_valid !== 1'b0) ||
          (trace_pc !== 8'h00) ||
          (trace_inst !== 16'h0005) ||
          (debug_regs !== 64'h0000_0000_0000_0005) ||
          (imem_addr !== 8'h01) ||
          (illegal_inst !== 1'b1)) begin
        $fatal(1, "tb_cpu_core: sticky illegal state did not remain frozen");
      end
    end

    apply_reset();
    check_commit(8'h00, 16'h0005, 64'h0000_0000_0000_0005, 8'h01);
    check_commit(8'h01, 16'h2001, 64'h0000_0000_0000_0006, 8'h02);

    $display("tb_cpu_core: PASS");
    disable clock_block;
    disable timeout_block;
  end

  initial begin : timeout_block
    #10000;
    $fatal(1, "tb_cpu_core: timeout");
  end
endmodule

`default_nettype wire
