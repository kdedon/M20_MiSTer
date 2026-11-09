// Motherboard I/O decode (U39, U21, U26, U8).
//
// Standard I/O (status 0010, U8 O2 IORQ) with A11-A15 = 0 (U26 NOR).  A8
// picks the 74LS138: U39 (A8 = 0) or U21 (A8 = 1); A7-A5 pick its output.
// A9/A10 are ignored (ports mirror at +0x200/+0x400/+0x600), as is A0: the
// byte lane follows from the device's data pins.
//
//   U39: O0 FDC 0x00, O1 latch 0x20, O3 CRTC 0x60, O4 8255 0x80,
//        O5 kbd 8251 0xA0, O6 RS-232 8251 0xC0  (O2, O7 open)
//   U21: O1 8253 0x120, O2 8259 0x140, O4 74LS670 0x180  (O0, O3, O5-O7 open)
//
// Selects are levels from the /AS latch to the clock after /DS rises (so
// they cover the io_*_end pulse).  Read data: byte devices on D7-D0 with
// D15-D8 floating High; the 8259 word as its wrapper gives it; anything
// else reads 0xFFFF.  Every output is combinational from registers.
`default_nettype none
module m20_iodec (
  input  logic [15:5] addr,        // latched at /AS
  input  logic        io_cyc,      // latched status = 0010, from /AS to /DS end
  input  logic        r_w,         // latched R/W, 1 = read
  input  logic        ds_n,
  input  logic        ds_rise,     // /DS rose this clock
  output logic        io_rd,
  output logic        io_wr,
  output logic        io_rd_end,
  output logic        io_wr_end,
  output logic        cs_fdc,
  output logic        cs_latch,
  output logic        cs_crtc,
  output logic        cs_ppi,
  output logic        cs_kbd,
  output logic        cs_ser,
  output logic        cs_pit,
  output logic        cs_pic,
  output logic        cs_pal,
  input  logic [7:0]  fdc_rdata,
  input  logic [7:0]  latch_rdata,
  input  logic [7:0]  crtc_rdata,
  input  logic [7:0]  ppi_rdata,
  input  logic [7:0]  kbd_rdata,
  input  logic [7:0]  ser_rdata,
  input  logic [7:0]  pit_rdata,
  input  logic [15:0] pic_rdata,
  output logic [15:0] rdata
);
  logic       sel;
  logic [7:0] u39, u21;
  assign sel = io_cyc && (addr[15:11] == 5'b00000);

  always_comb begin
    u39 = 8'h00;
    u21 = 8'h00;
    if (sel && !addr[8]) u39[addr[7:5]] = 1'b1;
    if (sel &&  addr[8]) u21[addr[7:5]] = 1'b1;
  end

  assign cs_fdc   = u39[0];
  assign cs_latch = u39[1];
  assign cs_crtc  = u39[3];
  assign cs_ppi   = u39[4];
  assign cs_kbd   = u39[5];
  assign cs_ser   = u39[6];
  assign cs_pit   = u21[1];
  assign cs_pic   = u21[2];
  assign cs_pal   = u21[4];

  assign io_rd     = io_cyc &&  r_w && !ds_n;
  assign io_wr     = io_cyc && !r_w && !ds_n;
  assign io_rd_end = io_cyc &&  r_w && ds_rise;
  assign io_wr_end = io_cyc && !r_w && ds_rise;

  always_comb begin
    rdata = 16'hFFFF;
    unique case (1'b1)
      cs_fdc:   rdata = {8'hFF, fdc_rdata};
      cs_latch: rdata = {8'hFF, latch_rdata};
      cs_crtc:  rdata = {8'hFF, crtc_rdata};
      cs_ppi:   rdata = {8'hFF, ppi_rdata};
      cs_kbd:   rdata = {8'hFF, kbd_rdata};
      cs_ser:   rdata = {8'hFF, ser_rdata};
      cs_pit:   rdata = {8'hFF, pit_rdata};
      cs_pic:   rdata = pic_rdata;
      default:  rdata = 16'hFFFF;
    endcase
  end
  // A10/A9 are not decoded; the open 138 outputs drive nothing.
  logic unused_ok;
  assign unused_ok = &{1'b0, addr[10:9], u39[7], u39[2], u21[7:5], u21[3], u21[0]};
endmodule
`default_nettype wire
