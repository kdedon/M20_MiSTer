// Behavioural 16-bit SDR SDRAM (4 banks, ROW_BITS x COL_BITS) for
// simulation.  Commands are decoded on the rising edge of clk; the
// protocol and the timing parameters below are checked with $error.
//
// Modelled: init order (>= T_INIT of clock with CKE high, PRECHARGE ALL,
// >= 2 AUTO REFRESH, LOAD MODE before any ACTIVE), bank state (ACTIVE to an
// open bank, READ/WRITE/auto-precharge to a closed bank), tRCD, tRP, tRAS
// (explicit PRECHARGE; an auto-precharge is held back to tRAS as the chips do),
// tRC, tRRD, tRFC, tMRD, tWR, refresh interval, input setup/hold, CAS
// latency from the mode register with tAC/tOH output timing, DQM write
// masking (latency 0) and read masking (latency 2), sequential read bursts
// of 1/2/4/8 with single-word writes, auto-precharge after READA (BL
// clocks) and WRITEA (1 clk + T_WR_AP).  Read data is unknown between tOH
// of one word and tAC of the next.  A11/A12 are ignored in column commands.
//
// Default timing is the worst of AS4C32M16SB-7 and MT48LC16M16A2-75.
`timescale 1ns/1ps
`default_nettype none
module sdram_model #(
  parameter int  ROW_BITS = 13,
  parameter int  COL_BITS = 9,
  parameter real T_INIT   = 100000.0,
  parameter real T_REFI   = 7812.5,
  parameter real T_RCD    = 21.0,
  parameter real T_RP     = 21.0,
  parameter real T_RAS    = 44.0,
  parameter real T_RC     = 66.0,
  parameter real T_RRD    = 15.0,
  parameter real T_RFC    = 70.0,
  parameter real T_WR     = 15.0,
  parameter real T_WR_AP  = 7.5,    // write auto-precharge: 1 clk + this
  parameter int  T_MRD    = 2,      // clocks
  parameter real T_AC2    = 6.0,
  parameter real T_AC3    = 5.4,
  parameter real T_OH     = 2.5,
  parameter real T_IS     = 1.5,
  parameter real T_IH     = 0.8
) (
  input  wire        clk,
  input  wire        cke,
  input  wire [12:0] a,
  input  wire [1:0]  ba,
  inout  wire [15:0] dq,
  input  wire        dqml,
  input  wire        dqmh,
  input  wire        ncs,
  input  wire        nras,
  input  wire        ncas,
  input  wire        nwe
);
  localparam real EPS = 0.001;

  int errors = 0;
  int n_ref  = 0;
  int n_act  = 0;
  int n_rd   = 0;
  int n_wr   = 0;
  real max_ref_gap = 0.0;

  // storage: key = {bank, row, col}
  logic [15:0] mem [longint unsigned];

  // mode register
  int  cl = 0;
  int  bl = 1;
  bit  mode_set = 0;

  // init tracking
  bit  cke_q = 0;
  real t_cke = -1.0;
  bit  pall_done = 0;
  int  init_refs = 0;
  bit  init_done = 0;

  // bank state
  bit          act   [4];
  int          row   [4];
  real         t_act [4];
  real         t_pre [4];       // precharge started
  bit          ap    [4];       // auto-precharge pending
  longint      ap_edge [4];     // read AP: edge index
  real         ap_time [4];     // write AP: earliest time
  real         t_wr  [4];       // last write
  real         t_last_act = -1.0e9;
  real         t_ref = -1.0e9;    // last REFRESH (tRFC)
  real         t_refi = -1.0e9;   // refresh interval start
  real         t_mrs_edge = -1;
  longint      mrs_edge = -100;
  longint      edge_n = 0;
  real         t_edge = -1.0e9;
  real         t_prev_edge = -1.0e9;

  // read pipeline: data for edge rp_edge[i]
  localparam int NRP = 16;
  bit          rp_v    [NRP];
  longint      rp_edge [NRP];
  logic [15:0] rp_data [NRP];
  logic [1:0]  dqm_d1 = 2'b11;   // DQM at the previous edge

  // output driver
  logic [15:0] dq_o = 16'h0;
  logic [1:0]  dq_en = 2'b00;
  int          drv_gen = 0;
  assign dq[7:0]  = dq_en[0] ? dq_o[7:0]  : 8'hzz;
  assign dq[15:8] = dq_en[1] ? dq_o[15:8] : 8'hzz;

  function automatic longint unsigned key(input int b, input int r, input int c);
    return (longint'(b) << (ROW_BITS + COL_BITS)) | (longint'(r) << COL_BITS) | longint'(c);
  endfunction

  function automatic logic [15:0] fetch(input longint unsigned k);
    if (mem.exists(k)) return mem[k];
    return 16'h5A00 ^ k[15:0];
  endfunction

  task automatic err(input string msg);
    errors++;
    $error("sdram_model @%0t: %s", $time, msg);
  endtask

  // ------------------------------------------------ input setup / hold
  real t_chg = -1.0e9;
  always @(a or ba or ncs or nras or ncas or nwe or dqml or dqmh or cke) begin
    if ($realtime > 0.0 && t_edge > 0.0 && ($realtime - t_edge) < T_IH - EPS)
      err($sformatf("hold violation: input changed %0.3f ns after edge", $realtime - t_edge));
    t_chg = $realtime;
  end

  // -------------------------------------------------------- data output
  task automatic drive(input logic [15:0] d, input logic [1:0] en, input real dly);
    int g;
    drv_gen++;
    g = drv_gen;
    fork
      begin
        #(dly);
        if (drv_gen == g) begin
          dq_o  = d;
          dq_en = en;
        end
      end
    join_none
  endtask

  // Unknown from tOH of the word ending now, then the next word at tAC.
  task automatic drive_next(input logic [15:0] d, input logic [1:0] en, input real toh, input real tac);
    int g;
    drv_gen++;
    g = drv_gen;
    fork
      begin
        #(toh);
        if (drv_gen == g) dq_o = 16'hxxxx;
        #(tac - toh);
        if (drv_gen == g) begin
          dq_o  = d;
          dq_en = en;
        end
      end
    join_none
  endtask

  task automatic release_dq(input real dly);
    int g;
    g = drv_gen;
    fork
      begin
        #(dly);
        if (drv_gen == g) dq_en = 2'b00;
      end
    join_none
  endtask

  // ------------------------------------------------------------ decode
  always @(posedge clk) begin
    logic [3:0] cmd;
    real now;
    int b, r, c;
    bit cke_prev;
    now = $realtime;
    t_prev_edge = t_edge;
    t_edge = now;
    edge_n++;
    cmd = {ncs, nras, ncas, nwe};
    cke_prev = cke_q;
    cke_q = cke;
    if (cke && t_cke < 0.0) t_cke = now;
    if (now > 0.0 && (now - t_chg) < T_IS - EPS)
      err($sformatf("setup violation: input changed %0.3f ns before edge", now - t_chg));

    // pending auto-precharges start
    for (int i = 0; i < 4; i++) begin
      // the chip holds an auto-precharge back until tRAS is met
      if (ap[i] && ((ap_edge[i] >= 0 && edge_n >= ap_edge[i]) ||
                    (ap_edge[i] < 0 && now >= ap_time[i] - EPS))) begin
        ap[i]  = 0;
        act[i] = 0;
        t_pre[i] = (now - t_act[i] < T_RAS) ? t_act[i] + T_RAS : now;
      end
    end

    // read data for this edge: release after tOH; next edge's data starts
    begin
      bit ending;
      ending = 0;
      for (int i = 0; i < NRP; i++) begin
        if (rp_v[i] && rp_edge[i] == edge_n) begin
          release_dq(T_OH);
          rp_v[i] = 0;
          ending = 1;
        end
      end
      for (int i = 0; i < NRP; i++) begin
        if (rp_v[i] && rp_edge[i] == edge_n + 1) begin
          // DQM latency 2: the mask was sampled at edge rp_edge - 2
          if (ending) drive_next(rp_data[i], ~dqm_d1, T_OH, (cl == 2) ? T_AC2 : T_AC3);
          else        drive(rp_data[i], ~dqm_d1, (cl == 2) ? T_AC2 : T_AC3);
        end
      end
    end

    if (init_done && (now - t_refi) > T_REFI + EPS) begin
      // reported once per late interval
      if ((now - t_refi) <= T_REFI + (now - t_prev_edge) + EPS)
        err($sformatf("refresh interval exceeded (%0.1f ns)", now - t_refi));
    end

    if (cke && cke_prev && !ncs && cmd != 4'b0111) begin
      if (mrs_edge >= 0 && edge_n - mrs_edge < T_MRD)
        err("tMRD violation");
      if (t_ref > 0.0 && now - t_ref < T_RFC - EPS)
        err($sformatf("tRFC violation (%0.1f ns)", now - t_ref));
      b = int'(ba);
      unique case (cmd)
        4'b0011: begin // ACTIVE
          r = int'(a) & ((1 << ROW_BITS) - 1);
          if (!init_done) err("ACTIVE before init complete");
          if (act[b] || ap[b]) err($sformatf("ACTIVE to open bank %0d", b));
          if (now - t_pre[b] < T_RP - EPS) err($sformatf("tRP violation bank %0d", b));
          if (now - t_act[b] < T_RC - EPS) err($sformatf("tRC violation bank %0d", b));
          if (now - t_last_act < T_RRD - EPS) err("tRRD violation");
          if ((int'(a) >> ROW_BITS) != 0) err("row address above ROW_BITS");
          act[b] = 1;
          row[b] = r;
          t_act[b] = now;
          t_last_act = now;
          n_act++;
        end
        4'b0101, 4'b0100: begin // READ / WRITE
          c = int'(a[9:0]) & ((1 << COL_BITS) - 1);
          if (!init_done) err("READ/WRITE before init complete");
          if (!act[b] || ap[b]) err($sformatf("READ/WRITE to closed bank %0d", b));
          if (now - t_act[b] < T_RCD - EPS) err($sformatf("tRCD violation bank %0d", b));
          if (COL_BITS < 10 && a[9]) err("column bit A9 set on a 512-column chip");
          if (cmd == 4'b0101) begin
            for (int w = 0; w < bl; w++) begin
              int cw;
              cw = (c & ~(bl - 1)) | ((c + w) & (bl - 1));
              for (int i = 0; i < NRP; i++)
                if (!rp_v[i]) begin
                  rp_v[i] = 1;
                  rp_edge[i] = edge_n + longint'(cl + w);
                  rp_data[i] = fetch(key(b, row[b], cw));
                  break;
                end
            end
            n_rd++;
            if (a[10]) begin
              ap[b] = 1;
              ap_edge[b] = edge_n + longint'(bl);
            end
          end else begin
            logic [15:0] old, d;
            longint unsigned k;
            k = key(b, row[b], c);
            old = fetch(k);
            d = dq;
            if (!dqml) old[7:0]  = d[7:0];
            if (!dqmh) old[15:8] = d[15:8];
            if (!dqml && $isunknown(d[7:0]))  err("WRITE with unknown low byte");
            if (!dqmh && $isunknown(d[15:8])) err("WRITE with unknown high byte");
            if (dq_en != 2'b00) err("WRITE while the chip drives DQ");
            mem[k] = old;
            t_wr[b] = now;
            n_wr++;
            if (a[10]) begin
              ap[b] = 1;
              ap_edge[b] = -1;
              ap_time[b] = now + (now - t_prev_edge) + T_WR_AP;
            end
          end
        end
        4'b0010: begin // PRECHARGE
          for (int i = 0; i < 4; i++)
            if (a[10] || i == b) begin
              if (act[i] && now - t_act[i] < T_RAS - EPS) err($sformatf("tRAS violation bank %0d", i));
              if (act[i] && now - t_wr[i] < T_WR - EPS) err($sformatf("tWR violation bank %0d", i));
              if (ap[i]) err($sformatf("PRECHARGE during auto-precharge bank %0d", i));
              if (act[i]) t_pre[i] = now;
              act[i] = 0;
            end
          if (a[10] && !pall_done) begin
            if (t_cke < 0.0 || now - t_cke < T_INIT - EPS)
              err($sformatf("PRECHARGE ALL only %0.1f ns after power-up", now - t_cke));
            pall_done = 1;
          end
        end
        4'b0001: begin // AUTO REFRESH
          for (int i = 0; i < 4; i++) begin
            if (act[i] || ap[i]) err($sformatf("REFRESH with bank %0d open", i));
            if (now - t_pre[i] < T_RP - EPS) err($sformatf("tRP violation before REFRESH bank %0d", i));
          end
          if (!pall_done) err("REFRESH before PRECHARGE ALL");
          if (!init_done) init_refs++;
          if (init_done && now - t_refi > max_ref_gap) max_ref_gap = now - t_refi;
          if (init_done) n_ref++;
          t_ref = now;
          t_refi = now;
        end
        4'b0000: begin // LOAD MODE
          for (int i = 0; i < 4; i++)
            if (act[i] || ap[i]) err("LOAD MODE with a bank open");
          if (!pall_done) err("LOAD MODE before PRECHARGE ALL");
          if (!init_done && init_refs < 2) err("LOAD MODE before two init REFRESHes");
          if (a[2:0] > 3'd3) err("full-page burst is not modelled");
          bl = 1 << int'(a[2:0]);
          if (bl > 1 && !a[9]) err("write bursts are not modelled");
          if (a[6:4] != 3'd2 && a[6:4] != 3'd3) err("unsupported CAS latency");
          if (a[3] != 1'b0) err("interleaved burst is not modelled");
          if (a[8:7] != 2'b00) err("reserved operating mode");
          cl = int'(a[6:4]);
          mode_set = 1;
          if (!init_done) begin
            init_done = 1;
            t_refi = now;          // interval check starts here
          end
          mrs_edge = edge_n;
        end
        default: err($sformatf("unsupported command %b", cmd));
      endcase
    end else if (!cke && init_done) begin
      err("CKE low after init (power-down is not modelled)");
    end
    dqm_d1 = {dqmh, dqml};
  end
endmodule
`default_nettype wire
