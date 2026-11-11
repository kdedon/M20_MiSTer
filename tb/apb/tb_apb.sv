// APB card bench: m20_apb against a Z-bus model of the mainboard.
//
//  1. Translator + mapping PROM: the 16 KB blocks every 8086 page reaches in
//     each of the seven memory configurations, against the published table.
//  2. Handshake: OUT 3FFA probe (NMI, no run), OUT 3FFC (run, /BUSREQ, the
//     8086 leaves reset), the 8086's OUT 7FFA (NMI, release, reset), twice;
//     and no response with the card not fitted.
//  3. The 8086 test program: byte lanes, page translation, I/O window, NVI
//     and VI acknowledge cycles with their vectors, odd-stack pushes, and the
//     return address of an interrupt taken inside a counting loop; a VI raised
//     during the NVI entry waits for its IRET; REP MOVSW at an odd address.
// The model's CPU clock rises at random 12-19 clock spacing; /BUSACK
// follows /BUSREQ after two rises.
`default_nettype none
module tb_apb;
  logic clk = 1'b0;
  always #10 clk = ~clk;
  logic rst_n = 1'b0;
  logic fitted = 1'b1;
  int   errors = 0;

  task automatic fail(input string m);
    $display("FAIL t=%0t: %s", $time, m);
    errors++;
  endtask

  // ---- 1. translator x PROM -------------------------------------------------------
  logic [5:0] xa;
  logic [3:0] x_sn;
  logic       x_a15, x_a14, x_bus, x_rom;
  logic [2:0] cfg;
  logic [7:0] prom_q;
  m20_apb_xlat u_xl (.a(xa), .sn(x_sn), .a15(x_a15), .a14(x_a14), .bus(x_bus), .rom(x_rom));
  m20_prom u_prom (.clk(clk), .a14(x_a14), .a15(x_a15), .sn(x_sn), .st2(1'b1),
                   .j_32_128(cfg[1]), .j_bw(cfg[2]), .j_col48(cfg[0]), .q(prom_q));

  // Block per page, -1 none; the table lists the RAM pages until the first hole or alias.
  task automatic check_cfg(input logic [2:0] code, input string name, input int exp[$]);
    int got[$];
    int blk;
    cfg = code;
    for (int p = 0; p < 32; p++) begin
      xa = 6'(p);
      @(posedge clk); @(posedge clk);
      blk = (x_bus && !prom_q[5] && prom_q[7]) ? int'(prom_q[4:0]) : -1;
      got.push_back(blk);
    end
    for (int i = 0; i < exp.size(); i++)
      if (got[i] != exp[i]) fail($sformatf("%s: page %0d block %0d, expected %0d", name, i, got[i], exp[i]));
    if (exp.size() < 32) begin
      blk = got[exp.size()];
      if (blk >= 0 && !(blk inside {exp})) fail($sformatf("%s: page %0d block %0d is new RAM", name, exp.size(), blk));
    end
    // video planes and the F0000 aliases
    xa = 6'h38; @(posedge clk); @(posedge clk);
    if (prom_q[5] || prom_q[4:0] != 5'd0) fail($sformatf("%s: E0000 not plane 0", name));
    xa = 6'h3C; @(posedge clk); @(posedge clk);
    if (prom_q[5] || prom_q[4:0] != 5'd1) fail($sformatf("%s: F0000 not block 1", name));
    xa = 6'h3D; @(posedge clk); @(posedge clk);
    if (prom_q[5] || prom_q[4:0] != 5'd0) fail($sformatf("%s: F4000 not plane 0", name));
    $display("config %s: %0d pages checked", name, exp.size());
  endtask

  function automatic void seq(ref int q[$], input int a, input int b);
    for (int i = a; i <= b; i++) q.push_back(i);
  endfunction

  // ---- card -------------------------------------------------------------------------
  logic        ld_we = 1'b0;
  logic [14:0] ld_addr = '0;
  logic [7:0]  ld_data = '0;
  logic        busreq_n, nmi_n, run;
  logic        busack_n = 1'b1, clk_rise = 1'b0;
  logic        as_n, ds_n, ad_drive, r_w, b_w;
  logic [15:0] ad, rdata;
  logic [6:0]  sn;
  logic [3:0]  st;
  logic [15:0] io_addr;
  logic        io_act, io_end;
  logic        vi = 1'b0, nvi = 1'b0;

  m20_apb dut (
    .clk, .rst_n, .fitted, .ld_we, .ld_addr, .ld_data,
    .busreq_n, .nmi_n, .busack_n, .clk_rise, .as_n, .ds_n, .ad, .ad_drive, .sn, .st,
    .r_w, .b_w, .rdata, .io_addr, .io_act, .io_end, .vi, .nvi, .run
  );

  // ---- mainboard model ----------------------------------------------------------------
  int gap = 12;
  always @(posedge clk) begin
    if (gap == 0) begin clk_rise <= 1'b1; gap = 11 + $urandom_range(0, 7); end
    else begin clk_rise <= 1'b0; gap--; end
  end
  int ackc = 0;
  always @(posedge clk) if (clk_rise) begin
    if (!busreq_n) begin if (ackc < 2) ackc++; else busack_n <= 1'b0; end
    else begin if (ackc > 0) ackc--; else busack_n <= 1'b1; end
  end

  // Z memory: 16 segments x 32 K words.  Initial word = f(SN, address).
  logic [15:0] zmem [0:524287];
  function automatic logic [15:0] zinit(input logic [3:0] s, input logic [15:0] a);
    return {s, a[15:4]} ^ 16'h5A00;
  endfunction
  initial for (int i = 0; i < 524288; i++) zmem[i] = zinit(4'(i >> 15), 16'(i << 1));

  // Bench as Z8001 bus master for its own I/O cycles.
  logic        zm = 1'b0, zm_act = 1'b0, zm_end = 1'b0;
  logic [15:0] zm_addr = '0;

  logic        as_q = 1'b1, ds_q = 1'b1;
  logic [15:0] a_l;  logic [3:0] sn_l, st_l; logic rw_l, bw_l;
  int n_nviack = 0, n_viack = 0, n_mem = 0, n_io = 0;
  typedef struct { logic [15:0] a; logic w; logic b; logic [15:0] d; } io_t;
  io_t io_log[$];
  function automatic io_t mk(input logic [15:0] a, input logic w, input logic b, input logic [15:0] d);
    io_t r;
    r.a = a; r.w = w; r.b = b; r.d = d;
    return r;
  endfunction
  always @(posedge clk) begin
    as_q <= as_n; ds_q <= ds_n;
    if (!as_n) begin
      a_l = ad; sn_l = sn[3:0]; st_l = st; rw_l = r_w; bw_l = b_w;
      if (busack_n) fail("card drove /AS without /BUSACK");
      if (sn[6:4] != 3'd0) fail("SN6-4 not 0");
    end
    if (!ds_q && ds_n) begin
      if (st_l == 4'b1100) begin
        n_mem++;
        if (!rw_l) begin
          automatic int w = {sn_l, a_l[15:1]};
          if (!bw_l) zmem[w] = ad;
          else if (a_l[0]) zmem[w][7:0] = ad[7:0];
          else zmem[w][15:8] = ad[15:8];
          if (bw_l && ad[15:8] != ad[7:0]) fail("byte write not on both halves");
        end
      end else if (st_l == 4'b0010) begin
        n_io++;
        io_log.push_back(mk(a_l, !rw_l, bw_l, rw_l ? 16'h0000 : ad));
        if ($test$plusargs("v")) $display("t=%0t I/O %s %04h b%0d %04h", $time, rw_l ? "in " : "out", a_l, bw_l, ad);
      end else if (st_l == 4'b0110) begin
        n_nviack++; nvi <= 1'b0;
      end else if (st_l == 4'b0111) begin
        n_viack++; vi <= 1'b0;
      end else fail($sformatf("status %b", st_l));
    end
    // read capture, as the mainboard's ad_q
    unique case (st_l)
      4'b1100: rdata <= zmem[{sn_l, a_l[15:1]}];
      4'b0010: rdata <= {~a_l[7:0], a_l[7:0]};
      4'b0111: rdata <= {7'h7F, 8'h04, 1'b0};
      default: rdata <= 16'hFFFF;
    endcase
  end
  logic card_io;
  assign card_io = !busack_n && st_l == 4'b0010;
  assign io_addr = zm ? zm_addr : a_l;
  assign io_act  = zm ? zm_act  : (card_io && !ds_n);
  assign io_end  = zm ? zm_end  : (card_io && !ds_q && ds_n);

  // +v2: every 8086 request
  always @(posedge clk) if (dut.start && $test$plusargs("v2"))
    $display("t=%0t 8086 %s%s%s %05h w%0d d %04h", $time, dut.c_inta ? "inta" : dut.c_wr ? "wr" : "rd",
             dut.c_io ? " io" : "", dut.x_bus ? "" : " local", dut.c_addr, dut.c_word, dut.c_dout);

  int n_nmi = 0;
  logic nmi_q = 1'b1;
  always @(posedge clk) begin
    nmi_q <= nmi_n;
    if (nmi_q && !nmi_n) n_nmi++;
  end

  task automatic z_out(input logic [15:0] port);
    if (!busack_n) fail("Z8001 I/O while granted");
    @(posedge clk); zm <= 1'b1; zm_addr <= port;
    repeat (4) @(posedge clk); zm_act <= 1'b1;
    repeat (24) @(posedge clk); zm_act <= 1'b0; zm_end <= 1'b1;
    @(posedge clk); zm_end <= 1'b0;
    @(posedge clk); zm <= 1'b0;
  endtask

  // ---- test program image ---------------------------------------------------------
  logic [7:0] img [0:18431];
  string img_file;

  task automatic load_image();
    int fd, n;
    if (!$value$plusargs("img=%s", img_file)) img_file = "obj_dir/apb_test.rom";
    fd = $fopen(img_file, "rb");
    if (fd == 0) $fatal(1, "cannot open %s", img_file);
    n = $fread(img, fd);
    $fclose(fd);
    if (n != 18432) $fatal(1, "%s: %0d bytes", img_file, n);
    for (int i = 0; i < 18432; i++) begin
      @(posedge clk); ld_we <= 1'b1; ld_addr <= 15'(i); ld_data <= img[i];
    end
    @(posedge clk); ld_we <= 1'b0;
  endtask

  function automatic logic [15:0] rom_w(input int off);
    return {img[off + 1], img[off]};
  endfunction

  // Expected word at 8086 page p, offset 0x10.
  function automatic logic [15:0] page_exp(input int p);
    logic [3:0] s; logic [1:0] q; logic [3:0] n;
    n = 4'(p >> 2); q = 2'(p);
    case (n)
      4'h0: return zinit(4'd0, {q, 14'h10});
      4'h1: return zinit(4'd2, {q, 14'h10});
      4'h2: return zinit({3'b100, q[1]}, {1'b1, q[0], 14'h10});
      4'h3, 4'h4, 4'h5, 4'h6: return zinit(n + 4'd8, {q, 14'h10});
      4'h7: return q == 2'd3 ? 16'hFFFF : zinit(4'hF, {q, 14'h10});
      4'hE: return zinit(4'd3, {q, 14'h10});
      4'hF: case (q)
              2'd0: return zinit(4'd0, 16'h0010);
              2'd1: return zinit(4'd3, 16'h0010);
              2'd2: return 16'hFFFF;
              default: return rom_w(16'h0010);
            endcase
      default: return 16'hFFFF;
    endcase
  endfunction

  // Z word at segment 0 (8086 page 0).
  function automatic logic [15:0] z0(input int a);
    return zmem[a >> 1];
  endfunction

  task automatic run_program(input int pass);
    int t0;
    logic [15:0] i2, i4, i6, i8;
    io_log.delete();
    n_nviack = 0; n_viack = 0;
    z_out(16'h3FFC);
    t0 = 0;
    while (!(busack_n == 1'b0)) begin @(posedge clk); t0++; if (t0 > 1000) break; end
    if (busack_n) begin fail("no /BUSACK after SETRUN"); return; end
    if (!dut.u_cpu.reset_n) begin
      repeat (2) @(posedge clk);
      if (!dut.u_cpu.reset_n) fail("8086 still in reset while granted");
    end
    // interrupts on the program's signal
    wait (io_log.size() == 7);
    if (io_log[6].a != 16'h0181 || io_log[6].d[7:0] != 8'h01) fail("no interrupt signal write");
    repeat (200) @(posedge clk);
    nvi <= 1'b1;
    t0 = 0;
    while (nvi && t0 < 200000) begin @(posedge clk); t0++; end
    if (nvi) fail("NVI never acknowledged");
    vi <= 1'b1;                                     // during the NVI entry: must wait for IRET
    t0 = 0;
    while (vi && t0 < 200000) begin @(posedge clk); t0++; end
    if (vi) fail("VI never acknowledged");
    t0 = 0;
    while (run && t0 < 2000000) begin @(posedge clk); t0++; end
    if (run) begin fail("8086 never cleared run"); return; end
    repeat (200) @(posedge clk);
    if (!busack_n) fail("/BUSACK held after CLRRUN");
    if (dut.u_cpu.reset_n) fail("8086 not in reset after CLRRUN");

    // scoreboard
    if (z0(0) != 16'h1234) fail($sformatf("word 0: %04h", z0(0)));
    i2 = zinit(0, 2); i4 = zinit(0, 4); i6 = zinit(0, 6); i8 = zinit(0, 8);
    if (z0(2) != {i2[15:8], 8'hAB}) fail($sformatf("byte 2: %04h", z0(2)));
    if (z0(4) != {8'hCD, i4[7:0]}) fail($sformatf("byte 5: %04h", z0(4)));
    if (z0(6) != {8'h78, i6[7:0]} || z0(8) != {i8[15:8], 8'h56})
      fail($sformatf("odd word 7: %04h %04h", z0(6), z0(8)));
    for (int p = 0; p < 64; p++)
      if (z0(16'h100 + 2 * p) != page_exp(p))
        fail($sformatf("page %02h: %04h, expected %04h", p, z0(16'h100 + 2 * p), page_exp(p)));
    i2 = z0(16'h200); i4 = z0(16'h204);
    if (i2[7:0] != 8'h61) fail($sformatf("IN 4060: %02h", i2[7:0]));
    if (z0(16'h202) != 16'hBF40) fail($sformatf("IN 4140 word: %04h", z0(16'h202)));
    if (i4[7:0] != 8'h9D) fail($sformatf("IN 4063: %02h", i4[7:0]));
    if (z0(16'h300) != 16'h0101) fail($sformatf("interrupt counts: %04h", z0(16'h300)));
    if (z0(16'h206) != 16'h2468 || z0(16'h208) != 16'h1357)
      fail($sformatf("odd stack: %04h %04h", z0(16'h206), z0(16'h208)));
    if (z0(16'h20A) != 16'h0000) fail("push/pop loop count wrong");
    if (z0(16'h20E) != 16'h0000 || z0(16'h226) != z0(16'h106))
      fail($sformatf("REP MOVSW at an odd address: CX %04h", z0(16'h20E)));
    if (z0(16'h20C) != 16'h7FF9) fail($sformatf("VI taken inside the NVI entry: SP %04h", z0(16'h20C)));
    if (n_nviack != 1 || n_viack != 1) fail($sformatf("acks: NVI %0d VI %0d", n_nviack, n_viack));
    begin
      io_t e[$];
      e.push_back(mk(16'h0140, 1, 0, 16'h00C8)); e.push_back(mk(16'h0021, 1, 1, 16'h5A5A));
      e.push_back(mk(16'h0060, 1, 1, 16'h3C3C)); e.push_back(mk(16'h0061, 0, 1, 16'h0000));
      e.push_back(mk(16'h0140, 0, 0, 16'h0000)); e.push_back(mk(16'h0062, 0, 1, 16'h0000));
      e.push_back(mk(16'h0181, 1, 1, 16'h0101)); e.push_back(mk(16'h0181, 1, 1, 16'h0202));
      if (io_log.size() != 9) fail($sformatf("%0d I/O cycles", io_log.size()));
      for (int i = 0; i < e.size() && i < io_log.size(); i++)
        if (io_log[i].a != e[i].a || io_log[i].w != e[i].w || io_log[i].b != e[i].b || io_log[i].d != e[i].d)
          fail($sformatf("I/O %0d: %04h w%0d b%0d %04h", i, io_log[i].a, io_log[i].w, io_log[i].b, io_log[i].d));
      if (io_log.size() == 9 && (io_log[8].a != 16'h3FFA || !io_log[8].w || io_log[8].b))
        fail("CLRRUN cycle");
    end
    $display("run %0d: %0d memory cycles, %0d I/O cycles, NMI %0d", pass, n_mem, n_io, n_nmi);
  endtask

  initial begin
    int q[$];
    // 1
    q = {}; seq(q, 1, 7);                                    check_cfg(3'd5, "128K B/W", q);
    q = {}; seq(q, 1, 9); q.push_back(16); q.push_back(17); q.push_back(24); q.push_back(25);
                                                              check_cfg(3'd7, "B/W 32K", q);
    q = {}; seq(q, 1, 31);                                   check_cfg(3'd6, "B/W 128K", q);
    q = {}; seq(q, 1, 7); q.push_back(9); q.push_back(16); q.push_back(17); q.push_back(24); q.push_back(25);
                                                              check_cfg(3'd3, "4 col 32K", q);
    q = {}; seq(q, 1, 7); q.push_back(9); q.push_back(17); q.push_back(24); q.push_back(25);
                                                              check_cfg(3'd2, "8 col 32K", q);
    q = {}; seq(q, 1, 7); seq(q, 9, 31);                     check_cfg(3'd1, "4 col 128K", q);
    q = {}; seq(q, 1, 7); seq(q, 9, 15); seq(q, 17, 31);     check_cfg(3'd0, "8 col 128K", q);

    // 2, 3
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    load_image();
    repeat (20) @(posedge clk);
    z_out(16'h3FFA);
    repeat (50) @(posedge clk);
    if (n_nmi != 1) fail($sformatf("probe: %0d NMI", n_nmi));
    if (run || !busreq_n) fail("probe set run");
    run_program(1);
    if (n_nmi != 2) fail($sformatf("%0d NMI after the 8086 release", n_nmi));
    run_program(2);
    fitted <= 1'b0;
    repeat (20) @(posedge clk);
    z_out(16'h3FFA);
    z_out(16'h3FFC);
    repeat (200) @(posedge clk);
    if (n_nmi != 3) fail($sformatf("not fitted: NMI count %0d", n_nmi));
    if (!busreq_n || !busack_n) fail("not fitted: bus requested");

    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d errors", errors);
    $finish;
  end

  initial begin
    #5ms;
    $display("FAIL: timeout");
    $finish;
  end
endmodule
`default_nettype wire
