// m20_iodec + m20_hdc + disk_stream against a behavioural hps_io block
// server.  Slot 2 is a 180-cylinder image (byte = pattern of its offset),
// slot 3 a small read-only one.  A reference copy of slot 2 follows every
// write and format; sectors read through the card are compared with it,
// and so is the whole image once disk_stream has written it back.
//
// Phases: card absent while nothing is mounted (reads 0xFFFF); status
// after mount; read both halves of a block; write then read back (the
// block's other half untouched); format of an odd and an even track start
// (neighbouring sectors kept); ID not found (sector 33, head 6, cylinder
// 180, size code 1, format head 6); not ready -> aborted; reads while busy
// return status; write to the read-only drive -> aborted; INTRQ; eject.
`timescale 1ns/1ps
`default_nettype none
module tb_hdc;
  localparam int CYL   = 180;
  localparam int SPC   = 198;                      // sectors per cylinder
  localparam int IMG2  = CYL * 99 * 512;
  localparam int CYL3  = 4;
  localparam int IMG3  = CYL3 * 99 * 512;

  logic clk = 1'b0;
  always #10 clk = ~clk;
  logic rst_n = 1'b0;

  logic [31:0] cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // ---- I/O decode and the card ------------------------------------------------------
  logic [15:0] a_q = 16'h0000, wd_q = 16'h0000;
  logic        io_cyc = 1'b0, r_w = 1'b1, ds_n = 1'b1, ds_rise = 1'b0;
  logic        io_rd, io_wr, io_rd_end, io_wr_end;
  logic        cs_exp;
  logic [7:0]  exp_rdata;
  logic [15:0] rdata;

  m20_iodec u_iodec (
    .addr(a_q[15:5]), .io_cyc(io_cyc), .r_w(r_w), .ds_n(ds_n), .ds_rise(ds_rise),
    .io_rd(io_rd), .io_wr(io_wr), .io_rd_end(io_rd_end), .io_wr_end(io_wr_end),
    .cs_fdc(), .cs_latch(), .cs_crtc(), .cs_ppi(), .cs_kbd(), .cs_ser(), .cs_pit(), .cs_pic(), .cs_pal(),
    .fdc_rdata(8'h00), .latch_rdata(8'h00), .crtc_rdata(8'h00), .ppi_rdata(8'h00),
    .kbd_rdata(8'h00), .ser_rdata(8'h00), .pit_rdata(8'h00), .pic_rdata(16'h0000),
    .cs_exp(cs_exp), .exp_rdata(exp_rdata), .rdata(rdata)
  );

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

  logic [1:0][31:0]  hd_lba;
  logic [1:0]        hd_rd, hd_wr;
  logic [1:0][7:0]   hd_din;
  logic              intrq;

  disk_stream #(.UMAX(99), .QUIET(40_000)) u_ds (
    .clk(clk), .rst_n(rst_n), .core_rst_n(rst_n), .bpc({12'd99, 12'd99}),
    .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
    .h_lba(h_lba), .h_blk_cnt(h_blk_cnt), .h_rd(h_rd), .h_wr(h_wr), .h_ack(h_ack),
    .h_buff_addr(h_buff_addr), .h_buff_dout(h_buff_dout), .h_buff_din(h_buff_din),
    .h_buff_wr(h_buff_wr),
    .d_mounted(d_mounted), .d_readonly(d_readonly), .d_size(d_size),
    .d_lba({hd_lba, 64'd0}), .d_scr(4'b0000), .d_rd({hd_rd, 2'b00}), .d_wr({hd_wr, 2'b00}),
    .d_ack(d_ack), .d_buff_addr(d_buff_addr), .d_buff_dout(d_buff_dout),
    .d_buff_din({hd_din, 16'h0000}), .d_buff_wr(d_buff_wr),
    .resident(resident), .busy(ds_busy), .wb_busy(wb_busy), .fmt_full(fmt_full),
    .ld_min(ld_min), .ld_max(ld_max)
  );

  m20_hdc dut (
    .clk(clk), .rst_n(rst_n),
    .io_addr(a_q), .io_wdata(wd_q), .io_rd(io_rd), .io_wr(io_wr),
    .io_rd_end(io_rd_end), .io_wr_end(io_wr_end),
    .sel(cs_exp), .rdata(exp_rdata), .intrq(intrq),
    .d_mounted(d_mounted[3:2]), .d_readonly(d_readonly), .d_size(d_size),
    .d_lba(hd_lba), .d_rd(hd_rd), .d_wr(hd_wr), .d_ack(d_ack[3:2]),
    .d_buff_addr(d_buff_addr), .d_buff_dout(d_buff_dout), .d_buff_din(hd_din),
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
  logic [7:0] img2 [IMG2];
  logic [7:0] ref2 [IMG2];
  logic [7:0] img3 [IMG3];
  function automatic logic [7:0] pat(input int off, input logic [7:0] k);
    return off[7:0] ^ off[15:8] ^ off[23:16] ^ k;
  endfunction

  int hps_reads = 0, hps_writes = 0;
  initial begin : server
    forever begin
      @(posedge clk);
      for (int s = 2; s < 4; s++) begin
        if (h_rd[s] || h_wr[s]) begin
          automatic int base = int'(h_lba[s]) * 512;
          automatic int n    = (int'(h_blk_cnt[s]) + 1) * 512;
          automatic int sz   = (s == 2) ? IMG2 : IMG3;
          automatic bit w    = h_wr[s];
          h_ack[s] <= 1'b1;
          repeat (3) @(posedge clk);
          for (int i = 0; i < n; i++) begin
            h_buff_addr <= 14'(i);
            if (!w) begin
              h_buff_dout <= (base + i >= sz) ? 8'h00 : (s == 2) ? img2[base + i] : img3[base + i];
              h_buff_wr <= 1'b1;
              @(posedge clk);
              h_buff_wr <= 1'b0;
              @(posedge clk);
            end else begin
              @(posedge clk);
              @(posedge clk);
              if (base + i < sz) begin
                if (s == 2) img2[base + i] = h_buff_din;
                else        img3[base + i] = h_buff_din;
              end
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

  // ---- Z8000 I/O cycles: address at /AS, /DS low 3 clocks ---------------------------
  task automatic io_write(input int r, input logic [7:0] d);
    @(posedge clk);
    a_q <= 16'(16'h01C1 + 2 * r); wd_q <= {d, d}; r_w <= 1'b0; io_cyc <= 1'b1;
    @(posedge clk); ds_n <= 1'b0;
    repeat (3) @(posedge clk);
    ds_n <= 1'b1; ds_rise <= 1'b1;
    @(posedge clk);
    ds_rise <= 1'b0; io_cyc <= 1'b0;
  endtask
  task automatic io_read16(input int r, output logic [15:0] d);
    @(posedge clk);
    a_q <= 16'(16'h01C1 + 2 * r); r_w <= 1'b1; io_cyc <= 1'b1;
    @(posedge clk); ds_n <= 1'b0;
    repeat (3) @(posedge clk);
    d = rdata;
    ds_n <= 1'b1; ds_rise <= 1'b1;
    @(posedge clk);
    ds_rise <= 1'b0; io_cyc <= 1'b0;
  endtask
  task automatic io_read(input int r, output logic [7:0] d);
    logic [15:0] w;
    io_read16(r, w);
    check(w[15:8] == 8'hFF, $sformatf("reg %0d: D15-D8 %02h", r, w[15:8]));
    d = w[7:0];
  endtask

  localparam int R_DATA = 0, R_ERR = 1, R_SCNT = 2, R_SEC = 3, R_CYLL = 4, R_CYLH = 5,
                 R_SDH = 6, R_CMD = 7;
  localparam logic [7:0] S_BSY = 8'h80, S_RDY = 8'h40, S_SC = 8'h10, S_DRQ = 8'h08,
                         S_ERR = 8'h01;

  task automatic task_file(input int drv, input int c, input int h, input int sec);
    io_write(R_SEC, 8'(sec));
    io_write(R_CYLL, 8'(c));
    io_write(R_CYLH, 8'(c >> 8));
    io_write(R_SDH, 8'((drv << 3) | h));
  endtask

  // Poll the sector register (below 0x80) until not busy: while busy it
  // reads as status.  INTRQ is checked before the status read clears it.
  int busy_seen = 0;
  task automatic wait_idle(output logic [7:0] s);
    logic [7:0] o;
    forever begin
      io_read(R_SEC, o);
      if (!o[7]) break;
      check(o == (S_BSY | S_RDY | S_SC), $sformatf("busy read of sector register: %02h", o));
      busy_seen++;
    end
    check(intrq, "INTRQ at command end");
    io_read(R_CMD, s);
    check(!intrq, "INTRQ cleared by status read");
  endtask

  logic [7:0] buf_q [256];
  task automatic read_sector(input int drv, input int c, input int h, input int sec, output logic [7:0] s);
    logic [7:0] e;
    task_file(drv, c, h, sec);
    io_write(R_CMD, 8'h20);
    wait_idle(s);
    if (s[3]) begin
      for (int i = 0; i < 256; i++) io_read(R_DATA, buf_q[i]);
      io_read(R_CMD, e);
      check(!e[3], $sformatf("DRQ after 256 bytes: %02h", e));
    end
  endtask

  task automatic write_sector(input int drv, input int c, input int h, input int sec, input logic [7:0] cmd,
                              output logic [7:0] s);
    task_file(drv, c, h, sec);
    io_write(R_CMD, cmd);
    io_read(R_CMD, s);
    check(s == (S_RDY | S_SC | S_DRQ), $sformatf("write DRQ: %02h", s));
    for (int i = 0; i < 256; i++) io_write(R_DATA, buf_q[i]);
    wait_idle(s);
  endtask

  function automatic int off2(input int c, input int h, input int sec);
    return ((c * 6 + h) * 33 + sec) * 256;
  endfunction

  task automatic check_sector(input int c, input int h, input int sec, input string what);
    logic [7:0] s;
    read_sector(0, c, h, sec, s);
    check(s == (S_RDY | S_SC | S_DRQ), $sformatf("%s c%0d h%0d s%0d: status %02h", what, c, h, sec, s));
    for (int i = 0; i < 256; i++)
      if (buf_q[i] != ref2[off2(c, h, sec) + i]) begin
        check(1'b0, $sformatf("%s c%0d h%0d s%0d byte %0d: %02h, expected %02h", what, c, h, sec, i,
                              buf_q[i], ref2[off2(c, h, sec) + i]));
        break;
      end
  endtask

  task automatic expect_err(input logic [7:0] s, input logic [7:0] er, input string what);
    logic [7:0] e;
    io_read(R_ERR, e);
    check(s[0] && !s[7] && !s[3] && e == er, $sformatf("%s: status %02h error %02h", what, s, e));
  endtask

  task automatic format_track(input int c, input int h);
    logic [7:0] s, n;
    io_write(R_SCNT, 8'd33);
    for (int i = 0; i < 256; i++) buf_q[i] = 8'((i & 1) ? (i >> 1) : 0);   // interleave table
    write_sector(0, c, h, 0, 8'h50, s);
    check(s == (S_RDY | S_SC), $sformatf("format c%0d h%0d: %02h", c, h, s));
    io_read(R_SCNT, n);
    check(n == 8'd0, $sformatf("format: sector count %02h", n));
    for (int i = 0; i < 33 * 256; i++) ref2[off2(c, h, 0) + i] = 8'h00;
  endtask

  initial begin
    logic [7:0]  s, e;
    logic [15:0] w;
    int c, h;

    for (int i = 0; i < IMG2; i++) begin img2[i] = pat(i, 8'hA5); ref2[i] = img2[i]; end
    for (int i = 0; i < IMG3; i++) img3[i] = pat(i, 8'h3C);
    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    repeat (8) @(posedge clk);

    // ---- no image: no card --------------------------------------------------------------
    for (int r = 0; r < 8; r++) begin
      io_read16(r, w);
      check(w == 16'hFFFF && !cs_exp, $sformatf("absent card reg %0d: %04h", r, w));
    end

    // ---- mount drive 0 -----------------------------------------------------------------
    mount(2, IMG2, 1'b0);
    io_read(R_CMD, s);
    check(s == (S_RDY | S_SC), $sformatf("status after mount: %02h", s));
    io_read(R_SDH, s);
    check(s == 8'h20, $sformatf("SDH after reset: %02h", s));
    io_write(R_SDH, 8'h00);
    io_write(R_CMD, 8'h10);                   // restore
    wait_idle(s);
    check(s == (S_RDY | S_SC), $sformatf("restore: %02h", s));
    io_write(R_CMD, 8'h70);                   // seek
    wait_idle(s);
    check(s == (S_RDY | S_SC), $sformatf("seek: %02h", s));

    // ---- read: both halves of a block, track ends -------------------------------------
    check_sector(5, 2, 6, "read");
    check_sector(5, 2, 7, "read");
    check_sector(5, 2, 0, "read");
    check_sector(5, 2, 32, "read");
    check_sector(179, 5, 32, "read");
    check_sector(0, 0, 0, "read");

    // ---- write, read back --------------------------------------------------------------
    for (int k = 0; k < 2; k++) begin
      automatic int sec = 11 - k;           // odd half, then even half of another block
      c = 10 + k; h = 3;
      for (int i = 0; i < 256; i++) begin buf_q[i] = 8'($urandom); ref2[off2(c, h, sec) + i] = buf_q[i]; end
      write_sector(0, c, h, sec, 8'h30, s);
      check(s == (S_RDY | S_SC), $sformatf("write c%0d s%0d: %02h", c, sec, s));
      check_sector(c, h, sec, "write");
      check_sector(c, h, sec ^ 1, "neighbour");
      check_sector(c, h, sec + 1, "neighbour");
    end

    // ---- format: odd (cyl 20 head 1) and even (cyl 21 head 2) track starts -------------
    format_track(20, 1);
    format_track(21, 2);
    for (int k = 0; k < 2; k++) begin
      c = 20 + k; h = 1 + k;
      check_sector(c, h, 0, "format");
      check_sector(c, h, 17, "format");
      check_sector(c, h, 32, "format");
      check_sector(c, h - 1, 32, "format neighbour");
      check_sector(c, h + 1, 0, "format neighbour");
    end
    format_track(30, 5);                      // last head: next cylinder's head 0 kept
    check_sector(31, 0, 0, "format neighbour");
    check_sector(30, 4, 32, "format neighbour");

    // ---- ID not found ------------------------------------------------------------------
    read_sector(0, 5, 0, 33, s);  expect_err(s, 8'h10, "sector 33");
    read_sector(0, 5, 6, 0, s);   expect_err(s, 8'h10, "head 6");
    read_sector(0, 180, 0, 0, s); expect_err(s, 8'h10, "cylinder 180");
    task_file(0, 5, 0, 0);
    io_write(R_SDH, 8'h20);                    // size code 1: 512 B
    io_write(R_CMD, 8'h20);
    wait_idle(s);  expect_err(s, 8'h10, "size code 1");
    for (int i = 0; i < 256; i++) buf_q[i] = 8'hEE;
    write_sector(0, 5, 0, 33, 8'h30, s);  expect_err(s, 8'h10, "write sector 33");
    io_write(R_SCNT, 8'd33);
    write_sector(0, 5, 6, 0, 8'h50, s);   expect_err(s, 8'h10, "format head 6");
    check_sector(6, 0, 0, "after format head 6");
    io_write(R_CMD, 8'h70);                    // a new command clears the error
    wait_idle(s);
    check(s == (S_RDY | S_SC), $sformatf("error cleared: %02h", s));

    // ---- not ready --------------------------------------------------------------------
    io_write(R_SDH, 8'h08);                    // drive 1, nothing mounted
    io_read(R_CMD, s);
    check(s == S_SC, $sformatf("drive 1 empty: %02h", s));
    io_write(R_CMD, 8'h20);
    io_read(R_CMD, s);  expect_err(s, 8'h04, "not ready");
    io_write(R_SDH, 8'h10);                    // drive 2: never fitted
    io_write(R_CMD, 8'h70);
    io_read(R_CMD, s);  expect_err(s, 8'h04, "drive 2");

    // ---- read-only drive 1 ------------------------------------------------------------
    mount(3, IMG3, 1'b1);
    read_sector(1, 3, 5, 9, s);
    check(s == (S_RDY | S_SC | S_DRQ), $sformatf("drive 1 read: %02h", s));
    for (int i = 0; i < 256; i++)
      if (buf_q[i] != pat(off2(3, 5, 9) + i, 8'h3C)) begin check(1'b0, "drive 1 data"); break; end
    read_sector(1, CYL3, 0, 0, s);  expect_err(s, 8'h10, "drive 1 past its end");
    for (int i = 0; i < 256; i++) buf_q[i] = 8'h77;
    write_sector(1, 1, 1, 1, 8'h30, s);  expect_err(s, 8'h04, "write protected");
    io_write(R_SCNT, 8'd33);
    write_sector(1, 1, 1, 0, 8'h50, s);  expect_err(s, 8'h04, "format protected");
    check_sector(12, 3, 10, "drive 0 again");

    // ---- written back to the image file -------------------------------------------------
    repeat (100) @(posedge clk);
    wait (!wb_busy);
    repeat (100) @(posedge clk);
    begin
      int bad = 0;
      for (int i = 0; i < IMG2; i++) if (img2[i] != ref2[i]) begin
        if (bad < 4) $display("image byte %0d: %02h, expected %02h", i, img2[i], ref2[i]);
        bad++;
      end
      check(bad == 0, $sformatf("drive 0 image: %0d bytes differ", bad));
      bad = 0;
      for (int i = 0; i < IMG3; i++) if (img3[i] != pat(i, 8'h3C)) bad++;
      check(bad == 0, $sformatf("drive 1 image: %0d bytes differ", bad));
    end

    // ---- eject: card gone ---------------------------------------------------------------
    mount(2, 0, 1'b0);
    io_read16(R_CMD, w);
    check(w != 16'hFFFF, "card stays while drive 1 is mounted");
    mount(3, 0, 1'b0);
    io_read16(R_CMD, w);
    check(w == 16'hFFFF && !cs_exp, $sformatf("ejected: %04h", w));

    check(busy_seen > 0, "busy status seen");
    $display("checks %0d, busy polls %0d, hps reads %0d, writes %0d, cycles %0d",
             checks, busy_seen, hps_reads, hps_writes, cyc);
    if (errors != 0) $fatal(1, "%0d failures", errors);
    $display("PASS");
    $finish;
  end

  initial begin
    #(64'd2_000_000_000);
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
