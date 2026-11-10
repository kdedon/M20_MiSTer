// m20_core: the Olivetti L1 M20 motherboard with its keyboard and drives.
// Wiring only:
//   m20_mainboard  Z8001, clocks, PROM map, ROM, DRAM client, I/O decode,
//                  port 0x21, NVI/VI, T3 stretch
//   m20_video      MC6845, bitmap planes, palette
//   m20_pic        8259A (U33)      IR0 FDC, IR3 RS-232 RxRDY, IR4 kbd RxRDY,
//                                   IR5 kbd TxRDY (JP4 6-3), IR6 8255 PC3
//   m20_pit        8253 (U152)      OUT0 RS-232 baud, OUT1 kbd baud, OUT2 NVI
//   m20_ppi        8255A (U62)      Centronics, no printer fitted
//   i8251 x2       U22 keyboard, U131 RS-232 (J7, the HPS UART)
//   m20_kbd        the keyboard unit (8048 HLE) on the U22 serial line
//   m20_fdc        FD1797 (U14) and two drives on the disk_stream drive side
//   m20_hdc        hard disk card, two drives on the disk_stream drive side;
//                  INTRQ not wired
//   m20_ieee       IEEE-488 card (optional), slave 8259 on IR1
//   m20_twin       twin RS-232 card (optional), slave 8259 on IR7
//
// The UART (ser_*) goes to one RS-232 port, picked by ser_sel; the others
// see an idle line with CTS and DSR asserted.

`default_nettype none

module m20_core (
  input  logic             clk,           // 48 MHz
  input  logic             rst_n,

  // Jumpers, sampled by the shell at reset
  input  logic [2:0]       cfg_code,      // {BW^COL, 32^128, COL4^8}
  input  logic             cfg_za,        // ZA jumper, port 0x21 D3
  input  logic             cfg_spare1,    // SPARE1 jumper, port 0x21 D4
  input  logic             cfg_ieee,      // IEEE-488 card fitted
  input  logic             cfg_twin,      // twin RS-232 card fitted
  input  logic [1:0]       ser_sel,       // UART on: 0 mainboard J7, 1 twin A, 2 twin B

  // ROM download: boot.rom (rom_ext = 0) or extension ROM (rom_ext = 1)
  input  logic             rom_wr,
  input  logic [15:0]      rom_addr,
  input  logic [7:0]       rom_data,
  input  logic             rom_ext,
  input  logic             rom_start,

  // DRAM (SDRAM controller client)
  output logic [23:1]      mem_addr,
  output logic             mem_rd,
  output logic             mem_wr,
  output logic [1:0]       mem_be,
  output logic [15:0]      mem_wdata,
  input  logic [15:0]      mem_rdata,
  input  logic             mem_rvalid,
  input  logic             mem_ack,
  input  logic             mem_ready,
  output logic             mem_refresh_ok,

  // Floppy drives (disk_stream drive side, slots 0 and 1)
  input  logic [1:0]       fd_mounted,
  input  logic             fd_readonly,
  input  logic [63:0]      fd_size,
  output logic [1:0][31:0] fd_lba,
  output logic [1:0]       fd_rd,
  output logic [1:0]       fd_wr,
  input  logic [1:0]       fd_ack,
  input  logic [8:0]       fd_buff_addr,
  input  logic [7:0]       fd_buff_dout,
  output logic [1:0][7:0]  fd_buff_din,
  input  logic             fd_buff_wr,

  // Hard disks (disk_stream slots 2 and 3; buffer bus, size, readonly shared)
  input  logic [1:0]       hd_mounted,
  output logic [1:0][31:0] hd_lba,
  output logic [1:0]       hd_rd,
  output logic [1:0]       hd_wr,
  input  logic [1:0]       hd_ack,
  output logic [1:0][7:0]  hd_buff_din,

  // Keyboard
  input  logic [10:0]      ps2_key,
  input  logic             osd_active,

  // UART
  input  logic             ser_rxd,
  output logic             ser_txd,
  input  logic             ser_cts_n,
  input  logic             ser_dsr_n,
  output logic             ser_rts_n,
  output logic             ser_dtr_n,

  // Video
  output logic             ce_pix,
  output logic [7:0]       vid_r,
  output logic [7:0]       vid_g,
  output logic [7:0]       vid_b,
  output logic             hsync,
  output logic             vsync,
  output logic             hblank,
  output logic             vblank,

  output logic             beep,
  output logic             led_fdd
);

  // ---------------------------------------------------------------- buses
  logic        ce16, ce_pit, ce_usart, ce_fdc;
  logic        vram_we;
  logic [1:0]  vram_plane, vram_be;
  logic [13:1] vram_addr;
  logic [15:0] vram_wdata;
  logic [15:0] io_addr, io_wdata;
  logic        io_rd, io_wr, io_rd_end, io_wr_end;
  logic        cs_fdc, cs_latch, cs_crtc, cs_ppi, cs_kbd, cs_ser, cs_pit, cs_pic, cs_pal;
  logic [7:0]  fdc_rdata, crtc_rdata, ppi_rdata, kbd_rdata, ser_rdata, pit_rdata;
  logic [15:0] pic_rdata, mpic_rdata;
  logic        pic_int, pic_inta_n;
  logic [2:0]  pic_cas;
  logic        cs_exp, cs_exp16;
  logic [7:0]  exp_rdata;
  logic [15:0] exp_rdata16;
  logic        pit_out0, pit_out1, pit_out2;
  logic        crt_fetch;
  logic [1:0]  fdc_ds;
  logic        fdc_motor, fdc_dden_n, fdc_tg43;
  logic        fdc_intrq, fdc_drq, fdc_busy;
  logic        hdc_intrq;
  logic        kbd_rxrdy, kbd_txrdy, ser_rxrdy;
  logic        kbd_txd, kbd_rxd;
  logic        ppi_ir6;
  logic [7:0]  ppi_pa, ppi_pc;

  // cs_latch is decoded inside the mainboard (port 0x21 latch U15/U16).
  logic unused_ok;
  assign unused_ok = &{1'b0, ce16, cs_latch, fdc_drq, fdc_busy, fdc_motor, fdc_tg43, hdc_intrq};

  // ------------------------------------------------------------ mainboard
  m20_mainboard u_mb (
    .clk, .rst_n,
    .ce16, .ce_pit, .ce_usart, .ce_fdc,
    .cfg_code, .cfg_za, .cfg_spare1,
    .rom_wr, .rom_addr, .rom_data, .rom_ext, .rom_start,
    .mem_addr, .mem_rd, .mem_wr, .mem_be, .mem_wdata, .mem_rdata, .mem_rvalid, .mem_ack,
    .mem_ready, .mem_refresh_ok,
    .vram_we, .vram_plane, .vram_addr, .vram_be, .vram_wdata,
    .io_addr, .io_wdata, .io_rd, .io_wr, .io_rd_end, .io_wr_end,
    .cs_fdc, .cs_latch, .cs_crtc, .cs_ppi, .cs_kbd, .cs_ser, .cs_pit, .cs_pic, .cs_pal,
    .fdc_rdata, .crtc_rdata, .ppi_rdata, .kbd_rdata, .ser_rdata, .pit_rdata, .pic_rdata,
    .cs_exp, .exp_rdata, .cs_exp16, .exp_rdata16,
    .pic_int, .pic_inta_n, .pit_out2, .crt_fetch,
    .fdc_ds, .fdc_motor, .fdc_dden_n, .fdc_tg43
  );

  // ---------------------------------------------------------------- video
  m20_video u_video (
    .clk, .rst_n,
    .io_addr, .io_wdata, .io_rd, .io_wr, .io_wr_end, .cs_crtc, .cs_pal, .crtc_rdata,
    .vram_we, .vram_plane, .vram_addr, .vram_be, .vram_wdata,
    .cfg_code,
    .ce_pix, .vga_r(vid_r), .vga_g(vid_g), .vga_b(vid_b), .hsync, .vsync, .hblank, .vblank,
    .crt_fetch
  );

  // ---------------------------------------------------------- interrupts
  logic comvi1, sysint;
  m20_pic u_pic (
    .clk, .rst_n, .cs_pic, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pic_rdata(mpic_rdata), .pic_inta_n, .pic_int,
    .ir_fdc(fdc_intrq), .ir_comvi1(comvi1), .ir_comvi2(1'b0), .ir_ser_rxrdy(ser_rxrdy),
    .ir_kbd_rxrdy(kbd_rxrdy), .ir_kbd_txrdy(kbd_txrdy), .ir_ppi(ppi_ir6), .ir_sysint(sysint),
    .cas(pic_cas)
  );

  // ------------------------------------------------------ expansion cards
  logic        hd_sel, ieee_cs, ieee_cs16, twin_cs, twin_cs16;
  logic [7:0]  hd_rdata, ieee_rdata, twin_rdata;
  logic [15:0] ieee_pic, twin_pic;
  logic [1:0]  tw_rxd, tw_txd, tw_cts_n, tw_dsr_n, tw_rts_n, tw_dtr_n;

  m20_ieee u_ieee (
    .clk, .rst_n, .en(cfg_ieee), .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .cs(ieee_cs), .rdata(ieee_rdata), .cs16(ieee_cs16), .pic_rdata(ieee_pic),
    .pic_inta_n, .cas(pic_cas), .comvi1
  );

  m20_twin u_twin (
    .clk, .rst_n, .en(cfg_twin), .ce_pit, .ce_usart,
    .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .cs(twin_cs), .rdata(twin_rdata), .cs16(twin_cs16), .pic_rdata(twin_pic),
    .pic_inta_n, .cas(pic_cas), .sysint,
    .rxd(tw_rxd), .txd(tw_txd), .cts_n(tw_cts_n), .dsr_n(tw_dsr_n),
    .rts_n(tw_rts_n), .dtr_n(tw_dtr_n)
  );

  assign cs_exp      = hd_sel || ieee_cs || twin_cs;
  assign exp_rdata   = hd_sel ? hd_rdata : ieee_cs ? ieee_rdata : twin_rdata;
  assign cs_exp16    = ieee_cs16 || twin_cs16;
  assign exp_rdata16 = ieee_cs16 ? ieee_pic : twin_pic;

  m20_cascade u_cascade (
    .clk, .rst_n, .pic_inta_n, .cas(pic_cas), .cs_pic, .master_rdata(mpic_rdata),
    .ieee_en(cfg_ieee), .ieee_rdata(ieee_pic), .twin_en(cfg_twin), .twin_rdata(twin_pic),
    .pic_rdata
  );

  m20_pit u_pit (
    .clk, .rst_n, .ce_pit, .cs_pit, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pit_rdata, .pit_out0, .pit_out1, .pit_out2
  );

  // ------------------------------------------------------------- printer
  m20_ppi u_ppi (
    .clk, .rst_n, .cs_ppi, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .ppi_rdata, .ppi_pa, .ppi_pc, .ppi_ir6
  );
  logic unused_ppi;
  assign unused_ppi = &{1'b0, ppi_pa, ppi_pc};

  // ------------------------------------------------------------- USARTs
  // Keyboard U22: TxC = RxC = 8253 OUT1 (BL.SerClk).  CTS/DSR tied active.
  logic kbd_txempty, kbd_syndet, kbd_dtr_n, kbd_rts_n;
  i8251 u_kbd_usart (
    .clk, .rst_n, .ce_usart, .cs(cs_kbd), .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .rdata(kbd_rdata), .txc(pit_out1), .rxc(pit_out1), .rxd(kbd_rxd), .txd(kbd_txd),
    .cts_n(1'b0), .dsr_n(1'b0), .dtr_n(kbd_dtr_n), .rts_n(kbd_rts_n),
    .txrdy(kbd_txrdy), .rxrdy(kbd_rxrdy), .txempty(kbd_txempty), .syndet(kbd_syndet)
  );

  // RS-232 U131: TxC = RxC = 8253 OUT0 (jumpers R/S internal).
  logic ser_txrdy, ser_txempty, ser_syndet;
  logic mb_txd, mb_rts_n, mb_dtr_n;
  logic [2:0] on_uart;
  assign on_uart = {ser_sel == 2'd2, ser_sel == 2'd1, ser_sel == 2'd0};
  i8251 u_ser_usart (
    .clk, .rst_n, .ce_usart, .cs(cs_ser), .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .rdata(ser_rdata), .txc(pit_out0), .rxc(pit_out0),
    .rxd(on_uart[0] ? ser_rxd : 1'b1), .txd(mb_txd),
    .cts_n(on_uart[0] && ser_cts_n), .dsr_n(on_uart[0] && ser_dsr_n),
    .dtr_n(mb_dtr_n), .rts_n(mb_rts_n),
    .txrdy(ser_txrdy), .rxrdy(ser_rxrdy), .txempty(ser_txempty), .syndet(ser_syndet)
  );

  assign tw_rxd   = {on_uart[2] ? ser_rxd : 1'b1, on_uart[1] ? ser_rxd : 1'b1};
  assign tw_cts_n = {on_uart[2] && ser_cts_n, on_uart[1] && ser_cts_n};
  assign tw_dsr_n = {on_uart[2] && ser_dsr_n, on_uart[1] && ser_dsr_n};

  // A twin channel picked with the card out leaves the UART idle.
  always_comb begin
    ser_txd   = mb_txd;
    ser_rts_n = mb_rts_n;
    ser_dtr_n = mb_dtr_n;
    if (!on_uart[0]) begin
      ser_txd   = !cfg_twin || (on_uart[1] ? tw_txd[0]   : tw_txd[1]);
      ser_rts_n = !cfg_twin || (on_uart[1] ? tw_rts_n[0] : tw_rts_n[1]);
      ser_dtr_n = !cfg_twin || (on_uart[1] ? tw_dtr_n[0] : tw_dtr_n[1]);
    end
  end
  logic unused_usart;
  assign unused_usart = &{1'b0, kbd_txempty, kbd_syndet, kbd_dtr_n, kbd_rts_n,
                          ser_txrdy, ser_txempty, ser_syndet};

  // ------------------------------------------------------------ keyboard
  // Keys typed while the OSD is open belong to the OSD.
  logic [10:0] key_q;
  always_ff @(posedge clk) begin
    if (!rst_n)           key_q <= 11'd0;
    else if (!osd_active) key_q <= ps2_key;
  end

  logic kbd_overflow;
  m20_kbd u_kbd (
    .clk, .rst_n, .ps2_key(key_q), .kbd_layout(4'd0),
    .kbd_txd, .kbd_rxd, .beep, .kbd_overflow
  );
  logic unused_kbd;
  assign unused_kbd = &{1'b0, kbd_overflow};

  // ---------------------------------------------------------------- floppy
  m20_fdc u_fdc (
    .clk, .rst_n, .ce_fdc,
    .cs_fdc, .io_addr(io_addr[2:1]), .io_wdata(io_wdata[7:0]), .io_rd, .io_wr, .io_rd_end, .io_wr_end,
    .fdc_rdata, .intrq(fdc_intrq), .drq(fdc_drq), .busy(fdc_busy),
    .fdc_ds, .fdc_motor, .fdc_dden_n, .fdc_tg43,
    .d_mounted(fd_mounted), .d_readonly(fd_readonly), .d_size(fd_size),
    .d_lba(fd_lba), .d_rd(fd_rd), .d_wr(fd_wr), .d_ack(fd_ack),
    .d_buff_addr(fd_buff_addr), .d_buff_dout(fd_buff_dout), .d_buff_din(fd_buff_din),
    .d_buff_wr(fd_buff_wr)
  );

  assign led_fdd = |fdc_ds;

  // ------------------------------------------------------------- hard disk
  m20_hdc u_hdc (
    .clk, .rst_n,
    .io_addr, .io_wdata, .io_rd, .io_wr, .io_rd_end, .io_wr_end,
    .sel(hd_sel), .rdata(hd_rdata), .intrq(hdc_intrq),
    .d_mounted(hd_mounted), .d_readonly(fd_readonly), .d_size(fd_size),
    .d_lba(hd_lba), .d_rd(hd_rd), .d_wr(hd_wr), .d_ack(hd_ack),
    .d_buff_addr(fd_buff_addr), .d_buff_dout(fd_buff_dout), .d_buff_din(hd_buff_din),
    .d_buff_wr(fd_buff_wr)
  );

  logic unused_io;
  assign unused_io = &{1'b0, io_addr[15:3], io_addr[0], io_wdata[15:8]};

endmodule

`default_nettype wire
