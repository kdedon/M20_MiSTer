// m20_mainboard running boot ROM 1.0 (boot.rom) against a behavioural
// SDRAM-latency model and the m20_stubs peripherals.
//
// Reference model, built from the CPU pins only (independent of the
// mainboard's own latches and decode):
//   * boot overlay: set at reset, cleared at the end of the first cycle
//     with A3 = 1; while set every memory cycle reads ROM0;
//   * otherwise the target of every memory cycle comes from the PROM
//     mapping tables (prom_vec.txt);
//     DRAM cycles must issue exactly one request with that physical
//     address, others none; reads must return the shadow DRAM word, the
//     boot.rom word, or 0xFFFF;
//   * SEGT after each /AS: status 1000-1101 with SN >= 16;
//   * port 0x21: read = {cfg, 1, za, latch[2:0]}, write latch outputs.
// Ordered milestones: reset vector, overlay clear on clrb <4>FFFF, memory
// size at memtest_ok, SEGT on ld r1,<7F>0000, check_devices, then the device
// probes up to chk_disk (VI test passed).
//
// Plusargs: +cfg=<code> (default 5), +za=<0|1> (default 1),
//           +rom=<file> (default boot.rom), +maxclk=<n>, +trace,
//           +lat=<n> SDRAM base latency in clocks (default 4)
`default_nettype none
module tb_bus;
  import z8000_zbus_pkg::*;

  logic clk = 1'b0;
  always #10417 clk = ~clk;          // 48 MHz

  logic rst_n = 1'b0;
  logic [2:0] cfg;
  logic       za;
  logic       rom_wr = 1'b0;
  logic [15:0] rom_addr = 16'd0;
  logic        rom_start = 1'b0;
  logic [7:0]  rom_data = 8'd0;

  // ---- DUT ----
  logic [23:1] mem_addr;
  logic mem_rd, mem_wr, mem_rvalid, mem_ack, mem_ready, mem_refresh_ok;
  logic [1:0] mem_be;
  logic [15:0] mem_wdata, mem_rdata;
  logic vram_we; logic [1:0] vram_plane, vram_be; logic [13:1] vram_addr; logic [15:0] vram_wdata;
  logic [15:0] io_addr, io_wdata;
  logic io_rd, io_wr, io_rd_end, io_wr_end;
  logic cs_fdc, cs_latch, cs_crtc, cs_ppi, cs_kbd, cs_ser, cs_pit, cs_pic, cs_pal;
  logic [7:0] fdc_rdata, crtc_rdata, ppi_rdata, kbd_rdata, ser_rdata, pit_rdata;
  logic [15:0] pic_rdata;
  logic pic_int, pic_inta_n, pit_out2, crt_fetch;
  logic [1:0] fdc_ds; logic fdc_motor, fdc_dden_n, fdc_tg43;
  logic ce16, ce_pit, ce_usart, ce_fdc;

  m20_mainboard #(.PROM_FILE("../../rtl/bus/m20_prom.hex")) dut (
    .clk(clk), .rst_n(rst_n), .ce16(ce16), .ce_pit(ce_pit), .ce_usart(ce_usart), .ce_fdc(ce_fdc),
    .cfg_code(cfg), .cfg_za(za), .cfg_spare1(1'b1), .rom_wr(rom_wr), .rom_addr(rom_addr), .rom_data(rom_data),
    .rom_ext(1'b0), .rom_start(rom_start),
    .mem_addr(mem_addr), .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_be(mem_be), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_rvalid(mem_rvalid), .mem_ack(mem_ack), .mem_ready(mem_ready),
    .mem_refresh_ok(mem_refresh_ok),
    .vram_we(vram_we), .vram_plane(vram_plane), .vram_addr(vram_addr), .vram_be(vram_be),
    .vram_wdata(vram_wdata),
    .io_addr(io_addr), .io_wdata(io_wdata), .io_rd(io_rd), .io_wr(io_wr),
    .io_rd_end(io_rd_end), .io_wr_end(io_wr_end),
    .cs_fdc(cs_fdc), .cs_latch(cs_latch), .cs_crtc(cs_crtc), .cs_ppi(cs_ppi), .cs_kbd(cs_kbd),
    .cs_ser(cs_ser), .cs_pit(cs_pit), .cs_pic(cs_pic), .cs_pal(cs_pal),
    .fdc_rdata(fdc_rdata), .crtc_rdata(crtc_rdata), .ppi_rdata(ppi_rdata), .kbd_rdata(kbd_rdata),
    .ser_rdata(ser_rdata), .pit_rdata(pit_rdata), .pic_rdata(pic_rdata),
    .cs_exp(1'b0), .exp_rdata(8'hFF), .cs_exp16(1'b0), .exp_rdata16(16'hFFFF),
    .pic_int(pic_int), .pic_inta_n(pic_inta_n), .pit_out2(pit_out2), .crt_fetch(crt_fetch),
    .fdc_ds(fdc_ds), .fdc_motor(fdc_motor), .fdc_dden_n(fdc_dden_n), .fdc_tg43(fdc_tg43),
    .ext_busreq_n(1'b1), .ext_nmi_n(1'b1), .ext_busack_n(), .ext_clk_rise(), .ext_as_n(1'b1),
    .ext_ds_n(1'b1), .ext_ad(16'h0000), .ext_ad_drive(1'b0), .ext_sn(7'd0), .ext_st(4'd0),
    .ext_r_w(1'b1), .ext_b_w(1'b0), .ext_rdata(), .nvi()
  );

  int n_rd, n_wr, n_kbd_tx, n_inta;
  sdram_lat u_sdram (
    .clk(clk), .rst_n(rst_n), .addr(mem_addr), .rd(mem_rd), .wr(mem_wr), .be(mem_be),
    .wdata(mem_wdata), .refresh_ok(mem_refresh_ok), .rdata(mem_rdata), .rvalid(mem_rvalid),
    .ack(mem_ack), .ready(mem_ready), .n_rd(n_rd), .n_wr(n_wr)
  );

  m20_stubs u_dev (
    .clk(clk), .rst_n(rst_n), .ce_pit(ce_pit),
    .io_addr(io_addr), .io_wdata(io_wdata), .io_rd(io_rd), .io_wr(io_wr),
    .io_rd_end(io_rd_end), .io_wr_end(io_wr_end),
    .cs_fdc(cs_fdc), .cs_crtc(cs_crtc), .cs_ppi(cs_ppi), .cs_kbd(cs_kbd), .cs_ser(cs_ser),
    .cs_pit(cs_pit), .cs_pic(cs_pic),
    .fdc_rdata(fdc_rdata), .crtc_rdata(crtc_rdata), .ppi_rdata(ppi_rdata), .kbd_rdata(kbd_rdata),
    .ser_rdata(ser_rdata), .pit_rdata(pit_rdata), .pic_rdata(pic_rdata),
    .pic_int(pic_int), .pic_inta_n(pic_inta_n), .pit_out2(pit_out2),
    .n_kbd_tx(n_kbd_tx), .n_inta(n_inta)
  );

  // CRT fetch every 64 clocks (1.333 us).
  int crt_ph = 0;
  always_ff @(posedge clk) crt_ph <= (crt_ph == 63) ? 0 : crt_ph + 1;
  assign crt_fetch = (crt_ph == 0);

  // ---- images ----
  logic [7:0] rom_img [0:8191];
  logic [7:0] prom_ref [0:1023];
  logic       prom_def [0:1023];
  logic [15:0] shadow [0:262143];

  function automatic logic [15:0] pattern(input logic [18:1] a);
    return 16'(a[16:1] * 16'h9E37) ^ {13'h0, a[18:16]};
  endfunction

  // ---- scoreboard state ----
  int  errors = 0;
  longint clk_n = 0, maxclk = 64'd2000000000;
  bit  trace = 0;
  int  stage = 0;          // ordered milestone index
  string stage_name [0:6] = '{"start", "reset vector", "boot overlay clear", "memory sizing",
                              "SEGT trap, check_devices", "device probes (chk_intrs)",
                              "NVI and VI tests (chk_disk)"};

  task automatic fail(input string msg);
    $display("FAIL [%0d] t=%0d clk=%0d: %s", stage, $time, clk_n, msg);
    errors++;
    if (errors > 10) $fatal(1, "too many errors");
  endtask

  // CPU pin view
  wire        as_n = dut.cpu_as_n, ds_n = dut.cpu_ds_n;
  wire [15:0] ad   = dut.cpu_ad_out;
  wire [6:0]  sn   = dut.cpu_sn;
  wire [3:0]  st   = dut.cpu_st;
  wire        rw   = dut.cpu_r_w, bw = dut.cpu_b_w;

  // Reference cycle (captured from the pins at /AS)
  logic        p_as = 1'b1, p_ds = 1'b1;
  logic [15:0] c_addr; logic [6:0] c_sn; logic [3:0] c_st; logic c_rw, c_bw;
  logic        ref_boot, ref_segt_n;
  int          c_kind;      // 0 none, 1 ROM0, 2 DRAM, 3 I/O, 4 other
  logic [18:1] c_phys;
  int          c_reqs;
  logic [15:0] c_wdata;
  logic [7:0]  ref_lat;

  localparam int K_NONE = 0, K_ROM = 1, K_DRAM = 2, K_IO = 3, K_OTHER = 4;

  // milestone bookkeeping
  int  n_reads = 0, n_writes = 0;
  int  mem_size_seen = -1, mem_size_exp;
  logic seen_memtest_ok = 0, seen_segt_rd = 0, seen_segt_ack = 0, seen_segv = 0;
  int  lat_reads = 0, lat_writes = 0;
  logic [22:0] last_pc = '1; int same_pc = 0;
  int  n_vram = 0;
  int  n_str = 0, n_freeze_rd = 0, n_nvi_ack = 0, n_vi_ack = 0, n_segt_ack = 0;
  longint t_rise = 0;
  int  min_period = 1000;

  function automatic int kind_of(input logic [7:0] q, output logic [18:1] phys,
                                 input logic [13:1] a);
    phys = {q[4:3], q[2:0], a};
    if (q[7:5] == 3'b110) return K_DRAM;
    if (q[7:5] == 3'b011 && q[2:0] == 3'd0) return K_ROM;
    return K_NONE;
  endfunction

  function automatic logic [9:0] prom_index(input logic [2:0] code, input logic [3:0] seg,
                                            input logic [1:0] blk, input logic st2);
    return {code[0], code[2], code[1], seg[3], st2, seg[2:0], blk};
  endfunction

  // label names for the IF1 trace
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
      16'h0AE0: return "sub4 (error print)";
      16'h0AF8: return "sub9 halt";
      default:  return "";
    endcase
  endfunction
  bit visited [int];

  task automatic advance(input int to);
    if (stage + 1 != to) fail($sformatf("milestone '%s' out of order (at '%s')", stage_name[to], stage_name[stage]));
    else $display("[%0d us] milestone %0d: %s", int'($time / 1000000), to, stage_name[to]);
    stage = to;
  endtask

  // ---- main monitor ----
  always @(posedge clk) if (rst_n) begin
    clk_n++;
    // CPU clock period: at least 4 x 62.5 ns
    if (dut.cpu_clk_rise) begin
      if (t_rise != 0 && int'(clk_n - t_rise) < min_period) min_period = int'(clk_n - t_rise);
      if (t_rise != 0 && clk_n - t_rise < 12) fail("CPU clock period below 250 ns");
      t_rise = clk_n;
    end
    if (dut.str_hold && dut.ce16) n_str++;
    if (dut.ce16 && dut.u29_q == 2'b01 && (dut.wait_rd || dut.wr_busy)) n_freeze_rd++;

    // End of a cycle with a data strobe (before a T1 on the same edge)
    if (!p_ds && ds_n) begin
      // /SEGT as the CPU saw it in this cycle (the flip-flop took it at /AS rise)
      if (dut.segt_n_q != ref_segt_n) fail($sformatf("/SEGT %b in <%02h>%04h st %h", dut.segt_n_q, c_sn, c_addr, c_st));
      if (c_kind == K_DRAM && c_reqs != 1) fail($sformatf("%0d DRAM requests in <%02h>%04h", c_reqs, c_sn, c_addr));
      if (!c_rw) begin
        n_writes++;
        if (trace) $display("W <%02h>%04h st %h %04h", c_sn, c_addr, c_st, c_wdata);
        if (c_kind == K_DRAM) begin
          if (!c_bw || !c_addr[0]) shadow[c_phys][15:8] = c_wdata[15:8];
          if (!c_bw ||  c_addr[0]) shadow[c_phys][7:0]  = c_wdata[7:0];
        end
        on_write();
      end
      if (ref_boot && c_addr[3]) ref_boot = 1'b0;
    end
    // /AS fall: a new cycle
    if (p_as && !as_n) begin
      c_addr = ad; c_sn = sn; c_st = st; c_rw = rw; c_bw = bw; c_reqs = 0;
      if (c_st[3] && !c_st[1]) begin
        if (ref_boot) begin c_kind = K_ROM; c_phys = '0; end
        else begin
          logic [9:0] pi;
          pi = prom_index(cfg, c_sn[3:0], c_addr[15:14], c_st[2]);
          if (!prom_def[pi]) begin fail($sformatf("no Appendix A entry for PROM %03h", pi)); c_kind = K_NONE; end
          else c_kind = kind_of(prom_ref[pi], c_phys, c_addr[13:1]);
        end
      end else if (c_st[3]) c_kind = K_NONE;
      else if (c_st == ST_IO) c_kind = K_IO;
      else c_kind = K_OTHER;
      if (c_st == ST_NVI_ACK) n_nvi_ack++;
      if (c_st == ST_VI_ACK)  n_vi_ack++;
      if (c_st == ST_SEGMENT_TRAP) begin
        n_segt_ack++;
        if (seen_segt_rd && !seen_segt_ack) seen_segt_ack = 1;
        else fail("segment trap acknowledge without a trapping access");
      end
    end
    // /AS rise: SEGT reference
    if (!p_as && as_n) ref_segt_n = !(c_st[3] && !(c_st[2] && c_st[1]) && c_sn[6:4] != 3'd0);

    // DRAM requests (first clock of each)
    if ((mem_rd || mem_wr) && !req_q) begin
      c_reqs++;
      if (c_kind != K_DRAM) fail($sformatf("DRAM request in a non-DRAM cycle <%02h>%04h st %h", c_sn, c_addr, c_st));
      else if (mem_addr != {5'd0, c_phys}) fail($sformatf("DRAM address %06h, expected %06h for <%02h>%04h",
                                                    {mem_addr, 1'b0}, {c_phys, 1'b0}, c_sn, c_addr));
      if (mem_wr) begin
        logic [1:0] be_exp;
        be_exp = !c_bw ? 2'b11 : (c_addr[0] ? 2'b01 : 2'b10);
        if (c_rw) fail("DRAM write in a read cycle");
        if (mem_be != be_exp) fail($sformatf("byte enables %b, expected %b", mem_be, be_exp));
        if (mem_wdata != ad) fail("write data differs from AD");
        if (vram_we != (c_phys[18:14] inside {5'b00000, 5'b01000, 5'b10000, 5'b11000}))
          fail($sformatf("vram_we %b for phys %06h", vram_we, {c_phys, 1'b0}));
        if (vram_we && (vram_plane != c_phys[18:17] || vram_addr != c_phys[13:1] ||
                        vram_be != be_exp || vram_wdata != ad))
          fail("video snoop payload differs");
        if (vram_we) n_vram++;
      end else if (vram_we) begin
        fail("vram_we on a read");
      end
    end

    // Write: data on AD at the /DS fall
    if (p_ds && !ds_n && !c_rw) c_wdata = ad;

    // Read data taken by the CPU
    if (dut.cpu_clk_rise && dut.u58.bus_done && c_rw && c_st != ST_INTERNAL_OP && c_st != ST_REFRESH) begin
      logic [15:0] got, exp;
      got = dut.ad_q;
      n_reads++;
      case (c_kind)
        K_ROM:  exp = {rom_img[{c_addr[12:1], 1'b0}], rom_img[{c_addr[12:1], 1'b1}]};
        K_DRAM: exp = shadow[c_phys];
        K_NONE: exp = 16'hFFFF;
        K_IO:   exp = io_expect(got);
        default: exp = got;
      endcase
      if (got != exp) fail($sformatf("read <%02h>%04h st %h kind %0d: %04h, expected %04h",
                                     c_sn, c_addr, c_st, c_kind, got, exp));
      if (trace) $display("R <%02h>%04h st %h %04h", c_sn, c_addr, c_st, got);
      on_read(got);
    end

    if (dut.boot_q != ref_boot && ds_n && p_ds) fail("boot overlay flip-flop differs from reference");
    p_as = as_n; p_ds = ds_n;
  end

  logic req_q = 1'b0;
  always @(posedge clk) req_q <= (mem_rd || mem_wr) && !mem_ack;

  // ---- I/O reference ----
  function automatic logic [15:0] io_expect(input logic [15:0] got);
    if (c_addr[15:11] != 5'd0) return 16'hFFFF;
    if (!c_addr[8]) begin
      unique case (c_addr[7:5])
        3'd1:    return {8'hFF, cfg, 1'b1, za, ref_lat[2:0]};
        3'd0, 3'd3, 3'd4, 3'd5, 3'd6: return {8'hFF, got[7:0]};
        default: return 16'hFFFF;
      endcase
    end
    unique case (c_addr[7:5])
      3'd1:    return {8'hFF, got[7:0]};
      3'd2:    return {7'h7F, got[8:1], 1'b1};
      default: return 16'hFFFF;
    endcase
  endfunction

  function automatic logic is_latch(input logic [15:0] a);
    return a[15:11] == 5'd0 && a[8:5] == 4'b0001;
  endfunction

  int lat_chk = 0;
  task automatic on_write();
    if (c_kind == K_IO && is_latch(c_addr)) begin
      ref_lat = c_wdata[7:0];
      lat_writes++;
      lat_chk = 3;
    end
    // overlay clear: clrb <4>FFFF is the first write
    if (stage == 1 && n_writes == 1) begin
      if (c_sn != 7'h04 || c_addr != 16'hFFFF || !c_bw) fail($sformatf("first write <%02h>%04h, expected clrb <4>FFFF", c_sn, c_addr));
      else if (u_sdram.n_wr != 0 || u_sdram.n_rd != 0) fail("DRAM used while the overlay was set");
    end
    if (stage == 1 && n_writes == 2) begin
      if (c_kind != K_DRAM || c_phys != 18'h0A001) fail($sformatf("second write <%02h>%04h not DRAM0 14002", c_sn, c_addr));
      else advance(2);
    end
    // memory size: ldb 0x20001,rh5 after memtest_ok
    if (seen_memtest_ok && mem_size_seen < 0 && c_sn == 7'h02 && c_addr == 16'h0001 && c_bw && c_st[3]) begin
      mem_size_seen = c_wdata[7:0];
      if (mem_size_seen != mem_size_exp) fail($sformatf("memory size %0d blocks, expected %0d", mem_size_seen, mem_size_exp));
      else begin
        $display("    memtest: %0d x 16 KB blocks (config code %0d)", mem_size_seen, cfg);
        advance(3);
      end
    end
  endtask

  // after a latch write, the outputs follow
  always @(posedge clk) if (lat_chk != 0) begin
    if (lat_chk == 1 && {fdc_tg43, fdc_dden_n, fdc_motor, fdc_ds} != {ref_lat[7], ref_lat[3:0]})
      fail($sformatf("port 0x21 outputs %b, latch %02h", {fdc_tg43, fdc_dden_n, fdc_motor, fdc_ds}, ref_lat));
    lat_chk = lat_chk - 1;
  end

  task automatic on_read(input logic [15:0] got);
    logic [22:0] pc;
    if (c_kind == K_IO && is_latch(c_addr)) begin
      lat_reads++;
      if (lat_reads == 1) begin
        if (lat_writes != 1 || got[7:0] != {cfg, 1'b1, za, 3'b000})
          fail($sformatf("first port 0x21 read %02h", got[7:0]));
        else $display("    port 0x21: wrote 00, read %02h", got[7:0]);
      end
    end
    // ordered reset-vector check: the first four reads
    if (stage == 0) begin
      case (n_reads)
        1: if (c_sn != 0 || c_addr != 16'h0002 || got != 16'hC000) fail($sformatf("FCW read <%02h>%04h=%04h", c_sn, c_addr, got));
        2: if (c_sn != 0 || c_addr != 16'h0004 || got != 16'h8400) fail($sformatf("PC seg read <%02h>%04h=%04h", c_sn, c_addr, got));
        3: if (c_sn != 0 || c_addr != 16'h0006 || got != 16'h0150) fail($sformatf("PC off read <%02h>%04h=%04h", c_sn, c_addr, got));
        4: if (c_st != ST_INSTR_FETCH_FIRST || c_sn != 4 || c_addr != 16'h0150 || got != 16'h4C08)
             fail($sformatf("first fetch <%02h>%04h st %h = %04h", c_sn, c_addr, c_st, got));
           else advance(1);
        default: ;
      endcase
    end
    // SEGT read
    if (c_sn == 7'h7F && c_addr == 16'h0000 && c_st[3] && !seen_segt_rd) begin
      seen_segt_rd = 1;
      $display("    SEGT: read <7F>0000 st %h kind %0d data %04h", c_st, c_kind, got);
    end
    if (c_st == ST_INSTR_FETCH_FIRST) begin
      pc = {c_sn, c_addr};
      if (pc == last_pc && got == 16'hE8FF) same_pc++; else same_pc = 0;   // jr t,.
      last_pc = pc;
      if (c_sn == 7'h04 && label(c_addr) != "" && !visited.exists(int'(c_addr))) begin
        visited[int'(c_addr)] = 1;
        $display("[%0d us] IF1 <04>%04h %s", int'($time / 1000000), c_addr, label(c_addr));
      end
      if (c_sn == 7'h04) unique case (c_addr)
        16'h06FE: seen_memtest_ok = 1;
        16'h076E: if (seen_segt_ack) seen_segv = 1; else fail("segv entered without a segment trap");
        16'h0800: if (stage == 3 && seen_segv) advance(4); else fail("check_devices before the SEGT test passed");
        16'h09DC: if (stage == 4) advance(5);
        16'h0A3C: if (stage == 5) advance(6);
        16'h0268, 16'h02E0, 16'h0344, 16'h0584, 16'h06A6, 16'h06FC, 16'h077A, 16'h095C,
        16'h09C2, 16'h0A10: fail($sformatf("ROM reached failure label %s", label(c_addr)));
        default: ;
      endcase
      if (stage == 3 && !seen_segt_rd && c_addr == 16'h0800) fail("no <7F>0000 read");
    end
  endtask

  // ---- run ----
  initial begin
    int fd, n, code;
    string rom_file, line;
    if (!$value$plusargs("cfg=%d", code)) code = 5;
    cfg = 3'(code);
    za  = 1'b1;
    if ($value$plusargs("za=%d", code)) za = code[0];
    if (!$value$plusargs("rom=%s", rom_file)) rom_file = "boot.rom";
    void'($value$plusargs("maxclk=%d", maxclk));
    trace = $test$plusargs("trace");
    mem_size_exp = (cfg == 3'd5) ? 8 : (cfg == 3'd0) ? 14 : -1;

    fd = $fopen(rom_file, "rb");
    if (fd == 0) $fatal(1, "cannot open %s (run scripts/make_boot_rom.sh)", rom_file);
    n = $fread(rom_img, fd);
    $fclose(fd);
    if (n != 8192) $fatal(1, "%s: %0d bytes, expected 8192", rom_file, n);

    for (int i = 0; i < 1024; i++) prom_def[i] = 1'b0;
    fd = $fopen("prom_vec.txt", "r");
    if (fd == 0) $fatal(1, "cannot open obj_dir/prom_vec.txt");
    while ($fgets(line, fd)) begin
      int a, v;
      if ($sscanf(line, "%h %h", a, v) == 2) begin prom_ref[a] = 8'(v); prom_def[a] = 1'b1; end
    end
    $fclose(fd);
    for (int i = 0; i < 262144; i++) shadow[i] = pattern(18'(i));
    ref_boot = 1'b1; ref_segt_n = 1'b1; ref_lat = 8'h00; c_kind = K_OTHER; c_st = 4'hF;

    $display("tb_bus: config code %0d, ZA %0d, %s", cfg, za, rom_file);
    // ioctl download while reset is held
    repeat (4) @(posedge clk);
    rom_start <= 1'b1;
    @(posedge clk); rom_start <= 1'b0;
    for (int i = 0; i < 8192; i++) begin
      @(posedge clk); rom_wr <= 1'b1; rom_addr <= 16'(i); rom_data <= rom_img[i];
      @(posedge clk); rom_wr <= 1'b0;
    end
    repeat (8) @(posedge clk);
    rst_n <= 1'b1;

    while (stage < 6 && clk_n < maxclk) begin
      @(posedge clk);
      if (same_pc > 200) begin
        fail($sformatf("CPU looping at <%02h>%04h %s", last_pc[22:16], last_pc[15:0], label(last_pc[15:0])));
        break;
      end
    end
    // run on a little past chk_disk to see the disk probe start
    repeat (200000) @(posedge clk);

    $display("stats: %0d clocks, %0d reads, %0d writes, DRAM %0d rd %0d wr, %0d stretch steps, %0d DRAM-wait steps,",
             clk_n, n_reads, n_writes, n_rd, n_wr, n_str, n_freeze_rd);
    $display("       min CPU period %0d clocks, %0d NVI acks, %0d VI acks (%0d INTA), %0d seg-trap acks,",
             min_period, n_nvi_ack, n_vi_ack, n_inta, n_segt_ack);
    $display("       port 0x21 %0d reads %0d writes, %0d keyboard bytes, %0d plane writes, last IF1 <%02h>%04h",
             lat_reads, lat_writes, n_kbd_tx, n_vram, last_pc[22:16], last_pc[15:0]);
    if (stage < 6) fail($sformatf("stopped at milestone '%s'", stage_name[stage]));
    if (errors == 0) $display("PASS");
    else $fatal(1, "%0d errors", errors);
    $finish;
  end
endmodule
`default_nettype wire
