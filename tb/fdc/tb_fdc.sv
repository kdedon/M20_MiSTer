// m20_fdc + disk_stream against a behavioural hps_io block server.
// Slot 0 is backed by a real PCOS image file (IMG, a copy the Makefile
// makes): reads come from its bytes, writes go to the file.  Slot 1 is a
// synthetic image (byte = pattern of its offset) of 640K or 160K size.
//
// Phases, every byte compared with the image:
//   boot: status, D0, sector register 255 values, then the boot ROM's
//     disk_io sequence: select via 0x21, /DDEN per block, restore 0x03,
//     seek 0x13 + verify 0x17, read 0x88/0x8A with DRQ/BUSY polling,
//     FM 128 B on T0S0, MFM 256 B after;
//     drive 1 empty: NOT READY.
//   density: /DDEN mismatch on T0S0 and on cylinder 1 gives RNF after
//     4+ revolutions.
//   multi: 0x9A from sector 1 reads the whole track, then RNF, sector 17.
//   read address, step/step-in/step-out, seek verify error, INTRQ,
//     force interrupt (D0 abort, D8 immediate).
//   write: 0xA8 one sector, 0xB8 multi; read back; disk_stream writes the
//     dirty unit back; the file is re-read from disk and compared.
//   write track: MFM format of cylinder 4 side 1 (image file), FM format
//     of T0S0 (slot 1); sectors read back, the file checked.
//   geometry: 640K cylinder 79 side 1; 160K single sided (side 1 RNF),
//     write protect.
`timescale 1ns/1ps
`default_nettype none
module tb_fdc;
  parameter int    CE_DIV = 2;          // clocks per FD1797 1 MHz tick
  parameter string IMG    = "obj_dir/m20_test.img";

  import "DPI-C" function int img_wr(input string path, input int off, input byte b);

  localparam int IMG0_SZ = 286720;
  localparam int IMG1_MX = 655360;

  logic clk = 1'b0;
  always #10 clk = ~clk;
  logic rst_n = 1'b0;

  logic [31:0] cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  logic ce_fdc;
  int   ce_cnt = 0;
  always @(posedge clk) ce_cnt <= (ce_cnt == CE_DIV - 1) ? 0 : ce_cnt + 1;
  assign ce_fdc = ce_cnt == CE_DIV - 1;

  // ---- DUT ------------------------------------------------------------------------
  logic        cs_fdc = 1'b0, io_rd = 1'b0, io_wr = 1'b0, io_rd_end = 1'b0, io_wr_end = 1'b0;
  logic [2:1]  io_addr = 2'd0;
  logic [7:0]  io_wdata = 8'h00;
  logic [7:0]  fdc_rdata;
  logic        intrq, drq, fbusy;
  logic [1:0]  fdc_ds = 2'b00;
  logic        fdc_dden_n = 1'b0;

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
  logic [3:0][31:0]  d_lba;
  logic [3:0]        d_rd, d_wr, d_ack;
  logic [8:0]        d_buff_addr;
  logic [7:0]        d_buff_dout;
  logic [3:0][7:0]   d_buff_din;
  logic              d_buff_wr;
  logic [3:0]        resident;
  logic              ds_busy, wb_busy, fmt_full;
  logic [1:0][15:0]  ld_min, ld_max;

  logic [1:0][31:0]  f_lba;
  logic [1:0]        f_rd, f_wr;
  logic [1:0][7:0]   f_din;

  disk_stream #(.QUIET(40_000)) u_ds (
    .clk(clk), .rst_n(rst_n), .core_rst_n(rst_n), .bpc('0),
    .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
    .h_lba(h_lba), .h_blk_cnt(h_blk_cnt), .h_rd(h_rd), .h_wr(h_wr), .h_ack(h_ack),
    .h_buff_addr(h_buff_addr), .h_buff_dout(h_buff_dout), .h_buff_din(h_buff_din),
    .h_buff_wr(h_buff_wr),
    .d_mounted(d_mounted), .d_readonly(d_readonly), .d_size(d_size),
    .d_lba(d_lba), .d_scr(4'b0000), .d_rd(d_rd), .d_wr(d_wr), .d_ack(d_ack),
    .d_buff_addr(d_buff_addr), .d_buff_dout(d_buff_dout), .d_buff_din(d_buff_din),
    .d_buff_wr(d_buff_wr),
    .resident(resident), .busy(ds_busy), .wb_busy(wb_busy), .fmt_full(fmt_full),
    .ld_min(ld_min), .ld_max(ld_max)
  );
  assign d_lba[1:0]  = f_lba;
  assign d_lba[3:2]  = '0;
  assign d_rd        = {2'b00, f_rd};
  assign d_wr        = {2'b00, f_wr};
  assign d_buff_din  = {16'h0000, f_din};

  m20_fdc u_fdc (
    .clk(clk), .rst_n(rst_n), .ce_fdc(ce_fdc),
    .cs_fdc(cs_fdc), .io_addr(io_addr), .io_wdata(io_wdata), .io_rd(io_rd), .io_wr(io_wr),
    .io_rd_end(io_rd_end), .io_wr_end(io_wr_end), .fdc_rdata(fdc_rdata),
    .intrq(intrq), .drq(drq), .busy(fbusy),
    .fdc_ds(fdc_ds), .fdc_motor(1'b0), .fdc_dden_n(fdc_dden_n), .fdc_tg43(1'b0),
    .d_mounted(d_mounted[1:0]), .d_readonly(d_readonly), .d_size(d_size),
    .d_lba(f_lba), .d_rd(f_rd), .d_wr(f_wr), .d_ack(d_ack[1:0]),
    .d_buff_addr(d_buff_addr), .d_buff_dout(d_buff_dout), .d_buff_din(f_din),
    .d_buff_wr(d_buff_wr)
  );

  // ---- scoreboard -------------------------------------------------------------------
  int errors = 0, checks = 0;
  task automatic check(input bit ok, input string msg);
    checks++;
    if (!ok) begin
      errors++;
      $display("FAIL @%0d: %s", cyc, msg);
      if (errors > 20) $fatal(1, "too many failures");
    end
  endtask

  // ---- images and the hps_io block server -----------------------------------------
  logic [7:0] img0 [IMG0_SZ];
  logic [7:0] orig0 [IMG0_SZ];
  logic [7:0] img1 [IMG1_MX];
  function automatic logic [7:0] pat1(input int off);
    return off[7:0] ^ off[15:8] ^ {3'b000, off[20:16]} ^ 8'h5A;
  endfunction

  int hps_reads = 0, hps_writes = 0;
  initial begin : server
    forever begin
      @(posedge clk);
      for (int s = 0; s < 2; s++) begin
        if (h_rd[s] || h_wr[s]) begin
          automatic int base = int'(h_lba[s]) * 512;
          automatic int n    = (int'(h_blk_cnt[s]) + 1) * 512;
          automatic bit w    = h_wr[s];
          h_ack[s] <= 1'b1;
          repeat (3) @(posedge clk);
          for (int i = 0; i < n; i++) begin
            h_buff_addr <= 14'(i);
            if (!w) begin
              h_buff_dout <= (s == 0) ? ((base + i < IMG0_SZ) ? img0[base + i] : 8'h00)
                                      : ((base + i < IMG1_MX) ? img1[base + i] : 8'h00);
              h_buff_wr <= 1'b1;
              @(posedge clk);
              h_buff_wr <= 1'b0;
              @(posedge clk);
            end else begin
              @(posedge clk);
              @(posedge clk);
              if (s == 0 && base + i < IMG0_SZ) begin
                img0[base + i] = h_buff_din;
                void'(img_wr(IMG, base + i, h_buff_din));
              end
              if (s == 1 && base + i < IMG1_MX) img1[base + i] = h_buff_din;
            end
          end
          if (w) hps_writes++; else hps_reads++;
          h_ack[s] <= 1'b0;
          repeat (4) @(posedge clk);
        end
      end
    end
  end

  task automatic mount(input int s, input int size, input bit ro);
    @(posedge clk);
    img_size     <= 64'(size);
    img_readonly <= ro;
    img_mounted[s] <= 1'b1;
    repeat (8) @(posedge clk);
    img_mounted[s] <= 1'b0;
    repeat (8) @(posedge clk);
  endtask

  // ---- I/O bus: level for a few clocks, end pulse ----------------------------------
  task automatic io_write(input logic [1:0] a, input logic [7:0] d);
    @(posedge clk);
    cs_fdc <= 1'b1; io_addr <= a; io_wdata <= d; io_wr <= 1'b1;
    repeat (3) @(posedge clk);
    io_wr <= 1'b0; io_wr_end <= 1'b1;
    @(posedge clk);
    io_wr_end <= 1'b0; cs_fdc <= 1'b0;
  endtask
  task automatic io_read(input logic [1:0] a, output logic [7:0] d);
    @(posedge clk);
    cs_fdc <= 1'b1; io_addr <= a; io_rd <= 1'b1;
    repeat (3) @(posedge clk);
    d = fdc_rdata;
    io_rd <= 1'b0; io_rd_end <= 1'b1;
    @(posedge clk);
    io_rd_end <= 1'b0; cs_fdc <= 1'b0;
  endtask
  task automatic wait_us(input int n);
    repeat (n * CE_DIV) @(posedge clk);
  endtask

  localparam logic [1:0] R_CMD = 2'd0, R_TRK = 2'd1, R_SEC = 2'd2, R_DAT = 2'd3;

  // command, then poll BUSY; returns the final status
  task automatic cmd_wait(input logic [7:0] c, output logic [7:0] s);
    io_write(R_CMD, c);
    wait_us(20);
    do io_read(R_CMD, s); while (s[0]);
  endtask

  // read-type command with DRQ polling (the ROM's sub22 loop)
  logic [7:0] rbuf [8192];
  task automatic cmd_read(input logic [7:0] c, output int n, output logic [7:0] s);
    n = 0;
    io_write(R_CMD, c);
    wait_us(20);
    forever begin
      io_read(R_CMD, s);
      if (s[1]) begin
        io_read(R_DAT, rbuf[n]);
        n++;
      end else if (!s[0]) break;
    end
  endtask

  logic [7:0] wbuf [8192];
  task automatic cmd_write(input logic [7:0] c, input int len, output int n, output logic [7:0] s);
    n = 0;
    io_write(R_CMD, c);
    forever begin
      io_read(R_CMD, s);
      if (s[1]) begin
        io_write(R_DAT, (n < len) ? wbuf[n] : 8'h4E);
        n++;
      end else if (!s[0]) break;
    end
  endtask

  // ---- the boot ROM's disk_io for one block (sub18-sub22) ---------------------------
  logic [7:0] trk_tab [2] = '{8'hFF, 8'hFF};
  int         cur_drv = -1;

  task automatic rom_sub17(input logic [7:0] c);        // 0xee2
    logic [7:0] s;
    io_read(R_CMD, s);
    if (s[0]) begin io_write(R_CMD, 8'hD0); wait_us(15); end
    io_write(R_CMD, c);
    wait_us(15);
  endtask
  task automatic rom_sub29(input logic [7:0] c, output logic [7:0] s);   // 0xe2c
    rom_sub17(c);
    forever begin
      io_read(R_CMD, s);
      if (!s[0]) return;
      if (s[7]) begin rom_sub17(8'hD0); return; end
    end
  endtask
  task automatic rom_sub21(output bit nr);              // 0xf08: wait for READY
    logic [7:0] s;
    nr = 1'b1;
    for (int i = 0; i < 'h96; i++) begin
      io_read(R_CMD, s);
      if (!s[7]) begin nr = 1'b0; return; end
      wait_us(1000);
    end
  endtask
  task automatic rom_sub25(input int drv, output logic [7:0] err);   // 0xe06: restore
    logic [7:0] s;
    bit nr;
    err = 8'h00;
    rom_sub21(nr);
    if (nr) begin err = 8'h80; return; end
    rom_sub29(8'h03, s);
    if (s[7]) begin err = 8'h80; return; end
    if (!s[2]) err = 8'h02;
    else trk_tab[drv] = 8'h00;
  endtask

  task automatic rom_block(input int drv, input int blk, output logic [7:0] err, output int n);
    logic [7:0] s;
    bit         nr;
    int         cyl, want;
    err = 8'h00;
    n   = 0;
    // sub19: select, /DDEN, position
    if (drv != cur_drv) begin
      cur_drv = drv;
      fdc_ds  <= 2'(1 << drv);
    end
    fdc_dden_n <= blk < 16;
    @(posedge clk);
    if (trk_tab[drv] == 8'hFF) begin
      rom_sub25(drv, err);
      if (err != 8'h00) return;
    end
    io_write(R_TRK, trk_tab[drv]);
    cyl = blk >> 5;
    if (cyl != int'(trk_tab[drv])) begin
      trk_tab[drv] = 8'(cyl);
      if (cyl == 0) begin
        rom_sub25(drv, err);
        if (err != 8'h00) return;
      end else begin
        io_write(R_DAT, 8'(cyl));
        rom_sub17(8'h13);                               // sub26
        do io_read(R_CMD, s); while (s[0]);
        wait_us(10 * 1000);                             // sub27
        io_write(R_DAT, 8'(cyl));                       // sub28
        rom_sub29(8'h17, s);
        if (s[7]) begin err = 8'h80; return; end
        if ((s & 8'h18) != 8'h00) begin err = 8'h04; return; end
      end
    end
    // sub20: sector, command, sub22 transfer
    rom_sub21(nr);
    if (nr) begin err = 8'h80; return; end
    io_write(R_SEC, 8'((blk & 15) + 1));
    want = (blk < 16) ? 128 : 256;
    rom_sub17(8'h88 | 8'((blk >> 3) & 2));
    forever begin                                       // L119
      io_read(R_CMD, s);
      if (!s[0] || s[7]) break;
      if (s[1]) begin
        do begin                                        // L121: INIB while DRQ, until !BUSY
          if (s[1]) begin io_read(R_DAT, rbuf[n]); n++; end
          io_read(R_CMD, s);
        end while (s[1] || s[0]);
        break;
      end
    end
    io_read(R_CMD, s);                                  // L101
    if (s[0]) rom_sub17(8'hD0);
    s = s & 8'hFC;
    if (n != want) s[3] = 1'b1;
    err = s;
  endtask

  // ---- helpers ------------------------------------------------------------------------
  function automatic int off0(input int cyl, input int side, input int sec);
    return ((cyl * 2 + side) * 16 + sec - 1) * 256;
  endfunction

  task automatic seek(input int c, input logic [7:0] cmd, output logic [7:0] s);
    io_write(R_DAT, 8'(c));
    cmd_wait(cmd, s);
  endtask

  function automatic logic [15:0] crc_b(input logic [15:0] c, input logic [7:0] b);
    logic [15:0] r = c;
    for (int i = 7; i >= 0; i--) begin
      if (r[15] ^ b[i]) r = (r << 1) ^ 16'h1021; else r = r << 1;
    end
    return r;
  endfunction

  // MFM format stream (IBM System/34 layout, M20 interleave)
  logic [7:0] fstream [8192];
  int         flen;
  task automatic push(input logic [7:0] b, input int cnt);
    for (int i = 0; i < cnt; i++) begin fstream[flen] = b; flen++; end
  endtask
  // F5-F7 are Write Track commands, never data
  function automatic logic [7:0] fmt_pat(input int sec, input int i);
    logic [7:0] v = 8'(sec * 16 + i) ^ 8'hC3;
    return (v >= 8'hF5 && v <= 8'hF7) ? 8'hE5 : v;
  endfunction
  function automatic int phys_sec(input int p);
    return (p & 1) ? (p + 1) / 2 : p / 2 + 9;
  endfunction
  task automatic build_mfm(input int cyl, input int side);
    flen = 0;
    push(8'h4E, 80); push(8'h00, 12); push(8'hF6, 3); push(8'hFC, 1); push(8'h4E, 50);
    for (int p = 0; p < 16; p++) begin
      automatic int sc = phys_sec(p);
      push(8'h00, 12); push(8'hF5, 3); push(8'hFE, 1);
      push(8'(cyl), 1); push(8'(side), 1); push(8'(sc), 1); push(8'h01, 1); push(8'hF7, 1);
      push(8'h4E, 22); push(8'h00, 12); push(8'hF5, 3); push(8'hFB, 1);
      for (int i = 0; i < 256; i++) push(fmt_pat(sc, i), 1);
      push(8'hF7, 1); push(8'h4E, 54);
    end
  endtask
  task automatic build_fm(input int cyl, input int side);
    flen = 0;
    push(8'hFF, 40); push(8'h00, 6); push(8'hFC, 1); push(8'hFF, 26);
    for (int p = 0; p < 16; p++) begin
      automatic int sc = phys_sec(p);
      push(8'h00, 6); push(8'hFE, 1);
      push(8'(cyl), 1); push(8'(side), 1); push(8'(sc), 1); push(8'h00, 1); push(8'hF7, 1);
      push(8'hFF, 11); push(8'h00, 6); push(8'hFB, 1);
      for (int i = 0; i < 128; i++) push(fmt_pat(sc, i), 1);
      push(8'hF7, 1); push(8'hFF, 27);
    end
  endtask
  task automatic write_track(input logic [7:0] c, output int n, output logic [7:0] s);
    n = 0;
    io_write(R_CMD, c);
    forever begin
      io_read(R_CMD, s);
      if (s[1]) begin
        io_write(R_DAT, (n < flen) ? fstream[n] : 8'h4E);
        n++;
      end else if (!s[0]) break;
    end
  endtask

  task automatic flush_wait;
    // a different unit's request makes disk_stream write the dirty one back
    int t = 0;
    while (wb_busy && t < 2_000_000) begin @(posedge clk); t++; end
    check(!wb_busy, "write-back did not finish");
  endtask

  logic [7:0] fchk [IMG0_SZ];
  task automatic reread_file;
    int fd, r;
    fd = $fopen(IMG, "rb");
    r  = $fread(fchk, fd);
    $fclose(fd);
    check(r == IMG0_SZ, $sformatf("file re-read %0d bytes", r));
  endtask

  // ---- test sequence --------------------------------------------------------------------
  initial begin : main
    logic [7:0] s, e, b;
    int         n, fd, r, t0;
    int         errs_before;

    fd = $fopen(IMG, "rb");
    if (fd == 0) $fatal(1, "cannot open %s", IMG);
    r = $fread(img0, fd);
    $fclose(fd);
    if (r != IMG0_SZ) $fatal(1, "image %s: %0d bytes", IMG, r);
    for (int i = 0; i < IMG0_SZ; i++) orig0[i] = img0[i];
    for (int i = 0; i < IMG1_MX; i++) img1[i] = pat1(i);
    check(img0[0] == 8'h01 && img0[1] == 8'h04, "image has no track 0");

    repeat (20) @(posedge clk);
    rst_n <= 1'b1;
    repeat (20) @(posedge clk);
    mount(0, IMG0_SZ, 1'b0);

    // ---- status, D0, sector register ------------------------------------------------
    io_read(R_CMD, s);
    if (s[0]) io_write(R_CMD, 8'hD0);
    io_write(R_CMD, 8'hD0);
    wait_us(20);
    io_read(R_CMD, s);
    check(!s[0], $sformatf("status after D0 busy: %02h", s));
    check(!intrq, "D0 raised INTRQ");
    for (int v = 255; v >= 1; v--) begin
      io_write(R_SEC, 8'(v));
      io_read(R_SEC, b);
      check(b == 8'(v), $sformatf("sector register %02h read %02h", v, b));
    end
    io_write(R_TRK, 8'h5A); io_read(R_TRK, b); check(b == 8'h5A, "track register");
    io_write(R_DAT, 8'hA5); io_read(R_DAT, b); check(b == 8'hA5, "data register");

    // ---- boot ROM disk sequence -----------------------------------------------------
    $display("[%0d] boot ROM sequence", cyc);
    fdc_ds <= 2'b00;                                    // disk_init: stop motors, D0
    rom_sub17(8'hD0);
    for (int blk = 0; blk < 48; blk++) begin
      errs_before = errors;
      rom_block(0, blk, e, n);
      check(e == 8'h00, $sformatf("ROM block %0d: error %02h", blk, e));
      for (int i = 0; i < n; i++)
        check(rbuf[i] == img0[blk * 256 + i],
              $sformatf("ROM block %0d byte %0d: %02h want %02h", blk, i, rbuf[i], img0[blk * 256 + i]));
      if (errors != errs_before) $display("  block %0d: %0d bytes", blk, n);
    end
    rom_block(0, 100, e, n);                            // cylinder 3 side 0 sector 5
    check(e == 8'h00 && n == 256, $sformatf("ROM block 100: %02h %0d", e, n));
    for (int i = 0; i < n; i++) check(rbuf[i] == img0[100 * 256 + i], "ROM block 100 data");
    rom_block(0, 0, e, n);                              // back to T0S0 via restore
    check(e == 8'h00 && n == 128, "ROM block 0 again");
    for (int i = 0; i < n; i++) check(rbuf[i] == img0[i], "ROM block 0 again data");
    rom_block(1, 0, e, n);                              // drive 1 empty
    check(e[7], $sformatf("drive 1 without medium: error %02h", e));
    io_read(R_CMD, s);
    check(s[7], "NOT READY with drive 1 empty");
    $display("[%0d] boot ROM sequence done", cyc);

    fdc_ds <= 2'b01;
    // ---- density mismatch -----------------------------------------------------------
    cmd_wait(8'h0B, s);                                 // restore
    check(s[2] && !s[4], $sformatf("restore status %02h", s));
    fdc_dden_n <= 1'b0;                                 // MFM on the FM track
    io_write(R_SEC, 8'd1);
    t0 = cyc;
    cmd_read(8'h88, n, s);
    check(n == 0 && s[4], $sformatf("T0S0 MFM: %0d bytes status %02h", n, s));
    check(cyc - t0 > 4 * 200000 * CE_DIV, $sformatf("RNF after %0d clocks", cyc - t0));
    fdc_dden_n <= 1'b1;
    seek(1, 8'h18, s);                                  // seek cylinder 1, h, 6 ms
    check(!s[4], "seek 1");
    io_read(R_TRK, b); check(b == 8'd1, "track register after seek");
    cmd_read(8'h88, n, s);                              // FM on an MFM track
    check(n == 0 && s[4], $sformatf("cyl 1 FM: %0d bytes status %02h", n, s));
    fdc_dden_n <= 1'b0;
    cmd_read(8'h88, n, s);
    check(n == 256 && s == 8'h00, $sformatf("cyl 1 MFM: %0d bytes status %02h", n, s));
    for (int i = 0; i < 256; i++) check(rbuf[i] == img0[off0(1, 0, 1) + i], "cyl 1 sector 1");

    // ---- L = 0 length coding: 512 bytes from a 256-byte sector, CRC error ---------
    io_write(R_SEC, 8'd3);
    cmd_read(8'h80, n, s);
    check(n == 512 && s[3] && !s[4], $sformatf("L=0: %0d bytes status %02h", n, s));
    for (int i = 0; i < 256; i++) check(rbuf[i] == img0[off0(1, 0, 3) + i], "L=0 data");

    // ---- multi-sector read -----------------------------------------------------------
    seek(2, 8'h1C, s);                                  // with verify
    check(s[4:3] == 2'b00, $sformatf("seek 2 verify %02h", s));
    io_write(R_SEC, 8'd1);
    cmd_read(8'h9A, n, s);
    check(n == 16 * 256 && s[4], $sformatf("multi read: %0d bytes status %02h", n, s));
    for (int i = 0; i < 4096; i++)
      if (rbuf[i] != img0[off0(2, 1, 1) + i]) begin
        check(1'b0, $sformatf("multi byte %0d", i)); break;
      end
    io_read(R_SEC, b);
    check(b == 8'd17, $sformatf("sector register after multi %0d", b));

    // ---- read address -----------------------------------------------------------------
    cmd_read(8'hC2, n, s);
    check(n == 6 && s == 8'h00, $sformatf("read address %0d status %02h", n, s));
    begin
      logic [15:0] c = 16'hFFFF;
      c = crc_b(c, 8'hA1); c = crc_b(c, 8'hA1); c = crc_b(c, 8'hA1); c = crc_b(c, 8'hFE);
      for (int i = 0; i < 4; i++) c = crc_b(c, rbuf[i]);
      check(rbuf[0] == 8'd2 && rbuf[1] == 8'd1 && rbuf[2] >= 8'd1 && rbuf[2] <= 8'd16 &&
            rbuf[3] == 8'd1, $sformatf("ID %02h %02h %02h %02h", rbuf[0], rbuf[1], rbuf[2], rbuf[3]));
      check({rbuf[4], rbuf[5]} == c, $sformatf("ID CRC %02h%02h want %04h", rbuf[4], rbuf[5], c));
    end
    io_read(R_SEC, b);
    check(b == 8'd2, "read address: sector register = track");

    // ---- step commands, seek verify error --------------------------------------------
    cmd_wait(8'h58, s);                                 // step in, update
    io_read(R_TRK, b); check(b == 8'd3, $sformatf("step in: track %0d", b));
    cmd_wait(8'h38, s);                                 // step, update (same direction)
    io_read(R_TRK, b); check(b == 8'd4, $sformatf("step: track %0d", b));
    cmd_wait(8'h68, s);                                 // step out, no update
    io_read(R_TRK, b); check(b == 8'd4, $sformatf("step out no update: track %0d", b));
    cmd_wait(8'h7C, s);                                 // step out, update, verify
    io_read(R_TRK, b); check(b == 8'd3, "step out update");
    check(s[4], $sformatf("verify with track register off by one: %02h", s));
    io_write(R_TRK, 8'd2);
    seek(3, 8'h1C, s);                                  // head now at 3
    check(!s[4] && !s[3], $sformatf("seek verify ok %02h", s));

    // ---- INTRQ and force interrupt ----------------------------------------------------
    io_write(R_DAT, 8'd3);
    io_write(R_CMD, 8'h18);                             // no status polling
    t0 = cyc;
    while (!intrq && cyc - t0 < 100000 * CE_DIV) @(posedge clk);
    check(intrq && !fbusy, "INTRQ at the end of a seek");
    io_read(R_CMD, s);
    @(posedge clk);
    check(!intrq, "status read clears INTRQ");
    io_write(R_SEC, 8'd2);
    io_write(R_CMD, 8'h88);
    wait_us(30000);
    io_write(R_CMD, 8'hD0);
    wait_us(10);
    io_read(R_CMD, s);
    check(!s[0] && !intrq, $sformatf("D0 abort: %02h intrq %0d", s, intrq));
    io_write(R_CMD, 8'hD8);
    wait_us(10);
    check(intrq, "D8 immediate interrupt");
    io_read(R_CMD, s);
    @(posedge clk);
    check(intrq, "D8 interrupt survives a status read");
    io_write(R_CMD, 8'hD0);
    @(posedge clk);
    check(!intrq, "D0 clears D8");
    io_write(R_CMD, 8'hD4);                             // index interrupt
    t0 = cyc;
    while (!intrq && cyc - t0 < 500000 * CE_DIV) @(posedge clk);
    check(intrq, "D4 index interrupt");
    io_write(R_CMD, 8'hD0);

    // ---- write sector, read back, write-back to the file -------------------------------
    $display("[%0d] write", cyc);
    for (int i = 0; i < 256; i++) wbuf[i] = 8'(i * 7 + 3);
    io_write(R_SEC, 8'd5);
    cmd_write(8'hA8, 256, n, s);
    check(n == 256 && s == 8'h00, $sformatf("write: %0d bytes status %02h", n, s));
    cmd_read(8'h88, n, s);
    check(n == 256 && s == 8'h00, "write read back");
    for (int i = 0; i < 256; i++) check(rbuf[i] == wbuf[i], $sformatf("write read back %0d", i));
    io_write(R_SEC, 8'd6);
    cmd_read(8'h88, n, s);
    for (int i = 0; i < 256; i++) check(rbuf[i] == orig0[off0(3, 0, 6) + i], "neighbour sector");
    // multi-sector write: sectors 15, 16 of side 1, then RNF
    for (int i = 0; i < 512; i++) wbuf[i] = 8'(i ^ 8'h96);
    io_write(R_SEC, 8'd15);
    cmd_write(8'hBA, 512, n, s);
    check(n == 512 && s[4], $sformatf("multi write: %0d bytes status %02h", n, s));
    io_write(R_SEC, 8'd15);
    cmd_read(8'h9A, n, s);
    check(n == 512, "multi write read back");
    for (int i = 0; i < 512; i++) check(rbuf[i] == wbuf[i], "multi write data");

    // ---- write track: MFM, cylinder 4 side 1 -----------------------------------------
    $display("[%0d] write track", cyc);
    seek(4, 8'h18, s);
    build_mfm(4, 1);
    write_track(8'hF2, n, s);
    check(s == 8'h00 && n > flen, $sformatf("write track: %0d bytes status %02h", n, s));
    for (int sc = 1; sc <= 16; sc++) begin
      io_write(R_SEC, 8'(sc));
      cmd_read(8'h8A, n, s);
      check(n == 256 && s == 8'h00, $sformatf("formatted sector %0d: %0d %02h", sc, n, s));
      for (int i = 0; i < 256; i++)
        if (rbuf[i] != fmt_pat(sc, i)) begin
          check(1'b0, $sformatf("formatted sector %0d byte %0d: %02h %02h %02h want %02h", sc, i, rbuf[i], rbuf[i+1], rbuf[i+2], fmt_pat(sc, i))); break;
        end
    end

    // ---- the file ----------------------------------------------------------------------
    seek(10, 8'h18, s);
    cmd_read(8'h88, n, s);                              // another unit: write-back
    flush_wait();
    reread_file();
    for (int i = 0; i < 256; i++)
      check(fchk[off0(3, 0, 5) + i] == 8'(i * 7 + 3), $sformatf("file: written sector byte %0d", i));
    for (int i = 0; i < 512; i++)
      check(fchk[off0(3, 1, 15) + i] == 8'(i ^ 8'h96), "file: multi write");
    for (int sc = 1; sc <= 16; sc++)
      for (int i = 0; i < 256; i++)
        if (fchk[off0(4, 1, sc) + i] != fmt_pat(sc, i)) begin
          check(1'b0, $sformatf("file: formatted sector %0d byte %0d", sc, i)); break;
        end
    begin
      int diffs = 0;
      for (int i = 0; i < IMG0_SZ; i++) begin
        automatic bit mod = (i >= off0(3, 0, 5) && i < off0(3, 0, 6)) ||
                            (i >= off0(3, 1, 15) && i < off0(3, 1, 15) + 512) ||
                            (i >= off0(4, 1, 1) && i < off0(4, 1, 1) + 4096);
        if (!mod && fchk[i] != orig0[i]) diffs++;
      end
      check(diffs == 0, $sformatf("file: %0d bytes changed outside the writes", diffs));
    end

    // ---- slot 1: 640K -------------------------------------------------------------------
    $display("[%0d] geometry", cyc);
    mount(1, 655360, 1'b0);
    fdc_ds <= 2'b10;
    cmd_wait(8'h08, s);
    check(s[2], "drive 1 restore");
    seek(79, 8'h18, s);
    io_write(R_SEC, 8'd16);
    cmd_read(8'h8A, n, s);
    check(n == 256 && s == 8'h00, $sformatf("640K cyl 79: %0d %02h", n, s));
    for (int i = 0; i < 256; i++)
      check(rbuf[i] == pat1(((79 * 2 + 1) * 16 + 15) * 256 + i), "640K data");
    // FM format of T0S0
    cmd_wait(8'h08, s);
    fdc_dden_n <= 1'b1;
    build_fm(0, 0);
    write_track(8'hF0, n, s);
    check(s == 8'h00, $sformatf("FM write track status %02h", s));
    for (int sc = 1; sc <= 16; sc++) begin
      io_write(R_SEC, 8'(sc));
      cmd_read(8'h88, n, s);
      check(n == 128 && s == 8'h00, $sformatf("FM sector %0d: %0d %02h", sc, n, s));
      for (int i = 0; i < 128; i++)
        if (rbuf[i] != fmt_pat(sc, i)) begin
          check(1'b0, $sformatf("FM sector %0d byte %0d", sc, i)); break;
        end
    end
    seek(5, 8'h18, s);
    fdc_dden_n <= 1'b0;
    cmd_read(8'h88, n, s);
    flush_wait();
    for (int sc = 1; sc <= 16; sc++)
      for (int i = 0; i < 256; i++)
        if (img1[(sc - 1) * 256 + i] != ((i < 128) ? fmt_pat(sc, i) : pat1((sc - 1) * 256 + i))) begin
          check(1'b0, $sformatf("FM image sector %0d byte %0d", sc, i)); break;
        end

    // ---- slot 1: 160K single sided, write protected -----------------------------------
    mount(1, 143360, 1'b1);
    cmd_wait(8'h08, s);
    check(s[6], "write protect in type I status");
    seek(34, 8'h18, s);
    io_write(R_SEC, 8'd3);
    cmd_read(8'h88, n, s);
    check(n == 256 && s == 8'h00, $sformatf("160K cyl 34: %0d %02h", n, s));
    for (int i = 0; i < 256; i++) check(rbuf[i] == pat1((34 * 16 + 2) * 256 + i), "160K data");
    cmd_read(8'h8A, n, s);
    check(n == 0 && s[4], $sformatf("160K side 1: %02h", s));
    cmd_write(8'hA8, 256, n, s);
    check(n == 0 && s[6] && !s[0], $sformatf("write protected: %02h", s));

    $display("checks %0d, hps reads %0d, writes %0d, cycles %0d", checks, hps_reads, hps_writes, cyc);
    if (errors != 0) $fatal(1, "%0d failures", errors);
    $display("PASS");
    $finish;
  end

  initial begin
    #(64'd4_000_000_000);
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
