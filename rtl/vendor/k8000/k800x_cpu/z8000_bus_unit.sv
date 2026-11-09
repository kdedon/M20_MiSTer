// z8000_bus_unit -- Z-Bus machine cycles and the bus pins.
//
// A machine cycle is one transaction plus its tail, or one internal
// operation. The pins are registers: each rising edge updates them as below
// (values just after the edge).
//
//   T1   /AS Low, address and status driven; /DS /MREQ High
//   T2   /AS High; /MREQ Low (memory, refresh); read: /DS Low, AD
//        released; write: data on AD
//   TAW  automatic waits: one for I/O (/DS falls), five for an
//        acknowledge (/DS falls at the fourth)
//   T3   /WAIT sampled; Low holds the cycle here as a TW. A write's /DS
//        falls on the first post-T2 edge. Read data is taken at this edge
//        and `done` is raised in the same clock.
//   next /DS /MREQ (and write data) released: the strobe trail. If the
//        next machine cycle opens on this edge its T1 overrides the release.
//   tail `tail` more clocks after the T3 clock, given by the requester
//        during that clock. /AS /DS /MREQ High, AD released; ST, N/S, R/W,
//        B/W and SN hold.
//
// An internal operation (ST=0000) is 3 to 8 clocks: an /AS pulse with
// `req_addr` on AD, then AD released. /DS and /MREQ stay High, /WAIT is
// ignored, N/S and SN hold. Its T-state is counted: one of `len` ends at
// Tlen (the baseline's /AS placement, no work of its own); a unit-ended
// one (`req_unit`) where the serial unit says, from T3 on. The unit gives
// its end two edges ahead (`unit_end3`), or one ahead from a pass
// (`unit_end2`); in an internal operation of `len` only its last end
// (`unit_last`) is taken, which may come before Tlen. `cyc_iop` is High
// through an internal operation.
//
// /WAIT is specified at the T2 falling edge; with outputs changing only on
// rising edges, that sample is the edge that would open T3. /ABORT is
// sampled as T2 opens and with each Low /WAIT sample (`abt_smp`).
//
// One requester. A request is taken on the edge that ends the machine
// cycle in flight (`cyc_end`), or on any edge while idle; it holds until
// then. A refresh (ST=0001) keeps R/W, B/W and N/S from the previous
// cycle. An aborted IF1 (`req_nodata`) is a fetch's /AS and status with
// /DS and /MREQ left High. `done`, `rdata`, `cyc_end` and `cyc_end3` are
// combinational.
//
// /BUSREQ is sampled on the edge that opens each machine cycle's T1. If
// it was Low there, /BUSACK falls on the edge that ends the cycle's T3 (an
// internal operation's third clock) unless `lock` holds; the strobes stay
// High and AD is released; ST, N/S, R/W, B/W and SN hold. The cycle's
// later clocks (tail, internal operation) run on; the next cycle waits.
// /BUSACK rises on the second edge that sees /BUSREQ High, and the next
// cycle opens on the edge after at the earliest. `bus_drive` is Low while
// granted: a system top floats /AS, /DS, /MREQ, ST, R/W, B/W, N/S and SN
// with it.

module z8000_bus_unit
  import z8000_zbus_pkg::*;
#(
  parameter bit SEGMENTED = 1
) (
  input  logic        clk,
  input  logic        clk_en,   // CLK rising edge seen this clock
  input  logic        reset_n,

  // the next machine cycle, held until taken
  input  logic        req,
  input  logic        req_internal,   // internal operation, else a transaction
  input  logic [22:0] req_addr,       // seg[22:16]:offset[15:0]
  input  logic [15:0] req_wdata,
  input  logic [3:0]  req_st,
  input  logic        req_write,
  input  logic        req_nodata,     // an aborted IF1: no data strobe
  input  logic        req_byte,
  input  logic        req_odd,        // a byte write's address bit 0, ahead of the address select
  input  logic        req_epu_drives, // the EPU supplies the write data
  input  logic        req_normal,     // N/S for the cycle (1 = normal)
  input  logic [3:0]  req_len,        // internal operation length
  input  logic        req_unit,       // ... or ended by the serial unit
  input  logic        unit_end3,      // the serial unit's cycle ends on the third edge from now
  input  logic        unit_end2,      // ... on the second, from a pass this clock
  input  logic        unit_last,      // ... and that end is the program's
  input  logic [2:0]  tail,           // read in a transaction's T3 clock
  input  logic        lock,           // no grant at the end of this clock's T3
  input  logic        busreq,         // /BUSREQ asserted as of this edge

  output logic        cyc_end,        // the next edge ends the machine cycle
  output logic        cyc_bound,      // ... or would, the bus not granted; or the bus is idle
  output logic        cyc_end3,       // ... the third edge from now does
  output logic        done,           // T3 opens on this edge
  output logic        twait,          // this clock is a wait state
  output logic        abt_smp,        // /ABORT is sampled on this edge
  output logic        held,           // between cycles, the bus granted or just back
  output logic        lost,           // the clock ending at this edge was granted or a wait state
  output logic        away,           // the bus is granted, or given up as this clock ends
  output logic        cyc_iop,        // this clock is an internal operation's
  output logic [15:0] rdata,          // read data, valid with done

  // pins
  input  logic        wait_n,
  input  logic [15:0] ad_in,
  output logic [15:0] ad_out,
  output logic        ad_drive,
  output logic [6:0]  sn,
  output logic        as_n,
  output logic        ds_n,
  output logic        mreq_n,
  output logic        r_w,
  output logic        b_w,
  output logic        n_s,
  output logic [3:0]  st,
  output logic        busack_n,
  output logic        bus_drive
);

  // T2, TAW and T3 name the clock the next edge opens; T3CLK, HOLD and IDLE
  // the clock now running.
  typedef enum logic [2:0] {
    BUS_IDLE,
    BUS_T2,
    BUS_TAW,
    BUS_T3,
    BUS_T3CLK,        // a transaction's T3 clock
    BUS_HOLD          // a tail, or an internal operation after its T1
  } bus_state_e;

  bus_state_e  state_q, state_d;
  logic        trail_q, trail_d;     // /DS /MREQ still Low from the last T3
  logic [2:0]  taw_q, taw_d;         // automatic waits left
  logic [3:0]  rest_q, rest_d;       // tail clocks after this one
  logic        iop_q, iop_d;         // HOLD is an internal operation
  logic [2:0]  t_q, t_d;             // its T-state less one
  logic [2:0]  tlen_q, tlen_d;       // its last T-state less one, for `len`
  logic        unit_q, unit_d;       // it is unit-ended
  logic        ue2_q, ue2_d, ue1_q, ue1_d;  // the unit's end two edges, one edge ahead
  logic        brq_q, brq_d;         // /BUSREQ as of the running cycle's T1 edge
  logic        gnt_q, gnt_d;         // the bus is granted
  logic        back_q, back_d;       // /BUSACK High again this clock
  logic        rel_q, rel_d;         // /BUSREQ seen High while granted
  logic        tw_q;                 // this clock is a wait state
  logic [3:0]  cyc_st_q, cyc_st_d;   // status of the cycle in flight
  logic        cyc_write_q, cyc_write_d;
  logic        cyc_epu_q, cyc_epu_d;
  logic        cyc_nod_q, cyc_nod_d;
  logic [15:0] cyc_wdata_q, cyc_wdata_d;
  logic        cyc_byte_q, cyc_odd_q;

  logic [15:0] ad_out_d;
  logic        ad_drive_d, as_n_d, ds_n_d, mreq_n_d, r_w_d, b_w_d, n_s_d;
  logic [6:0]  sn_d;
  logic [3:0]  st_d;

  // ---- machine-cycle boundary -------------------------------------------------
  // The bus is given up as T3 ends; no cycle opens while it is away.
  logic bound, give;
  always_comb begin
    unique case (state_q)
      BUS_IDLE:  bound = 1'b1;
      BUS_T3CLK: bound = tail == 3'd0;
      BUS_HOLD:  bound = !iop_q ? rest_q == 4'd0 : ue1_q || (!unit_q && t_q == tlen_q);
      default:   bound = 1'b0;
    endcase
  end
  assign give    = brq_q && !lock && (state_q == BUS_T3CLK || (state_q == BUS_HOLD && iop_q && t_q == 3'd2));
  assign cyc_end = bound && !give && !gnt_q;
  assign cyc_bound = bound;

  // The unit's end, taken in an internal operation from its T1: the end it
  // gives there is T3's. An operation of `len` takes only the last.
  logic ue_take;
  assign ue_take = iop_q && unit_end3 && (unit_q || unit_last);

  always_comb begin
    unique case (state_q)
      BUS_T3CLK: cyc_end3 = tail == 3'd2;
      BUS_HOLD:  cyc_end3 = !iop_q ? rest_q == 4'd2 : ue_take || (!unit_q && t_q + 3'd2 == tlen_q);
      default:   cyc_end3 = 1'b0;
    endcase
  end

  logic start, start_txn, start_iop;
  assign start     = req && cyc_end;
  assign start_txn = start && !req_internal;
  assign start_iop = start && req_internal;

  // ---- the transaction to start -------------------------------------------------
  logic req_io, req_refresh, cyc_io, cyc_ack, cyc_epux, cyc_iot, cyc_refresh;
  assign req_io      = req_st == ST_IO || req_st == ST_SPECIAL_IO;
  assign req_refresh = req_st == ST_REFRESH;
  assign cyc_io      = cyc_st_q == ST_IO || cyc_st_q == ST_SPECIAL_IO;
  assign cyc_ack     = cyc_st_q[3:2] == 2'b01;
  assign cyc_epux    = cyc_st_q == ST_EPU_TRANSFER;
  assign cyc_refresh = cyc_st_q == ST_REFRESH;
  // I/O timing, with its automatic wait: I/O and EPU transfers.
  assign cyc_iot     = cyc_io || cyc_epux;

  // A byte write, memory or I/O, carries the byte on both halves; the
  // receiver picks the lane from A0. The EPU flag byte rides AD7:AD0 alone.
  // The data is held at every cycle end, read only in a write's T2, and
  // the byte placed there, off the request decode.
  logic [7:0]  wbyte;
  logic [15:0] wdata_bus;
  assign wbyte     = cyc_odd_q ? cyc_wdata_q[7:0] : cyc_wdata_q[15:8];
  assign wdata_bus = (cyc_byte_q && !cyc_epux) ? {wbyte, wbyte} : cyc_wdata_q;

  assign held    = (gnt_q || back_q) && state_q == BUS_IDLE;
  assign away    = give || gnt_q;
  assign cyc_iop = state_q == BUS_HOLD && iop_q;
  assign done  = state_q == BUS_T3 && wait_n;
  assign twait = state_q == BUS_T3 && !wait_n;
  assign lost  = gnt_q || tw_q;
  assign rdata = ad_in;

  // /ABORT is sampled as a memory transaction's T2 opens and at each wait
  // after it; not for I/O, an acknowledge, refresh, an EPU transfer or an
  // aborted IF1.
  assign abt_smp = (state_q == BUS_T2 || (state_q == BUS_T3 && !wait_n)) &&
                   cyc_st_q[3] && !cyc_epux && !cyc_nod_q;

  logic [2:0] taw_dec;
  assign taw_dec = taw_q - 3'd1;

  // ---- cycle state ------------------------------------------------------------------
  always_comb begin
    state_d     = state_q;
    taw_d       = taw_q;
    rest_d      = rest_q;
    iop_d       = iop_q;
    t_d         = t_q;
    tlen_d      = tlen_q;
    unit_d      = unit_q;
    ue2_d       = 1'b0;
    ue1_d       = 1'b0;
    cyc_st_d    = cyc_st_q;
    cyc_write_d = cyc_write_q;
    cyc_epu_d   = cyc_epu_q;
    cyc_nod_d   = cyc_nod_q;
    cyc_wdata_d = cyc_end ? req_wdata : cyc_wdata_q;
    if (start_txn) begin
      cyc_st_d    = req_st;
      cyc_write_d = req_write;
      cyc_epu_d   = req_epu_drives;
      cyc_nod_d   = req_nodata;
      state_d     = BUS_T2;
    end else if (start_iop) begin
      iop_d   = 1'b1;
      t_d     = 3'd0;
      tlen_d  = 3'(req_len - 4'd1);
      unit_d  = req_unit;
      state_d = BUS_HOLD;
    end else begin
      unique case (state_q)
        BUS_IDLE: ;
        BUS_T2: begin
          if (cyc_ack) begin
            taw_d   = 3'd5;
            state_d = BUS_TAW;
          end else if (cyc_iot) begin
            taw_d   = 3'd1;
            state_d = BUS_TAW;
          end else begin
            state_d = BUS_T3;
          end
        end
        BUS_TAW: begin
          // An external wait delays the acknowledge string. I/O samples
          // /WAIT only mid-TWA, in BUS_T3 (Fig 9-5).
          if (wait_n || !cyc_ack) begin
            taw_d = taw_dec;
            if (taw_dec == 3'd0) state_d = BUS_T3;
          end
        end
        BUS_T3:    if (wait_n) state_d = BUS_T3CLK;
        BUS_T3CLK: begin
          rest_d  = {1'b0, tail} - 4'd1;
          iop_d   = 1'b0;
          state_d = (tail == 3'd0) ? BUS_IDLE : BUS_HOLD;
        end
        BUS_HOLD: begin
          rest_d = rest_q - 4'd1;
          t_d    = t_q + 3'd1;
          if (iop_q) begin
            ue2_d = ue_take;
            ue1_d = ue2_q || (unit_end2 && t_q != 3'd0 && (unit_q || unit_last));
          end
          if (bound) state_d = BUS_IDLE;
        end
        default: state_d = BUS_IDLE;
      endcase
    end
  end

  // ---- bus request ------------------------------------------------------------------
  // Released: /BUSACK rises on the second edge that sees /BUSREQ High.
  always_comb begin
    brq_d  = start ? busreq : brq_q;
    gnt_d  = gnt_q;
    back_d = 1'b0;
    rel_d  = 1'b0;
    if (give) begin
      gnt_d = 1'b1;
    end else if (gnt_q) begin
      rel_d = !busreq;
      if (!busreq && rel_q) begin
        gnt_d  = 1'b0;
        back_d = 1'b1;
      end
    end
  end

  // ---- pins -----------------------------------------------------------------------------
  always_comb begin
    trail_d    = trail_q;
    ad_out_d   = ad_out;
    ad_drive_d = ad_drive;
    sn_d       = sn;
    as_n_d     = as_n;
    ds_n_d     = ds_n;
    mreq_n_d   = mreq_n;
    r_w_d      = r_w;
    b_w_d      = b_w;
    n_s_d      = n_s;
    st_d       = st;

    if (trail_q) begin
      ds_n_d     = 1'b1;
      mreq_n_d   = 1'b1;
      ad_drive_d = 1'b0;
      trail_d    = 1'b0;
    end

    if (start_txn) begin
      ad_out_d   = req_addr[15:0];
      ad_drive_d = 1'b1;
      as_n_d     = 1'b0;
      ds_n_d     = 1'b1;
      mreq_n_d   = 1'b1;
      st_d       = req_st;
      sn_d       = SEGMENTED ? req_addr[22:16] : 7'd0;
      if (!req_refresh) begin
        r_w_d = !req_write;
        b_w_d = req_byte;
        n_s_d = req_normal && !req_io;
      end
    end else if (start_iop) begin
      ad_out_d   = req_addr[15:0];
      ad_drive_d = 1'b1;
      as_n_d     = 1'b0;
      ds_n_d     = 1'b1;
      mreq_n_d   = 1'b1;
      st_d       = ST_INTERNAL_OP;
      r_w_d      = 1'b1;
      b_w_d      = 1'b0;
    end else begin
      unique case (state_q)
        BUS_T2: begin
          as_n_d   = 1'b1;
          mreq_n_d = cyc_io || cyc_ack || cyc_epux || cyc_nod_q;
          if (!cyc_refresh && !cyc_ack && !cyc_iot && !cyc_write_q && !cyc_nod_q)
            ds_n_d = 1'b0;
          if (cyc_write_q && !cyc_epu_q) begin
            ad_out_d   = wdata_bus;
            ad_drive_d = 1'b1;
          end else begin
            ad_drive_d = 1'b0;
          end
        end
        BUS_TAW: begin
          if (!cyc_ack || (wait_n && taw_dec <= 3'd1))
            ds_n_d = 1'b0;
        end
        BUS_T3: begin
          if (cyc_write_q && !cyc_refresh && !cyc_iot)
            ds_n_d = 1'b0;
          if (wait_n) begin
            if (!cyc_write_q)
              ad_drive_d = 1'b0;
            trail_d = 1'b1;
          end
        end
        BUS_HOLD: begin
          as_n_d     = 1'b1;
          ad_drive_d = 1'b0;
        end
        default: ;
      endcase
    end
  end

  // Reset values are the reset pin state: AD floated (and High), strobes
  // High, SN Low, ST 1111, N/S system.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q     <= BUS_IDLE;
      taw_q       <= 3'd0;
      rest_q      <= 4'd0;
      iop_q       <= 1'b0;
      t_q         <= 3'd0;
      tlen_q      <= 3'd0;
      unit_q      <= 1'b0;
      ue2_q       <= 1'b0;
      ue1_q       <= 1'b0;
      brq_q       <= 1'b0;
      gnt_q       <= 1'b0;
      back_q      <= 1'b0;
      rel_q       <= 1'b0;
      tw_q        <= 1'b0;
      busack_n    <= 1'b1;
      bus_drive   <= 1'b1;
      cyc_st_q    <= 4'b1111;
      cyc_write_q <= 1'b0;
      cyc_epu_q   <= 1'b0;
      cyc_nod_q   <= 1'b0;
      cyc_wdata_q <= 16'h0000;
      cyc_byte_q  <= 1'b0;
      cyc_odd_q   <= 1'b0;
    end else if (clk_en) begin
      state_q     <= state_d;
      taw_q       <= taw_d;
      rest_q      <= rest_d;
      iop_q       <= iop_d;
      t_q         <= t_d;
      tlen_q      <= tlen_d;
      unit_q      <= unit_d;
      ue2_q       <= ue2_d;
      ue1_q       <= ue1_d;
      brq_q       <= brq_d;
      gnt_q       <= gnt_d;
      back_q      <= back_d;
      rel_q       <= rel_d;
      // An acknowledge's external waits count too.
      tw_q        <= twait || (state_q == BUS_TAW && cyc_ack && !wait_n);
      busack_n    <= !gnt_d;
      bus_drive   <= !gnt_d;
      cyc_st_q    <= cyc_st_d;
      cyc_write_q <= cyc_write_d;
      cyc_epu_q   <= cyc_epu_d;
      cyc_nod_q   <= cyc_nod_d;
      cyc_wdata_q <= cyc_wdata_d;
      if (cyc_end) begin
        cyc_byte_q <= req_byte;
        cyc_odd_q  <= req_odd;
      end
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      trail_q  <= 1'b0;
      ad_out   <= 16'hFFFF;
      ad_drive <= 1'b0;
      sn       <= 7'd0;
      as_n     <= 1'b1;
      ds_n     <= 1'b1;
      mreq_n   <= 1'b1;
      r_w      <= 1'b1;
      b_w      <= 1'b0;
      n_s      <= 1'b0;
      st       <= 4'b1111;
    end else if (clk_en) begin
      trail_q  <= trail_d;
      ad_out   <= ad_out_d;
      ad_drive <= ad_drive_d;
      sn       <= sn_d;
      as_n     <= as_n_d;
      ds_n     <= ds_n_d;
      mreq_n   <= mreq_n_d;
      r_w      <= r_w_d;
      b_w      <= b_w_d;
      n_s      <= n_s_d;
      st       <= st_d;
    end
  end

  // synthesis translate_off
  // A unit-ended internal operation is at most eight clocks.
  // verilator lint_off UNUSEDSIGNAL
  logic check_q = 1'b0;
  // verilator lint_on UNUSEDSIGNAL
  always_ff @(posedge clk) if (clk_en) begin
    if (state_q == BUS_HOLD && iop_q && unit_q && t_q == 3'd7 && !bound) begin
      $display("%%Error: %m: unit-ended internal operation past T8");
      check_q <= 1'b1;
    end
    // An end from a pass is taken from T2: one in T1 is lost.
    if (cyc_iop && unit_end2 && t_q == 3'd0 && (unit_q || unit_last)) begin
      $display("%%Error: %m: unit end from a pass in T1");
      check_q <= 1'b1;
    end
    // The program's last end comes two edges ahead, for its last clocks.
    if (cyc_iop && unit_end2 && t_q != 3'd0 && unit_last) begin
      $display("%%Error: %m: unit's last end from a pass");
      check_q <= 1'b1;
    end
  end
  // synthesis translate_on

endmodule
