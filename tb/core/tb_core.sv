// Whole machine: m20_core with a latency-modelled SDRAM (sdram_lat), the
// shell's disk_stream fed by an image-backed hps_io block server (PCOS on
// drive 0), boot.rom downloaded through the ioctl port, and a scripted PS/2
// key injector.  The real peripherals answer every boot ROM probe.
//
// Progress (boot ROM 1.0 labels): ordered milestones reset ->
// check_devices -> chk_intrs -> chk_disk -> pwrup_boot -> L148 (boot block
// read) -> jump to the loaded program; then PCOS runs from DRAM.  A ROM
// failure label or a ROM halt loop (jr t,.) ends the run.  Every new drive
// LBA is logged.  Frames are taken from the video outputs (active area,
// ce_pix) and written to <out>/frame_<n>.ppm when they change, at most
// every +fevery frames, and <out>/last.ppm at the end.
//
// Keys: +keys=<text> is typed once the disk has been quiet for +kquiet
// clocks after the ROM was left (letters, digits, space, '.', ',';
// '~' = RETURN, '`' = wait 1 s, then until the disks are quiet; a RETURN is
// added at the end).  The run then continues for
// +kpost clocks after the last key, or until the disk is quiet again.
//
// Plusargs: +rom=<file> (8 or 16 KB) +img=<file> +out=<dir> +maxclk=<n> +cfg=<n> +za=<n> +spare1=<n>
//   +hd=<file> (hard disk 0 image)
//   +ext=<file> (extension ROM, up to 48 KB)  +ieee +twin (cards fitted)
//   +bootkey=<c> (key pressed when the ROM first reads the keyboard data port)
//   +stoppc=<hex> (end the run, passing, at the first IF1 of <seg>offset, e.g. 74010)
//   +dumpmem=<clk> (DRAM dump at the first /SEGT after clk) +dumpend (DRAM dump at the end)
//   +watchw=<hex> (log writes to one DRAM word)
//   +pctrace=<from> +pcto=<to> (IF1 and data read trace window, clocks)  +iolog=<from> (I/O log)
//   +rom20 (labels off: ROM 2.0 has other addresses)
//   +apb=<file> (APB card fitted, apb.rom) +apbkeys=<text> (typed +apbkdelay clocks
//   after the first /NMI, the ROM's card probe); the 8086 start counts as leaving
//   the ROM.  With the card, key '^' is COMMAND+RESET (code 0x90).
//   +kgap=<clk> sets the gap after each key (default 80 ms).
`default_nettype none
module tb_core;
  import z8000_zbus_pkg::*;
  import "DPI-C" function int img_wr(input string path, input int off, input byte b);
  import "DPI-C" function void fb_set(input int x, input int y, input int rgb);
  import "DPI-C" function int fb_hash(input int w, input int h);
  import "DPI-C" function int fb_dump(input string path, input int w, input int h);

  localparam int IMG_MX = 655360;
  localparam int HD_MX  = 180 * 99 * 512;

  logic clk = 1'b0;
  always #10417 clk = ~clk;          // 48 MHz

  logic ds_rst_n = 1'b0;              // shell side (SDRAM, disk_stream): PLL lock
  logic rst_n = 1'b0;                 // machine reset
  logic [2:0] cfg = 3'd5;
  logic       za = 1'b1;
  logic       spare1 = 1'b1;
  logic        rom_wr = 1'b0;
  logic [15:0] rom_addr = 16'd0;
  logic [7:0]  rom_data = 8'd0;
  logic        rom_ext = 1'b0, rom_start = 1'b0;
  logic        cfg_ieee = 1'b0, cfg_twin = 1'b0;
  logic [10:0] ps2_key = 11'd0;
  logic        apb_fitted = 1'b0, apb_ld_we = 1'b0, apb_run;
  logic [14:0] apb_ld_addr = '0;
  logic [7:0]  apb_ld_data = '0;

  // ---- SDRAM ----
  logic [23:1] mem_addr;
  logic mem_rd, mem_wr, mem_rvalid, mem_ack, mem_ready, mem_refresh_ok;
  logic [1:0] mem_be;
  logic [15:0] mem_wdata, mem_rdata;
  int n_rd, n_wr;
  sdram_lat u_sdram (
    .clk(clk), .rst_n(ds_rst_n), .addr(mem_addr), .rd(mem_rd), .wr(mem_wr), .be(mem_be),
    .wdata(mem_wdata), .refresh_ok(mem_refresh_ok), .rdata(mem_rdata), .rvalid(mem_rvalid),
    .ack(mem_ack), .ready(mem_ready), .n_rd(n_rd), .n_wr(n_wr)
  );

  // ---- disk_stream and the hps_io block server ----
  logic [3:0]        img_mounted = '0;
  logic              img_readonly = 1'b0;
  logic [63:0]       img_size = '0;
  logic [3:0][31:0]  h_lba;
  logic [3:0][5:0]   h_blk_cnt;
  logic [3:0]        h_rd, h_wr;
  logic [3:0]        h_ack = '0;
  logic [13:0]       h_buff_addr = '0;
  logic [7:0]        h_buff_dout = '0;
  logic [7:0]        h_buff_din;
  logic              h_buff_wr = 1'b0;
  logic [3:0]        d_mounted;
  logic              d_readonly;
  logic [63:0]       d_size;
  logic [3:0]        d_ack;
  logic [8:0]        d_buff_addr;
  logic [7:0]        d_buff_dout;
  logic              d_buff_wr;
  logic [3:0]        resident;
  logic              ds_busy, wb_busy, fmt_full;
  logic [1:0][15:0]  ld_min, ld_max;
  logic [1:0][31:0]  fd_lba;
  logic [1:0]        fd_rd, fd_wr;
  logic [1:0][7:0]   fd_din;
  logic [1:0][31:0]  hd_lba;
  logic [1:0]        hd_rd, hd_wr;
  logic [1:0][7:0]   hd_din;

  disk_stream #(.UMAX(99)) u_ds (
    .clk(clk), .rst_n(ds_rst_n), .core_rst_n(rst_n), .bpc({12'd99, 12'd99}),
    .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
    .h_lba(h_lba), .h_blk_cnt(h_blk_cnt), .h_rd(h_rd), .h_wr(h_wr), .h_ack(h_ack),
    .h_buff_addr(h_buff_addr), .h_buff_dout(h_buff_dout), .h_buff_din(h_buff_din),
    .h_buff_wr(h_buff_wr),
    .d_mounted(d_mounted), .d_readonly(d_readonly), .d_size(d_size),
    .d_lba({hd_lba, fd_lba}), .d_scr(4'b0000),
    .d_rd({hd_rd, fd_rd}), .d_wr({hd_wr, fd_wr}), .d_ack(d_ack),
    .d_buff_addr(d_buff_addr), .d_buff_dout(d_buff_dout), .d_buff_din({hd_din, fd_din}),
    .d_buff_wr(d_buff_wr),
    .resident(resident), .busy(ds_busy), .wb_busy(wb_busy), .fmt_full(fmt_full),
    .ld_min(ld_min), .ld_max(ld_max)
  );

  // ---- machine ----
  logic ce_pix, hsync, vsync, hblank, vblank, beep, led_fdd, ser_txd, ser_rts_n, ser_dtr_n;
  logic [7:0] vid_r, vid_g, vid_b;
  m20_core dut (
    .clk(clk), .rst_n(rst_n), .cfg_code(cfg), .cfg_za(za), .cfg_spare1(spare1),
    .cfg_ieee(cfg_ieee), .cfg_twin(cfg_twin), .ser_sel(2'd0),
    .rom_wr(rom_wr), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ext(rom_ext), .rom_start(rom_start),
    .apb_fitted(apb_fitted), .apb_ld_we(apb_ld_we), .apb_ld_addr(apb_ld_addr),
    .apb_ld_data(apb_ld_data), .apb_run(apb_run),
    .mem_addr(mem_addr), .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_be(mem_be),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_rvalid(mem_rvalid), .mem_ack(mem_ack),
    .mem_ready(mem_ready), .mem_refresh_ok(mem_refresh_ok),
    .fd_mounted(d_mounted[1:0]), .fd_readonly(d_readonly), .fd_size(d_size),
    .fd_lba(fd_lba), .fd_rd(fd_rd), .fd_wr(fd_wr), .fd_ack(d_ack[1:0]),
    .fd_buff_addr(d_buff_addr), .fd_buff_dout(d_buff_dout), .fd_buff_din(fd_din),
    .fd_buff_wr(d_buff_wr),
    .hd_mounted(d_mounted[3:2]), .hd_lba(hd_lba), .hd_rd(hd_rd), .hd_wr(hd_wr),
    .hd_ack(d_ack[3:2]), .hd_buff_din(hd_din),
    .ps2_key(ps2_key), .osd_active(1'b0),
    .ser_rxd(1'b1), .ser_txd(ser_txd),
    .ser_rts_n(ser_rts_n), .ser_dtr_n(ser_dtr_n),
    .ce_pix(ce_pix), .vid_r(vid_r), .vid_g(vid_g), .vid_b(vid_b),
    .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
    .beep(beep), .led_fdd(led_fdd)
  );

  // ---- run state ----
  string  img_file, out_dir, keys, hd_file;
  int     img_sz = 0, hd_sz = 0;
  logic [7:0] img [IMG_MX];
  logic [7:0] hd_img [HD_MX];
  longint clk_n = 0, maxclk = 64'd1_500_000_000;
  longint last_disk = 0;
  longint kquiet;
  longint pctrace_from = -1, pctrace_to = -1;
  bit     labels = 1;
  longint iolog_from = -1;
  int     errors = 0;
  bit     done = 0;
  bit     stop_hit = 0;
  string  end_reason = "maxclk";

  task automatic fail(input string msg);
    $display("FAIL clk=%0d: %s", clk_n, msg);
    errors++;
  endtask

  function automatic real ms();
    return real'(clk_n) / 48000.0;
  endfunction

  // ---- hps_io block server (slot 0 = drive 0 image, slot 2 = +hd image) ----
  int hps_reads = 0, hps_writes = 0;
  initial begin : server
    forever begin
      @(posedge clk);
      for (int s = 0; s < 4; s++) begin
        if (ds_rst_n && (h_rd[s] || h_wr[s])) begin
          automatic int base = int'(h_lba[s]) * 512;
          automatic int n    = (int'(h_blk_cnt[s]) + 1) * 512;
          automatic bit w    = h_wr[s];
          h_ack[s] <= 1'b1;
          repeat (3) @(posedge clk);
          for (int i = 0; i < n; i++) begin
            h_buff_addr <= 14'(i);
            if (!w) begin
              h_buff_dout <= (s == 0 && base + i < img_sz) ? img[base + i] :
                             (s == 2 && base + i < hd_sz) ? hd_img[base + i] : 8'h00;
              h_buff_wr <= 1'b1;
              @(posedge clk);
              h_buff_wr <= 1'b0;
              @(posedge clk);
            end else begin
              @(posedge clk);
              @(posedge clk);
              if (s == 0 && base + i < img_sz && img[base + i] != h_buff_din) begin
                img[base + i] = h_buff_din;
                void'(img_wr(img_file, base + i, h_buff_din));
              end
              if (s == 2 && base + i < hd_sz && hd_img[base + i] != h_buff_din) begin
                hd_img[base + i] = h_buff_din;
                void'(img_wr(hd_file, base + i, h_buff_din));
              end
            end
          end
          if (w) hps_writes++; else hps_reads++;
          if (s == 2) last_disk = clk_n;
          $display("[%9.3f ms] hps %s slot %0d lba %0d x%0d", ms(), w ? "write" : "read", s,
                   h_lba[s], int'(h_blk_cnt[s]) + 1);
          h_ack[s] <= 1'b0;
          repeat (4) @(posedge clk);
        end
      end
    end
  end

  // ---- drive requests ----
  int     n_lba = 0, n_lba_wr = 0;
  logic [1:0] fd_rd_q = 2'b00, fd_wr_q = 2'b00;
  always @(posedge clk) begin
    for (int d = 0; d < 2; d++) begin
      if (fd_rd[d] && !fd_rd_q[d]) begin
        n_lba++;
        last_disk = clk_n;
        if (n_lba <= 400)
          $display("[%9.3f ms] drive %0d read  lba %0d (cyl %0d side %0d sec %0d-%0d)", ms(), d, fd_lba[d],
                   fd_lba[d] / 16, (fd_lba[d] / 8) % 2, (fd_lba[d] % 8) * 2 + 1, (fd_lba[d] % 8) * 2 + 2);
      end
      if (fd_wr[d] && !fd_wr_q[d]) begin
        n_lba_wr++;
        last_disk = clk_n;
        $display("[%9.3f ms] drive %0d write lba %0d", ms(), d, fd_lba[d]);
      end
    end
    fd_rd_q <= fd_rd;
    fd_wr_q <= fd_wr;
  end

  // ---- CPU monitor ----
  wire        as_n = dut.u_mb.cpu_as_n, ds_n = dut.u_mb.cpu_ds_n;
  wire [15:0] ad   = dut.u_mb.cpu_ad_out;
  wire [6:0]  sn   = dut.u_mb.cpu_sn;
  wire [3:0]  st   = dut.u_mb.cpu_st;
  wire        rw   = dut.u_mb.cpu_r_w;

  function automatic string label(input logic [15:0] pc);
    case (pc)
      16'h0150: return "reset";
      16'h0268: return "haltsys";
      16'h02E0: return "haltsys2";
      16'h0344: return "haltsys3";
      16'h044E: return "finish1";
      16'h0490: return "memtest";
      16'h0584: return "mt_eb_mismatch";
      16'h06A6: return "memtest_err";
      16'h06FC: return "haltsys4";
      16'h06FE: return "memtest_ok";
      16'h076E: return "segv";
      16'h077A: return "nmi_halt";
      16'h0800: return "check_devices";
      16'h095C: return "device_check_failed";
      16'h0966: return "chk_keyboard";
      16'h09C2: return "keyb_chk_failed";
      16'h09DC: return "chk_intrs";
      16'h09FA: return "nvi_test_ok";
      16'h0A10: return "intr_test_failed";
      16'h0A1C: return "vec_int4";
      16'h0A3C: return "chk_disk";
      16'h0A96: return "L70 (disk error)";
      16'h0AA6: return "L71 (boot drive found)";
      16'h0AE0: return "sub4 (error print)";
      16'h0AF8: return "sub9 halt";
      16'h0B76: return "disk_init";
      16'h0BAE: return "disk_io";
      16'h1070: return "pwrup_boot";
      16'h107A: return "cold_boot";
      16'h10B6: return "L145 (boot loader)";
      16'h1116: return "L148 (boot block read)";
      16'h1184: return "L156 (load loop)";
      16'h11F2: return "L152 (load done)";
      16'h121A: return "boot checks passed";
      16'h125C: return "jp @rr12 (enter loaded program)";
      16'h1430: return "L149";
      16'h145A: return "L147 (disk error)";
      16'h146E: return "L150 (boot error)";
      16'h14C0: return "L165 (wait for key)";
      16'h1BB0: return "screen_init";
      default:  return "";
    endcase
  endfunction
  function automatic bit is_fail_label(input logic [15:0] pc);
    return pc inside {16'h0268, 16'h02E0, 16'h0344, 16'h0584, 16'h06A6, 16'h06FC, 16'h077A,
                      16'h095C, 16'h09C2, 16'h0A10, 16'h0A96, 16'h0AF8, 16'h145A, 16'h146E};
  endfunction

  bit     visited [int];
  bit     seg_seen [int];
  bit     page_seen [int];
  int     n_pages = 0;
  logic   p_as = 1'b1, p_ds = 1'b1;
  logic [15:0] c_addr, c_wdata; logic [6:0] c_sn; logic [3:0] c_st; logic c_rw;
  logic [22:0] last_pc = '1;
  int     same_pc = 0;
  bit     left_rom = 0;
  longint t_left_rom = 0;
  int     n_if1 = 0;

  always @(posedge clk) if (rst_n) begin
    clk_n++;
    if (p_ds && !ds_n && !c_rw) c_wdata = ad;
    if (!p_ds && ds_n && c_st == ST_IO && iolog_from >= 0 && clk_n >= iolog_from && !c_rw)
      io_event($sformatf("OUT %04h <- %04h", c_addr, c_wdata));
    if (p_as && !as_n) begin
      c_addr = ad; c_sn = sn; c_st = st; c_rw = rw;
    end
    // read data as the CPU takes it
    if (dut.u_mb.cpu_clk_rise && dut.u_mb.u58.bus_done && c_rw) begin
      logic [15:0] got;
      got = dut.u_mb.ad_q;
      if (c_st == ST_IO && iolog_from >= 0 && clk_n >= iolog_from) io_event($sformatf("IN  %04h -> %04h", c_addr, got));
      if (c_st == ST_IO && c_addr == 16'h00A1 && !kbd_read_seen) begin
        kbd_read_seen = 1;
        $display("[%9.3f ms] first keyboard data read", ms());
      end
      if (c_st == ST_INSTR_FETCH_FIRST) on_if1({c_sn, c_addr}, got);
      if (c_st == ST_DATA_MEM && clk_n >= pctrace_from && clk_n <= pctrace_to)
        $display("[%9.3f ms] RD  <%02h>%04h -> %04h", ms(), c_sn, c_addr, got);
    end
    p_as = as_n; p_ds = ds_n;
  end

  // ---- APB: 8086 runs and its I/O ----
  logic p_run = 1'b0, p_nmi = 1'b1;
  int   n_nmi = 0, n_runs = 0;
  longint t_nmi0 = -1;
  always @(posedge clk) if (rst_n) begin
    if (p_nmi && !dut.ext_nmi_n) begin
      n_nmi++;
      if (t_nmi0 < 0) t_nmi0 = clk_n;
      $display("[%9.3f ms] /NMI (card handshake) %0d", ms(), n_nmi);
    end
    if (apb_run != p_run) begin
      $display("[%9.3f ms] APB run %0d", ms(), apb_run);
      if (apb_run) begin
        n_runs++;
        if (!left_rom) begin
          left_rom = 1;
          t_left_rom = clk_n;
          $display("[%9.3f ms] milestone: 8086 started", ms());
        end
      end
    end
    p_nmi = dut.ext_nmi_n;
    p_run = apb_run;
  end

  // +apbring=<hex word>: when an 8086 read of the vector table returns this
  // word, print the last 4096 8086 requests (ROM fetches only where the flow jumps; the delay loop left out)
  int   apbring = -1;
  string ring [4096];
  int   ring_n = 0;
  bit   ring_done = 0;
  logic [19:0] ring_a;
  logic ring_rd, ring_io;
  logic [19:0] ring_f = '0;
  // +apbwa=<hex addr> +apbwd=<hex word>: the same on an 8086 write of that word there
  int   apbwa = -1, apbwd = 0;
  // +apbnone=<clk> +apbtop=<hex>: the same on the first 8086 read from apbtop-DFFFF from that clock
  longint apbnone = -1;
  int     apbtop = 'h1C000;
  initial void'($value$plusargs("apbtop=%h", apbtop));
  initial void'($value$plusargs("apbnone=%d", apbnone));
  initial void'($value$plusargs("apbring=%h", apbring));
  initial void'($value$plusargs("apbwa=%h", apbwa));
  initial void'($value$plusargs("apbwd=%h", apbwd));
  always @(posedge clk) if (apbring >= 0 && !ring_done) begin
    if (dut.u_apb.start && !(dut.u_apb.c_addr >= 20'hFE434 && dut.u_apb.c_addr < 20'hFE44A) &&
        !(dut.u_apb.c_rd && !dut.u_apb.c_io && dut.u_apb.c_addr[19:14] == 6'h3F &&
          (dut.u_apb.c_addr == ring_f + 20'd2 || dut.u_apb.c_addr == ring_f + 20'd1))) begin
      ring[ring_n++ % 4096] = $sformatf("[%9.3f ms] %s%s %05h w%0d d %04h", ms(),
        dut.u_apb.c_inta ? "inta" : dut.u_apb.c_wr ? "wr" : "rd", dut.u_apb.c_io ? " io" : "",
        dut.u_apb.c_addr, dut.u_apb.c_word, dut.u_apb.c_dout);
    end
    if (dut.u_apb.start) begin
      ring_a  = dut.u_apb.c_addr;
      ring_rd = dut.u_apb.c_rd && !dut.u_apb.c_io;
      ring_io = dut.u_apb.c_rd && dut.u_apb.c_io;
      if (dut.u_apb.c_rd && !dut.u_apb.c_io && dut.u_apb.c_addr[19:14] == 6'h3F) ring_f = dut.u_apb.c_addr;
    end
    if (dut.u_apb.start && dut.u_apb.c_rd && !dut.u_apb.c_io && dut.u_apb.c_addr >= 20'(apbtop) &&
        dut.u_apb.c_addr < 20'hE0000 && apbnone >= 0 && clk_n >= apbnone) begin
      for (int i = ring_n - 4096; i < ring_n; i++) if (i >= 0) $display("%s", ring[i % 4096]);
      $display("[%9.3f ms] read above the memory top %05h", ms(), dut.u_apb.c_addr);
      ring_done = 1;
    end
    if (dut.u_apb.start && dut.u_apb.c_wr && !dut.u_apb.c_io && apbwa >= 0 &&
        dut.u_apb.c_addr == 20'(apbwa) && dut.u_apb.c_dout == 16'(apbwd)) begin
      for (int i = ring_n - 4096; i < ring_n; i++) if (i >= 0) $display("%s", ring[i % 4096]);
      ring_done = 1;
    end
    if (dut.u_apb.c_ready && dut.u_apb.ce8) begin
      if (ring_io) ring[ring_n++ % 4096] = $sformatf("    in %04h", dut.u_apb.c_din);
      if (ring_rd && ring_a < 20'h00400 && dut.u_apb.c_din == 16'(apbring)) begin
        for (int i = ring_n - 4096; i < ring_n; i++) if (i >= 0) $display("%s", ring[i % 4096]);
        ring_done = 1;
      end
    end
  end

  // +fdclog: FD1797 register writes and command ends
  logic p_intrq = 1'b0;
  always @(posedge clk) if (rst_n && $test$plusargs("fdclog")) begin
    if (dut.u_fdc.ev_wr)
      $display("[%9.3f ms] FDC reg %0d <= %02h", ms(), dut.u_fdc.acc_a, dut.u_fdc.acc_d);
    if (dut.u_fdc.intrq && !p_intrq)
      $display("[%9.3f ms] FDC INTRQ, status %02h, %0d LBA reads", ms(), dut.u_fdc.status, n_lba);
    p_intrq <= dut.u_fdc.intrq;
  end
  // +apbdump=<clk>: print the 8086 request ring at that clock
  longint apbdump = -1;
  initial void'($value$plusargs("apbdump=%d", apbdump));
  always @(posedge clk) if (apbdump >= 0 && clk_n == apbdump && !ring_done) begin
    for (int i = ring_n - 4096; i < ring_n; i++) if (i >= 0) $display("%s", ring[i % 4096]);
    ring_done = 1;
  end

  // +watchw=<hex>: log CPU writes to one DRAM word (mem_addr[23:1])
  int   watchw = -1;
  logic p_mem_wr = 1'b0;
  initial void'($value$plusargs("watchw=%h", watchw));
  always @(posedge clk) begin
    if (watchw >= 0 && mem_wr && !p_mem_wr && mem_addr == 23'(watchw))
      $display("[%9.3f ms] WATCH %06h <= %04h be %b, last IF1 <%02h>%04h", ms(), {mem_addr, 1'b0},
               mem_wdata, mem_be, last_pc[22:16], last_pc[15:0]);
    p_mem_wr = mem_wr;
  end

  // /SEGT: report the trapping access; +dumpmem writes DRAM at the first one after it
  logic p_segt_n = 1'b1;
  bit   segt_dumped = 0;
  longint dumpmem_from = -1;
  initial void'($value$plusargs("dumpmem=%d", dumpmem_from));
  always @(posedge clk) if (rst_n) begin
    if (p_segt_n && !dut.u_mb.segt_n_q) begin
      $display("[%9.3f ms] SEGT: status %h <%02h>%04h %s, last IF1 <%02h>%04h", ms(), c_st, c_sn, c_addr,
               c_rw ? "read" : "write", last_pc[22:16], last_pc[15:0]);
      if (!segt_dumped && dumpmem_from >= 0 && clk_n >= dumpmem_from) begin
        $writememh({out_dir, "/dram.hex"}, u_sdram.mem);
        segt_dumped = 1;
      end
    end
    p_segt_n = dut.u_mb.segt_n_q;
  end

  // I/O log: runs of identical accesses (polling) print once with a count
  string io_last = "";
  int    io_rep = 0;
  task automatic io_event(input string e);
    if (e == io_last) begin io_rep++; return; end
    if (io_rep > 0) $display("             (x%0d)", io_rep + 1);
    $display("[%9.3f ms] %s", ms(), e);
    io_last = e;
    io_rep = 0;
  endtask

  bit kbd_read_seen = 0;
  int stoppc = -1;
  task automatic on_if1(input logic [22:0] pc, input logic [15:0] op);
    n_if1++;
    if (stoppc >= 0 && {pc[22:16], pc[15:0]} == 23'(stoppc) && !done) begin
      $display("[%9.3f ms] milestone: reached <%02h>%04h (+stoppc)", ms(), pc[22:16], pc[15:0]);
      end_reason = "stoppc";
      stop_hit = 1;
      done = 1;
    end
    if (clk_n >= pctrace_from && clk_n <= pctrace_to)
      $display("[%9.3f ms] IF1 <%02h>%04h %04h", ms(), pc[22:16], pc[15:0], op);
    if (pc == last_pc && op == 16'hE8FF) same_pc++; else same_pc = 0;
    last_pc = pc;
    if (pc[22:16] == 7'h04) begin
      if (labels && label(pc[15:0]) != "" && !visited.exists(int'(pc[15:0]))) begin
        visited[int'(pc[15:0])] = 1;
        $display("[%9.3f ms] milestone <04>%04h %s", ms(), pc[15:0], label(pc[15:0]));
        if (is_fail_label(pc[15:0])) fail($sformatf("ROM reached %s", label(pc[15:0])));
      end
      if (same_pc == 200) begin
        fail($sformatf("ROM halted in jr t,. at <04>%04h", pc[15:0]));
        end_reason = "ROM halt";
        done = 1;
      end
    end else begin
      if (!left_rom) begin
        left_rom = 1;
        t_left_rom = clk_n;
        $display("[%9.3f ms] milestone: left the ROM, first IF1 <%02h>%04h", ms(), pc[22:16], pc[15:0]);
      end
      if (!seg_seen.exists(int'(pc[22:16]))) begin
        seg_seen[int'(pc[22:16])] = 1;
        $display("[%9.3f ms] first IF1 in segment %02h at %04h", ms(), pc[22:16], pc[15:0]);
      end
      if (!page_seen.exists(int'(pc[22:8])) && n_pages < 200) begin
        page_seen[int'(pc[22:8])] = 1;
        n_pages++;
        if (n_pages <= 60) $display("[%9.3f ms] new code page <%02h>%02hxx", ms(), pc[22:16], pc[15:8]);
      end
      if (same_pc == 2000) $display("[%9.3f ms] note: jr t,. at <%02h>%04h", ms(), pc[22:16], pc[15:0]);
    end
  endtask

  // ---- frames ----
  // Sampled at the clock edge: the values the video mixer takes when ce_pix is high.
  int  ax = 0, ay = 0, fw = 0, fh = 0, frames = 0, n_dump = 0, last_hash = 0, fevery = 25;
  int  last_dump_frame = -1000;
  logic phb = 1'b1, pvb = 1'b1;
  bit  dump_req = 0;
  string dump_name;
  always @(posedge clk) if (ce_pix) begin
    if (!vblank && pvb) begin ax = 0; ay = 0; end
    if (!hblank && !vblank) begin
      fb_set(ax, ay, {8'h00, vid_r, vid_g, vid_b});
      ax++;
    end
    if (hblank && !phb && !vblank) begin
      if (ax > 0) begin fw = ax; ay++; end
      ax = 0;
    end
    if (vblank && !pvb) begin
      fh = ay;
      frames++;
      if (fw > 0 && fh > 0) begin
        if (dump_req) begin
          void'(fb_dump({out_dir, "/", dump_name}, fw, fh));
          $display("[%9.3f ms] frame %0d (%0dx%0d) -> %s/%s", ms(), frames, fw, fh, out_dir, dump_name);
          dump_req = 0;
        end
        if (frames - last_dump_frame >= fevery) begin
          int hsh;
          hsh = fb_hash(fw, fh);
          if (hsh != last_hash) begin
            string f;
            f = $sformatf("frame_%03d.ppm", n_dump);
            void'(fb_dump({out_dir, "/", f}, fw, fh));
            $display("[%9.3f ms] frame %0d (%0dx%0d) -> %s/%s", ms(), frames, fw, fh, out_dir, f);
            n_dump++;
            last_hash = hsh;
            last_dump_frame = frames;
          end
        end
      end
    end
    phb = hblank; pvb = vblank;
  end

  task automatic snap(input string name);
    int f0;
    dump_name = name;
    dump_req = 1;
    f0 = frames;
    wait (frames >= f0 + 2 && !dump_req);
  endtask

  // ---- PS/2 key injector ----
  function automatic logic [8:0] ps2_code(input byte c);   // {E0, set-2 code}
    case (c)
      "a": return 9'h01C; "b": return 9'h032; "c": return 9'h021; "d": return 9'h023;
      "e": return 9'h024; "f": return 9'h02B; "g": return 9'h034; "h": return 9'h033;
      "i": return 9'h043; "j": return 9'h03B; "k": return 9'h042; "l": return 9'h04B;
      "m": return 9'h03A; "n": return 9'h031; "o": return 9'h044; "p": return 9'h04D;
      "q": return 9'h015; "r": return 9'h02D; "s": return 9'h01B; "t": return 9'h02C;
      "u": return 9'h03C; "v": return 9'h02A; "w": return 9'h01D; "x": return 9'h022;
      "y": return 9'h035; "z": return 9'h01A;
      "0": return 9'h045; "1": return 9'h016; "2": return 9'h01E; "3": return 9'h026;
      "4": return 9'h025; "5": return 9'h02E; "6": return 9'h036; "7": return 9'h03D;
      "8": return 9'h03E; "9": return 9'h046;
      " ": return 9'h029; ".": return 9'h049; ",": return 9'h041; "~": return 9'h05A;
      default: return 9'h000;
    endcase
  endfunction

  task automatic key_event(input logic [8:0] code, input bit press);
    @(posedge clk);
    ps2_key <= {~ps2_key[10], press, code};
  endtask

  longint kgap = 64'd3_840_000;
  initial void'($value$plusargs("kgap=%d", kgap));

  task automatic type_keys(input string s);
    for (int i = 0; i < s.len(); i++) begin
      logic [8:0] k;
      if (s[i] == "`") begin
        $display("[%9.3f ms] waiting for the disks to be quiet", ms());
        repeat (48_000_000) @(posedge clk);
        while (clk_n - last_disk <= kquiet && clk_n < maxclk) @(posedge clk);
        continue;
      end
      if (s[i] == "^" && apb_fitted) begin
        $display("[%9.3f ms] key COMMAND+RESET", ms());
        key_event(9'h00D, 1'b1);
        repeat (480_000) @(posedge clk);
        key_event(9'h076, 1'b1);
        repeat (960_000) @(posedge clk);
        key_event(9'h076, 1'b0);
        repeat (480_000) @(posedge clk);
        key_event(9'h00D, 1'b0);
        repeat (3_840_000) @(posedge clk);
        continue;
      end
      k = ps2_code(s[i]);
      if (k == 9'h000) begin $display("key '%c' not mapped", s[i]); continue; end
      $display("[%9.3f ms] key '%s'", ms(), (s[i] == "~") ? "RETURN" : string'(s[i]));
      key_event(k, 1'b1);
      repeat (960_000) @(posedge clk);      // 20 ms held
      key_event(k, 1'b0);
      repeat (kgap) @(posedge clk);
    end
  endtask

  // ---- boot key: held for 1 s from the ROM's first keyboard read ----
  string bootkey;
  initial begin
    if ($value$plusargs("bootkey=%s", bootkey)) begin
      wait (kbd_read_seen);
      $display("[%9.3f ms] boot key '%s' pressed", ms(), bootkey);
      key_event(ps2_code(bootkey[0]), 1'b1);
      repeat (48_000_000) @(posedge clk);
      key_event(ps2_code(bootkey[0]), 1'b0);
    end
  end

  // ---- run ----
  initial begin
    int fd, n, code;
    string rom_file, ext_file;
    logic [7:0] rom_img [0:16383];
    logic [7:0] ext_img [0:49151];
    int rom_n, ext_n;
    longint kpost, status_every, next_status, apbkdelay;
    bit keys_sent, apb_keys_sent;
    string apb_file, apb_keys;

    if ($value$plusargs("cfg=%d", code)) cfg = 3'(code);
    if ($value$plusargs("za=%d", code)) za = code[0];
    if ($value$plusargs("spare1=%d", code)) spare1 = code[0];
    if (!$value$plusargs("rom=%s", rom_file)) rom_file = "boot.rom";
    if (!$value$plusargs("img=%s", img_file)) img_file = "m20_boot.img";
    if (!$value$plusargs("out=%s", out_dir)) out_dir = "out";
    if (!$value$plusargs("keys=%s", keys)) keys = "";
    void'($value$plusargs("maxclk=%d", maxclk));
    void'($value$plusargs("fevery=%d", fevery));
    void'($value$plusargs("pctrace=%d", pctrace_from));
    if (pctrace_from >= 0) begin
      pctrace_to = pctrace_from + 2_000_000;
      void'($value$plusargs("pcto=%d", pctrace_to));
    end
    kquiet = 64'd96_000_000;                // 2 s without a disk access
    void'($value$plusargs("kquiet=%d", kquiet));
    kpost = 64'd240_000_000;                // 5 s after the last key
    void'($value$plusargs("kpost=%d", kpost));
    void'($value$plusargs("iolog=%d", iolog_from));
    labels = !$test$plusargs("rom20");
    cfg_ieee = $test$plusargs("ieee");
    cfg_twin = $test$plusargs("twin");
    if ($value$plusargs("stoppc=%h", code)) stoppc = code;

    fd = $fopen(rom_file, "rb");
    if (fd == 0) $fatal(1, "cannot open %s", rom_file);
    rom_n = $fread(rom_img, fd);
    $fclose(fd);
    if (rom_n != 8192 && rom_n != 16384) $fatal(1, "%s: %0d bytes, expected 8192 or 16384", rom_file, rom_n);
    ext_n = 0;
    if ($value$plusargs("ext=%s", ext_file)) begin
      fd = $fopen(ext_file, "rb");
      if (fd == 0) $fatal(1, "cannot open %s", ext_file);
      ext_n = $fread(ext_img, fd);
      $fclose(fd);
      $display("tb_core: extension ROM %s (%0d B)", ext_file, ext_n);
    end
    if (cfg_ieee || cfg_twin) $display("tb_core: cards fitted:%s%s", cfg_ieee ? " IEEE-488" : "", cfg_twin ? " twin RS-232" : "");

    fd = $fopen(img_file, "rb");
    if (fd == 0) $fatal(1, "cannot open %s", img_file);
    img_sz = $fread(img, fd);
    $fclose(fd);
    if (img_sz != 286720 && img_sz != 368640) $fatal(1, "%s: %0d bytes, expected 286720 or 368640", img_file, img_sz);

    $display("tb_core: config code %0d, ZA %0d, rom %s, drive 0 %s (%0d B), keys \"%s\"",
             cfg, za, rom_file, img_file, img_sz, keys);

    repeat (4) @(posedge clk);
    ds_rst_n <= 1'b1;
    repeat (16) @(posedge clk);
    img_size <= 64'(img_sz);
    img_readonly <= 1'b0;
    img_mounted[0] <= 1'b1;
    repeat (8) @(posedge clk);
    img_mounted[0] <= 1'b0;
    if ($value$plusargs("hd=%s", hd_file)) begin
      fd = $fopen(hd_file, "rb");
      if (fd == 0) $fatal(1, "cannot open %s", hd_file);
      hd_sz = $fread(hd_img, fd);
      $fclose(fd);
      if (hd_sz != HD_MX) $fatal(1, "%s: %0d bytes, expected %0d", hd_file, hd_sz, HD_MX);
      $display("tb_core: hard disk 0 %s (%0d B)", hd_file, hd_sz);
      repeat (8) @(posedge clk);
      img_size <= 64'(hd_sz);
      img_mounted[2] <= 1'b1;
      repeat (8) @(posedge clk);
      img_mounted[2] <= 1'b0;
    end
    // ioctl downloads while the machine is held in reset
    @(posedge clk); rom_ext <= 1'b0; rom_start <= 1'b1;
    @(posedge clk); rom_start <= 1'b0;
    for (int i = 0; i < rom_n; i++) begin
      @(posedge clk); rom_wr <= 1'b1; rom_addr <= 16'(i); rom_data <= rom_img[i];
      @(posedge clk); rom_wr <= 1'b0;
    end
    if (ext_n > 0) begin
      @(posedge clk); rom_ext <= 1'b1; rom_start <= 1'b1;
      @(posedge clk); rom_start <= 1'b0;
      for (int i = 0; i < ext_n; i++) begin
        @(posedge clk); rom_wr <= 1'b1; rom_addr <= 16'(i); rom_data <= ext_img[i];
        @(posedge clk); rom_wr <= 1'b0;
      end
      @(posedge clk); rom_ext <= 1'b0;
    end
    if ($value$plusargs("apb=%s", apb_file)) begin
      logic [7:0] apb_img [0:18431];
      fd = $fopen(apb_file, "rb");
      if (fd == 0) $fatal(1, "cannot open %s", apb_file);
      n = $fread(apb_img, fd);
      $fclose(fd);
      if (n != 18432) $fatal(1, "%s: %0d bytes, expected 18432", apb_file, n);
      for (int i = 0; i < 18432; i++) begin
        @(posedge clk); apb_ld_we <= 1'b1; apb_ld_addr <= 15'(i); apb_ld_data <= apb_img[i];
      end
      @(posedge clk); apb_ld_we <= 1'b0;
      apb_fitted <= 1'b1;
      $display("tb_core: APB card fitted, %s", apb_file);
    end
    if (!$value$plusargs("apbkeys=%s", apb_keys)) apb_keys = "";
    apbkdelay = 64'd48_000_000;
    void'($value$plusargs("apbkdelay=%d", apbkdelay));
    wait (mem_ready);
    repeat (8) @(posedge clk);
    rst_n <= 1'b1;

    status_every = 64'd24_000_000;          // 0.5 s
    next_status = status_every;
    keys_sent = 0;
    apb_keys_sent = 0;
    while (!done && clk_n < maxclk) begin
      @(posedge clk);
      if (!apb_keys_sent && apb_keys != "" && t_nmi0 >= 0 && clk_n - t_nmi0 > apbkdelay) begin
        snap("apb_prompt.ppm");
        type_keys(apb_keys);
        apb_keys_sent = 1;
      end
      if (clk_n >= next_status) begin
        next_status += status_every;
        $display("[%9.3f ms] status: IF1 <%02h>%04h, %0d frames (%0dx%0d), %0d LBA reads, %0d hps reads, DRAM %0d rd %0d wr",
                 ms(), last_pc[22:16], last_pc[15:0], frames, fw, fh, n_lba, hps_reads, n_rd, n_wr);
      end
      if (!keys_sent && left_rom && keys != "" && clk_n - last_disk > kquiet && clk_n - t_left_rom > kquiet) begin
        snap("before_keys.ppm");
        type_keys({keys, "~"});
        keys_sent = 1;
        begin
          longint t_k;
          t_k = clk_n;
          while (clk_n - t_k < kpost && clk_n < maxclk) @(posedge clk);
        end
        end_reason = "keys typed";
        done = 1;
      end
      if (!keys_sent && left_rom && keys == "" && clk_n - last_disk > kquiet && clk_n - t_left_rom > kquiet) begin
        end_reason = "disk quiet after boot";
        done = 1;
      end
    end
    snap("last.ppm");
    if ($test$plusargs("dumpend")) $writememh({out_dir, "/dram_end.hex"}, u_sdram.mem);

    $display("end (%s): %0d clocks (%.3f s machine time), %0d frames, %0d IF1, last IF1 <%02h>%04h",
             end_reason, clk_n, real'(clk_n) / 48.0e6, frames, n_if1, last_pc[22:16], last_pc[15:0]);
    $display("     disk: %0d LBA reads, %0d LBA writes, %0d hps reads, %0d hps writes; DRAM %0d rd %0d wr",
             n_lba, n_lba_wr, hps_reads, hps_writes, n_rd, n_wr);
    if (!left_rom && !stop_hit) fail("the boot ROM never started the loaded program");
    if (stoppc >= 0 && !stop_hit) fail("+stoppc address never reached");
    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d errors", errors);
    $finish;
  end
endmodule
`default_nettype wire
