`timescale 1ns/1ps
`default_nettype none

module tb_cpu_core;
  logic        clk;
  logic        rst;

  logic        imem_req_valid;
  logic        imem_req_ready;
  logic [31:0] imem_req_addr;
  logic        imem_rsp_valid;
  logic        imem_rsp_ready;
  logic [31:0] imem_rsp_rdata;
  logic        imem_rsp_error;

  logic        dmem_req_valid;
  logic        dmem_req_ready;
  logic [31:0] dmem_req_addr;
  logic        dmem_req_write;
  logic [1:0]  dmem_req_size;
  logic [31:0] dmem_req_wdata;
  logic [3:0]  dmem_req_wstrb;
  logic        dmem_rsp_valid;
  logic        dmem_rsp_ready;
  logic [31:0] dmem_rsp_rdata;
  logic        dmem_rsp_error;

  logic        trace_valid;
  logic [31:0] trace_pc;
  logic [31:0] trace_inst;
  logic [3:0]  debug_reg_addr;
  logic [31:0] debug_reg_data;
  logic        fault_valid;
  dc_isa_pkg::fault_cause_e fault_cause;
  logic [31:0] fault_pc;
  logic        fault_inst_valid;
  logic [31:0] fault_inst;

  cpu_core dut (
    .clk              (clk),
    .rst              (rst),
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_rdata   (imem_rsp_rdata),
    .imem_rsp_error   (imem_rsp_error),
    .dmem_req_valid   (dmem_req_valid),
    .dmem_req_ready   (dmem_req_ready),
    .dmem_req_addr    (dmem_req_addr),
    .dmem_req_write   (dmem_req_write),
    .dmem_req_size    (dmem_req_size),
    .dmem_req_wdata   (dmem_req_wdata),
    .dmem_req_wstrb   (dmem_req_wstrb),
    .dmem_rsp_valid   (dmem_rsp_valid),
    .dmem_rsp_ready   (dmem_rsp_ready),
    .dmem_rsp_rdata   (dmem_rsp_rdata),
    .dmem_rsp_error   (dmem_rsp_error),
    .trace_valid      (trace_valid),
    .trace_pc         (trace_pc),
    .trace_inst       (trace_inst),
    .debug_reg_addr   (debug_reg_addr),
    .debug_reg_data   (debug_reg_data),
    .fault_valid      (fault_valid),
    .fault_cause      (fault_cause),
    .fault_pc         (fault_pc),
    .fault_inst_valid (fault_inst_valid),
    .fault_inst       (fault_inst)
  );

  initial begin : clock_block
    forever #5 clk = ~clk;
  end

  function automatic logic [31:0] enc_add(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
  );
    enc_add = {7'b0000000, rs2, rs1, 3'b000, rd,
               dc_isa_pkg::OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_addi(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input integer     imm
  );
    enc_addi = {imm[11:0], rs1, 3'b000, rd,
                dc_isa_pkg::OPCODE_OP_IMM};
  endfunction

  function automatic logic [31:0] enc_lui(
    input logic [4:0]  rd,
    input logic [19:0] imm
  );
    enc_lui = {imm, rd, dc_isa_pkg::OPCODE_LUI};
  endfunction

  function automatic logic [31:0] enc_lw(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input integer     imm
  );
    enc_lw = {imm[11:0], rs1, 3'b010, rd,
              dc_isa_pkg::OPCODE_LOAD};
  endfunction

  function automatic logic [31:0] enc_lbu(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input integer     imm
  );
    enc_lbu = {imm[11:0], rs1, 3'b100, rd,
               dc_isa_pkg::OPCODE_LOAD};
  endfunction

  function automatic logic [31:0] enc_sw(
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input integer     imm
  );
    logic [11:0] imm_bits;
    begin
      imm_bits = imm[11:0];
      enc_sw = {imm_bits[11:5], rs2, rs1, 3'b010,
                imm_bits[4:0], dc_isa_pkg::OPCODE_STORE};
    end
  endfunction

  function automatic logic [31:0] enc_sb(
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input integer     imm
  );
    logic [11:0] imm_bits;
    begin
      imm_bits = imm[11:0];
      enc_sb = {imm_bits[11:5], rs2, rs1, 3'b000,
                imm_bits[4:0], dc_isa_pkg::OPCODE_STORE};
    end
  endfunction

  function automatic logic [31:0] enc_jalr(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input integer     imm
  );
    enc_jalr = {imm[11:0], rs1, 3'b000, rd,
                dc_isa_pkg::OPCODE_JALR};
  endfunction

  function automatic logic [31:0] enc_auipc(
    input logic [4:0]  rd,
    input logic [19:0] imm
  );
    enc_auipc = {imm, rd, dc_isa_pkg::OPCODE_AUIPC};
  endfunction

  function automatic logic [31:0] enc_jal(
    input logic [4:0] rd,
    input integer     imm
  );
    logic [20:0] imm_bits;
    begin
      imm_bits = imm[20:0];
      enc_jal = {imm_bits[20], imm_bits[10:1], imm_bits[11], imm_bits[19:12],
                 rd, dc_isa_pkg::OPCODE_JAL};
    end
  endfunction

  function automatic logic [31:0] enc_beq(
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input integer     imm
  );
    logic [12:0] imm_bits;
    begin
      imm_bits = imm[12:0];
      enc_beq = {imm_bits[12], imm_bits[10:5], rs2, rs1, 3'b000,
                 imm_bits[4:1], imm_bits[11], dc_isa_pkg::OPCODE_BRANCH};
    end
  endfunction

  function automatic logic [31:0] enc_bne(
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input integer     imm
  );
    logic [12:0] imm_bits;
    begin
      imm_bits = imm[12:0];
      enc_bne = {imm_bits[12], imm_bits[10:5], rs2, rs1, 3'b001,
                 imm_bits[4:1], imm_bits[11], dc_isa_pkg::OPCODE_BRANCH};
    end
  endfunction

  function automatic logic [31:0] enc_sub(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
  );
    enc_sub = {7'b0100000, rs2, rs1, 3'b000, rd,
               dc_isa_pkg::OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_sh(
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input integer     imm
  );
    logic [11:0] imm_bits;
    begin
      imm_bits = imm[11:0];
      enc_sh = {imm_bits[11:5], rs2, rs1, 3'b001,
                imm_bits[4:0], dc_isa_pkg::OPCODE_STORE};
    end
  endfunction

  function automatic logic [31:0] enc_lh(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input integer     imm
  );
    enc_lh = {imm[11:0], rs1, 3'b001, rd,
              dc_isa_pkg::OPCODE_LOAD};
  endfunction

  task automatic clear_bus_inputs;
    begin
      imem_req_ready = 1'b0;
      imem_rsp_valid = 1'b0;
      imem_rsp_rdata = 32'd0;
      imem_rsp_error = 1'b0;
      dmem_req_ready = 1'b0;
      dmem_rsp_valid = 1'b0;
      dmem_rsp_rdata = 32'd0;
      dmem_rsp_error = 1'b0;
    end
  endtask

  task automatic check_reset_state;
    begin
      debug_reg_addr = 4'd0;
      #1;
      if ((imem_req_valid !== 1'b0) ||
          (imem_rsp_ready !== 1'b0) ||
          (dmem_req_valid !== 1'b0) ||
          (dmem_rsp_ready !== 1'b0) ||
          (trace_valid !== 1'b0) ||
          (debug_reg_data !== 32'd0) ||
          (fault_valid !== 1'b0) ||
          (fault_cause !== dc_isa_pkg::FAULT_NONE) ||
          (fault_pc !== 32'd0) ||
          (fault_inst_valid !== 1'b0) ||
          (fault_inst !== 32'd0)) begin
        $fatal(1, "tb_cpu_core: reset state mismatch");
      end
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      clear_bus_inputs();
      rst = 1'b1;
      repeat (2) begin
        @(posedge clk);
        #1;
        check_reset_state();
      end
      @(negedge clk);
      rst = 1'b0;
      #1;
      if ((imem_req_valid !== 1'b1) ||
          (imem_req_addr !== 32'h0000_0000) ||
          (imem_rsp_ready !== 1'b0)) begin
        $fatal(1, "tb_cpu_core: fetch request missing after reset");
      end
    end
  endtask

  task automatic check_reg(
    input logic [3:0]  addr,
    input logic [31:0] expected
  );
    begin
      debug_reg_addr = addr;
      #1;
      if (debug_reg_data !== expected) begin
        $fatal(1, "tb_cpu_core: x%0d expected=%h actual=%h",
               addr, expected, debug_reg_data);
      end
    end
  endtask

  task automatic check_fetch_request(input logic [31:0] expected_pc);
    begin
      #1;
      if ((imem_req_valid !== 1'b1) ||
          (imem_req_addr !== expected_pc) ||
          (imem_rsp_ready !== imem_req_ready) ||
          (dmem_req_valid !== 1'b0) || (fault_valid !== 1'b0)) begin
        $fatal(1, "tb_cpu_core: fetch request mismatch at pc=%h",
               expected_pc);
      end
    end
  endtask

  task automatic fetch_same_cycle(
    input logic [31:0] expected_pc,
    input logic [31:0] inst,
    input logic        error
  );
    begin
      @(negedge clk);
      check_fetch_request(expected_pc);
      imem_req_ready = 1'b1;
      imem_rsp_valid = 1'b1;
      imem_rsp_rdata = inst;
      imem_rsp_error = error;
      #1;
      if (imem_rsp_ready !== 1'b1) begin
        $fatal(1, "tb_cpu_core: same-cycle fetch response not accepted");
      end
      @(posedge clk);
      #1;
      imem_req_ready = 1'b0;
      imem_rsp_valid = 1'b0;
      imem_rsp_error = 1'b0;
    end
  endtask

  task automatic fetch_delayed(
    input logic [31:0] expected_pc,
    input logic [31:0] inst,
    input logic        error
  );
    integer stall_count;
    begin
      @(negedge clk);
      imem_req_ready = 1'b0;
      for (stall_count = 0; stall_count < 2;
           stall_count = stall_count + 1) begin
        check_fetch_request(expected_pc);
        @(posedge clk);
        #1;
        if (trace_valid !== 1'b0) begin
          $fatal(1, "tb_cpu_core: committed during fetch request stall");
        end
        @(negedge clk);
      end

      imem_req_ready = 1'b1;
      check_fetch_request(expected_pc);
      @(posedge clk);
      #1;
      imem_req_ready = 1'b0;
      if ((imem_req_valid !== 1'b0) || (imem_rsp_ready !== 1'b1) ||
          (trace_valid !== 1'b0)) begin
        $fatal(1, "tb_cpu_core: fetch wait state mismatch");
      end

      repeat (2) begin
        @(posedge clk);
        #1;
        if ((imem_rsp_ready !== 1'b1) || (trace_valid !== 1'b0)) begin
          $fatal(1, "tb_cpu_core: fetch response wait was not stable");
        end
      end

      @(negedge clk);
      imem_rsp_valid = 1'b1;
      imem_rsp_rdata = inst;
      imem_rsp_error = error;
      @(posedge clk);
      #1;
      imem_rsp_valid = 1'b0;
      imem_rsp_error = 1'b0;
    end
  endtask

  task automatic check_commit(
    input logic [31:0] expected_pc,
    input logic [31:0] expected_inst,
    input logic [31:0] expected_next_pc
  );
    begin
      if ((trace_valid !== 1'b1) || (trace_pc !== expected_pc) ||
          (trace_inst !== expected_inst) || (fault_valid !== 1'b0) ||
          (imem_req_valid !== 1'b1) ||
          (imem_req_addr !== expected_next_pc)) begin
        $fatal(1,
               {"tb_cpu_core: commit mismatch expected=%h/%h next=%h ",
                "actual=%b/%h/%h next=%h fault=%b"},
               expected_pc, expected_inst, expected_next_pc,
               trace_valid, trace_pc, trace_inst, imem_req_addr,
               fault_valid);
      end
    end
  endtask

  task automatic check_dmem_request(
    input logic [31:0] expected_addr,
    input logic        expected_write,
    input logic [1:0]  expected_size,
    input logic [31:0] expected_wdata,
    input logic [3:0]  expected_wstrb
  );
    begin
      #1;
      if ((dmem_req_valid !== 1'b1) ||
          (dmem_req_addr !== expected_addr) ||
          (dmem_req_write !== expected_write) ||
          (dmem_req_size !== expected_size) ||
          (dmem_req_wdata !== expected_wdata) ||
          (dmem_req_wstrb !== expected_wstrb) ||
          (dmem_rsp_ready !== dmem_req_ready) ||
          (imem_req_valid !== 1'b0) || (trace_valid !== 1'b0)) begin
        $fatal(1,
               {"tb_cpu_core: dmem request mismatch addr=%h write=%b ",
                "size=%b wdata=%h wstrb=%b"},
               dmem_req_addr, dmem_req_write, dmem_req_size,
               dmem_req_wdata, dmem_req_wstrb);
      end
    end
  endtask

  task automatic dmem_delayed(
    input logic [31:0] expected_addr,
    input logic        expected_write,
    input logic [1:0]  expected_size,
    input logic [31:0] expected_wdata,
    input logic [3:0]  expected_wstrb,
    input logic [31:0] response_data,
    input logic        response_error
  );
    integer stall_count;
    begin
      dmem_req_ready = 1'b0;
      for (stall_count = 0; stall_count < 2;
           stall_count = stall_count + 1) begin
        check_dmem_request(expected_addr, expected_write, expected_size,
                           expected_wdata, expected_wstrb);
        @(posedge clk);
        #1;
        @(negedge clk);
      end

      dmem_req_ready = 1'b1;
      check_dmem_request(expected_addr, expected_write, expected_size,
                         expected_wdata, expected_wstrb);
      @(posedge clk);
      #1;
      dmem_req_ready = 1'b0;
      if ((dmem_req_valid !== 1'b0) || (dmem_rsp_ready !== 1'b1) ||
          (trace_valid !== 1'b0)) begin
        $fatal(1, "tb_cpu_core: dmem wait state mismatch");
      end

      repeat (2) begin
        @(posedge clk);
        #1;
        if ((dmem_rsp_ready !== 1'b1) || (trace_valid !== 1'b0)) begin
          $fatal(1, "tb_cpu_core: dmem response wait was not stable");
        end
      end

      @(negedge clk);
      dmem_rsp_valid = 1'b1;
      dmem_rsp_rdata = response_data;
      dmem_rsp_error = response_error;
      @(posedge clk);
      #1;
      dmem_rsp_valid = 1'b0;
      dmem_rsp_error = 1'b0;
    end
  endtask

  task automatic dmem_same_cycle(
    input logic [31:0] expected_addr,
    input logic        expected_write,
    input logic [1:0]  expected_size,
    input logic [31:0] expected_wdata,
    input logic [3:0]  expected_wstrb,
    input logic [31:0] response_data,
    input logic        response_error
  );
    begin
      @(negedge clk);
      check_dmem_request(expected_addr, expected_write, expected_size,
                         expected_wdata, expected_wstrb);
      dmem_req_ready = 1'b1;
      dmem_rsp_valid = 1'b1;
      dmem_rsp_rdata = response_data;
      dmem_rsp_error = response_error;
      #1;
      if (dmem_rsp_ready !== 1'b1) begin
        $fatal(1, "tb_cpu_core: same-cycle dmem response not accepted");
      end
      @(posedge clk);
      #1;
      dmem_req_ready = 1'b0;
      dmem_rsp_valid = 1'b0;
      dmem_rsp_error = 1'b0;
    end
  endtask

  task automatic check_fault(
    input dc_isa_pkg::fault_cause_e expected_cause,
    input logic [31:0] expected_pc,
    input logic        expected_inst_valid,
    input logic [31:0] expected_inst
  );
    integer hold_count;
    begin
      if ((fault_valid !== 1'b1) || (fault_cause !== expected_cause) ||
          (fault_pc !== expected_pc) ||
          (fault_inst_valid !== expected_inst_valid) ||
          (fault_inst !== expected_inst) || (trace_valid !== 1'b0) ||
          (imem_req_valid !== 1'b0) || (imem_rsp_ready !== 1'b0) ||
          (dmem_req_valid !== 1'b0) || (dmem_rsp_ready !== 1'b0)) begin
        $fatal(1,
               {"tb_cpu_core: fault mismatch expected cause=%0d pc=%h ",
                "inst_valid=%b inst=%h; actual=%b/%0d/%h/%b/%h"},
               expected_cause, expected_pc, expected_inst_valid,
               expected_inst, fault_valid, fault_cause, fault_pc,
               fault_inst_valid, fault_inst);
      end

      imem_req_ready = 1'b1;
      imem_rsp_valid = 1'b1;
      dmem_req_ready = 1'b1;
      dmem_rsp_valid = 1'b1;
      for (hold_count = 0; hold_count < 2; hold_count = hold_count + 1) begin
        @(posedge clk);
        #1;
        if ((fault_valid !== 1'b1) ||
            (fault_cause !== expected_cause) ||
            (fault_pc !== expected_pc) ||
            (fault_inst_valid !== expected_inst_valid) ||
            (fault_inst !== expected_inst) || (trace_valid !== 1'b0) ||
            (imem_req_valid !== 1'b0) || (imem_rsp_ready !== 1'b0) ||
            (dmem_req_valid !== 1'b0) || (dmem_rsp_ready !== 1'b0)) begin
          $fatal(1, "tb_cpu_core: fault state was not sticky");
        end
      end
      clear_bus_inputs();
    end
  endtask

  logic [31:0] inst;
  integer lane;

  initial begin
    clk            = 1'b0;
    rst            = 1'b1;
    debug_reg_addr = 4'd0;
    clear_bus_inputs();

    repeat (2) begin
      @(posedge clk);
      #1;
      check_reset_state();
    end
    @(negedge clk);
    rst = 1'b0;

    inst = enc_addi(5'd1, 5'd0, 256);
    fetch_delayed(32'h0000_0000, inst, 1'b0);
    check_commit(32'h0000_0000, inst, 32'h0000_0004);
    check_reg(4'd1, 32'h0000_0100);

    inst = enc_lui(5'd2, 20'h12345);
    fetch_same_cycle(32'h0000_0004, inst, 1'b0);
    check_commit(32'h0000_0004, inst, 32'h0000_0008);
    check_reg(4'd2, 32'h1234_5000);

    inst = enc_add(5'd3, 5'd1, 5'd2);
    fetch_same_cycle(32'h0000_0008, inst, 1'b0);
    check_commit(32'h0000_0008, inst, 32'h0000_000c);
    check_reg(4'd3, 32'h1234_5100);

    inst = enc_addi(5'd15, 5'd0, -1);
    fetch_same_cycle(32'h0000_000c, inst, 1'b0);
    check_commit(32'h0000_000c, inst, 32'h0000_0010);
    check_reg(4'd15, 32'hffff_ffff);

    inst = enc_sw(5'd3, 5'd1, 0);
    fetch_same_cycle(32'h0000_0010, inst, 1'b0);
    if (trace_valid !== 1'b0) begin
      $fatal(1, "tb_cpu_core: store committed before data response");
    end
    dmem_delayed(32'h0000_0100, 1'b1, 2'b10, 32'h1234_5100,
                 4'b1111, 32'd0, 1'b0);
    check_commit(32'h0000_0010, inst, 32'h0000_0014);

    inst = enc_lw(5'd4, 5'd1, 0);
    fetch_same_cycle(32'h0000_0014, inst, 1'b0);
    dmem_same_cycle(32'h0000_0100, 1'b0, 2'b10, 32'd0, 4'b0000,
                    32'hdead_beef, 1'b0);
    check_commit(32'h0000_0014, inst, 32'h0000_0018);
    check_reg(4'd4, 32'hdead_beef);

    for (lane = 0; lane < 4; lane = lane + 1) begin
      inst = enc_sb(5'd4, 5'd1, lane);
      fetch_same_cycle(32'h0000_0018 + (lane * 4), inst, 1'b0);
      dmem_same_cycle(32'h0000_0100 + lane, 1'b1, 2'b00,
                      32'h0000_00ef << (lane * 8), 4'b0001 << lane,
                      32'd0, 1'b0);
      check_commit(32'h0000_0018 + (lane * 4), inst,
                   32'h0000_001c + (lane * 4));
    end

    for (lane = 0; lane < 4; lane = lane + 1) begin
      inst = enc_lbu(5'd5 + lane, 5'd1, lane);
      fetch_same_cycle(32'h0000_0028 + (lane * 4), inst, 1'b0);
      dmem_same_cycle(32'h0000_0100 + lane, 1'b0, 2'b00,
                      32'd0, 4'b0000, 32'ha1b2_c3d4, 1'b0);
      check_commit(32'h0000_0028 + (lane * 4), inst,
                   32'h0000_002c + (lane * 4));
    end
    check_reg(4'd5, 32'h0000_00d4);
    check_reg(4'd6, 32'h0000_00c3);
    check_reg(4'd7, 32'h0000_00b2);
    check_reg(4'd8, 32'h0000_00a1);

    inst = enc_lw(5'd0, 5'd1, 0);
    fetch_same_cycle(32'h0000_0038, inst, 1'b0);
    dmem_same_cycle(32'h0000_0100, 1'b0, 2'b10, 32'd0, 4'b0000,
                    32'hffff_ffff, 1'b0);
    check_commit(32'h0000_0038, inst, 32'h0000_003c);
    check_reg(4'd0, 32'd0);

    inst = enc_addi(5'd9, 5'd0, 288);
    fetch_same_cycle(32'h0000_003c, inst, 1'b0);
    check_commit(32'h0000_003c, inst, 32'h0000_0040);
    check_reg(4'd9, 32'h0000_0120);

    inst = enc_jalr(5'd9, 5'd9, 4);
    fetch_same_cycle(32'h0000_0040, inst, 1'b0);
    check_commit(32'h0000_0040, inst, 32'h0000_0124);
    check_reg(4'd9, 32'h0000_0044);

    apply_reset();
    inst = enc_addi(5'd10, 5'd0, -2048);
    fetch_same_cycle(32'h0000_0000, inst, 1'b0);
    check_commit(32'h0000_0000, inst, 32'h0000_0004);
    check_reg(4'd10, 32'hffff_f800);

    inst = enc_addi(5'd11, 5'd0, 2047);
    fetch_same_cycle(32'h0000_0004, inst, 1'b0);
    check_commit(32'h0000_0004, inst, 32'h0000_0008);
    check_reg(4'd11, 32'h0000_07ff);

    inst = enc_lui(5'd12, 20'hfffff);
    fetch_same_cycle(32'h0000_0008, inst, 1'b0);
    check_commit(32'h0000_0008, inst, 32'h0000_000c);
    check_reg(4'd12, 32'hffff_f000);

    inst = enc_add(5'd13, 5'd10, 5'd11);
    fetch_same_cycle(32'h0000_000c, inst, 1'b0);
    check_commit(32'h0000_000c, inst, 32'h0000_0010);
    check_reg(4'd13, 32'hffff_ffff);

    inst = enc_addi(5'd14, 5'd13, 1);
    fetch_same_cycle(32'h0000_0010, inst, 1'b0);
    check_commit(32'h0000_0010, inst, 32'h0000_0014);
    check_reg(4'd14, 32'h0000_0000);

    inst = enc_sb(5'd0, 5'd0, 2047);
    fetch_same_cycle(32'h0000_0014, inst, 1'b0);
    dmem_same_cycle(32'h0000_07ff, 1'b1, 2'b00, 32'd0, 4'b1000,
                    32'd0, 1'b0);
    check_commit(32'h0000_0014, inst, 32'h0000_0018);

    inst = enc_sb(5'd0, 5'd0, -2048);
    fetch_same_cycle(32'h0000_0018, inst, 1'b0);
    dmem_same_cycle(32'hffff_f800, 1'b1, 2'b00, 32'd0, 4'b0001,
                    32'd0, 1'b0);
    check_commit(32'h0000_0018, inst, 32'h0000_001c);

    apply_reset();
    inst = 32'hffff_ffff;
    fetch_same_cycle(32'd0, inst, 1'b0);
    check_fault(dc_isa_pkg::FAULT_ILLEGAL_INSTRUCTION,
                32'd0, 1'b1, inst);

    apply_reset();
    fetch_same_cycle(32'd0, 32'hdead_beef, 1'b1);
    check_fault(dc_isa_pkg::FAULT_INSTRUCTION_ACCESS,
                32'd0, 1'b0, 32'd0);

    apply_reset();
    inst = enc_jalr(5'd1, 5'd0, 2);
    fetch_same_cycle(32'd0, inst, 1'b0);
    check_fault(dc_isa_pkg::FAULT_INSTRUCTION_MISALIGNED,
                32'd0, 1'b1, inst);
    check_reg(4'd1, 32'd0);

    apply_reset();
    inst = enc_lw(5'd1, 5'd0, 2);
    fetch_same_cycle(32'd0, inst, 1'b0);
    check_fault(dc_isa_pkg::FAULT_LOAD_MISALIGNED,
                32'd0, 1'b1, inst);

    apply_reset();
    inst = enc_lw(5'd1, 5'd0, 0);
    fetch_same_cycle(32'd0, inst, 1'b0);
    dmem_same_cycle(32'd0, 1'b0, 2'b10, 32'd0, 4'b0000,
                    32'hfeed_face, 1'b1);
    check_fault(dc_isa_pkg::FAULT_LOAD_ACCESS,
                32'd0, 1'b1, inst);
    check_reg(4'd1, 32'd0);

    apply_reset();
    inst = enc_sw(5'd0, 5'd0, 2);
    fetch_same_cycle(32'd0, inst, 1'b0);
    check_fault(dc_isa_pkg::FAULT_STORE_MISALIGNED,
                32'd0, 1'b1, inst);

    apply_reset();
    inst = enc_sw(5'd0, 5'd0, 0);
    fetch_same_cycle(32'd0, inst, 1'b0);
    dmem_delayed(32'd0, 1'b1, 2'b10, 32'd0, 4'b1111,
                 32'd0, 1'b1);
    check_fault(dc_isa_pkg::FAULT_STORE_ACCESS,
                32'd0, 1'b1, inst);

    apply_reset();
    @(negedge clk);
    imem_req_ready = 1'b0;
    check_fetch_request(32'd0);
    rst = 1'b1;
    #1;
    if ((imem_req_valid !== 1'b0) || (imem_rsp_ready !== 1'b0)) begin
      $fatal(1, "tb_cpu_core: reset did not cancel unaccepted fetch");
    end
    @(posedge clk);
    #1;
    check_reset_state();
    @(negedge clk);
    rst = 1'b0;
    imem_rsp_valid = 1'b1;
    imem_rsp_rdata = enc_addi(5'd1, 5'd0, 7);
    #1;
    if (imem_rsp_ready !== 1'b0) begin
      $fatal(1, "tb_cpu_core: stale fetch response was accepted");
    end
    imem_rsp_valid = 1'b0;

    @(negedge clk);
    imem_req_ready = 1'b1;
    @(posedge clk);
    #1;
    imem_req_ready = 1'b0;
    if ((imem_req_valid !== 1'b0) || (imem_rsp_ready !== 1'b1)) begin
      $fatal(1, "tb_cpu_core: fetch request did not enter wait state");
    end
    @(negedge clk);
    rst = 1'b1;
    imem_rsp_valid = 1'b1;
    imem_rsp_rdata = enc_addi(5'd1, 5'd0, 8);
    #1;
    if (imem_rsp_ready !== 1'b0) begin
      $fatal(1, "tb_cpu_core: reset did not abandon fetch response");
    end
    @(posedge clk);
    #1;
    check_reset_state();
    @(negedge clk);
    rst = 1'b0;
    #1;
    if (imem_rsp_ready !== 1'b0) begin
      $fatal(1, "tb_cpu_core: late fetch response matched a new request");
    end
    imem_rsp_valid = 1'b0;

    inst = enc_lw(5'd1, 5'd0, 0);
    fetch_same_cycle(32'd0, inst, 1'b0);
    @(negedge clk);
    dmem_req_ready = 1'b1;
    @(posedge clk);
    #1;
    dmem_req_ready = 1'b0;
    if (dmem_rsp_ready !== 1'b1) begin
      $fatal(1, "tb_cpu_core: data request did not enter wait state");
    end
    @(negedge clk);
    rst = 1'b1;
    dmem_rsp_valid = 1'b1;
    dmem_rsp_rdata = 32'hffff_ffff;
    #1;
    if (dmem_rsp_ready !== 1'b0) begin
      $fatal(1, "tb_cpu_core: reset did not abandon data response");
    end
    @(posedge clk);
    #1;
    check_reset_state();
    @(negedge clk);
    rst = 1'b0;
    #1;
    if (dmem_rsp_ready !== 1'b0) begin
      $fatal(1, "tb_cpu_core: stale data response was accepted after reset");
    end
    dmem_rsp_valid = 1'b0;
    check_reg(4'd1, 32'd0);

    inst = enc_addi(5'd1, 5'd0, 9);
    fetch_same_cycle(32'd0, inst, 1'b0);
    check_commit(32'd0, inst, 32'd4);
    check_reg(4'd1, 32'd9);

    // Test AUIPC: PC=4, imm=0x1000, rd=x2 -> x2 = 4 + 0x01000000 = 0x01000004
    inst = enc_auipc(5'd2, 20'h01000);
    fetch_same_cycle(32'd4, inst, 1'b0);
    check_commit(32'd4, inst, 32'd8);
    check_reg(4'd2, 32'h01000004);

    // Test JAL: PC=8, target = 8 + 16 = 24, link x3 = 8 + 4 = 12
    inst = enc_jal(5'd3, 16);
    fetch_same_cycle(32'd8, inst, 1'b0);
    check_commit(32'd8, inst, 32'd24);
    check_reg(4'd3, 32'd12);

    // Test BEQ (not taken): PC=24, x1=9, x0=0 -> not equal -> not taken -> PC=28
    inst = enc_beq(5'd1, 5'd0, 16);
    fetch_same_cycle(32'd24, inst, 1'b0);
    check_commit(32'd24, inst, 32'd28);

    // Test BNE (taken): PC=28, x1=9, x0=0 -> not equal -> taken -> PC=28 + 16 = 44
    inst = enc_bne(5'd1, 5'd0, 16);
    fetch_same_cycle(32'd28, inst, 1'b0);
    check_commit(32'd28, inst, 32'd44);

    // Test SUB: PC=44, x4 = x1 - x1 = 0
    inst = enc_sub(5'd4, 5'd1, 5'd1);
    fetch_same_cycle(32'd44, inst, 1'b0);
    check_commit(32'd44, inst, 32'd48);
    check_reg(4'd4, 32'd0);

    $display("tb_cpu_core: PASS");
    disable clock_block;
    disable timeout_block;
  end

  initial begin : timeout_block
    #200000;
    $fatal(1, "tb_cpu_core: timeout");
  end
endmodule

`default_nettype wire
