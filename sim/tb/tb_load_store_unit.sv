`timescale 1ns/1ps
`default_nettype none

module tb_load_store_unit;
  logic clk, rst, issue_valid, issue_ready, issue_misaligned;
  dc_isa_pkg::lsu_issue_t issue;
  dc_isa_pkg::fault_cause_e issue_fault_cause;
  dc_isa_pkg::lsu_completion_t completion;
  logic req_valid, req_ready, req_write;
  logic [31:0] req_addr, req_wdata, rsp_rdata;
  logic [1:0] req_size;
  logic [3:0] req_wstrb;
  logic rsp_valid, rsp_ready, rsp_error, rsp_skip_ref;

  load_store_unit dut (
    .clk_i(clk), .rst_i(rst), .issue_valid_i(issue_valid),
    .issue_ready_o(issue_ready), .issue_i(issue),
    .issue_misaligned_o(issue_misaligned),
    .issue_fault_cause_o(issue_fault_cause), .completion_o(completion),
    .dmem_req_valid_o(req_valid), .dmem_req_ready_i(req_ready),
    .dmem_req_addr_o(req_addr), .dmem_req_write_o(req_write),
    .dmem_req_size_o(req_size), .dmem_req_wdata_o(req_wdata),
    .dmem_req_wstrb_o(req_wstrb), .dmem_rsp_valid_i(rsp_valid),
    .dmem_rsp_ready_o(rsp_ready), .dmem_rsp_rdata_i(rsp_rdata),
    .dmem_rsp_error_i(rsp_error), .dmem_rsp_skip_ref_i(rsp_skip_ref)
  );

  always #5 clk = ~clk;

  task automatic reset_dut;
    begin
      @(negedge clk);
      rst = 1'b1;
      issue_valid = 1'b0;
      req_ready = 1'b0;
      rsp_valid = 1'b0;
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
      #1;
      if (!issue_ready || req_valid || rsp_ready) $fatal(1, "tb_lsu: reset");
    end
  endtask

  task automatic set_issue(
    input dc_isa_pkg::mem_op_e op,
    input logic [31:0] addr,
    input logic [31:0] store_data
  );
    begin
      issue = '0;
      issue.pc = 32'h80;
      issue.inst = 32'h1234_5678;
      issue.rd = 4'd9;
      issue.addr = addr;
      issue.store_data = store_data;
      issue.mem_op = op;
    end
  endtask

  task automatic accept_issue;
    begin
      #1;
      if (!issue_ready || issue_misaligned) $fatal(1, "tb_lsu: issue rejected");
      issue_valid = 1'b1;
      @(posedge clk);
      #1 issue_valid = 1'b0;
    end
  endtask

  task automatic check_request(
    input logic [31:0] addr,
    input logic write,
    input logic [1:0] size,
    input logic [31:0] wdata,
    input logic [3:0] wstrb
  );
    begin
      #1;
      if (!req_valid || req_addr !== addr || req_write !== write ||
          req_size !== size || req_wdata !== wdata || req_wstrb !== wstrb)
        $fatal(1, "tb_lsu: request payload");
    end
  endtask

  task automatic complete_same_cycle(
    input logic [31:0] data,
    input logic error,
    input logic skip_ref
  );
    begin
      req_ready = 1'b1;
      rsp_valid = 1'b1;
      rsp_rdata = data;
      rsp_error = error;
      rsp_skip_ref = skip_ref;
      #1;
      if (!rsp_ready || !completion.valid) $fatal(1, "tb_lsu: completion absent");
      @(posedge clk);
      #1;
      req_ready = 1'b0;
      rsp_valid = 1'b0;
      rsp_error = 1'b0;
      rsp_skip_ref = 1'b0;
    end
  endtask

  integer lane;
  initial begin
    clk = 1'b0;
    rst = 1'b1;
    issue_valid = 1'b0;
    issue = '0;
    req_ready = 1'b0;
    rsp_valid = 1'b0;
    rsp_rdata = '0;
    rsp_error = 1'b0;
    rsp_skip_ref = 1'b0;
    reset_dut();

    // Misaligned accesses are rejected before a request is created.
    set_issue(dc_isa_pkg::MEM_LW, 32'd2, 0); #1;
    if (!issue_misaligned || issue_fault_cause != dc_isa_pkg::FAULT_LOAD_MISALIGNED)
      $fatal(1, "tb_lsu: load alignment");
    issue_valid = 1'b1; @(posedge clk); #1; issue_valid = 1'b0;
    if (req_valid) $fatal(1, "tb_lsu: misaligned request escaped");
    set_issue(dc_isa_pkg::MEM_SH, 32'd1, 0); #1;
    if (!issue_misaligned || issue_fault_cause != dc_isa_pkg::FAULT_STORE_MISALIGNED)
      $fatal(1, "tb_lsu: store alignment");

    // Store lanes and request payload stability under backpressure.
    for (lane = 0; lane < 4; lane = lane + 1) begin
      set_issue(dc_isa_pkg::MEM_SB, 32'h100 + lane, 32'h89ab_cdef);
      accept_issue();
      check_request(32'h100 + lane, 1'b1, 2'b00,
                    32'h0000_00ef << (lane * 8), 4'b0001 << lane);
      repeat (2) begin
        @(posedge clk);
        check_request(32'h100 + lane, 1'b1, 2'b00,
                      32'h0000_00ef << (lane * 8), 4'b0001 << lane);
      end
      complete_same_cycle(0, 1'b0, 1'b0);
    end
    set_issue(dc_isa_pkg::MEM_SH, 32'h102, 32'h1234_abcd); accept_issue();
    check_request(32'h102, 1'b1, 2'b01, 32'habcd_0000, 4'b1100);
    complete_same_cycle(0, 1'b0, 1'b0);
    set_issue(dc_isa_pkg::MEM_SW, 32'h104, 32'h1234_abcd); accept_issue();
    check_request(32'h104, 1'b1, 2'b10, 32'h1234_abcd, 4'b1111);
    complete_same_cycle(0, 1'b0, 1'b0);

    // Byte and halfword extension from every legal lane.
    for (lane = 0; lane < 4; lane = lane + 1) begin
      set_issue(dc_isa_pkg::MEM_LBU, 32'h200 + lane, 0); accept_issue();
      check_request(32'h200 + lane, 1'b0, 2'b00, 0, 0);
      req_ready = 1'b1; rsp_valid = 1'b1; rsp_rdata = 32'h80ff_7f01; #1;
      case (lane)
        0: if (completion.writeback_data !== 32'h01) $fatal(1, "tb_lsu: lbu0");
        1: if (completion.writeback_data !== 32'h7f) $fatal(1, "tb_lsu: lbu1");
        2: if (completion.writeback_data !== 32'hff) $fatal(1, "tb_lsu: lbu2");
        3: if (completion.writeback_data !== 32'h80) $fatal(1, "tb_lsu: lbu3");
      endcase
      @(posedge clk); #1; req_ready = 0; rsp_valid = 0;
    end
    set_issue(dc_isa_pkg::MEM_LB, 32'h202, 0); accept_issue();
    req_ready = 1; rsp_valid = 1; rsp_rdata = 32'h00ff_0000; #1;
    if (completion.writeback_data !== 32'hffff_ffff) $fatal(1, "tb_lsu: lb sign");
    @(posedge clk); #1; req_ready = 0; rsp_valid = 0;
    set_issue(dc_isa_pkg::MEM_LH, 32'h202, 0); accept_issue();
    req_ready = 1; rsp_valid = 1; rsp_rdata = 32'h8001_0000; #1;
    if (completion.writeback_data !== 32'hffff_8001) $fatal(1, "tb_lsu: lh sign");
    @(posedge clk); #1; req_ready = 0; rsp_valid = 0;
    set_issue(dc_isa_pkg::MEM_LHU, 32'h200, 0); accept_issue();
    req_ready = 1; rsp_valid = 1; rsp_rdata = 32'h0000_8001; #1;
    if (completion.writeback_data !== 32'h0000_8001) $fatal(1, "tb_lsu: lhu");
    @(posedge clk); #1; req_ready = 0; rsp_valid = 0;

    // Delayed response, fault classification, and skip_ref propagation.
    set_issue(dc_isa_pkg::MEM_LW, 32'h300, 0); accept_issue();
    req_ready = 1; @(posedge clk); #1; req_ready = 0;
    if (!rsp_ready || req_valid) $fatal(1, "tb_lsu: wait state");
    rsp_valid = 1; rsp_rdata = 32'hdead_beef; rsp_skip_ref = 1; #1;
    if (!completion.valid || completion.error || !completion.skip_ref ||
        completion.writeback_data != 32'hdead_beef || completion.rd != 9)
      $fatal(1, "tb_lsu: delayed completion");
    @(posedge clk); #1; rsp_valid = 0; rsp_skip_ref = 0;

    set_issue(dc_isa_pkg::MEM_LW, 32'h300, 0); accept_issue();
    req_ready = 1; rsp_valid = 1; rsp_error = 1; #1;
    if (!completion.error || completion.fault_cause != dc_isa_pkg::FAULT_LOAD_ACCESS)
      $fatal(1, "tb_lsu: load fault");
    @(posedge clk); #1; req_ready = 0; rsp_valid = 0; rsp_error = 0;
    set_issue(dc_isa_pkg::MEM_SW, 32'h300, 0); accept_issue();
    req_ready = 1; rsp_valid = 1; rsp_error = 1; #1;
    if (!completion.error || completion.fault_cause != dc_isa_pkg::FAULT_STORE_ACCESS)
      $fatal(1, "tb_lsu: store fault");
    @(posedge clk); #1; req_ready = 0; rsp_valid = 0; rsp_error = 0;

    // Reset abandons an accepted transaction and rejects a late response.
    set_issue(dc_isa_pkg::MEM_LW, 32'h400, 0); accept_issue();
    req_ready = 1; @(posedge clk); #1; req_ready = 0;
    @(negedge clk); rst = 1; rsp_valid = 1; #1;
    if (rsp_ready || completion.valid) $fatal(1, "tb_lsu: reset accepted response");
    @(posedge clk); @(negedge clk); rst = 0; #1;
    if (rsp_ready || !issue_ready) $fatal(1, "tb_lsu: stale response after reset");
    rsp_valid = 0;

    $display("tb_load_store_unit: PASS");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_load_store_unit: timeout");
  end
endmodule

`default_nettype wire
