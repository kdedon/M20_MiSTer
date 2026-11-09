// c900_sdram (with the vendored controller) against two timing-checking
// SDRAM models wired as the 128 MB MiSTer module (chip 1 selected by nCS
// High).  The controller's outputs reach the chips PAD_DLY ns late (clock
// included) and read data comes back with the chips' tAC/tOH plus RET_DLY.
//
// Phase C900: requests one at a time, the next one any number of clocks
// after ack (at least GUARD after an ack in which a refresh starts),
// refresh_ok given at random only when no request is first seen within
// GUARD clocks.  Every read must be acked exactly READ_LAT clocks after the
// clock it was first seen: write-then-read,
// read-then-read, refresh just before a read included.
// Phase WORST: a refresh started from refresh_ok, or from the clock after
// a read's or a write's ack, then a read first seen D = 1..12 clocks after
// the refresh's start clock, each case 4 times: from D = GUARD on, every
// read must meet the deadline; below it some must miss (the guard is
// tight), none by more than 3 clocks.
// Phase DENSE: refresh_ok never given, the next request 0..3 clocks after
// ack: every refresh starts after an ack and delays the next request by at
// most 3 clocks; data and the refresh interval are still checked.
// Every read is compared with a reference array.
`timescale 1ns/1ps
`default_nettype none
module tb_sdram;
  parameter int  N_C900   = 120000;
  parameter int  N_FORCE  = 30000;  // phase DENSE
  parameter int  POOL     = 512;
  parameter int  GUARD    = 4;     // refresh_ok: no request first seen within GUARD clocks
  parameter int  READ_LAT = 4;
  parameter real PAD_DLY  = 3.0;
  parameter real RET_DLY  = 2.0;
  // The controller gives tRCD and tRP two clk_ram clocks, 20.83 ns: the
  // MT48LC16M16A2-75 figure (20 ns), 0.17 ns under the AS4C32M16SB-7 (21 ns).
  parameter real T_RCD    = 20.0;
  parameter real T_RP     = 20.0;

  localparam real TQ = 1000.0 / 96.0 / 2.0;

  // clk = clk_ram / 2, rising edges together
  logic clk_ram = 1'b1, clk = 1'b0;
  always #(TQ) begin
    clk_ram = ~clk_ram;
    if (clk_ram) clk = ~clk;
  end

  logic        rst_n = 1'b0;
  logic [23:1] addr = '0;
  logic        rd = 1'b0, wr = 1'b0;
  logic [1:0]  be = 2'b11;
  logic [15:0] wdata = '0;
  logic [15:0] rdata;
  logic        ack, rvalid, ready;
  logic        refresh_ok = 1'b0;

  wire         s_clk, s_cke, s_dqml, s_dqmh, s_ncs, s_nras, s_ncas, s_nwe;
  wire  [12:0] s_a;
  wire  [1:0]  s_ba;
  tri   [15:0] s_dq;

  c900_sdram dut (
    .clk(clk), .clk_ram(clk_ram), .rst_n(rst_n), .rst_ram_n(rst_n), .refresh_ok(refresh_ok),
    .ready(ready), .addr(addr), .rd(rd), .wr(wr), .be(be), .wdata(wdata), .rdata(rdata),
    .rvalid(rvalid), .ack(ack),
    .sdram_clk(s_clk), .sdram_cke(s_cke), .sdram_a(s_a), .sdram_ba(s_ba), .sdram_dq(s_dq),
    .sdram_dqml(s_dqml), .sdram_dqmh(s_dqmh), .sdram_ncs(s_ncs), .sdram_nras(s_nras),
    .sdram_ncas(s_ncas), .sdram_nwe(s_nwe)
  );

  // board: every controller output arrives PAD_DLY late
  logic        m_clk = 1'b0, m_cke = 1'b0, m_dqml = 1'b1, m_dqmh = 1'b1;
  logic        m_ncs = 1'b1, m_nras = 1'b1, m_ncas = 1'b1, m_nwe = 1'b1;
  logic [12:0] m_a = '0;
  logic [1:0]  m_ba = '0;
  always @(s_clk) m_clk <= #(PAD_DLY) s_clk;
  always @(s_cke or s_a or s_ba or s_dqml or s_dqmh or s_ncs or s_nras or s_ncas or s_nwe) begin
    m_cke  <= #(PAD_DLY) s_cke;
    m_a    <= #(PAD_DLY) s_a;
    m_ba   <= #(PAD_DLY) s_ba;
    m_dqml <= #(PAD_DLY) s_dqml;
    m_dqmh <= #(PAD_DLY) s_dqmh;
    m_ncs  <= #(PAD_DLY) s_ncs;
    m_nras <= #(PAD_DLY) s_nras;
    m_ncas <= #(PAD_DLY) s_ncas;
    m_nwe  <= #(PAD_DLY) s_nwe;
  end

  sdram_model #(.ROW_BITS(13), .COL_BITS(10), .T_RCD(T_RCD), .T_RP(T_RP),
                .T_AC2(6.0 + RET_DLY), .T_AC3(5.4 + RET_DLY), .T_OH(2.5 + RET_DLY)) chip0 (
    .clk(m_clk), .cke(m_cke), .a(m_a), .ba(m_ba), .dq(s_dq), .dqml(m_dqml), .dqmh(m_dqmh),
    .ncs(m_ncs), .nras(m_nras), .ncas(m_ncas), .nwe(m_nwe)
  );
  sdram_model #(.ROW_BITS(13), .COL_BITS(10), .T_RCD(T_RCD), .T_RP(T_RP),
                .T_AC2(6.0 + RET_DLY), .T_AC3(5.4 + RET_DLY), .T_OH(2.5 + RET_DLY)) chip1 (
    .clk(m_clk), .cke(m_cke), .a(m_a), .ba(m_ba), .dq(s_dq), .dqml(m_dqml), .dqmh(m_dqmh),
    .ncs(~m_ncs), .nras(m_nras), .ncas(m_ncas), .nwe(m_nwe)
  );

  // ---------------------------------------------------------- reference
  logic [15:0] refmem [logic [23:1]];
  logic [23:1] pool [POOL];

  initial begin
    pool[0] = 23'h000000;
    pool[1] = 23'h7FFFFF;
    pool[2] = 23'h0001FF;            // last column
    pool[3] = 23'h000200;            // row 1
    pool[4] = 23'h400000;            // bank 1
    pool[5] = 23'h3FFE00;            // last row, bank 0
    for (int i = 6; i < POOL; i++) begin
      if (i % 4 == 0) pool[i] = pool[i - 1] + 23'h1;      // neighbours, same row
      else            pool[i] = 23'($urandom);
    end
  end

  // ------------------------------------------------------------- client
  typedef enum logic [2:0] {P_INIT, P_FILL, P_C900, P_WORST, P_DENSE, P_DONE} phase_e;
  phase_e phase = P_INIT;

  longint cyc = 0, seen_cyc = 0;
  bit     busy = 1'b0, seen = 1'b0, last_wr = 1'b0, is_rd = 1'b0;
  int     gap = 0;
  int     n_done = 0, n_reads = 0, n_writes = 0, n_bytew = 0;
  int     n_wr_rd = 0, n_ref_rd = 0, n_late = 0, mismatches = 0;
  int     lat_rd_min = 1 << 30, lat_rd_max = 0, lat_wr_max = 0, lat_force_max = 0;
  int     fill_i = 0;
  int     n_ref_c900 = 0, n_ref_ack = 0, n_forced = 0;
  // phase WORST: source 0 refresh_ok, 1 after a read's ack, 2 after a write's ack
  localparam int W_DMIN = 1, W_DMAX = 12, W_REPS = 4;
  typedef enum logic [2:0] {W_ARM, W_WAITGO, W_DELAY, W_READ, W_NEXT} wstate_e;
  wstate_e w_st = W_ARM;
  int     w_src = 0, w_d = W_DMIN, w_rep = 0, w_win = 0, w_miss = 0, w_bad = 0, w_tight = 0;
  longint w_go = 0;
  int     w_late [3][W_DMAX + 1];
  int     w_done [3][W_DMAX + 1];
  initial foreach (w_late[i, j]) begin w_late[i][j] = 0; w_done[i][j] = 0; end
  longint last_ref_go = -100;
  longint last_ack = 0;

  function automatic int pick_gap();
    int r;
    r = int'($urandom % 100);
    if (r < 30) return 0;
    if (r < 60) return 1 + int'($urandom % 4);
    if (r < 95) return 5 + int'($urandom % 30);
    return 35 + int'($urandom % 400);
  endfunction

  task automatic issue(input bit is_wr, input logic [23:1] ad, input logic [1:0] b);
    addr  <= ad;
    rd    <= !is_wr;
    wr    <= is_wr;
    be    <= is_wr ? b : 2'b11;
    wdata <= 16'($urandom);
    busy  <= 1'b1;
    seen  <= 1'b0;
  endtask

  task automatic issue_random();
    int r;
    logic [1:0] b;
    r = int'($urandom % 100);
    b = (r < 15) ? 2'b01 : (r < 30) ? 2'b10 : 2'b11;
    issue(($urandom % 2) == 1, pool[$urandom % POOL], b);
  endtask

  // A refresh taken just before a request, for the coverage count.
  always @(posedge clk) if (dut.ref_go) last_ref_go <= cyc;
  always @(posedge clk) if (dut.ref_go && phase == P_C900) begin
    if (refresh_ok)     n_ref_c900++;
    else if (dut.ack_q) n_ref_ack++;
    else                n_forced++;
  end

  // refresh_ok: only while no request is outstanding and none starts within
  // GUARD clocks, and then only at random.
  always @(posedge clk)
    refresh_ok <= (phase == P_C900) ? !busy && (gap >= GUARD) && ($urandom_range(0, 2) != 0) :
                  (phase == P_WORST) && w_win > 0;

  always @(posedge clk) begin
    int lat;
    logic [15:0] m;
    cyc <= cyc + 1;
    if (busy && !seen) begin
      seen     <= 1'b1;       // the controller samples the request at this edge
      seen_cyc <= cyc;
    end
    if (rst_n && ready) begin
      if (busy && ack) begin
        lat = int'(cyc - seen_cyc) - 1;   // ack rose at the previous edge
        if (wr) begin
          m = refmem.exists(addr) ? refmem[addr] : 16'h0000;
          if (be[0]) m[7:0]  = wdata[7:0];
          if (be[1]) m[15:8] = wdata[15:8];
          refmem[addr] = m;
          n_writes++;
          if (be != 2'b11) n_bytew++;
          if (lat > lat_wr_max) lat_wr_max = lat;
        end else begin
          n_reads++;
          if (!rvalid) begin
            mismatches++;
            $display("read acked without rvalid");
          end
          if (refmem.exists(addr) && rdata !== refmem[addr]) begin
            mismatches++;
            if (mismatches <= 10)
              $display("MISMATCH addr %06h: got %04h want %04h", {addr, 1'b0}, rdata, refmem[addr]);
          end
          if (phase == P_C900) begin
            if (lat != READ_LAT) begin
              n_late++;
              if (n_late <= 10) $display("LATE read at %0t: %0d clocks (seen %0d, last ref_go %0d, last ack %0d)",
                                         $time, lat, seen_cyc, last_ref_go, last_ack);
            end
            if (lat < lat_rd_min) lat_rd_min = lat;
            if (lat > lat_rd_max) lat_rd_max = lat;
            if (last_wr) n_wr_rd++;
            if (seen_cyc - last_ref_go <= longint'(GUARD + 1)) n_ref_rd++;
          end else if (phase == P_WORST && w_st == W_READ) begin
            w_done[w_src][w_d]++;
            if (lat > lat_force_max) lat_force_max = lat;
            if (lat != READ_LAT) w_late[w_src][w_d]++;
          end else if (phase == P_DENSE && lat > lat_force_max) lat_force_max = lat;
        end
        last_wr <= wr;
        last_ack <= cyc;
        n_done++;
        busy <= 1'b0;
        rd   <= 1'b0;
        wr   <= 1'b0;
        if (phase == P_WORST) begin
          if (w_st == W_WAITGO) begin         // the refresh starts in this ack clock
            if (!dut.ref_go) w_miss++;
            w_go <= cyc;
            w_st <= W_DELAY;
          end
          if (w_st == W_READ)   w_st <= W_NEXT;
        end
        // phase C900 always leaves a refresh window soon
        gap  <= (phase == P_C900 && dut.ref_due_q) ? GUARD + int'($urandom % 3) :
                (phase == P_DENSE) ? int'($urandom % 4) : pick_gap();
        // D = 1: the read follows in the clock after the ack clock
        if (phase == P_WORST && w_st == W_WAITGO && w_d == 1) begin
          issue(1'b0, pool[$urandom % POOL], 2'b11);
          w_st <= W_READ;
        end
        if (n_done % 30000 == 0) begin
          $display("progress: %0d ops at %0t", n_done, $time);
          $fflush;
        end
      end else if (!busy) begin
        unique case (phase)
          P_INIT: phase <= P_FILL;
          P_FILL: begin
            if (fill_i < POOL) begin
              issue(1'b1, pool[fill_i], 2'b11);
              fill_i <= fill_i + 1;
            end else phase <= P_C900;
          end
          P_C900: begin
            if (n_done >= POOL + N_C900) phase <= P_WORST;
            else if (gap > 0) gap <= gap - 1;
            else issue_random();
          end
          P_WORST: begin
            if (w_win > 0) w_win <= w_win - 1;
            unique case (w_st)
              W_ARM: if (dut.ref_due_q) begin
                if (w_src == 0) begin
                  w_win <= 1;
                  w_st  <= W_WAITGO;
                end else begin
                  issue(w_src == 2, pool[$urandom % POOL], 2'b11);
                  w_st <= W_WAITGO;
                end
              end
              W_WAITGO: if (w_src == 0 && dut.ref_go) begin
                w_go <= cyc;
                w_st <= W_DELAY;
                if (w_d == 1) begin
                  issue(1'b0, pool[$urandom % POOL], 2'b11);
                  w_st <= W_READ;
                end
              end
              // D = request's first clock - the refresh_ok or ack clock
              W_DELAY: if (cyc == w_go + longint'(w_d) - 1) begin
                issue(1'b0, pool[$urandom % POOL], 2'b11);
                w_st <= W_READ;
              end
              W_NEXT: begin
                w_st <= W_ARM;
                if (w_rep < W_REPS - 1) w_rep <= w_rep + 1;
                else begin
                  w_rep <= 0;
                  if (w_d < W_DMAX) w_d <= w_d + 1;
                  else begin
                    w_d <= W_DMIN;
                    if (w_src < 2) w_src <= w_src + 1;
                    else phase <= P_DENSE;
                  end
                end
              end
              default: ;
            endcase
          end
          P_DENSE: begin
            if (n_done >= POOL + N_C900 + N_FORCE) phase <= P_DONE;
            else if (gap > 0) gap <= gap - 1;
            else issue_random();
          end
          P_DONE: ;
          default: ;
        endcase
      end
    end
  end

  initial begin
    repeat (7) @(posedge clk);
    #1 rst_n = 1'b1;
    wait (phase == P_DONE);
    repeat (20) @(posedge clk);
    $display("sdram tb: ops %0d (reads %0d, writes %0d, byte writes %0d)",
             n_done, n_reads, n_writes, n_bytew);
    $display("  chip 0: ACT %0d READ %0d WRITE %0d REF %0d, max REF gap %0.1f ns, errors %0d",
             chip0.n_act, chip0.n_rd, chip0.n_wr, chip0.n_ref, chip0.max_ref_gap, chip0.errors);
    $display("  chip 1: ACT %0d REF %0d, max REF gap %0.1f ns, errors %0d",
             chip1.n_act, chip1.n_ref, chip1.max_ref_gap, chip1.errors);
    $display("  C900 phase: reads %0d..%0d clocks after first seen (deadline %0d), %0d late;",
             lat_rd_min, lat_rd_max, READ_LAT, n_late);
    $display("    %0d reads right after a write, %0d within %0d clocks of a refresh;",
             n_wr_rd, n_ref_rd, GUARD + 1);
    $display("    refreshes %0d in refresh_ok clocks, %0d after an ack, %0d otherwise; write ack max %0d",
             n_ref_c900, n_ref_ack, n_forced, lat_wr_max);
    for (int src = 0; src < 3; src++) begin
      string line;
      line = "";
      for (int d = W_DMIN; d <= W_DMAX; d++) begin
        line = {line, $sformatf(" %0d/%0d", w_late[src][d], w_done[src][d])};
        if (d >= GUARD ? w_late[src][d] != 0 : w_done[src][d] != W_REPS) w_bad++;
        if (d < GUARD) w_tight += w_late[src][d];
      end
      $display("  worst case, refresh from %s: late/reads at D = %0d..%0d:%s",
               (src == 0) ? "refresh_ok  " : (src == 1) ? "a read ack  " : "a write ack ", W_DMIN, W_DMAX, line);
    end
    $display("  worst-case and dense phases: read latency max %0d", lat_force_max);
    if (mismatches == 0 && chip0.errors == 0 && chip1.errors == 0 && n_late == 0 &&
        n_forced == 0 && n_ref_rd > 0 && n_wr_rd > 0 && chip1.n_ref > 0 && chip1.n_act == 0 &&
        w_bad == 0 && w_tight > 0 && w_miss == 0 && lat_force_max > READ_LAT && lat_force_max <= READ_LAT + 3)
      $display("PASS");
    else begin
      $display("FAIL: %0d mismatches, %0d chip errors, %0d late, %0d forced",
               mismatches, chip0.errors + chip1.errors, n_late, n_forced);
      $fatal(1, "sdram tb failed");
    end
    $finish;
  end

  initial begin
    #(2.0e9);
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
