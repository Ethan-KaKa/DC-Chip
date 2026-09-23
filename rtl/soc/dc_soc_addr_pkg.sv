package dc_soc_addr_pkg;
  localparam logic [31:0] IROM_BASE    = 32'h0000_0000;
  localparam int unsigned IROM_BYTES   = 65536;
  localparam logic [31:0] MMIO_BASE    = 32'h1000_0000;
  localparam int unsigned MMIO_BYTES   = 65536;
  localparam logic [31:0] UART_BASE    = 32'h1000_0000;
  localparam logic [31:0] LED_BASE     = 32'h1000_0100;
  localparam logic [31:0] BUTTONS_BASE = 32'h1000_0200;
  localparam logic [31:0] SEG7_BASE    = 32'h1000_0300;
  localparam logic [31:0] DRAM_BASE    = 32'h2000_0000;
  localparam int unsigned DRAM_BYTES   = 65536;
  localparam logic [31:0] TOHOST_ADDR  = 32'hffff_fff0;
endpackage
