// i8259A interrupt controller U33, wrapping KF8259.
//
// D0-D7 sit on AD1-AD8: word I/O at 0x140 (A0 = 0) and 0x142 (A0 = 1).
//
// pic_rdata[15:0]:
//   normal read      {7'h7F, d[7:0], 1'b1}   (AD9-AD15 and AD0 float high)
//   pic_inta_n low   {7'h7F, v[7:0], 1'b0}   (U4 7416 pulls AD0 low during /INTA)
//
// pic_inta_n pulses low twice per acknowledge.  In 8086 mode KF8259
// latches the ISR on the first falling edge and drives the vector
// {ICW2[7:3], IR} while the second pulse is low; with ICW2 = 0 the
// identifier low byte is 2n.
//
// IR0 FDC INTRQ, IR1 *COMVI1, IR2 *COMVI2, IR3 RS-232 RxRDY, IR4 keyboard
// RxRDY, IR5 keyboard TxRDY, IR6 8255 PC3, IR7 *SYSINT.  The ROM programs
// cascade mode with slaves on IR1, IR2, IR7: for those the master puts the
// slave number on CAS0-2 during the acknowledge and drives no vector.
`default_nettype none
module m20_pic (
  input  logic        clk,
  input  logic        rst_n,
  // I/O bus
  input  logic        cs_pic,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [15:0] pic_rdata,
  // acknowledge and interrupt
  input  logic        pic_inta_n,
  output logic        pic_int,        // to the CPU /VI (active high here)
  // requests
  input  logic        ir_fdc,         // IR0
  input  logic        ir_comvi1,      // IR1
  input  logic        ir_comvi2,      // IR2
  input  logic        ir_ser_rxrdy,   // IR3
  input  logic        ir_kbd_rxrdy,   // IR4
  input  logic        ir_kbd_txrdy,   // IR5
  input  logic        ir_ppi,         // IR6
  input  logic        ir_sysint,      // IR7
  output logic [2:0]  cas             // CAS0-2
);

  wire       rd_act = cs_pic & io_rd;
  wire       wr_act = cs_pic & io_wr;
  wire       inta   = ~pic_inta_n;
  wire [7:0] ir     = {ir_sysint, ir_ppi, ir_kbd_txrdy, ir_kbd_rxrdy, ir_ser_rxrdy,
                       ir_comvi2, ir_comvi1, ir_fdc};

  logic [7:0] kf_dout;
  logic       nc_dbio, nc_casio, nc_buf, nc_spen;

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
    .cascade_in                     (3'b000),
    .cascade_out                    (cas),
    .cascade_io                     (nc_casio),
    .slave_program_n                (1'b1),
    .buffer_enable                  (nc_buf),
    .slave_program_or_enable_buffer (nc_spen),
    .interrupt_acknowledge_n        (pic_inta_n),
    .interrupt_to_cpu               (pic_int),
    .interrupt_request              (ir)
  );

  wire [15:0] live = {7'h7F, kf_dout, ~inta};

  // Last value driven, still valid in the clock the strobe ends.
  logic [15:0] hold_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                hold_q <= 16'hFFFF;
    else if (inta || rd_act)   hold_q <= live;
  end

  assign pic_rdata = (inta || rd_act) ? live : hold_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, io_rd_end, io_wr_end, io_addr[15:2], io_addr[0],
                     io_wdata[15:9], io_wdata[0],
                     nc_dbio, nc_casio, nc_buf, nc_spen};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
