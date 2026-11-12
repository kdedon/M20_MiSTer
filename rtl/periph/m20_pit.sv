// i8253 interval timer U152, wrapping KF8253 (PCXT_MiSTer copy, with its LSB/MSB preset fix).
// Ports 0x121/0x123/0x125 counters 0-2, 0x127 control.
//
// All CLK inputs are ce_pit (16 MHz / 13 = 1.230769 MHz); KF8253 counts
// on the falling edge, so one ce_pit pulse is one count.  GATE tied high.
//   OUT0 -> RS-232 8251 TxC/RxC (count 8, mode 3: 9615 baud x16)
//   OUT1 -> keyboard 8251 TxC/RxC (count 0x40, mode 3: 1202 baud x16)
//   OUT2 -> NVI flip-flop (count 0xF062, mode 2: 20 Hz)
`default_nettype none
module m20_pit (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        ce_pit,
  // I/O bus
  input  logic        cs_pit,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [7:0]  pit_rdata,
  // counter outputs
  output logic        pit_out0,
  output logic        pit_out1,
  output logic        pit_out2
);

  wire rd_act = cs_pit & io_rd;
  wire wr_act = cs_pit & io_wr;

  logic [7:0] kf_dout;

  KF8253 u_kf8253 (
    .clock           (clk),
    .reset           (~rst_n),
    .chip_select_n   (~(rd_act | wr_act)),
    .read_enable_n   (~rd_act),
    .write_enable_n  (~wr_act),
    .address         (io_addr[2:1]),
    .data_bus_in     (io_wdata[7:0]),
    .data_bus_out    (kf_dout),
    .counter_0_clock (ce_pit),
    .counter_0_gate  (1'b1),
    .counter_0_out   (pit_out0),
    .counter_1_clock (ce_pit),
    .counter_1_gate  (1'b1),
    .counter_1_out   (pit_out1),
    .counter_2_clock (ce_pit),
    .counter_2_gate  (1'b1),
    .counter_2_out   (pit_out2)
  );

  // Last value driven, still valid in the clock the strobe ends.
  logic [7:0] hold_q;
  always_ff @(posedge clk) begin
    if (!rst_n)      hold_q <= 8'hFF;
    else if (rd_act) hold_q <= kf_dout;
  end

  assign pit_rdata = rd_act ? kf_dout : hold_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, io_rd_end, io_wr_end, io_addr[15:3], io_addr[0], io_wdata[15:8]};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
