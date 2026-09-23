`default_nettype none

module sim_top (
  input  logic        clk,
  input  logic        rst,

  // Trace and architectural visibility
  output logic        trace_valid,
  output logic [31:0] trace_pc,
  output logic [31:0] trace_inst,
  output logic        is_skip_ref,
  input  logic [3:0]  debug_reg_addr,
  output logic [31:0] debug_reg_data,

  // Structured fault
  output logic        fault_valid,
  output logic [2:0]  fault_cause,
  output logic [31:0] fault_pc,
  output logic        fault_inst_valid,
  output logic [31:0] fault_inst,

  // Simulation control (tohost)
  output logic        tohost_exit,
  output logic [31:0] guest_exit_code,

  // Current fetch state for debug/SDB
  output logic [31:0] fetch_pc,
  output logic [31:0] fetch_inst,

  // Peripheral output pins (LEDs and UART)
  output logic [15:0] o_led,
  output logic        o_uart_tx,
  input  logic        i_uart_rx,
  input  logic [20:0] i_button,
  output logic [7:0]  o_seg0,
  output logic [7:0]  o_seg1,
  output logic [7:0]  o_seg2,
  output logic [7:0]  o_seg3,
  output logic [7:0]  o_seg4,
  output logic [7:0]  o_seg5,
  output logic [7:0]  o_seg6,
  output logic [7:0]  o_seg7
);

  dc_soc_top u_dc_soc_top (
    .clk              (clk),
    .rst              (rst),
    .clk_periph       (clk),
    .rst_periph       (rst),
    .o_led            (o_led),
    .o_uart_tx        (o_uart_tx),
    .i_uart_rx        (i_uart_rx),
    .i_button         (i_button),
    .o_seg0           (o_seg0),
    .o_seg1           (o_seg1),
    .o_seg2           (o_seg2),
    .o_seg3           (o_seg3),
    .o_seg4           (o_seg4),
    .o_seg5           (o_seg5),
    .o_seg6           (o_seg6),
    .o_seg7           (o_seg7),
    .trace_valid      (trace_valid),
    .trace_pc         (trace_pc),
    .trace_inst       (trace_inst),
    .trace_skip_ref   (is_skip_ref),
    .debug_reg_addr   (debug_reg_addr),
    .debug_reg_data   (debug_reg_data),
    .fault_valid      (fault_valid),
    .fault_cause      (fault_cause),
    .fault_pc         (fault_pc),
    .fault_inst_valid (fault_inst_valid),
    .fault_inst       (fault_inst),
    .tohost_exit      (tohost_exit),
    .guest_exit_code  (guest_exit_code),
    .debug_fetch_addr (fetch_pc),
    .debug_fetch_data (fetch_inst)
  );

endmodule

`default_nettype wire
