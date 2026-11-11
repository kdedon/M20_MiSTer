// ====================================================================
//
//  FD1797 floppy disk controller for the Olivetti M20 (U14),
//  sector-level, on the disk_stream drive side.
//
//  Copyright (C) 2007,2008 Viacheslav Slavinsky
//  Copyright (C) 2016 Sorgelig
//  Copyright (C) 2026 M20_MiSTer authors
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
// ====================================================================
//
// Derived from sorgelig's wd1793.sv (ZX-Spectrum_MISTer).
//
// Registers (A2:A1): 0 command/status, 1 track, 2 sector, 3 data.
// True (non-inverted) data bus.
//
// Medium: 16 sectors per track, 2:1 interleave (physical slot p holds
// sector p odd ? (p+1)/2 : p/2+9).  Cylinder 0 side 0 is FM, 128-byte
// sectors; all other tracks MFM, 256 bytes.  An ID is seen only when
// /DDEN (1 = FM) matches the track density.  Sector image block:
// (cyl * sides + side) * 8 + (sector - 1) / 2, at byte ((sector-1)&1)*256.
// Image size <= 143360 is single sided; cylinders = size / (4096 * sides),
// at most 84.
//
// PC images (163840, 184320, 327680, 368640 bytes): 40 cylinders, 8 or 9
// sectors of 512 bytes, all MFM, 1:1 interleave; block
// (cyl * sides + side) * spt + sector - 1.  The revolution has spt slots.
//
// Command bit 1 (U) sets SSO, which selects the head; no side compare.
// Type II bit 3 (L): 1 = 128 << code, 0 = 256, 512, 1024, 128.  A transfer
// longer than the sector reads gap filler (FF FM, 4E MFM) and ends with
// CRC error; written bytes past it are dropped.
//
// Timing (1 tick = 1 us): 300 rpm, 16 slots of SLOT_T ticks, ID at tick
// ID_T of each slot, data field 18 (FM) / 38 (MFM) byte times later, bytes
// every 64 / 32 ticks.  Not found = 5 index pulses; head unloads after 15
// idle index pulses.  READY = selected drive has a medium.  TG43 and the
// motor bit are ignored.
//
// Write Track parses the CPU stream: FE opens an ID (track, side, sector,
// size), FB/F8 a data field ending at F7 or 128 << size bytes.  Data of
// sectors 1..16 goes to the physical track; gaps, deleted marks and format
// density are not recorded.  Read Track returns no data and ends at the
// second index pulse.
//
// Image blocks are fetched on demand into a 4 KB track buffer (8 slots).
// Sector writes read-modify-write their block; Write Track loads all 8
// blocks first and writes them back after the second index.
`default_nettype none
module m20_fdc #(
  parameter int unsigned SLOT_T = 12500,    // ticks per sector slot (200 ms / 16)
  parameter int unsigned SLOT_T8 = 25000,   // PC, 8 sectors
  parameter int unsigned SLOT_T9 = 22222,   // PC, 9 sectors
  parameter int unsigned ID_T   = 600,      // ID position in the slot
  parameter int unsigned IDX_T  = 4000,     // index pulse width
  parameter int unsigned MS     = 1000      // ticks per ms
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             ce_fdc,          // 1 MHz
  // I/O bus
  input  logic             cs_fdc,
  input  logic [2:1]       io_addr,
  input  logic [7:0]       io_wdata,
  input  logic             io_rd,
  input  logic             io_wr,
  input  logic             io_rd_end,
  input  logic             io_wr_end,
  output logic [7:0]       fdc_rdata,
  output logic             intrq,           // -> 8259 IR0
  output logic             drq,
  output logic             busy,
  // port 0x21 latch
  input  logic [1:0]       fdc_ds,
  input  logic             fdc_motor,
  input  logic             fdc_dden_n,      // 1 = FM
  input  logic             fdc_tg43,
  // disk_stream drive side, slots 0 and 1
  input  logic [1:0]       d_mounted,
  input  logic             d_readonly,
  input  logic [63:0]      d_size,
  output logic [1:0][31:0] d_lba,
  output logic [1:0]       d_rd,
  output logic [1:0]       d_wr,
  input  logic [1:0]       d_ack,
  input  logic [8:0]       d_buff_addr,
  input  logic [7:0]       d_buff_dout,
  output logic [1:0][7:0]  d_buff_din,
  input  logic             d_buff_wr
);
  localparam int unsigned MS6  = 6 * MS, MS12 = 12 * MS, MS20 = 20 * MS, MS30 = 30 * MS;
  localparam int unsigned SLOT_M1 = SLOT_T - 1, SLOT8_M1 = SLOT_T8 - 1, SLOT9_M1 = SLOT_T9 - 1;
  localparam logic [15:0] T_SETTLE = MS30[15:0];
  localparam logic [14:0] SLOT_END = SLOT_M1[14:0], SLOT8_END = SLOT8_M1[14:0], SLOT9_END = SLOT9_M1[14:0];
  localparam logic [14:0] ID_POS   = ID_T[14:0];
  localparam logic [14:0] IDX_W    = IDX_T[14:0];
  localparam logic [6:0]  CYL_MAX  = 7'd83;

  function automatic logic [15:0] step_t(input logic [1:0] r);
    case (r)
      2'd0:    return MS6[15:0];
      2'd1:    return MS12[15:0];
      2'd2:    return MS20[15:0];
      default: return MS30[15:0];
    endcase
  endfunction

  // CCITT CRC-16 (x^16 + x^12 + x^5 + 1), one byte, MSB first
  function automatic logic [15:0] crc8(input logic [15:0] c, input logic [7:0] b);
    logic [15:0] r;
    r = c;
    for (int i = 7; i >= 0; i--)
      r = {r[14:0], 1'b0} ^ ((r[15] ^ b[i]) ? 16'h1021 : 16'h0000);
    return r;
  endfunction

  // ---- bus access -------------------------------------------------------------------
  // Latched access; done_q blocks a second event while the strobe level stays.
  logic       acc_q, acc_w, done_q;
  logic [1:0] acc_a;
  logic [7:0] acc_d;
  logic       lvl;
  assign lvl = cs_fdc && (io_rd || io_wr);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      acc_q <= 1'b0; acc_w <= 1'b0; done_q <= 1'b0; acc_a <= 2'd0; acc_d <= 8'h00;
    end else if (io_rd_end || io_wr_end) begin
      acc_q  <= 1'b0;
      done_q <= lvl;
    end else if (lvl && !done_q) begin
      acc_q <= 1'b1;
      acc_w <= io_wr;
      acc_a <= io_addr;
      if (io_wr) acc_d <= io_wdata;
    end else if (!lvl) begin
      done_q <= 1'b0;
    end
  end
  logic ev_rd, ev_wr;
  assign ev_rd = io_rd_end && acc_q && !acc_w;
  assign ev_wr = io_wr_end && acc_q && acc_w;
  logic ev_rd_st, ev_rd_dat, ev_wr_cmd, ev_wr_trk, ev_wr_sec, ev_wr_dat;
  assign ev_rd_st  = ev_rd && acc_a == 2'd0;
  assign ev_rd_dat = ev_rd && acc_a == 2'd3;
  assign ev_wr_cmd = ev_wr && acc_a == 2'd0;
  assign ev_wr_trk = ev_wr && acc_a == 2'd1;
  assign ev_wr_sec = ev_wr && acc_a == 2'd2;
  assign ev_wr_dat = ev_wr && acc_a == 2'd3;

  // ---- media ------------------------------------------------------------------------
  // Per drive: medium present, write protect, double sided, cylinders, PC
  // format and its 9-sector variant.
  logic [1:0]      mnt, ro, ds2, pc, pc9;
  logic [1:0][6:0] ncyl;
  logic            sz_pc, sz_pc9, sz_pcds;
  assign sz_pc9  = d_size == 64'd184320 || d_size == 64'd368640;
  assign sz_pc   = sz_pc9 || d_size == 64'd163840 || d_size == 64'd327680;
  assign sz_pcds = d_size == 64'd327680 || d_size == 64'd368640;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mnt <= 2'b00; ro <= 2'b00; ds2 <= 2'b00; pc <= 2'b00; pc9 <= 2'b00; ncyl <= '0;
    end else begin
      for (int i = 0; i < 2; i++)
        if (d_mounted[i]) begin
          mnt[i]  <= d_size[22:0] != 23'd0 && d_size[63:23] == 41'd0;
          ro[i]   <= d_readonly;
          pc[i]   <= sz_pc;
          pc9[i]  <= sz_pc9;
          if (sz_pc) begin
            ds2[i]  <= sz_pcds;
            ncyl[i] <= 7'd40;
          end else begin
            ds2[i]  <= d_size[22:0] > 23'd143360;
            if (d_size[22:0] > 23'd143360)
              ncyl[i] <= (d_size[22:13] > 10'd84) ? 7'd84 : d_size[19:13];
            else
              ncyl[i] <= {1'b0, d_size[17:12]};
          end
        end
    end
  end

  // ---- spindle: 16 slots per revolution (PC: one per sector), the selected drive's ---
  logic        sel_pc, sel_pc9;
  logic [14:0] rot_t, slot_end;
  logic [3:0]  rot_s, s_last;
  assign slot_end = !sel_pc ? SLOT_END : sel_pc9 ? SLOT9_END : SLOT8_END;
  assign s_last   = !sel_pc ? 4'd15 : sel_pc9 ? 4'd8 : 4'd7;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rot_t <= 15'd0; rot_s <= 4'd0;
    end else if (ce_fdc) begin
      if (rot_t >= slot_end) begin
        rot_t <= 15'd0;
        rot_s <= (rot_s >= s_last) ? 4'd0 : rot_s + 4'd1;
      end else begin
        rot_t <= rot_t + 15'd1;
      end
    end
  end
  logic idx_lvl, idx_rise, id_ev;
  assign idx_lvl  = rot_s == 4'd0 && rot_t < IDX_W;
  assign idx_rise = ce_fdc && rot_s == 4'd0 && rot_t == 15'd0;
  assign id_ev    = ce_fdc && rot_t == ID_POS;
  logic [4:0] id_sec;                         // sector number of the passing ID
  assign id_sec = sel_pc ? {1'b0, rot_s} + 5'd1 :
                  rot_s[0] ? {2'b00, rot_s[3:1]} + 5'd1 : {2'b00, rot_s[3:1]} + 5'd9;

  // ---- selected drive ---------------------------------------------------------------
  logic [1:0][6:0] head;
  logic       sel, sel_ok, ready, tr00, wp_in;
  logic [6:0] cyl;
  logic       sso;                            // side select output
  assign sel    = !fdc_ds[0];
  assign sel_ok = |fdc_ds;
  assign ready  = sel_ok && mnt[sel];
  assign cyl    = head[sel];
  assign tr00   = sel_ok && cyl == 7'd0;
  assign wp_in  = sel_ok && ro[sel];
  assign sel_pc  = pc[sel];
  assign sel_pc9 = pc9[sel];
  logic exists, trk_fm, den_ok;
  assign exists = ready && cyl < ncyl[sel] && (!sso || ds2[sel]);
  assign trk_fm = cyl == 7'd0 && !sso && !sel_pc;
  assign den_ok = fdc_dden_n == trk_fm;

  // Image block k of a track (M20: sector pair, PC: sector - 1).
  function automatic logic [31:0] lba_of(input logic p, input logic p9, input logic d2,
                                         input logic [6:0] c, input logic s, input logic [3:0] k);
    logic [31:0] t;
    t = d2 ? {24'd0, c, s} : {25'd0, c};
    if (!p)      return {t[28:0], k[2:0]};
    else if (p9) return {t[28:0], 3'd0} + t + {28'd0, k};
    else         return {t[28:0], 3'd0} + {28'd0, k};
  endfunction

  // ---- track buffer: 16 image blocks (M20 uses 8) ---------------------------------------
  logic [12:0] a_addr, b_addr, b_wa;
  logic [7:0]  a_q, b_q, b_d;
  logic        a_we, b_we;
  (* ramstyle = "M10K, no_rw_check" *) logic [7:0] tbuf [0:8191];
  always_ff @(posedge clk) begin
    if (a_we) tbuf[a_addr] <= d_buff_dout;
    a_q <= tbuf[a_addr];
  end
  always_ff @(posedge clk) begin
    if (b_we) tbuf[b_addr] <= b_d;
    b_q <= tbuf[b_addr];
  end

  // ---- block engine: one disk_stream block job ---------------------------------------
  typedef enum logic [1:0] {B_IDLE, B_REQ, B_XFER} blk_e;
  blk_e        b_st;
  logic        b_drv, b_wr;
  logic [31:0] b_lba;
  logic [3:0]  b_slot;
  logic        blk_go, blk_go_wr, blk_go_drv;   // from the sequencer, one clock
  logic [31:0] blk_go_lba;
  logic [3:0]  blk_go_slot;
  logic        blk_pend;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      b_st <= B_IDLE; b_drv <= 1'b0; b_wr <= 1'b0; b_lba <= 32'd0; b_slot <= 4'd0;
    end else begin
      unique case (b_st)
        B_IDLE: if (blk_go) begin
          b_drv  <= blk_go_drv;
          b_wr   <= blk_go_wr;
          b_lba  <= blk_go_lba;
          b_slot <= blk_go_slot;
          b_st   <= B_REQ;
        end
        B_REQ:  if (d_ack[b_drv]) b_st <= B_XFER;
        B_XFER: if (!d_ack[b_drv]) b_st <= B_IDLE;
        default: b_st <= B_IDLE;
      endcase
    end
  end
  assign blk_pend = blk_go || b_st != B_IDLE;
  always_comb begin
    for (int i = 0; i < 2; i++) begin
      d_lba[i]      = b_lba;
      d_rd[i]       = b_st == B_REQ && !b_wr && b_drv == 1'(i);
      d_wr[i]       = b_st == B_REQ &&  b_wr && b_drv == 1'(i);
      d_buff_din[i] = a_q;
    end
    a_addr = {b_slot, d_buff_addr};
    a_we   = b_st != B_IDLE && !b_wr && d_buff_wr && d_ack[b_drv];
  end

  // ---- sequencer --------------------------------------------------------------------------
  typedef enum logic [4:0] {
    S_IDLE, S_T1, S_STEPW, S_VFY, S_SETTLE, S_EDLY, S_PREP, S_SRCH, S_HOLD,
    S_RD, S_RD2, S_RDE, S_WR1, S_WR, S_WRE, S_WRF, S_RA, S_RAE,
    S_WT_LD, S_WT_IX, S_WT, S_WT_FL, S_RT, S_END
  } seq_e;
  seq_e st;

  logic [7:0]  trk_r, sec_r, dat_r, cmd_q;
  logic        busy_q, drq_q, intrq_q, intrq_imm, st_t1;
  logic        f_s4, f_crc, f_lost, f_wp;
  logic        dir_in, hld;
  logic [3:0]  hld_n;
  logic [7:0]  step_n;
  logic [15:0] tmr;
  logic [2:0]  idx_n;
  logic [2:0]  fi_c;
  logic        rdy_q;
  logic [4:0]  m_sec;
  logic [6:0]  m_cyl;
  logic        m_side, m_fm, m_drv, m_ex, m_pc, m_pc9;
  logic [10:0] cnt, len;
  logic [3:0]  k;
  logic [1:0]  wt_f;
  logic [10:0] wt_n;
  logic [7:0]  wt_sec;
  logic [1:0]  wt_sz;
  logic        b_we_q;
  logic [12:0] b_wa_q;
  logic [7:0]  b_d_q;

  localparam logic [1:0] WF_NONE = 2'd0, WF_ID = 2'd1, WF_DATA = 2'd2;

  logic [3:0] cty;                            // command type nibble
  assign cty = cmd_q[7:4];
  logic c_rd, c_wr, c_ra, c_wt, c_t1;
  assign c_t1 = !cmd_q[7];
  assign c_rd = cty == 4'h8 || cty == 4'h9;
  assign c_wr = cty == 4'hA || cty == 4'hB;
  assign c_ra = cty == 4'hC;
  assign c_wt = cty == 4'hF;

  logic [7:0] sec_m1;
  logic [4:0] msec_m1;
  assign sec_m1  = sec_r - 8'd1;
  assign msec_m1 = m_sec - 5'd1;

  // byte time and data-field offsets for the matched sector
  logic [15:0] bt, bt2, dstart, gap2, wstart;
  // a reload on a tick clock counts that tick, so byte times stay exact
  assign bt     = (m_fm ? 16'd64 : 16'd32) - {15'd0, ce_fdc};
  assign bt2    = m_fm ? 16'd128 : 16'd64;
  assign dstart = m_fm ? 16'd1152 : 16'd1216;      // 18 / 38 byte times
  assign gap2   = m_fm ? 16'd704  : 16'd704;       // 11 / 22 byte times
  assign wstart = m_fm ? 16'd448  : 16'd512;       // 7 / 16 byte times
  logic [10:0] phys;
  assign phys = m_fm ? 11'd128 : m_pc ? 11'd512 : 11'd256;

  // matched sector: image block slot, transfer address, sectors per track
  logic [3:0]  m_slot, m_nblk;
  logic [12:0] x_addr;
  assign m_slot = m_pc ? msec_m1[3:0] : {1'b0, msec_m1[3:1]};
  assign m_nblk = (m_pc && m_pc9) ? 4'd9 : 4'd8;
  assign x_addr = m_pc ? {msec_m1[3:0], cnt[8:0]} : {1'b0, msec_m1[3:0], cnt[7:0]};
  logic [7:0] sel_spt;
  assign sel_spt = !sel_pc ? 8'd16 : sel_pc9 ? 8'd9 : 8'd8;
  logic [7:0] m_len_code;
  assign m_len_code = m_pc ? 8'd2 : {7'd0, !m_fm};

  // Read Address bytes
  logic [15:0] id_crc;
  logic [7:0]  ra_byte;
  always_comb begin
    id_crc = crc8(crc8(crc8(crc8(crc8(m_fm ? 16'hFFFF : 16'hCDB4, 8'hFE), {1'b0, m_cyl}),
                            {7'd0, m_side}), {3'd0, m_sec}), m_len_code);
    case (cnt[2:0])
      3'd0:    ra_byte = {1'b0, m_cyl};
      3'd1:    ra_byte = {7'd0, m_side};
      3'd2:    ra_byte = {3'd0, m_sec};
      3'd3:    ra_byte = m_len_code;
      3'd4:    ra_byte = id_crc[15:8];
      default: ra_byte = id_crc[7:0];
    endcase
  end

  // port B: a write one clock after its decision, else the transfer byte
  assign b_we   = b_we_q;
  assign b_d    = b_d_q;
  assign b_wa   = b_wa_q;
  assign b_addr = b_we_q ? b_wa : x_addr;

  // CPU byte for a write: this clock's bus write, else the data register
  logic [7:0] wbyte;
  logic       wlost;
  assign wlost = drq_q && !ev_wr_dat;
  assign wbyte = ev_wr_dat ? acc_d : wlost ? 8'h00 : dat_r;
  logic       rlost;
  assign rlost = drq_q && !ev_rd_dat;

  logic [7:0] wb;                              // Write Track: this byte time's byte
  assign wb = (cnt == 11'd0) ? dat_r : wbyte;

  logic wt_v;                                  // the open ID names a sector of this track
  assign wt_v = m_ex && wt_sec >= 8'd1 && wt_sec <= (m_pc ? {4'd0, m_nblk} : 8'd16);

  logic [7:0] cmd_in;
  assign cmd_in = acc_d;
  logic [6:0] head_in, head_out;
  assign head_in  = (cyl == CYL_MAX) ? cyl : cyl + 7'd1;
  assign head_out = (cyl == 7'd0) ? cyl : cyl - 7'd1;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= S_IDLE;
      trk_r <= 8'h00; sec_r <= 8'h00; dat_r <= 8'h00; cmd_q <= 8'h00;
      busy_q <= 1'b0; drq_q <= 1'b0; intrq_q <= 1'b0; intrq_imm <= 1'b0; st_t1 <= 1'b1;
      f_s4 <= 1'b0; f_crc <= 1'b0; f_lost <= 1'b0; f_wp <= 1'b0;
      dir_in <= 1'b1; hld <= 1'b0; hld_n <= 4'd0; step_n <= 8'd0; tmr <= 16'd0; idx_n <= 3'd0;
      fi_c <= 3'd0; rdy_q <= 1'b0; sso <= 1'b0; head <= '0;
      m_sec <= 5'd1; m_cyl <= 7'd0; m_side <= 1'b0; m_fm <= 1'b0; m_drv <= 1'b0; m_ex <= 1'b0;
      m_pc <= 1'b0; m_pc9 <= 1'b0;
      cnt <= 11'd0; len <= 11'd0; k <= 4'd0;
      wt_f <= WF_NONE; wt_n <= 11'd0; wt_sec <= 8'd0; wt_sz <= 2'd0;
      b_we_q <= 1'b0; b_wa_q <= 13'd0; b_d_q <= 8'h00;
      blk_go <= 1'b0; blk_go_wr <= 1'b0; blk_go_drv <= 1'b0; blk_go_lba <= 32'd0; blk_go_slot <= 4'd0;
    end else begin
      blk_go <= 1'b0;
      b_we_q <= 1'b0;
      rdy_q  <= ready;
      if (ce_fdc && tmr != 16'd0) tmr <= tmr - 16'd1;

      // ---- register access ----------------------------------------------------------
      if (ev_rd_st)  intrq_q <= 1'b0;
      if (ev_rd_dat) drq_q <= 1'b0;
      if (ev_wr_trk && !busy_q) trk_r <= acc_d;
      if (ev_wr_sec) sec_r <= acc_d;
      if (ev_wr_dat) begin dat_r <= acc_d; drq_q <= 1'b0; end

      // ---- force-interrupt conditions ----------------------------------------------
      if ((fi_c[0] && ready && !rdy_q) || (fi_c[1] && !ready && rdy_q) || (fi_c[2] && idx_rise))
        intrq_q <= 1'b1;

      // ---- head unload after 15 idle revolutions ----------------------------------
      if (st == S_IDLE && hld && idx_rise) begin
        hld_n <= hld_n + 4'd1;
        if (hld_n == 4'd14) hld <= 1'b0;
      end

      unique case (st)
        S_IDLE: ;

        // ---- type I: one decision per step -------------------------------------------
        S_T1: begin
          st <= S_STEPW;
          tmr <= step_t(cmd_q[1:0]);
          if (cty == 4'h0) begin                           // restore
            dir_in <= 1'b0;
            if (tr00) begin
              trk_r <= 8'h00;
              st    <= S_VFY;
            end else if (step_n == 8'hFF) begin
              f_s4 <= 1'b1;
              st   <= S_END;
            end else begin
              step_n <= step_n + 8'd1;
              if (sel_ok) head[sel] <= head_out;
            end
          end else if (cty == 4'h1) begin                  // seek
            if (trk_r == dat_r) begin
              st <= S_VFY;
            end else begin
              dir_in <= dat_r > trk_r;
              if (dat_r < trk_r && tr00) begin
                trk_r <= 8'h00;
                st    <= S_VFY;
              end else begin
                trk_r <= (dat_r > trk_r) ? trk_r + 8'd1 : trk_r - 8'd1;
                if (sel_ok) head[sel] <= (dat_r > trk_r) ? head_in : head_out;
              end
            end
          end else begin                                   // step, step in, step out
            if (!dir_in && tr00) begin
              trk_r <= 8'h00;
              st    <= S_VFY;
            end else begin
              if (cmd_q[4]) trk_r <= dir_in ? trk_r + 8'd1 : trk_r - 8'd1;
              if (sel_ok) head[sel] <= dir_in ? head_in : head_out;
            end
          end
        end
        S_STEPW: if (tmr == 16'd0) st <= (cty == 4'h0 || cty == 4'h1) ? S_T1 : S_VFY;
        S_VFY: begin
          if (cmd_q[2]) begin
            hld <= 1'b1;
            tmr <= T_SETTLE;
            st  <= S_SETTLE;
          end else begin
            st <= S_END;
          end
        end
        S_SETTLE: if (tmr == 16'd0) begin
          idx_n <= 3'd0;
          st    <= S_SRCH;
        end

        // ---- type II / III ------------------------------------------------------------------
        S_EDLY: if (tmr == 16'd0) st <= S_PREP;
        S_PREP: if (!blk_pend) begin
          idx_n  <= 3'd0;
          m_drv  <= sel;
          m_cyl  <= cyl;
          m_side <= sso;
          m_ex   <= exists;
          m_pc   <= sel_pc;
          m_pc9  <= sel_pc9;
          st     <= S_SRCH;
          if ((c_rd || c_wr) && exists && sec_r >= 8'd1 && sec_r <= sel_spt) begin
            blk_go      <= 1'b1;                          // fetch the sector's block
            blk_go_wr   <= 1'b0;
            blk_go_drv  <= sel;
            blk_go_lba  <= lba_of(sel_pc, sel_pc9, ds2[sel], cyl, sso,
                                  sel_pc ? sec_m1[3:0] : {1'b0, sec_m1[3:1]});
            blk_go_slot <= sel_pc ? sec_m1[3:0] : {1'b0, sec_m1[3:1]};
          end
          if (c_wt) begin
            k  <= 4'd0;
            st <= S_WT_LD;
          end
          if (cty == 4'hE) begin
            idx_n <= 3'd0;
            st    <= S_RT;
          end
        end

        // ---- ID search (verify, sector, address) -------------------------------------
        S_SRCH: begin
          if (idx_rise) begin
            idx_n <= idx_n + 3'd1;
            if (idx_n == 3'd4) begin
              f_s4 <= 1'b1;                               // seek error / record not found
              st   <= S_END;
            end
          end
          if (id_ev && exists && den_ok) begin
            m_sec  <= id_sec;
            m_cyl  <= cyl;
            m_side <= sso;
            m_fm   <= trk_fm;
            m_pc   <= sel_pc;
            m_pc9  <= sel_pc9;
            if (c_t1) begin
              if ({1'b0, cyl} == trk_r) st <= S_END;
            end else if (c_ra) begin
              st <= S_HOLD;
            end else if ({1'b0, cyl} == trk_r && {3'd0, id_sec} == sec_r) begin
              st <= S_HOLD;
            end
          end
        end
        // the block may still be on its way
        S_HOLD: if (!blk_pend) begin
          cnt <= 11'd0;
          len <= phys << !cmd_q[3];
          if (c_rd) begin
            tmr <= dstart;
            st  <= S_RD;
          end else if (c_wr) begin
            drq_q <= 1'b1;
            tmr   <= gap2;
            st    <= S_WR1;
          end else begin
            tmr <= 16'd0;
            st  <= S_RA;
          end
        end

        // ---- read sector: b_addr follows cnt, the byte is there one clock later -------
        S_RD: if (tmr == 16'd0) st <= S_RD2;
        S_RD2: begin
          dat_r <= (cnt < phys) ? b_q : (m_fm ? 8'hFF : 8'h4E);
          if (rlost) f_lost <= 1'b1;
          drq_q <= 1'b1;
          cnt   <= cnt + 11'd1;
          if (cnt == len - 11'd1) begin
            tmr <= bt2;                                   // CRC
            st  <= S_RDE;
          end else begin
            tmr <= bt;
            st  <= S_RD;
          end
        end
        S_RDE: if (tmr == 16'd0) begin
          if (len > phys) begin
            f_crc <= 1'b1;
            st    <= S_END;
          end else if (cmd_q[4]) begin
            sec_r <= sec_r + 8'd1;
            st    <= S_PREP;
          end else begin
            st <= S_END;
          end
        end

        // ---- write sector ---------------------------------------------------------------
        S_WR1: if (tmr == 16'd0) begin
          if (wlost) begin
            f_lost <= 1'b1;
            drq_q  <= 1'b0;
            st     <= S_END;
          end else begin
            if (ev_wr_dat) dat_r <= acc_d;
            tmr <= wstart;
            st  <= S_WR;
          end
        end
        S_WR: if (tmr == 16'd0) begin
          if (cnt != 11'd0 && wlost) f_lost <= 1'b1;
          if (cnt < phys) begin
            b_we_q <= 1'b1;
            b_wa_q <= x_addr;
            b_d_q  <= (cnt == 11'd0) ? dat_r : wbyte;
          end
          cnt <= cnt + 11'd1;
          if (cnt == len - 11'd1) begin
            tmr <= bt2;
            st  <= S_WRE;
          end else begin
            drq_q <= 1'b1;
            tmr   <= bt;
          end
        end
        S_WRE: if (tmr == 16'd0) begin
          if (m_ex) begin
            blk_go      <= 1'b1;
            blk_go_wr   <= 1'b1;
            blk_go_drv  <= m_drv;
            blk_go_lba  <= lba_of(m_pc, m_pc9, ds2[m_drv], m_cyl, m_side, m_slot);
            blk_go_slot <= m_slot;
          end
          st <= S_WRF;
        end
        S_WRF: if (!blk_pend) begin
          if (cmd_q[4]) begin
            sec_r <= sec_r + 8'd1;
            st    <= S_PREP;
          end else begin
            st <= S_END;
          end
        end

        // ---- read address -----------------------------------------------------------------
        S_RA: if (tmr == 16'd0) begin
          dat_r <= ra_byte;
          if (rlost) f_lost <= 1'b1;
          drq_q <= 1'b1;
          cnt   <= cnt + 11'd1;
          if (cnt == 11'd5) begin
            tmr <= bt2;
            st  <= S_RAE;
          end else begin
            tmr <= bt;
          end
        end
        S_RAE: if (tmr == 16'd0) begin
          sec_r <= {1'b0, m_cyl};
          st    <= S_END;
        end

        // ---- write track: load the track, stream from index to index, write back ----
        S_WT_LD: if (!blk_pend) begin
          if (k == m_nblk || !m_ex) begin
            m_fm <= trk_fm;
            st   <= S_WT_IX;
          end else begin
            blk_go      <= 1'b1;
            blk_go_wr   <= 1'b0;
            blk_go_drv  <= m_drv;
            blk_go_lba  <= lba_of(m_pc, m_pc9, ds2[m_drv], m_cyl, m_side, k);
            blk_go_slot <= k;
            k           <= k + 4'd1;
          end
        end
        S_WT_IX: if (idx_rise) begin
          if (wlost) begin
            f_lost <= 1'b1;
            drq_q  <= 1'b0;
            st     <= S_END;
          end else begin
            if (ev_wr_dat) dat_r <= acc_d;
            wt_f  <= WF_NONE;
            wt_n  <= 11'd0;
            wt_sec <= 8'd0;
            tmr   <= 16'd0;
            cnt   <= 11'd0;                               // 0: the first byte is in dat_r
            st    <= S_WT;
          end
        end
        S_WT: begin
          if (idx_rise) begin
            drq_q <= 1'b0;
            k     <= 4'd0;
            st    <= S_WT_FL;
          end else if (tmr == 16'd0) begin
            if (cnt != 11'd0 && wlost) f_lost <= 1'b1;
            cnt   <= 11'd1;
            drq_q <= 1'b1;
            tmr   <= bt;
            unique case (wt_f)
              WF_ID: begin
                if (wt_n[1:0] == 2'd2) wt_sec <= wb;
                if (wt_n[1:0] == 2'd3) begin
                  wt_sz <= wb[1:0];
                  wt_f  <= WF_NONE;
                end
                wt_n <= wt_n + 11'd1;
              end
              WF_DATA: begin
                if (wb == 8'hF7 || wt_n == (11'd128 << wt_sz)) begin
                  wt_f <= WF_NONE;
                end else begin
                  if (wt_v && wt_n < phys) begin
                    b_we_q <= 1'b1;
                    b_wa_q <= m_pc ? {wt_sec[3:0] - 4'd1, wt_n[8:0]} : {1'b0, wt_sec[3:0] - 4'd1, wt_n[7:0]};
                    b_d_q  <= wb;
                  end
                  wt_n <= wt_n + 11'd1;
                end
              end
              default: begin
                if (wb == 8'hFE) begin
                  wt_f   <= WF_ID;
                  wt_n   <= 11'd0;
                  wt_sec <= 8'd0;
                end else if (wb == 8'hFB || wb == 8'hF8) begin
                  wt_f <= WF_DATA;
                  wt_n <= 11'd0;
                end
              end
            endcase
          end
        end
        S_WT_FL: if (!blk_pend) begin
          if (k == m_nblk || !m_ex) begin
            st <= S_END;
          end else begin
            blk_go      <= 1'b1;
            blk_go_wr   <= 1'b1;
            blk_go_drv  <= m_drv;
            blk_go_lba  <= lba_of(m_pc, m_pc9, ds2[m_drv], m_cyl, m_side, k);
            blk_go_slot <= k;
            k           <= k + 4'd1;
          end
        end

        // ---- read track: not supported -----------------------------------------------
        S_RT: if (idx_rise) begin
          idx_n <= idx_n + 3'd1;
          if (idx_n == 3'd1) st <= S_END;
        end

        S_END: begin
          busy_q  <= 1'b0;
          intrq_q <= 1'b1;
          hld_n   <= 4'd0;
          st      <= S_IDLE;
        end
        default: st <= S_IDLE;
      endcase

      // ---- command register ---------------------------------------------------------
      if (ev_wr_cmd) begin
        intrq_q <= 1'b0;
        if (cmd_in[7:4] == 4'hD) begin                    // force interrupt
          fi_c      <= cmd_in[2:0];
          intrq_imm <= cmd_in[3];
          if (busy_q) begin
            busy_q <= 1'b0;
            drq_q  <= 1'b0;
            st     <= S_IDLE;
          end else begin
            st_t1 <= 1'b1;
          end
        end else if (!busy_q) begin
          cmd_q  <= cmd_in;
          busy_q <= 1'b1;
          drq_q  <= 1'b0;
          fi_c   <= 3'd0;
          st_t1  <= !cmd_in[7];
          f_s4 <= 1'b0; f_crc <= 1'b0; f_lost <= 1'b0; f_wp <= 1'b0;
          hld_n  <= 4'd0;
          if (!cmd_in[7]) begin                           // type I
            hld    <= cmd_in[3];
            step_n <= 8'd0;
            if (cmd_in[7:4] == 4'h0) begin
              trk_r <= 8'hFF;
              dat_r <= 8'h00;
            end
            if (cmd_in[6]) dir_in <= !cmd_in[5];
            st <= S_T1;
          end else begin                                  // type II / III
            sso <= cmd_in[1];
            hld <= 1'b1;
            tmr <= T_SETTLE;
            if (!ready) begin
              st <= S_END;
            end else if ((cmd_in[7:5] == 3'b101 || cmd_in[7:4] == 4'hF) && wp_in) begin
              f_wp <= 1'b1;
              st   <= S_END;
            end else begin
              if (cmd_in[7:4] == 4'hF) drq_q <= 1'b1;     // first format byte
              st <= cmd_in[2] ? S_EDLY : S_PREP;
            end
          end
        end
      end
    end
  end

  // ---- outputs ---------------------------------------------------------------------------
  logic [7:0] status;
  assign status = st_t1 ?
    {!ready, wp_in, hld, f_s4, f_crc, tr00, ready && idx_lvl, busy_q} :
    {!ready, f_wp, 1'b0, f_s4, f_crc, f_lost, drq_q, busy_q};
  always_comb begin
    unique case (io_addr)
      2'd0:    fdc_rdata = status;
      2'd1:    fdc_rdata = trk_r;
      2'd2:    fdc_rdata = sec_r;
      default: fdc_rdata = dat_r;
    endcase
  end
  assign intrq = intrq_q || intrq_imm;
  assign drq   = drq_q;
  assign busy  = busy_q;

  logic unused_ok;
  assign unused_ok = &{1'b0, fdc_motor, fdc_tg43, sec_m1[7:4], msec_m1[4]};
endmodule
`default_nettype wire
