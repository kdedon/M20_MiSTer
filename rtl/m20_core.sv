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

`default_nettype none

module m20_core (
  input  logic             clk,           // 48 MHz
  input  logic             rst_n,

  // Jumpers, sampled by the shell at reset
  input  logic [2:0]       cfg_code,      // {BW^COL, 32^128, COL4^8}
  input  logic             cfg_za,        // ZA jumper, port 0x21 D3
  input  logic             cfg_spare1,    // SPARE1 jumper, port 0x21 D4

  // boot.rom download
  input  logic             rom_wr,
  input  logic [12:0]      rom_addr,
  input  logic [7:0]       rom_data,

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

  // Keyboard
  input  logic [10:0]      ps2_key,
  input  logic             osd_active,

  // RS-232 (J7)
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
  logic [15:0] pic_rdata;
  logic        pic_int, pic_inta_n;
  logic        pit_out0, pit_out1, pit_out2;
  logic        crt_fetch;
  logic [1:0]  fdc_ds;
  logic        fdc_motor, fdc_dden_n, fdc_tg43;
  logic        fdc_intrq, fdc_drq, fdc_busy;
  logic        kbd_rxrdy, kbd_txrdy, ser_rxrdy;
  logic        kbd_txd, kbd_rxd;
  logic        ppi_ir6;
  logic [7:0]  ppi_pa, ppi_pc;

  // cs_latch is decoded inside the mainboard (port 0x21 latch U15/U16).
  logic unused_ok;
  assign unused_ok = &{1'b0, ce16, cs_latch, fdc_drq, fdc_busy, fdc_motor, fdc_tg43};

  // ------------------------------------------------------------ mainboard
  m20_mainboard u_mb (
    .clk, .rst_n,
    .ce16, .ce_pit, .ce_usart, .ce_fdc,
    .cfg_code, .cfg_za, .cfg_spare1,
    .rom_wr, .rom_addr, .rom_data,
    .mem_addr, .mem_rd, .mem_wr, .mem_be, .mem_wdata, .mem_rdata, .mem_rvalid, .mem_ack,
    .mem_ready, .mem_refresh_ok,
    .vram_we, .vram_plane, .vram_addr, .vram_be, .vram_wdata,
    .io_addr, .io_wdata, .io_rd, .io_wr, .io_rd_end, .io_wr_end,
    .cs_fdc, .cs_latch, .cs_crtc, .cs_ppi, .cs_kbd, .cs_ser, .cs_pit, .cs_pic, .cs_pal,
    .fdc_rdata, .crtc_rdata, .ppi_rdata, .kbd_rdata, .ser_rdata, .pit_rdata, .pic_rdata,
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
  m20_pic u_pic (
    .clk, .rst_n, .cs_pic, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pic_rdata, .pic_inta_n, .pic_int,
    .ir_fdc(fdc_intrq), .ir_ser_rxrdy(ser_rxrdy), .ir_kbd_rxrdy(kbd_rxrdy),
    .ir_kbd_txrdy(kbd_txrdy), .ir_ppi(ppi_ir6)
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
  i8251 u_ser_usart (
    .clk, .rst_n, .ce_usart, .cs(cs_ser), .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .rdata(ser_rdata), .txc(pit_out0), .rxc(pit_out0), .rxd(ser_rxd), .txd(ser_txd),
    .cts_n(ser_cts_n), .dsr_n(ser_dsr_n), .dtr_n(ser_dtr_n), .rts_n(ser_rts_n),
    .txrdy(ser_txrdy), .rxrdy(ser_rxrdy), .txempty(ser_txempty), .syndet(ser_syndet)
  );
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

  logic unused_io;
  assign unused_io = &{1'b0, io_addr[15:3], io_addr[0], io_wdata[15:8]};

endmodule

`default_nettype wire
