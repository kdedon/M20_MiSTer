// Olivetti M20 motherboard logic around the Z8001.
//
// CPU U58, clock U12/U29, status decode U8, /AS address and
// segment latches, mapping PROM U44, SEGT U6B, boot overlay U18B, boot
// EPROMs U54/U65, DRAM through the platform RAM port, video plane snoop,
// I/O decode U39/U21, port 0x21 latch U16/U15, NVI flip-flop U92A, VI
// acknowledge (U3/U4/U5/U20), T3 stretch (U18A/U11/U28).
//
// Ports
//   clk, rst_n           48 MHz; machine reset, active low, sync release
//   ce16 ce_pit ce_usart ce_fdc        out  clock enables (m20_clkgen)
//   cfg_code[2:0]        in   configuration jumpers {BW^COL, 32^128, COL4^8}
//                             = port 0x21 D7..D5 = PROM A8, A7, A9
//   cfg_za               in   ZA jumper JP5, port 0x21 D3 (ROM 1.x: 1 = full tests)
//   cfg_spare1           in   SPARE1 jumper JP3, port 0x21 D4.  ROM 2.x reads
//                             D4:D3 as the floppy type: 0 = ask, 1 = 160K,
//                             2 = 320K, 3 = 640K (types 1-3 run the self-tests)
//   rom_wr rom_addr[12:0] rom_data[7:0]  in  boot.rom loader (ioctl index 0)
//   mem_addr[23:1] mem_rd mem_wr mem_be[1:0] mem_wdata[15:0]   out
//   mem_rdata[15:0] mem_rvalid mem_ack mem_ready               in
//   mem_refresh_ok       out  no request outstanding
//   vram_we vram_plane[1:0] vram_addr[13:1] vram_be[1:0] vram_wdata[15:0]  out
//   io_addr[15:0] io_wdata[15:0] io_rd io_wr io_rd_end io_wr_end   out
//   cs_fdc cs_latch cs_crtc cs_ppi cs_kbd cs_ser cs_pit cs_pic cs_pal  out
//   fdc_rdata crtc_rdata ppi_rdata kbd_rdata ser_rdata pit_rdata [7:0]  in
//   pic_rdata[15:0]      in   8259 word: {7'h7F, D7-D0, 1'b1}, or
//                             {7'h7F, vector, 1'b0} during the second INTA
//   pic_int              in   8259 INT (High = request) -> CPU /VI
//   pic_inta_n           out  8259 /INTA (two pulses per VI acknowledge)
//   pit_out2             in   8253 OUT2 -> NVI flip-flop
//   crt_fetch            in   one-clock pulse at each CRT DRAM fetch
//   fdc_ds[1:0] fdc_motor fdc_dden_n fdc_tg43   out  port 0x21 write latch
//
// Bus cycle timing (CPU clock rises e0..; master clocks between rises >= 12):
//   memory read   e0 /AS, e1 /DS low (DRAM read requested), e2 data taken,
//                 e3 /DS high
//   memory write  e0 /AS, e1 data on AD, e2 /DS low (DRAM write requested),
//                 e3 /DS high
// U29 is held before e2 until a DRAM read word is in, and before any rise
// while a DRAM write is outstanding.  The CRT stretch holds U29 with SCLOCK
// High in T3 (after e2) for STRETCH 16 MHz steps.
//
// Assumed: the CRT DRAM window is CRT_WIN clocks from
// crt_fetch; port 0x21 latch, boot and SEGT flip-flops reset as below; the
// U18B J input is Low; extension ROM sockets and SRAM0 read 0xFFFF; reads in
// NVI acknowledge read 0xFFFF; /WAIT, /BUSREQ, /STOP, NMI, MEMDIS inactive;
// the CPU leaves reset 8 CPU clocks after rst_n.
`default_nettype none
module m20_mainboard
  import z8000_zbus_pkg::*;
#(
  parameter int STRETCH   = 4,       // T3 stretch, 62.5 ns steps
  parameter int CRT_WIN   = 12,      // CRT DRAM window after crt_fetch, clocks
  parameter     PROM_FILE = "rtl/bus/m20_prom.hex"
) (
  input  logic        clk,
  input  logic        rst_n,

  output logic        ce16,
  output logic        ce_pit,
  output logic        ce_usart,
  output logic        ce_fdc,

  input  logic [2:0]  cfg_code,
  input  logic        cfg_za,
  input  logic        cfg_spare1,

  input  logic        rom_wr,
  input  logic [12:0] rom_addr,
  input  logic [7:0]  rom_data,

  output logic [23:1] mem_addr,
  output logic        mem_rd,
  output logic        mem_wr,
  output logic [1:0]  mem_be,
  output logic [15:0] mem_wdata,
  input  logic [15:0] mem_rdata,
  input  logic        mem_rvalid,
  input  logic        mem_ack,
  input  logic        mem_ready,
  output logic        mem_refresh_ok,

  output logic        vram_we,
  output logic [1:0]  vram_plane,
  output logic [13:1] vram_addr,
  output logic [1:0]  vram_be,
  output logic [15:0] vram_wdata,

  output logic [15:0] io_addr,
  output logic [15:0] io_wdata,
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
  input  logic [7:0]  crtc_rdata,
  input  logic [7:0]  ppi_rdata,
  input  logic [7:0]  kbd_rdata,
  input  logic [7:0]  ser_rdata,
  input  logic [7:0]  pit_rdata,
  input  logic [15:0] pic_rdata,

  input  logic        pic_int,
  output logic        pic_inta_n,
  input  logic        pit_out2,
  input  logic        crt_fetch,

  output logic [1:0]  fdc_ds,
  output logic        fdc_motor,
  output logic        fdc_dden_n,
  output logic        fdc_tg43
);
  localparam int SW = $clog2(STRETCH + 1);
  localparam int CW = $clog2(CRT_WIN + 1);

  // ---- clocks -------------------------------------------------------------
  logic       u29_hold, cpu_clk_rise, cpu_clk_fall;
  logic [1:0] u29_q;
  m20_clkgen u_clk (
    .clk(clk), .rst_n(rst_n), .hold(u29_hold),
    .ce16(ce16), .ce_pit(ce_pit), .ce_usart(ce_usart), .ce_fdc(ce_fdc),
    .cpu_clk_rise(cpu_clk_rise), .cpu_clk_fall(cpu_clk_fall), .q(u29_q)
  );

  // ---- CPU reset ----------------------------------------------------------
  // The Z8001 needs CLK running while /RESET is Low: its reset ends 8 CPU
  // clocks after the machine reset.
  // CPU clocks seen since the machine reset.
  logic [3:0] rst_cnt_q;
  logic       cpu_rst_n;
  always_ff @(posedge clk) begin
    if (!rst_n)                              rst_cnt_q <= 4'd0;
    else if (cpu_clk_rise && !rst_cnt_q[3])  rst_cnt_q <= rst_cnt_q + 4'd1;
  end
  assign cpu_rst_n = rst_cnt_q[3];

  // ---- CPU ----------------------------------------------------------------
  logic [15:0] cpu_ad_out, ad_q;
  logic        cpu_ad_drive, cpu_bus_drive;
  logic [6:0]  cpu_sn;
  logic        cpu_as_n, cpu_ds_n, cpu_mreq_n, cpu_r_w, cpu_b_w, cpu_n_s;
  logic [3:0]  cpu_st;
  logic        cpu_busack_n, cpu_mo_n;
  logic        segt_n_q, nvi_q;

  z8000_cpu #(.SEGMENTED(1'b1), .VMPU(1'b0)) u58 (
    .clk(clk), .reset_n(cpu_rst_n), .clk_in(cpu_clk_rise),
    .ad_in(ad_q), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(!nvi_q), .vi_n(!pic_int), .segt_n(segt_n_q),
    .abort_n(1'b1), .mi_n(1'b1),
    .ad_out(cpu_ad_out), .ad_drive(cpu_ad_drive), .bus_drive(cpu_bus_drive),
    .sn(cpu_sn), .as_n(cpu_as_n), .ds_n(cpu_ds_n), .mreq_n(cpu_mreq_n),
    .r_w(cpu_r_w), .b_w(cpu_b_w), .n_s(cpu_n_s), .st(cpu_st),
    .busack_n(cpu_busack_n), .mo_n(cpu_mo_n)
  );

  // ---- strobe edges -------------------------------------------------------
  // Previous /AS, /DS for edge detection.
  logic as_q, ds_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      as_q <= 1'b1;
      ds_q <= 1'b1;
    end else begin
      as_q <= cpu_as_n;
      ds_q <= cpu_ds_n;
    end
  end
  logic as_fall, as_rise, ds_fall, ds_rise;
  assign as_fall = as_q && !cpu_as_n;
  assign as_rise = !as_q && cpu_as_n;
  assign ds_fall = ds_q && !cpu_ds_n;
  assign ds_rise = !ds_q && cpu_ds_n;

  // ---- /AS latches: address (U45/U46), segment (U43), cycle status --------
  // Transparent while /AS is Low, held after.
  logic [15:0] a_q;
  logic [6:0]  sn_q;
  logic [3:0]  st_q;
  logic        rw_q, bw_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_q  <= 16'h0000;
      sn_q <= 7'd0;
      st_q <= ST_INTERNAL_OP;
      rw_q <= 1'b1;
      bw_q <= 1'b0;
    end else if (!cpu_as_n) begin
      a_q  <= cpu_ad_out;
      sn_q <= cpu_sn;
      st_q <= cpu_st;
      rw_q <= cpu_r_w;
      bw_q <= cpu_b_w;
    end
  end

  // In a bus cycle: from /AS to the clock after /DS rises.
  logic cyc_q;
  always_ff @(posedge clk) begin
    if (!rst_n)         cyc_q <= 1'b0;
    else if (!cpu_as_n) cyc_q <= 1'b1;
    else if (ds_rise)   cyc_q <= 1'b0;
  end

  // CPU clock rises since the cycle's T1 (saturating).
  logic [1:0] tst_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                             tst_q <= 2'd0;
    else if (as_fall)                       tst_q <= 2'd0;
    else if (cpu_clk_rise && tst_q != 2'd3) tst_q <= tst_q + 2'd1;
  end

  // ---- status decode (U8 for ST3 = 0; PROM enables for ST3 = 1) -----------
  logic mem_c, prom_en, io_c;
  assign mem_c   = cyc_q && st_q[3];
  assign prom_en = st_q[3] && !st_q[1];          // CE3 = ST3, *CE2 = ST1
  assign io_c    = cyc_q && (st_q == ST_IO);

  // ---- mapping PROM U44 ---------------------------------------------------
  logic [7:0] prom_q;
  m20_prom #(.INIT_FILE(PROM_FILE)) u44 (
    .clk(clk), .a14(a_q[14]), .a15(a_q[15]), .sn(sn_q[3:0]), .st2(st_q[2]),
    .j_32_128(cfg_code[1]), .j_bw(cfg_code[2]), .j_col48(cfg_code[0]), .q(prom_q)
  );

  // ---- boot overlay U18B --------------------------------------------------
  // Preset by reset; clocked by the end of each data strobe, K = A3.
  // BOOT flip-flop.
  logic boot_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                boot_q <= 1'b1;
    else if (ds_rise && a_q[3]) boot_q <= 1'b0;
  end

  // While BOOT is set every memory cycle selects the boot EPROMs (TA14,
  // TA15, TSN0 inhibited, U36 forced to O0).  ROM sockets 1-3, 7 are
  // unused; 4-6 are empty extension sockets; SRAM0 is not fitted.
  logic rom_sel, dram_sel;
  assign rom_sel  = mem_c && (boot_q || (prom_en && !prom_q[7] && prom_q[2:0] == 3'd0));
  assign dram_sel = mem_c && !boot_q && prom_en && prom_q[7] && !prom_q[5];

  // ---- SEGT U6B -----------------------------------------------------------
  // /SEGT = D at the /AS rise: Low for status 1000-1101 with SN6-SN4 != 0.
  always_ff @(posedge clk) begin
    if (!rst_n)       segt_n_q <= 1'b1;
    else if (as_rise) segt_n_q <= !(st_q[3] && !(st_q[2] && st_q[1]) && (sn_q[6:4] != 3'd0));
  end

  // ---- boot EPROMs --------------------------------------------------------
  logic [15:0] rom_q;
  m20_boot_rom u54_u65 (
    .clk(clk), .addr(a_q[12:1]), .q(rom_q),
    .ld_we(rom_wr), .ld_addr(rom_addr), .ld_data(rom_data)
  );

  // ---- DRAM ---------------------------------------------------------------
  logic rd_have, rd_hit, wr_busy, start_rd, start_wr;
  logic [1:0] be;
  assign start_rd = ds_fall && dram_sel && rw_q;
  assign start_wr = ds_fall && dram_sel && !rw_q;
  assign be       = !bw_q ? 2'b11 : (a_q[0] ? 2'b01 : 2'b10);

  m20_dram u_dram (
    .clk(clk), .rst_n(rst_n), .new_cyc(as_fall), .start_rd(start_rd), .start_wr(start_wr),
    .dev(prom_q[4:3]), .blk(prom_q[2:0]), .a(a_q[13:1]), .be(be), .wdata(cpu_ad_out),
    .rd_have(rd_have), .rd_hit(rd_hit), .wr_busy(wr_busy),
    .mem_addr(mem_addr), .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_be(mem_be),
    .mem_wdata(mem_wdata), .mem_rvalid(mem_rvalid), .mem_ack(mem_ack),
    .vram_we(vram_we), .vram_plane(vram_plane), .vram_addr(vram_addr),
    .vram_be(vram_be), .vram_wdata(vram_wdata)
  );
  assign mem_refresh_ok = !mem_rd && !mem_wr;

  // ---- T3 stretch (U18A, U11, U28) -----------------------------------------
  // CRT window left; stretch steps left this cycle.
  logic [CW-1:0] crt_win_q;
  logic [SW-1:0] str_q;
  logic          str_hold;
  always_ff @(posedge clk) begin
    if (!rst_n)                 crt_win_q <= '0;
    else if (crt_fetch)         crt_win_q <= CW'(CRT_WIN);
    else if (crt_win_q != '0)   crt_win_q <= crt_win_q - CW'(1);
  end
  // U18A J = /BOOT.FF: no stretch while the overlay is set.
  assign str_hold = (str_q != '0) && tst_q == 2'd2 && u29_q == 2'b10;
  always_ff @(posedge clk) begin
    if (!rst_n)                                           str_q <= '0;
    else if (as_fall)                                     str_q <= '0;
    else if (ds_fall && dram_sel && crt_win_q != '0 && !boot_q) str_q <= SW'(STRETCH);
    else if (str_hold && ce16)                            str_q <= str_q - SW'(1);
  end

  // ---- U29 hold -----------------------------------------------------------
  logic wait_rd;
  assign wait_rd  = dram_sel && rw_q && !cpu_ds_n && tst_q == 2'd1 && !rd_have;
  assign u29_hold = !mem_ready || str_hold ||
                    (u29_q == 2'b01 && (wait_rd || wr_busy));

  // ---- port 0x21 latch U16 (write) / U15 (read) ---------------------------
  logic [4:0]  lat_q;              // D7, D3-D0 (U16 O4-O6 open)
  logic [7:0]  lat_rd;
  logic [15:0] wd_q;
  // U16 74LS374.
  always_ff @(posedge clk) begin
    if (!rst_n)                     lat_q <= 5'h00;
    else if (io_wr_end && cs_latch) lat_q <= {wd_q[7], wd_q[3:0]};
  end
  assign lat_rd     = {cfg_code, cfg_spare1, cfg_za, lat_q[2:0]};
  assign fdc_ds     = lat_q[1:0];
  assign fdc_motor  = lat_q[2];
  assign fdc_dden_n = lat_q[3];
  assign fdc_tg43   = lat_q[4];

  // ---- I/O bus --------------------------------------------------------------
  // Write data from T2 to the end of the cycle.
  always_ff @(posedge clk) begin
    if (!rst_n)                                  wd_q <= 16'h0000;
    else if (cyc_q && cpu_as_n && cpu_ad_drive && !rw_q) wd_q <= cpu_ad_out;
  end
  assign io_addr  = a_q;
  assign io_wdata = wd_q;

  logic [15:0] io_word;
  m20_iodec u_iodec (
    .addr(a_q[15:5]), .io_cyc(io_c), .r_w(rw_q), .ds_n(cpu_ds_n), .ds_rise(ds_rise),
    .io_rd(io_rd), .io_wr(io_wr), .io_rd_end(io_rd_end), .io_wr_end(io_wr_end),
    .cs_fdc(cs_fdc), .cs_latch(cs_latch), .cs_crtc(cs_crtc), .cs_ppi(cs_ppi),
    .cs_kbd(cs_kbd), .cs_ser(cs_ser), .cs_pit(cs_pit), .cs_pic(cs_pic), .cs_pal(cs_pal),
    .fdc_rdata(fdc_rdata), .latch_rdata(lat_rd), .crtc_rdata(crtc_rdata),
    .ppi_rdata(ppi_rdata), .kbd_rdata(kbd_rdata), .ser_rdata(ser_rdata),
    .pit_rdata(pit_rdata), .pic_rdata(pic_rdata), .rdata(io_word)
  );

  // ---- interrupts -----------------------------------------------------------
  // NVI U92A: set at the OUT2 rise, cleared by the NVI acknowledge (U8 O6).
  // OUT2 edge detect, NVI flip-flop.
  logic out2_q;
  always_ff @(posedge clk) begin
    if (!rst_n) out2_q <= 1'b0;
    else        out2_q <= pit_out2;
  end
  always_ff @(posedge clk) begin
    if (!rst_n)                    nvi_q <= 1'b0;
    else if (cpu_st == ST_NVI_ACK) nvi_q <= 1'b0;
    else if (pit_out2 && !out2_q)  nvi_q <= 1'b1;
  end

  // VI acknowledge: /INTA = NAND(VI_ACK, NAND(PK041, /DS)), PK041 = /AS
  // through U5A, U5B on the SCLOCK falls.
  // U5A, U5B.
  logic u5a_q, u5b_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      u5a_q <= 1'b1;
      u5b_q <= 1'b1;
    end else if (cpu_clk_fall) begin
      u5a_q <= cpu_as_n;
      u5b_q <= u5a_q;
    end
  end
  assign pic_inta_n = !(cpu_st == ST_VI_ACK && (!u5b_q || !cpu_ds_n));

  // ---- read capture (the CPU's ad_in) -----------------------------------------
  logic [15:0] ad_d;
  always_comb begin
    ad_d = 16'hFFFF;
    if (rom_sel)                       ad_d = rom_q;
    else if (dram_sel)                 ad_d = rd_hit ? mem_rdata : ad_q;
    else if (io_c)                     ad_d = io_word;
    else if (st_q == ST_VI_ACK)        ad_d = pic_rdata;
  end
  always_ff @(posedge clk) begin
    if (!rst_n) ad_q <= 16'hFFFF;
    else        ad_q <= ad_d;
  end

  logic unused_ok;
  assign unused_ok = &{1'b0, cpu_bus_drive, cpu_mreq_n, cpu_n_s, cpu_busack_n, cpu_mo_n,
                       cpu_b_w, cpu_r_w, prom_q[6]};
endmodule
`default_nettype wire
