// Slave i8259A on an expansion card, wrapping KF8259 (/SP = 0).
//
// D0-D7 sit on D1-D8, A0 = CPU A1, as on the mainboard 8259.  The card
// decodes the chip select.  The slave answers an acknowledge when the
// master's CAS0-2 carry its ICW3 number, driving {ICW2[7:3], IR} during
// the second /INTA.
//
// rdata[15:0]:
//   normal read      {7'h7F, d[7:0], 1'b1}
//   pic_inta_n low   {7'h7F, v[7:0], 1'b0}
`default_nettype none
module m20_xpic (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cs,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [15:0] rdata,
  input  logic        pic_inta_n,
  input  logic [2:0]  cas,
  input  logic [7:0]  ir,
  output logic        irq             // INT, active high
);

  wire rd_act = cs & io_rd;
  wire wr_act = cs & io_wr;
  wire inta   = ~pic_inta_n;

  logic [7:0] kf_dout;
  logic       nc_dbio, nc_casio, nc_buf, nc_spen;
  logic [2:0] nc_cas;

  KF8259 u_kf8259 (
    .clock                          (clk),
    .reset                          (~rst_n),
    .chip_select_n                  (~(rd_act | wr_act)),
    .read_enable_n                  (~rd_act),
    .write_enable_n                 (~wr_act),
    .address                        (io_addr[1]),
    .data_bus_in                    (io_wdata[8:1]),
    .data_bus_out                   (kf_dout),
    .data_bus_io                    (nc_dbio),
    .cascade_in                     (cas),
    .cascade_out                    (nc_cas),
    .cascade_io                     (nc_casio),
    .slave_program_n                (1'b0),
    .buffer_enable                  (nc_buf),
    .slave_program_or_enable_buffer (nc_spen),
    .interrupt_acknowledge_n        (pic_inta_n),
    .interrupt_to_cpu               (irq),
    .interrupt_request              (ir)
  );

  wire [15:0] live = {7'h7F, kf_dout, ~inta};

  // Last value driven, still valid in the clock the strobe ends.
  logic [15:0] hold_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                hold_q <= 16'hFFFF;
    else if (inta || rd_act)   hold_q <= live;
  end

  assign rdata = (inta || rd_act) ? live : hold_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, io_addr[15:2], io_addr[0], io_wdata[15:9], io_wdata[0],
                     nc_dbio, nc_cas, nc_casio, nc_buf, nc_spen};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
