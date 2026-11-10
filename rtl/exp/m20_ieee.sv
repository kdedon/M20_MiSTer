// G0220 IEEE-488 card: i8292 controller, i8291A talker/listener (m20_gpib,
// empty bus) and a slave i8259A whose INT drives *COMVI1 (master IR1).
//
// Decode: A15-A11 = 0, A8 = 1, A7-A5 picks the chip; A9, A10, A4, A0 are
// not decoded.  These are the mainboard's open U21 outputs O0, O3, O5.
//   0x101/0x103          8292, A0 = A1
//   0x161-0x16F (odd)    8291A, RS2-RS0 = A3-A1
//   0x1A0/0x1A2          8259A on D1-D8, A0 = A1 (word I/O)
// Slave 8259 inputs: IR1 8292 TCI, IR2 8292 SPI, IR3 8291A INT,
// IR4 8292 input buffer empty, IR5 8292 OBF.
//
// cs / cs16 cover the strobe and its end clock (mainboard read mux).
`default_nettype none
module m20_ieee (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,             // card fitted
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic        cs,             // byte port: rdata
  output logic [7:0]  rdata,
  output logic        cs16,           // 8259: pic_rdata
  output logic [15:0] pic_rdata,      // also the vector word in an acknowledge
  input  logic        pic_inta_n,
  input  logic [2:0]  cas,
  output logic        comvi1
);

  logic strobe, board;
  assign strobe = io_rd || io_wr || io_rd_end || io_wr_end;
  assign board  = en && strobe && io_addr[15:11] == 5'd0 && io_addr[8];

  logic cs_ctl, cs_tl;
  assign cs_ctl = board && io_addr[7:5] == 3'b000;
  assign cs_tl  = board && io_addr[7:5] == 3'b011;
  assign cs16   = board && io_addr[7:5] == 3'b101;
  assign cs     = cs_ctl || cs_tl;

  logic tl_int, tci, spi, obf, ibf;
  m20_gpib u_gpib (
    .clk, .rst_n, .cs_tl, .cs_ctl, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .rdata, .tl_int, .ctl_tci(tci), .ctl_spi(spi), .ctl_obf(obf), .ctl_ibf(ibf)
  );

  logic irq;
  m20_xpic u_pic (
    .clk, .rst_n, .cs(cs16), .io_rd, .io_wr, .io_addr, .io_wdata, .rdata(pic_rdata),
    .pic_inta_n, .cas, .ir({2'b00, obf, !ibf, tl_int, spi, tci, 1'b0}), .irq
  );
  assign comvi1 = en && irq;

endmodule
`default_nettype wire
