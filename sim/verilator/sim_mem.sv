`default_nettype none

// Reference: /home/kaka/ysyx-workbench/JYDSoC/{irom.sv, dram.sv}
// Commit: 6ea56f945ade14033f0fc9b48f6a95d0fd3b199a
// Timing characteristics (async read for IROM, 1-cycle sync read-first for DRAM)
// are borrowed from JYDSoC, but independently implemented for the DC-Chip v0.2
// 32-bit architecture, native byte strobes, and valid/ready handshake protocols.

module sim_mem #(
  parameter logic [31:0] IROM_BASE    = 32'h0000_0000,
  parameter int unsigned IROM_BYTES   = 1024,
  parameter logic [31:0] DRAM_BASE    = 32'h0000_1000,
  parameter int unsigned DRAM_BYTES   = 4096,
  parameter logic [31:0] TOHOST_ADDR  = 32'hffff_fff0
) (
  input  logic        clk,
  input  logic        rst,

  // Instruction interface (to cpu_core)
  input  logic        imem_req_valid,
  output logic        imem_req_ready,
  input  logic [31:0] imem_req_addr,
  output logic        imem_rsp_valid,
  input  logic        imem_rsp_ready,
  output logic [31:0] imem_rsp_rdata,
  output logic        imem_rsp_error,

  // Data interface (to cpu_core)
  input  logic        dmem_req_valid,
  output logic        dmem_req_ready,
  input  logic [31:0] dmem_req_addr,
  input  logic        dmem_req_write,
  input  logic [1:0]  dmem_req_size,
  input  logic [31:0] dmem_req_wdata,
  input  logic [3:0]  dmem_req_wstrb,
  output logic        dmem_rsp_valid,
  input  logic        dmem_rsp_ready,
  output logic [31:0] dmem_rsp_rdata,
  output logic        dmem_rsp_error,

  // Simulation control
  output logic        tohost_exit,
  output logic [31:0] guest_exit_code
);

  import "DPI-C" function void sim_irom_read(
    input  int unsigned addr,
    output int unsigned data
  );

  import "DPI-C" function void sim_dram_read(
    input  int unsigned addr,
    output int unsigned data
  );

  import "DPI-C" function void sim_dram_write(
    input int unsigned addr,
    input int unsigned data,
    input int unsigned wstrb
  );

  // ---------------------------------------------------------------------------
  // Instruction Memory (IROM): Asynchronous read, same-cycle response
  // ---------------------------------------------------------------------------
  logic in_irom;
  logic [31:0] irom_data_comb;

  /* verilator lint_off UNSIGNED */
  assign in_irom = (imem_req_addr >= IROM_BASE) &&
                   (imem_req_addr < (IROM_BASE + 32'(IROM_BYTES))) &&
                   (imem_req_addr[1:0] == 2'b00);
  /* verilator lint_on UNSIGNED */

  always_comb begin
    if (imem_req_valid && in_irom) begin
      sim_irom_read(imem_req_addr, irom_data_comb);
    end else begin
      irom_data_comb = 32'd0;
    end
  end

  always_comb begin
    if (!rst && imem_req_valid) begin
      imem_req_ready = 1'b1;
      imem_rsp_valid = 1'b1;
      if (in_irom) begin
        imem_rsp_error = 1'b0;
        imem_rsp_rdata = irom_data_comb;
      end else begin
        imem_rsp_error = 1'b1;
        imem_rsp_rdata = 32'd0;
      end
    end else begin
      imem_req_ready = 1'b0;
      imem_rsp_valid = 1'b0;
      imem_rsp_error = 1'b0;
      imem_rsp_rdata = 32'd0;
    end
  end

  // ---------------------------------------------------------------------------
  // Data Memory (DRAM & tohost): Synchronous 1-cycle latency, read-first
  // ---------------------------------------------------------------------------
  logic in_dram;
  logic dram_aligned;
  logic is_tohost;
  logic tohost_legal_sw;
  logic req_is_dram;
  logic req_is_tohost;
  logic req_is_error;

  logic dmem_req_fire;
  logic dmem_rsp_fire;

  logic        rsp_valid_q;
  logic        rsp_error_q;
  logic [31:0] rsp_rdata_q;

  logic [31:0] pending_addr_q;
  logic        pending_write_q;
  logic [31:0] pending_wdata_q;
  logic [3:0]  pending_wstrb_q;
  logic        pending_in_dram_q;
  logic        pending_tohost_q;
  logic        pending_error_q;

  assign in_dram = (dmem_req_addr >= DRAM_BASE) &&
                   (dmem_req_addr < (DRAM_BASE + 32'(DRAM_BYTES)));

  assign dram_aligned = (dmem_req_size != 2'b10) || (dmem_req_addr[1:0] == 2'b00);

  assign is_tohost = (dmem_req_addr == TOHOST_ADDR);
  assign tohost_legal_sw = is_tohost &&
                           (dmem_req_write == 1'b1) &&
                           (dmem_req_size == 2'b10) &&
                           (dmem_req_wstrb == 4'b1111);

  assign req_is_dram   = in_dram && dram_aligned;
  assign req_is_tohost = tohost_legal_sw;
  assign req_is_error  = !(req_is_dram || req_is_tohost);

  // Ready to accept new request if no pending response or response handshakes now
  assign dmem_req_ready = !rst && (!rsp_valid_q || dmem_rsp_fire);

  assign dmem_req_fire = dmem_req_valid && dmem_req_ready;
  assign dmem_rsp_fire = rsp_valid_q && dmem_rsp_ready;

  assign dmem_rsp_valid = rsp_valid_q;
  assign dmem_rsp_error = rsp_error_q;
  assign dmem_rsp_rdata = rsp_rdata_q;

  logic [31:0] dram_sampled_rdata;

  always_comb begin
    if (dmem_req_fire && req_is_dram) begin
      sim_dram_read(dmem_req_addr, dram_sampled_rdata);
    end else begin
      dram_sampled_rdata = 32'd0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_valid_q        <= 1'b0;
      rsp_error_q        <= 1'b0;
      rsp_rdata_q        <= 32'd0;
      pending_addr_q     <= 32'd0;
      pending_write_q    <= 1'b0;
      pending_wdata_q    <= 32'd0;
      pending_wstrb_q    <= 4'd0;
      pending_in_dram_q  <= 1'b0;
      pending_tohost_q   <= 1'b0;
      pending_error_q    <= 1'b0;
      tohost_exit        <= 1'b0;
      guest_exit_code    <= 32'd0;
    end else begin
      // Store write and tohost exit are triggered strictly on response handshake edge
      if (dmem_rsp_fire) begin
        if (pending_in_dram_q && pending_write_q && !pending_error_q) begin
          sim_dram_write(pending_addr_q, pending_wdata_q, {28'd0, pending_wstrb_q});
        end
        if (pending_tohost_q) begin
          tohost_exit     <= 1'b1;
          guest_exit_code <= pending_wdata_q;
        end
      end

      // Process new incoming request
      if (dmem_req_fire) begin
        rsp_valid_q       <= 1'b1;
        pending_addr_q    <= dmem_req_addr;
        pending_write_q   <= dmem_req_write;
        pending_wdata_q   <= dmem_req_wdata;
        pending_wstrb_q   <= dmem_req_wstrb;
        pending_in_dram_q <= req_is_dram;
        pending_tohost_q  <= req_is_tohost;
        pending_error_q   <= req_is_error;

        if (req_is_dram) begin
          rsp_error_q <= 1'b0;
          rsp_rdata_q <= dram_sampled_rdata;
        end else if (req_is_tohost) begin
          rsp_error_q <= 1'b0;
          rsp_rdata_q <= 32'd0;
        end else begin
          rsp_error_q <= 1'b1;
          rsp_rdata_q <= 32'd0;
        end
      end else if (dmem_rsp_fire) begin
        // Response finished and no new request accepted
        rsp_valid_q       <= 1'b0;
        rsp_error_q       <= 1'b0;
        rsp_rdata_q       <= 32'd0;
        pending_write_q   <= 1'b0;
        pending_in_dram_q <= 1'b0;
        pending_tohost_q  <= 1'b0;
        pending_error_q   <= 1'b0;
      end
      // If !dmem_req_fire && !dmem_rsp_fire: retain all response registers (backpressure hold)
    end
  end

  // Tie off unused inputs cleanly for lint
  logic _unused;
  assign _unused = &{1'b0, imem_rsp_ready, 1'b0};

endmodule

`default_nettype wire
