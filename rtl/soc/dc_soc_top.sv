`default_nettype none

module dc_soc_top #(
  parameter logic [31:0] DRAM_BASE   = 32'h2000_0000,
  parameter int unsigned DRAM_BYTES  = 65536,
  parameter logic [31:0] MMIO_BASE   = 32'h1000_0000,
  parameter int unsigned MMIO_BYTES  = 65536,
  parameter logic [31:0] TOHOST_ADDR = 32'hffff_fff0,
  parameter bit          ASYNC_CDC   = 1'b0
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        clk_periph,
  input  logic        rst_periph,

  // Instruction memory interface (to IROM / sim_mem)
  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_rsp_valid,
  output logic        imem_rsp_ready,
  input  logic [31:0] imem_rsp_rdata,
  input  logic        imem_rsp_error,

  // Data memory interface (to DRAM / sim_mem)
  output logic        dram_req_valid,
  input  logic        dram_req_ready,
  output logic [31:0] dram_req_addr,
  output logic        dram_req_write,
  output logic [1:0]  dram_req_size,
  output logic [31:0] dram_req_wdata,
  output logic [3:0]  dram_req_wstrb,
  input  logic        dram_rsp_valid,
  output logic        dram_rsp_ready,
  input  logic [31:0] dram_rsp_rdata,
  input  logic        dram_rsp_error,

  // Peripherals
  output logic [15:0] o_led,
  output logic        o_uart_tx,
  input  logic        i_uart_rx,
  input  logic [20:0] i_button,

  // Trace & Debug
  output logic        trace_valid,
  output logic [31:0] trace_pc,
  output logic [31:0] trace_inst,
  output logic        trace_skip_ref,
  input  logic [3:0]  debug_reg_addr,
  output logic [31:0] debug_reg_data,
  output logic        fault_valid,
  output logic [2:0]  fault_cause,
  output logic [31:0] fault_pc,
  output logic        fault_inst_valid,
  output logic [31:0] fault_inst
);

  // Internal CPU DMEM bus
  logic        cpu_dmem_req_valid;
  logic        cpu_dmem_req_ready;
  logic [31:0] cpu_dmem_req_addr;
  logic        cpu_dmem_req_write;
  logic [1:0]  cpu_dmem_req_size;
  logic [31:0] cpu_dmem_req_wdata;
  logic [3:0]  cpu_dmem_req_wstrb;
  logic        cpu_dmem_rsp_valid;
  logic        cpu_dmem_rsp_ready;
  logic [31:0] cpu_dmem_rsp_rdata;
  logic        cpu_dmem_rsp_error;
  logic        cpu_dmem_rsp_skip_ref;

  // Internal MMIO bus
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

  cpu_core u_cpu_core (
    .clk               (clk),
    .rst               (rst),
    .imem_req_valid    (imem_req_valid),
    .imem_req_ready    (imem_req_ready),
    .imem_req_addr     (imem_req_addr),
    .imem_rsp_valid    (imem_rsp_valid),
    .imem_rsp_ready    (imem_rsp_ready),
    .imem_rsp_rdata    (imem_rsp_rdata),
    .imem_rsp_error    (imem_rsp_error),
    .dmem_req_valid    (cpu_dmem_req_valid),
    .dmem_req_ready    (cpu_dmem_req_ready),
    .dmem_req_addr     (cpu_dmem_req_addr),
    .dmem_req_write    (cpu_dmem_req_write),
    .dmem_req_size     (cpu_dmem_req_size),
    .dmem_req_wdata    (cpu_dmem_req_wdata),
    .dmem_req_wstrb    (cpu_dmem_req_wstrb),
    .dmem_rsp_valid    (cpu_dmem_rsp_valid),
    .dmem_rsp_ready    (cpu_dmem_rsp_ready),
    .dmem_rsp_rdata    (cpu_dmem_rsp_rdata),
    .dmem_rsp_error    (cpu_dmem_rsp_error),
    .dmem_rsp_skip_ref (cpu_dmem_rsp_skip_ref),
    .trace_valid       (trace_valid),
    .trace_pc          (trace_pc),
    .trace_inst        (trace_inst),
    .trace_skip_ref    (trace_skip_ref),
    .debug_reg_addr    (debug_reg_addr),
    .debug_reg_data    (debug_reg_data),
    .fault_valid       (fault_valid),
    .fault_cause       (fault_cause),
    .fault_pc          (fault_pc),
    .fault_inst_valid  (fault_inst_valid),
    .fault_inst        (fault_inst)
  );

  soc_interconnect #(
    .DRAM_BASE   (DRAM_BASE),
    .DRAM_BYTES  (DRAM_BYTES),
    .MMIO_BASE   (MMIO_BASE),
    .MMIO_BYTES  (MMIO_BYTES),
    .TOHOST_ADDR (TOHOST_ADDR)
  ) u_interconnect (
    .clk              (clk),
    .rst              (rst),
    .cpu_req_valid    (cpu_dmem_req_valid),
    .cpu_req_ready    (cpu_dmem_req_ready),
    .cpu_req_addr     (cpu_dmem_req_addr),
    .cpu_req_write    (cpu_dmem_req_write),
    .cpu_req_size     (cpu_dmem_req_size),
    .cpu_req_wdata    (cpu_dmem_req_wdata),
    .cpu_req_wstrb    (cpu_dmem_req_wstrb),
    .cpu_rsp_valid    (cpu_dmem_rsp_valid),
    .cpu_rsp_ready    (cpu_dmem_rsp_ready),
    .cpu_rsp_rdata    (cpu_dmem_rsp_rdata),
    .cpu_rsp_error    (cpu_dmem_rsp_error),
    .cpu_rsp_skip_ref (cpu_dmem_rsp_skip_ref),
    .dram_req_valid   (dram_req_valid),
    .dram_req_ready  (dram_req_ready),
    .dram_req_addr   (dram_req_addr),
    .dram_req_write  (dram_req_write),
    .dram_req_size   (dram_req_size),
    .dram_req_wdata  (dram_req_wdata),
    .dram_req_wstrb  (dram_req_wstrb),
    .dram_rsp_valid  (dram_rsp_valid),
    .dram_rsp_ready  (dram_rsp_ready),
    .dram_rsp_rdata  (dram_rsp_rdata),
    .dram_rsp_error  (dram_rsp_error),
    .mmio_req_valid  (mmio_req_valid),
    .mmio_req_ready  (mmio_req_ready),
    .mmio_req_addr   (mmio_req_addr),
    .mmio_req_write  (mmio_req_write),
    .mmio_req_size   (mmio_req_size),
    .mmio_req_wdata  (mmio_req_wdata),
    .mmio_req_wstrb  (mmio_req_wstrb),
    .mmio_rsp_valid  (mmio_rsp_valid),
    .mmio_rsp_ready  (mmio_rsp_ready),
    .mmio_rsp_rdata  (mmio_rsp_rdata),
    .mmio_rsp_error  (mmio_rsp_error)
  );

  // Periph bus after CDC bridge (clk_periph domain)
  logic        periph_bus_req_valid;
  logic        periph_bus_req_ready;
  logic [31:0] periph_bus_req_addr;
  logic        periph_bus_req_write;
  logic [1:0]  periph_bus_req_size;
  logic [31:0] periph_bus_req_wdata;
  logic [3:0]  periph_bus_req_wstrb;
  logic        periph_bus_rsp_valid;
  logic        periph_bus_rsp_ready;
  logic [31:0] periph_bus_rsp_rdata;
  logic        periph_bus_rsp_error;

  mmio_cdc_bridge #(
    .ASYNC_CDC (ASYNC_CDC)
  ) u_cdc_bridge (
    .clk_cpu          (clk),
    .rst_cpu          (rst),
    .cpu_req_valid    (mmio_req_valid),
    .cpu_req_ready    (mmio_req_ready),
    .cpu_req_addr     (mmio_req_addr),
    .cpu_req_write    (mmio_req_write),
    .cpu_req_size     (mmio_req_size),
    .cpu_req_wdata    (mmio_req_wdata),
    .cpu_req_wstrb    (mmio_req_wstrb),
    .cpu_rsp_valid    (mmio_rsp_valid),
    .cpu_rsp_ready    (mmio_rsp_ready),
    .cpu_rsp_rdata    (mmio_rsp_rdata),
    .cpu_rsp_error    (mmio_rsp_error),
    .clk_periph       (clk_periph),
    .rst_periph       (rst_periph),
    .periph_req_valid (periph_bus_req_valid),
    .periph_req_ready (periph_bus_req_ready),
    .periph_req_addr  (periph_bus_req_addr),
    .periph_req_write (periph_bus_req_write),
    .periph_req_size  (periph_bus_req_size),
    .periph_req_wdata (periph_bus_req_wdata),
    .periph_req_wstrb (periph_bus_req_wstrb),
    .periph_rsp_valid (periph_bus_rsp_valid),
    .periph_rsp_ready (periph_bus_rsp_ready),
    .periph_rsp_rdata (periph_bus_rsp_rdata),
    .periph_rsp_error (periph_bus_rsp_error)
  );

  // Per-peripheral interconnect buses
  logic        uart_req_valid, uart_req_ready;
  logic [31:0] uart_req_addr;
  logic        uart_req_write;
  logic [1:0]  uart_req_size;
  logic [31:0] uart_req_wdata;
  logic [3:0]  uart_req_wstrb;
  logic        uart_rsp_valid, uart_rsp_ready;
  logic [31:0] uart_rsp_rdata;
  logic        uart_rsp_error;

  logic        led_req_valid, led_req_ready;
  logic [31:0] led_req_addr;
  logic        led_req_write;
  logic [1:0]  led_req_size;
  logic [31:0] led_req_wdata;
  logic [3:0]  led_req_wstrb;
  logic        led_rsp_valid, led_rsp_ready;
  logic [31:0] led_rsp_rdata;
  logic        led_rsp_error;

  logic        buttons_req_valid, buttons_req_ready;
  logic [31:0] buttons_req_addr;
  logic        buttons_req_write;
  logic [1:0]  buttons_req_size;
  logic [31:0] buttons_req_wdata;
  logic [3:0]  buttons_req_wstrb;
  logic        buttons_rsp_valid, buttons_rsp_ready;
  logic [31:0] buttons_rsp_rdata;
  logic        buttons_rsp_error;

  periph_interconnect #(
    .UART_BASE (32'h1000_0000),
    .LED_BASE  (32'h1000_0100),
    .BUTTONS_BASE (32'h1000_0200)
  ) u_periph_interconnect (
    .clk             (clk_periph),
    .rst             (rst_periph),
    .s_req_valid     (periph_bus_req_valid),
    .s_req_ready     (periph_bus_req_ready),
    .s_req_addr      (periph_bus_req_addr),
    .s_req_write     (periph_bus_req_write),
    .s_req_size      (periph_bus_req_size),
    .s_req_wdata     (periph_bus_req_wdata),
    .s_req_wstrb     (periph_bus_req_wstrb),
    .s_rsp_valid     (periph_bus_rsp_valid),
    .s_rsp_ready     (periph_bus_rsp_ready),
    .s_rsp_rdata     (periph_bus_rsp_rdata),
    .s_rsp_error     (periph_bus_rsp_error),
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
    .led_rsp_error   (led_rsp_error),
    .buttons_req_valid (buttons_req_valid),
    .buttons_req_ready (buttons_req_ready),
    .buttons_req_addr  (buttons_req_addr),
    .buttons_req_write (buttons_req_write),
    .buttons_req_size  (buttons_req_size),
    .buttons_req_wdata (buttons_req_wdata),
    .buttons_req_wstrb (buttons_req_wstrb),
    .buttons_rsp_valid (buttons_rsp_valid),
    .buttons_rsp_ready (buttons_rsp_ready),
    .buttons_rsp_rdata (buttons_rsp_rdata),
    .buttons_rsp_error (buttons_rsp_error)
  );

  uart_controller #(
    .ADDR_BASE  (32'h1000_0000),
    .BAUD_DIV   (432),
    .FIFO_DEPTH (16)
  ) u_uart_controller (
    .clk       (clk_periph),
    .rst       (rst_periph),
    .req_valid (uart_req_valid),
    .req_ready (uart_req_ready),
    .req_addr  (uart_req_addr),
    .req_write (uart_req_write),
    .req_size  (uart_req_size),
    .req_wdata (uart_req_wdata),
    .req_wstrb (uart_req_wstrb),
    .rsp_valid (uart_rsp_valid),
    .rsp_ready (uart_rsp_ready),
    .rsp_rdata (uart_rsp_rdata),
    .rsp_error (uart_rsp_error),
    .o_uart_tx (o_uart_tx),
    .i_uart_rx (i_uart_rx)
  );

  led_controller #(
    .ADDR_BASE (32'h1000_0100)
  ) u_led_controller (
    .clk       (clk_periph),
    .rst       (rst_periph),
    .req_valid (led_req_valid),
    .req_ready (led_req_ready),
    .req_addr  (led_req_addr),
    .req_write (led_req_write),
    .req_size  (led_req_size),
    .req_wdata (led_req_wdata),
    .req_wstrb (led_req_wstrb),
    .rsp_valid (led_rsp_valid),
    .rsp_ready (led_rsp_ready),
    .rsp_rdata (led_rsp_rdata),
    .rsp_error (led_rsp_error),
    .o_led     (o_led)
  );

  buttons_controller #(
    .ADDR_BASE       (32'h1000_0200),
    .WIDTH           (21),
    .DEBOUNCE_CYCLES (0)
  ) u_buttons_controller (
    .clk       (clk_periph),
    .rst       (rst_periph),
    .req_valid (buttons_req_valid),
    .req_ready (buttons_req_ready),
    .req_addr  (buttons_req_addr),
    .req_write (buttons_req_write),
    .req_size  (buttons_req_size),
    .req_wdata (buttons_req_wdata),
    .req_wstrb (buttons_req_wstrb),
    .rsp_valid (buttons_rsp_valid),
    .rsp_ready (buttons_rsp_ready),
    .rsp_rdata (buttons_rsp_rdata),
    .rsp_error (buttons_rsp_error),
    .i_button  (i_button)
  );

endmodule

`default_nettype wire
