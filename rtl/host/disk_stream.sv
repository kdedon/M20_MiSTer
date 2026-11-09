// Disk images streamed from the SD card on demand: floppy slots 0, 1 and
// hard disk slots 2, 3.  Each slot keeps one unit of its image in BRAM:
// floppy 16 aligned blocks (one cylinder, 2 sides x 8), hard disk one
// cylinder (bpc blocks).  A miss loads the unit holding the block with
// reads of up to 32 blocks, after writing back the dirty runs of the old
// unit.  Dirty blocks are also flushed after QUIET clocks without drive
// writes.  Blocks past the image end read as zero and are never written.
//
// Scratch blocks (d_scr) live in BRAM only:
//   floppy: reads zero, writes dropped.
//   hard disk: recorded track formats, LBA {cyl, head}.  ID cyl/head are
//     stored XOR the track's own, so identically formatted tracks share
//     one of NFMT reference-counted entries.  fmt_full: a format found no
//     free entry and was dropped.
// An unwritten scratch block reads as zero.
//
// Mounts are taken on the rising edge of img_mounted and passed to the
// drive as a one-clock pulse with the size; a machine reset replays each
// slot's medium, cached units survive it.  A request to an empty slot
// completes at once without data.  A hard disk without geometry (bpc 0)
// is served one block at a time straight from the file.
//
// Both sides use the hps_io sd_* protocol.  The drives share one buffer
// bus, so the drive engine serves one block at a time, round robin; the
// HPS engine runs one hps_io job at a time.  They meet in a true
// dual-port BRAM.
//
//   drive engine (port A)            HPS engine (port B)
//   hit / scratch / no medium        load: flush dirty runs, then read
//   -> 512 bytes, one per clock      the unit; zero-fill past the end
//   write -> byte per 2 clocks,      idle flush after QUIET clocks
//   marks the block dirty            probe: one block into its own block
`default_nettype none
module disk_stream
#(
  parameter int UMAX  = 119,                             // hard disk cylinder blocks (7 heads x 17)
  parameter int NFMT  = 8,                               // format entries per hard disk
  parameter int QUIET = 4_800_000                        // clocks without a write before a flush
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              core_rst_n,   // machine reset (drives and controllers)
  input  logic [1:0][11:0]  bpc,          // hard disks: blocks per cylinder, 0 unknown
  // hps_io side
  input  logic [3:0]        img_mounted,
  input  logic              img_readonly,
  input  logic [63:0]       img_size,
  output logic [3:0][31:0]  h_lba,
  output logic [3:0][5:0]   h_blk_cnt,
  output logic [3:0]        h_rd,
  output logic [3:0]        h_wr,
  input  logic [3:0]        h_ack,
  input  logic [13:0]       h_buff_addr,
  input  logic [7:0]        h_buff_dout,
  output logic [7:0]        h_buff_din,
  input  logic              h_buff_wr,
  // drive side
  output logic [3:0]        d_mounted,
  output logic              d_readonly,
  output logic [63:0]       d_size,
  input  logic [3:0][31:0]  d_lba,
  input  logic [3:0]        d_scr,
  input  logic [3:0]        d_rd,
  input  logic [3:0]        d_wr,
  output logic [3:0]        d_ack,
  output logic [8:0]        d_buff_addr,
  output logic [7:0]        d_buff_dout,
  input  logic [3:0][7:0]   d_buff_din,
  output logic              d_buff_wr,
  output logic [3:0]        resident,     // a unit is held
  output logic              busy,         // a unit is loading
  output logic              wb_busy,      // written blocks not yet in the image file
  output logic              fmt_full,     // a recorded format found no free entry
  // unit load times (clk / 1024) for floppy and hard disk slots
  output logic [1:0][15:0]  ld_min,
  output logic [1:0][15:0]  ld_max
);
  localparam int NSLOT = 4;
  localparam int FD_U  = 16;       // floppy unit: one M20 cylinder, 2 x 8 blocks
  localparam int FW_U  = $clog2(FD_U);
  localparam int UM    = (UMAX > FD_U) ? UMAX : FD_U;
  localparam int FW    = $clog2(NFMT);
  localparam int UW    = $clog2(UM);
  localparam int LW    = 20;               // block numbers inside the units (512 MB)

  // ---- BRAM layout (blocks) ---------------------------------------------------------
  localparam int U_FD1 = FD_U;
  localparam int U_HD  = 2 * FD_U;
  localparam int U_HD1 = U_HD + UMAX;
  localparam int P_HD  = U_HD1 + UMAX;            // probe block, per hard disk
  localparam int F_HD  = P_HD + 2;                // format entries, per hard disk
  localparam int TOT   = F_HD + 2 * NFMT;
  localparam int BW    = $clog2(TOT);
  localparam int AW    = BW + 9;
  localparam logic [BW-1:0] B_FD1 = U_FD1[BW-1:0];
  localparam logic [BW-1:0] B_HD  = U_HD[BW-1:0];
  localparam logic [BW-1:0] B_HD1 = U_HD1[BW-1:0];
  localparam logic [BW-1:0] B_P   = P_HD[BW-1:0];
  localparam logic [BW-1:0] B_F   = F_HD[BW-1:0];
  localparam logic [11:0]   UMAX12 = UMAX[11:0];
  localparam logic [22:0]   QUIET23 = QUIET[22:0];

  logic [AW-1:0] a_addr, b_addr;
  logic [7:0]    a_d, b_d, a_q, b_q;
  logic          a_we, b_we;
  (* ramstyle = "M10K, no_rw_check" *) logic [7:0] mem [0:TOT*512-1];
  always_ff @(posedge clk) begin
    if (a_we) mem[a_addr] <= a_d;
    a_q <= mem[a_addr];
  end
  always_ff @(posedge clk) begin
    if (b_we) mem[b_addr] <= b_d;
    b_q <= mem[b_addr];
  end

  function automatic logic [BW-1:0] ublk(input logic [1:0] s, input logic [7:0] i);
    return (s[1] ? (s[0] ? B_HD1 : B_HD) : s[0] ? B_FD1 : {BW{1'b0}}) + {{(BW-8){1'b0}}, i};
  endfunction
  function automatic logic [BW-1:0] pblk(input logic s);
    return B_P + {{(BW-1){1'b0}}, s};
  endfunction
  function automatic logic [BW-1:0] fblk(input logic s, input logic [FW-1:0] e);
    return B_F + {{(BW-FW-1){1'b0}}, s, e};
  endfunction

  // ---- per-slot medium ------------------------------------------------------------------
  logic [3:0]  mnt_q, ro_q, mlvl_q, mlvl_q2, mnt_ev, rpl_q;
  logic [LW-1:0] nblk_q [NSLOT];
  logic [40:0] size_q [NSLOT];
  logic        crst_q;
  always_ff @(posedge clk) begin
    mlvl_q  <= rst_n ? img_mounted : '0;
    mlvl_q2 <= mlvl_q;
    crst_q  <= core_rst_n;
  end
  assign mnt_ev = mlvl_q & ~mlvl_q2;

  // size and block count: meaningful only while mnt_q says so
  always_ff @(posedge clk)
    for (int s = 0; s < NSLOT; s++)
      if (mnt_ev[s]) begin
        nblk_q[s] <= (img_size[40:29] != 12'd0) ? {LW{1'b1}} : img_size[28:9] + {19'd0, |img_size[8:0]};
        size_q[s] <= img_size[40:0];
      end

  // the lowest slot still to be told again after a reset
  logic [1:0] rp;
  always_comb begin
    rp = 2'd0;
    for (int s = NSLOT - 1; s >= 0; s--) if (rpl_q[s]) rp = 2'(s);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mnt_q <= '0; ro_q <= '0; rpl_q <= '0;
      d_mounted <= '0; d_readonly <= 1'b0; d_size <= 64'd0;
    end else begin
      d_mounted <= '0;
      if (core_rst_n && !crst_q) rpl_q <= mnt_q;
      if (|mnt_ev) begin
        for (int s = 0; s < NSLOT; s++)
          if (mnt_ev[s]) begin
            mnt_q[s]  <= img_size[40:0] != 41'd0;
            ro_q[s]   <= img_readonly;
            rpl_q[s]  <= 1'b0;
            d_mounted[s] <= 1'b1;
          end
        d_size     <= {23'd0, img_size[40:0]};
        d_readonly <= img_readonly;
      end else if (core_rst_n && |rpl_q) begin
        d_mounted[rp] <= 1'b1;
        d_size        <= {23'd0, size_q[rp]};
        d_readonly    <= ro_q[rp];
        rpl_q[rp]     <= 1'b0;
      end
    end
  end

  // ---- resident units ---------------------------------------------------------------
  // Per slot: resident unit (valid, first block, length) and dirty blocks;
  // quiet counts clocks since the last drive write; pt_* is the probe block.
  logic [3:0]            u_val;
  logic [LW-1:0]         u_base [NSLOT];
  logic [7:0]            u_len  [NSLOT];
  logic [1:0][FD_U-1:0]  dirty_fd;
  logic [1:0][UMAX-1:0]  dirty_hd;
  logic [22:0]           quiet;
  logic [3:0]            pt_val;
  logic [LW-1:0]         pt_lba [2];
  assign resident = u_val;

  // a hard disk slot without a usable geometry: one block at a time from the file
  logic [3:0] pt_mode;
  always_comb begin
    pt_mode[1:0] = 2'b00;
    for (int k = 0; k < 2; k++)
      pt_mode[2 + k] = bpc[k] == 12'd0 || bpc[k] > UMAX12;
  end

  logic [1:0] clr_busy;           // a hard disk's format index is being cleared
  logic [3:0] hit, pt_hit, cand, need, scr_wait, far;
  logic [LW-1:0] dl [NSLOT];
  always_comb
    for (int s = 0; s < NSLOT; s++) begin
      dl[s]  = d_lba[s][LW-1:0];
      far[s] = d_lba[s][31:LW] != '0;      // past any image: zeros at once
    end
  assign scr_wait = {clr_busy, 2'b00};
  always_comb begin
    for (int s = 0; s < NSLOT; s++) begin
      hit[s]    = u_val[s] && (dl[s] - u_base[s]) < {{(LW-8){1'b0}}, u_len[s]};
      pt_hit[s] = pt_val[s] && dl[s] == pt_lba[s[0]];
      // can be served now
      cand[s]   = (d_rd[s] || d_wr[s]) &&
                  (!mnt_q[s] || (d_scr[s] ? !scr_wait[s] : far[s] || (pt_mode[s] ? pt_hit[s] : hit[s])));
      // waits for the HPS engine
      need[s]   = (d_rd[s] || d_wr[s]) && mnt_q[s] && !d_scr[s] && !far[s] &&
                  !(pt_mode[s] ? pt_hit[s] : hit[s]);
    end
  end

  // ---- hard disk format index: {disk, cyl[9:0], head} -> {held, entry} ------------
  logic [13:0] fi_addr;
  logic [FW:0] fi_d, fi_q;
  logic        fi_we;
  (* ramstyle = "M10K" *) logic [FW:0] fidx [0:16383];
  always_ff @(posedge clk) begin
    if (fi_we) fidx[fi_addr] <= fi_d;
    fi_q <= fidx[fi_addr];
  end

  // Per hard disk: tracks using each format entry.
  logic [13:0] rc [2][NFMT];

  // A format block's ID words (bytes 0-255): byte 1 {size, head, cyl[10:8]},
  // byte 2 cyl[7:0].  An ID with a size code is stored XOR the track
  // {cyl, head}; the size bits decide it, so the same function restores it.
  function automatic logic [7:0] fnorm(input logic [7:0] b, input logic hi, input logic [1:0] p,
                                       input logic f, input logic [13:0] t);
    if (hi) return b;
    if (p == 2'd1 && b[7:6] != 2'b00) return b ^ {2'b00, t[2:0], t[13:11]};
    if (p == 2'd2 && f) return b ^ t[10:3];
    return b;
  endfunction

  // ---- drive engine -----------------------------------------------------------------------
  typedef enum logic [2:0] {D_IDLE, D_FIND, D_READ, D_WRITE, D_CMP, D_UPD, D_UPD2, D_END} drv_e;
  drv_e          d_st;
  logic [1:0]    d_slot, d_rr;
  logic          d_wrq, d_zero, d_img, d_drop, d_fmt, d_fl;
  logic [BW-1:0] d_blk;          // BRAM block of the job
  logic [7:0]    d_ib;           // image job: block in the unit
  logic [13:0]   d_tag;          // format job: {cyl, head}
  logic [FW:0]   d_old;          // format job: the track's index before
  logic [FW-1:0] d_stg, d_kc;    // format job: entry written, entry compared
  logic [10:0]   d_bc;
  logic          d_s1v, d_ph;
  logic [8:0]    d_s1b;
  logic [7:0]    d_sb;           // compare: the written entry's byte

  logic       dreq_any;
  logic [1:0] dreq_slot, dreq_k;
  always_comb begin
    dreq_any  = 1'b0;
    dreq_slot = d_rr;
    dreq_k    = d_rr;
    for (int k = NSLOT - 1; k >= 0; k--) begin
      dreq_k = d_rr + k[1:0];
      if (cand[dreq_k]) begin
        dreq_any  = 1'b1;
        dreq_slot = dreq_k;
      end
    end
  end

  // entries in use by the job's disk, and the first free one
  logic [NFMT-1:0] e_used;
  logic            e_free_ok;
  logic [FW-1:0]   e_free;
  always_comb begin
    e_free_ok = 1'b0;
    e_free    = '0;
    for (int e = NFMT - 1; e >= 0; e--) begin
      e_used[e] = rc[d_slot[0]][e] != 14'd0;
      if (!e_used[e]) begin e_free_ok = 1'b1; e_free = e[FW-1:0]; end
    end
  end
  // the next entry after d_kc to compare with
  logic          kc_ok;
  logic [FW-1:0] kc_nx;
  always_comb begin
    kc_ok = 1'b0;
    kc_nx = '0;
    for (int e = NFMT - 1; e >= 0; e--)
      if (e > int'(d_kc) && e_used[e] && e[FW-1:0] != d_stg) begin kc_ok = 1'b1; kc_nx = e[FW-1:0]; end
  end
  logic          kc0_ok;
  logic [FW-1:0] kc0;
  always_comb begin
    kc0_ok = 1'b0;
    kc0    = '0;
    for (int e = NFMT - 1; e >= 0; e--)
      if (e_used[e] && e[FW-1:0] != d_stg) begin kc0_ok = 1'b1; kc0 = e[FW-1:0]; end
  end

  logic d_issue;
  assign d_issue = d_st == D_READ && !d_bc[9];
  always_comb begin
    a_addr = {d_blk, d_bc[8:0]};
    if (d_st == D_WRITE) a_addr = {d_blk, d_buff_addr};
    if (d_st == D_CMP)   a_addr = {d_bc[0] ? fblk(d_slot[0], d_kc) : d_blk, d_bc[9:1]};
    a_we = d_st == D_WRITE && d_ph && !d_drop;
    a_d  = d_fmt ? fnorm(d_buff_din[d_slot], d_buff_addr[8], d_buff_addr[1:0], d_fl, d_tag) : d_buff_din[d_slot];
  end

  logic [3:0] dw_mark;           // the drive engine marks a block dirty
  logic [7:0] dw_blk;

  logic          clr_act, clr_k;
  logic [12:0]   clr_a;
  logic          fi_drv;
  assign fi_drv = d_st == D_FIND || d_st == D_UPD;
  always_comb begin
    fi_addr = {clr_k, clr_a};
    fi_we   = clr_act && !fi_drv;
    fi_d    = '0;
    if (fi_drv) begin
      fi_addr = {d_slot[0], d_tag[12:0]};
      fi_we   = d_st == D_UPD && !clr_busy[d_slot[0]];
      fi_d    = {1'b1, d_kc};
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n || !core_rst_n) begin
      d_st <= D_IDLE; d_slot <= '0; d_rr <= '0; d_wrq <= 1'b0; d_zero <= 1'b0; d_img <= 1'b0;
      d_drop <= 1'b0; d_fmt <= 1'b0; d_fl <= 1'b0; d_blk <= '0; d_ib <= 8'd0; d_tag <= 14'd0;
      d_old <= '0; d_stg <= '0; d_kc <= '0; d_bc <= 11'd0; d_sb <= 8'h00;
      d_s1v <= 1'b0; d_s1b <= 9'd0; d_ph <= 1'b0;
      d_ack <= '0; d_buff_addr <= 9'd0; d_buff_dout <= 8'h00; d_buff_wr <= 1'b0;
      dw_mark <= '0; dw_blk <= 8'd0;
    end else begin
      d_buff_wr <= 1'b0;
      d_s1v     <= 1'b0;
      dw_mark   <= '0;
      unique case (d_st)
        D_IDLE: if (dreq_any) begin
          d_slot  <= dreq_slot;
          d_rr    <= dreq_slot + 2'd1;
          d_ack[dreq_slot] <= 1'b1;
          d_wrq   <= d_wr[dreq_slot];
          d_bc    <= 11'd0;
          d_ph    <= 1'b0;
          d_buff_addr <= 9'd0;
          d_img   <= 1'b0;
          d_drop  <= 1'b0;
          d_zero  <= 1'b0;
          d_fmt   <= 1'b0;
          d_tag   <= d_lba[dreq_slot][13:0];
          d_ib    <= 8'(dl[dreq_slot] - u_base[dreq_slot]);
          if (!mnt_q[dreq_slot]) begin
            d_st <= D_END;                                  // no medium: at once, no data
          end else if (d_scr[dreq_slot]) begin
            if (dreq_slot[1]) begin
              d_st <= D_FIND;
            end else begin
              d_zero <= 1'b1;                               // floppy: no scratch blocks
              d_drop <= 1'b1;
              d_st   <= d_wr[dreq_slot] ? D_WRITE : D_READ;
            end
          end else if (far[dreq_slot]) begin
            d_zero <= 1'b1;
            d_drop <= 1'b1;
            d_st   <= d_wr[dreq_slot] ? D_WRITE : D_READ;
          end else if (pt_mode[dreq_slot]) begin
            d_blk  <= pblk(dreq_slot[0]);
            d_drop <= 1'b1;
            d_st   <= d_wr[dreq_slot] ? D_WRITE : D_READ;
          end else begin
            d_blk  <= ublk(dreq_slot, 8'(dl[dreq_slot] - u_base[dreq_slot]));
            d_img  <= 1'b1;
            d_st   <= d_wr[dreq_slot] ? D_WRITE : D_READ;
          end
        end

        // ---- hard disk format: the track's index (one clock to read) ---------------
        D_FIND: begin
          d_ph <= 1'b1;
          if (d_tag[13]) begin                              // cylinder 1024 and up: not held
            d_zero <= 1'b1;
            d_drop <= 1'b1;
            d_fmt  <= 1'b1;
            d_ph   <= 1'b0;
            d_st   <= d_wrq ? D_WRITE : D_READ;
          end else if (d_ph) begin
            d_ph  <= 1'b0;
            d_old <= fi_q;
            d_fmt <= 1'b1;
            if (!d_wrq) begin
              d_zero <= !fi_q[FW];
              d_blk  <= fblk(d_slot[0], fi_q[FW-1:0]);
              d_st   <= D_READ;
            end else begin
              d_st <= D_WRITE;
              if (e_free_ok) begin
                d_stg <= e_free;
                d_blk <= fblk(d_slot[0], e_free);
              end else if (fi_q[FW] && rc[d_slot[0]][fi_q[FW-1:0]] == 14'd1) begin
                d_stg <= fi_q[FW-1:0];                      // the track's own entry, used by it alone
                d_blk <= fblk(d_slot[0], fi_q[FW-1:0]);
              end else begin
                d_drop <= 1'b1;
              end
            end
          end
        end

        // ---- read: one byte per clock ----------------------------------------------
        D_READ: begin
          if (d_issue) begin
            d_s1v <= 1'b1;
            d_s1b <= d_bc[8:0];
            d_bc  <= d_bc + 11'd1;
          end
          if (d_s1v) begin
            d_buff_addr <= d_s1b;
            d_buff_dout <= d_zero ? 8'h00 : d_fmt ? fnorm(a_q, d_s1b[8], d_s1b[1:0], d_fl, d_tag) : a_q;
            d_buff_wr   <= 1'b1;
            if (d_s1b[1:0] == 2'd1) d_fl <= a_q[7:6] != 2'b00;
            if (d_s1b == 9'd511) d_st <= D_END;
          end
        end

        // ---- write: a byte every two clocks ----------------------------------------
        D_WRITE: begin
          d_ph <= !d_ph;
          if (d_ph) begin
            if (d_buff_addr[1:0] == 2'd1) d_fl <= d_buff_din[d_slot][7:6] != 2'b00;
            if (d_buff_addr == 9'd511) begin
              d_st <= D_END;
              if (d_img && !ro_q[d_slot] && u_base[d_slot] + {{(LW-8){1'b0}}, d_ib} < nblk_q[d_slot]) begin
                dw_mark[d_slot] <= 1'b1;
                dw_blk <= d_ib;
              end
              if (d_fmt && !d_drop) begin
                d_bc <= 11'd0;
                d_kc <= kc0;
                d_st <= kc0_ok ? D_CMP : D_UPD;
                if (!kc0_ok) d_kc <= d_stg;
              end
            end else begin
              d_buff_addr <= d_buff_addr + 9'd1;
            end
          end
        end

        // ---- format: an entry holding the same block (bytes alternate) ------------
        // a_q is the byte addressed one clock before: odd d_bc, the written
        // entry's; even, the compared entry's
        D_CMP: begin
          d_bc <= d_bc + 11'd1;
          if (d_bc[0]) d_sb <= a_q;
          if (!d_bc[0] && d_bc != 11'd0 && a_q != d_sb) begin
            d_bc <= 11'd0;                                  // differs: the next entry, or none
            if (kc_ok) d_kc <= kc_nx;
            else begin d_kc <= d_stg; d_st <= D_UPD; end
          end else if (d_bc == 11'd1024) begin
            d_st <= D_UPD;                                  // d_kc holds the same block
          end
        end

        D_UPD:  d_st <= D_UPD2;
        D_UPD2: d_st <= D_END;

        D_END: begin
          d_ack[d_slot] <= 1'b0;
          d_st <= D_IDLE;
        end
        default: d_st <= D_IDLE;
      endcase
    end
  end

  // reference count update, one entry per clock through one adder
  logic          rc_go, rc_dec;
  logic [FW-1:0] rc_e;
  logic [13:0]   rc_nx;
  assign rc_dec = d_st == D_UPD;
  assign rc_e   = rc_dec ? d_old[FW-1:0] : d_kc;
  assign rc_go  = (d_st == D_UPD || d_st == D_UPD2) && !clr_busy[d_slot[0]] &&
                  !(d_old[FW] && d_old[FW-1:0] == d_kc) && (!rc_dec || d_old[FW]);
  assign rc_nx  = rc[d_slot[0]][rc_e] + (rc_dec ? 14'h3FFF : 14'd1);

  // format index clear after a hard disk mount (one entry per clock while
  // the drive engine leaves the index alone); reference counts
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      clr_act <= 1'b0; clr_k <= 1'b0; clr_a <= 13'd0; clr_busy <= 2'b11;
      for (int k = 0; k < 2; k++) for (int e = 0; e < NFMT; e++) rc[k][e] <= 14'd0;
    end else begin
      if (clr_act) begin
        if (!fi_drv) begin
          clr_a <= clr_a + 13'd1;
          if (clr_a == 13'h1FFF) begin
            clr_busy[clr_k] <= 1'b0;
            clr_act <= 1'b0;
          end
        end
      end else if (|clr_busy) begin
        clr_act <= 1'b1;
        clr_k   <= !clr_busy[0];
        clr_a   <= 13'd0;
      end
      // the track leaves its old entry (D_UPD) and joins d_kc (D_UPD2)
      if (rc_go) rc[d_slot[0]][rc_e] <= rc_nx;
      for (int k = 0; k < 2; k++)
        if (mnt_ev[2 + k]) begin
          clr_busy[k] <= 1'b1;
          if (clr_act && clr_k == 1'(k)) clr_a <= 13'd0;
          for (int e = 0; e < NFMT; e++) rc[k][e] <= 14'd0;
        end
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n || |mnt_ev[3:2]) fmt_full <= 1'b0;
    else if (d_st == D_WRITE && d_fmt && d_drop && d_wrq) fmt_full <= 1'b1;
  end

  // ---- HPS engine ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    H_IDLE, H_CLAIM, H_DIV, H_WSCAN, H_WRUN, H_WREQ, H_WXFER, H_LREQ, H_LXFER, H_ZERO, H_DONE, H_PREQ, H_PXFER
  } hps_e;
  hps_e          h_st;
  logic [1:0]    h_slot;
  logic          h_ab;           // the job's slot saw a mount: its result is dropped
  logic [LW-1:0] h_lba_q;        // the request that missed
  logic [LW-1:0] h_base;
  logic [LW-1:0] h_lba_r;        // the hps_io request (one at a time)
  logic [5:0]    h_cnt_r;
  logic [7:0]    h_len, h_done, h_run, h_i, h_j;
  logic [16:0]   h_z;            // zero fill byte
  logic          h_ackq;
  logic [25:0]   h_clk;          // load time

  logic [3:0] any_dirty;
  assign any_dirty = {|dirty_hd[1], |dirty_hd[0], |dirty_fd[1], |dirty_fd[0]};
  // dirty bit of block i / j of h_slot's unit
  logic dbit_i, dbit_j;
  assign dbit_i = h_slot[1] ? dirty_hd[h_slot[0]][h_i[UW-1:0]] : dirty_fd[h_slot[0]][h_i[FW_U-1:0]];
  assign dbit_j = h_slot[1] ? dirty_hd[h_slot[0]][h_j[UW-1:0]] : dirty_fd[h_slot[0]][h_j[FW_U-1:0]];

  assign h_lba     = {4{{(32-LW){1'b0}}, h_lba_r}};
  assign h_blk_cnt = {4{h_cnt_r}};

  logic       hreq_any, hflush_any;
  logic [1:0] hreq_slot, hflush_slot;
  always_comb begin
    hreq_any = 1'b0; hreq_slot = '0; hflush_any = 1'b0; hflush_slot = '0;
    for (int s = NSLOT - 1; s >= 0; s--) begin
      if (need[s]) begin hreq_any = 1'b1; hreq_slot = 2'(s); end
      if (any_dirty[s] && quiet == QUIET23) begin hflush_any = 1'b1; hflush_slot = 2'(s); end
    end
  end

  // blocks of the unit inside the file
  logic [LW-1:0] h_nin_c;
  assign h_nin_c = (h_base >= nblk_q[h_slot]) ? '0 :
                   ((nblk_q[h_slot] - h_base) < {{(LW-8){1'b0}}, h_len}) ? nblk_q[h_slot] - h_base :
                   {{(LW-8){1'b0}}, h_len};

  always_comb begin
    b_addr = {ublk(h_slot, h_done), 9'd0} + {{(AW-14){1'b0}}, h_buff_addr};
    b_we   = (h_st == H_LXFER || h_st == H_PXFER) && h_buff_wr && h_ack[h_slot] && !h_ab;
    b_d    = h_buff_dout;
    if (h_st == H_PREQ || h_st == H_PXFER) b_addr = {pblk(h_slot[0]), 9'd0} + {{(AW-14){1'b0}}, h_buff_addr};
    if (h_st == H_WREQ || h_st == H_WXFER) b_addr = {ublk(h_slot, h_i), 9'd0} + {{(AW-14){1'b0}}, h_buff_addr};
    if (h_st == H_ZERO) begin
      b_addr = {ublk(h_slot, 8'd0), 9'd0} + {{(AW-17){1'b0}}, h_z};
      b_we   = !h_ab;
      b_d    = 8'h00;
    end
  end
  assign h_buff_din = b_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      h_st <= H_IDLE; h_slot <= '0; h_ab <= 1'b0; h_lba_q <= '0; h_base <= '0;
      h_len <= 8'd0; h_done <= 8'd0; h_run <= 8'd0; h_i <= 8'd0; h_j <= 8'd0;
      h_z <= 17'd0; h_ackq <= 1'b0; h_clk <= 26'd0;
      h_lba_r <= '0; h_cnt_r <= '0; h_rd <= '0; h_wr <= '0;
      u_val <= '0; pt_val <= '0; dirty_fd <= '0; dirty_hd <= '0;
      quiet <= 23'd0; pt_lba[0] <= '0; pt_lba[1] <= '0;
      for (int s = 0; s < NSLOT; s++) begin u_base[s] <= '0; u_len[s] <= 8'd0; end
      ld_min <= {16'hFFFF, 16'hFFFF}; ld_max <= '0;
    end else begin
      h_ackq <= h_ack[h_slot];
      h_clk  <= h_clk + 26'd1;
      if (mnt_ev[h_slot] && h_st != H_IDLE) h_ab <= 1'b1;

      if (|dw_mark)               quiet <= 23'd0;
      else if (quiet != QUIET23)  quiet <= quiet + 23'd1;
      for (int s = 0; s < NSLOT; s++) begin
        if (mnt_ev[s]) begin
          u_val[s]  <= 1'b0;
          u_base[s] <= '0;
          pt_val[s] <= 1'b0;
        end
      end

      unique case (h_st)
        H_IDLE: begin
          h_ab <= 1'b0;
          if (hreq_any && !h_ack[hreq_slot]) begin
            h_slot  <= hreq_slot;
            h_lba_q <= dl[hreq_slot];
            h_i     <= 8'd0;
            if (pt_mode[hreq_slot]) begin
              pt_val[hreq_slot] <= 1'b0;
              h_st <= H_PREQ;
            end else if (any_dirty[hreq_slot]) begin
              h_len <= u_len[hreq_slot];
              h_st  <= H_WSCAN;
            end else begin
              h_st <= H_CLAIM;
            end
          end else if (hflush_any && !h_ack[hflush_slot]) begin
            h_slot <= hflush_slot;
            h_i    <= 8'd0;
            h_len  <= u_len[hflush_slot];
            h_st   <= H_WSCAN;
          end
        end

        // ---- the unit holding h_lba_q ------------------------------------------
        H_CLAIM: begin
          u_val[h_slot]  <= 1'b0;
          pt_val[h_slot] <= 1'b0;
          h_base <= (h_slot[1] && h_lba_q >= u_base[h_slot]) ? u_base[h_slot] : '0;
          h_clk  <= 26'd0;
          h_st   <= H_DIV;
        end

        H_DIV: begin
          if (h_slot[1]) begin
            if (h_lba_q >= h_base + {{(LW-12){1'b0}}, bpc[h_slot[0]]}) begin
              h_base <= h_base + {{(LW-12){1'b0}}, bpc[h_slot[0]]};
            end else begin
              h_len <= 8'(bpc[h_slot[0]]);
              h_st  <= H_LREQ;
            end
          end else begin
            h_base <= {h_lba_q[LW-1:FW_U], {FW_U{1'b0}}};
            h_len  <= FD_U[7:0];
            h_st   <= H_LREQ;
          end
          h_done <= 8'd0;
        end

        // ---- load: blocks in the file, up to 32 per request ---------------------
        H_LREQ: begin
          if (h_ab) begin
            h_rd[h_slot] <= 1'b0;
            h_st <= H_IDLE;
          end else if ({{(LW-8){1'b0}}, h_done} >= h_nin_c) begin
            h_z  <= {h_done, 9'd0};
            h_st <= (h_done == h_len) ? H_DONE : H_ZERO;
          end else begin
            h_lba_r <= h_base + {{(LW-8){1'b0}}, h_done};
            h_cnt_r <= 6'(((h_nin_c - {{(LW-8){1'b0}}, h_done}) > 20'd32 ? 20'd32 :
                          (h_nin_c - {{(LW-8){1'b0}}, h_done})) - 20'd1);
            h_rd[h_slot]      <= 1'b1;
            if (h_ack[h_slot] && !h_ackq) begin
              h_rd[h_slot] <= 1'b0;
              h_st <= H_LXFER;
            end
          end
        end
        H_LXFER: if (!h_ack[h_slot]) begin
          h_done <= h_done + 8'd1 + {2'd0, h_cnt_r};
          h_st   <= H_LREQ;
        end
        H_ZERO: begin   // blocks past the file's end
          h_z <= h_z + 17'd1;
          if (h_z == {h_len, 9'd0} - 17'd1) h_st <= H_DONE;
        end
        H_DONE: begin
          if (!h_ab) begin
            u_val[h_slot]  <= 1'b1;
            u_base[h_slot] <= h_base;
            u_len[h_slot]  <= h_len;
            if (h_clk[25:10] < ld_min[h_slot[1]]) ld_min[h_slot[1]] <= h_clk[25:10];
            if (h_clk[25:10] > ld_max[h_slot[1]]) ld_max[h_slot[1]] <= h_clk[25:10];
          end
          h_st <= H_IDLE;
        end

        // ---- write-back: runs of dirty blocks --------------------------------------
        H_WSCAN: begin
          if (h_ab || h_i >= h_len || int'(h_i) >= UM) begin
            h_st <= H_IDLE;            // after a flush for a miss the load follows
          end else if (dbit_i) begin
            h_run <= 8'd0;
            h_j   <= h_i;
            h_st  <= H_WRUN;
          end else begin
            h_i <= h_i + 8'd1;
          end
        end
        // the run: dirty blocks from h_i, at most 32, one per clock, each
        // marked clean as it joins (a drive write meanwhile marks it again)
        H_WRUN: begin
          if (h_j < h_len && int'(h_j) < UM && h_run != 8'd32 && dbit_j) begin
            if (h_slot[1]) dirty_hd[h_slot[0]][h_j[UW-1:0]] <= 1'b0;
            else           dirty_fd[h_slot[0]][h_j[FW_U-1:0]] <= 1'b0;
            h_run <= h_run + 8'd1;
            h_j   <= h_j + 8'd1;
          end else begin
            h_st <= H_WREQ;
          end
        end
        H_WREQ: begin
          if (h_ab) begin
            h_wr[h_slot] <= 1'b0;
            h_st <= H_IDLE;
          end else begin
            h_lba_r <= u_base[h_slot] + {{(LW-8){1'b0}}, h_i};
            h_cnt_r <= 6'(h_run - 8'd1);
            h_wr[h_slot]      <= 1'b1;
            if (h_ack[h_slot] && !h_ackq) begin
              h_wr[h_slot] <= 1'b0;
              h_st <= H_WXFER;
            end
          end
        end
        H_WXFER: if (!h_ack[h_slot]) begin
          h_i  <= h_i + h_run;
          h_st <= H_WSCAN;
        end

        // ---- probe: one block straight from the file -------------------------------
        H_PREQ: begin
          if (h_ab) begin
            h_rd[h_slot] <= 1'b0;
            h_st <= H_IDLE;
          end else begin
            h_lba_r <= h_lba_q;
            h_cnt_r <= 6'd0;
            h_rd[h_slot]      <= 1'b1;
            if (h_ack[h_slot] && !h_ackq) begin
              h_rd[h_slot] <= 1'b0;
              h_st <= H_PXFER;
            end
          end
        end
        H_PXFER: if (!h_ack[h_slot]) begin
          if (!h_ab) begin
            pt_val[h_slot] <= 1'b1;
            pt_lba[h_slot[0]] <= h_lba_q;
          end
          h_st <= H_IDLE;
        end
        default: h_st <= H_IDLE;
      endcase
      for (int s = 0; s < 2; s++) begin
        if (dw_mark[s]) dirty_fd[s][dw_blk[FW_U-1:0]] <= 1'b1;
        if (mnt_ev[s])  dirty_fd[s] <= '0;
      end
      for (int k = 0; k < 2; k++) begin
        if (dw_mark[2 + k]) dirty_hd[k][dw_blk[UW-1:0]] <= 1'b1;
        if (mnt_ev[2 + k])  dirty_hd[k] <= '0;
      end
      // the probe's block is used once
      if (d_st == D_END && d_drop && !d_scr[d_slot]) pt_val[d_slot] <= 1'b0;
    end
  end

  assign busy    = h_st == H_CLAIM || h_st == H_DIV || h_st == H_LREQ || h_st == H_LXFER ||
                   h_st == H_ZERO || h_st == H_PREQ || h_st == H_PXFER;
  assign wb_busy = |any_dirty || h_st == H_WSCAN || h_st == H_WRUN || h_st == H_WREQ || h_st == H_WXFER;

  logic unused_ok;
  assign unused_ok = &{1'b0, h_clk[9:0], img_size[63:41], d_bc[10], dw_blk[7]};
endmodule
`default_nettype wire
