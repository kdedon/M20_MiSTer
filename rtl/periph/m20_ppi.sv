// i8255A-5 parallel interface U62, wrapping KF8255 (PCXT_MiSTer copy, with its IBF fix).
// Ports 0x81 PA, 0x83 PB, 0x85 PC, 0x87 control.
//
// The ROM sets mode 0xA6: PA strobed output (Centronics data latch, read
// back by a ROM test), PB strobed input (printer and modem status).
// PC3 = INTR A goes to IR6.
//
// No printer is fitted, so the inputs are constants:
//   PB[5:0] = 1  printer lines pulled up; PB1 = 1 (not ready) makes the
//                ROM skip its Centronics error output
//   PB6 = 1      RS-232 RING IND inactive
//   PB7 = 1      RS-232 SIGDET (DCD) inactive
//   PC2 = 0      /STB B held low, so PB reads the status lines directly
//   PC4, PC6 = 1 /STB A and /ACK A inactive
`default_nettype none
module m20_ppi (
  input  logic        clk,
  input  logic        rst_n,
  // I/O bus
  input  logic        cs_ppi,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [7:0]  ppi_rdata,
  // Centronics side (stub)
  output logic [7:0]  ppi_pa,         // printer data latch
  output logic [7:0]  ppi_pc,         // port C output latch (strobe, OBF, ...)
  output logic        ppi_ir6         // PC3 -> 8259 IR6
);

  localparam logic [7:0] PB_IDLE = 8'hFF;
  localparam logic [7:0] PC_IDLE = 8'b1111_1011;

  wire rd_act = cs_ppi & io_rd;
  wire wr_act = cs_ppi & io_wr;

  logic [7:0] kf_dout;
  logic [7:0] pb_out;
  logic [7:0] pc_io;
  logic       pa_io, pb_io;

  KF8255 u_kf8255 (
    .clock          (clk),
    .reset          (~rst_n),
    .chip_select_n  (~(rd_act | wr_act)),
    .read_enable_n  (~rd_act),
    .write_enable_n (~wr_act),
    .address        (io_addr[2:1]),
    .data_bus_in    (io_wdata[7:0]),
    .data_bus_out   (kf_dout),
    .port_a_in      (8'hFF),
    .port_a_out     (ppi_pa),
    .port_a_io      (pa_io),
    .port_b_in      (PB_IDLE),
    .port_b_out     (pb_out),
    .port_b_io      (pb_io),
    .port_c_in      (PC_IDLE),
    .port_c_out     (ppi_pc),
    .port_c_io      (pc_io)
  );

  assign ppi_ir6 = ppi_pc[3] & ~pc_io[3];

  // Last value driven, still valid in the clock the strobe ends.
  logic [7:0] hold_q;
  always_ff @(posedge clk) begin
    if (!rst_n)      hold_q <= 8'hFF;
    else if (rd_act) hold_q <= kf_dout;
  end

  assign ppi_rdata = rd_act ? kf_dout : hold_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, io_rd_end, io_wr_end, io_addr[15:3], io_addr[0], io_wdata[15:8],
                     pb_out, pa_io, pb_io, pc_io[7:4], pc_io[2:0]};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
