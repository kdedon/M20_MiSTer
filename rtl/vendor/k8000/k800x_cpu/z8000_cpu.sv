// z8000_cpu -- Z8001/Z8002 (Z8003/Z8004 with VMPU) CPU, top level.
//
// SEGMENTED=1: Z8001/Z8003 (SN pins, the PC segment read at reset, SEGT).
// VMPU=1: Z8003/Z8004 (ABORT pin).
//
// AD is split into ad_in / ad_out / ad_drive. ad_in must come straight from
// a register (the read-data capture): its decode look-ahead takes the clock.
// The test harness reads and pokes u_regfile.r, fcw, pc, psap, refresh,
// nspoff, nspseg, refresh_en and halted by name.

module z8000_cpu
  import z8000_ctrl_pkg::*, z8000_mc_pkg::*;
#(
  parameter bit SEGMENTED = 1,
  parameter bit VMPU      = 0
) (
  input  logic        clk,        // board master clock; every flop runs on it
  input  logic        reset_n,    // asynchronous, active low

  // CLK pin as the board's edge pulses: High for the one master clock in
  // which CLK rises, or falls. Both in one master clock act as the fall,
  // then the rise.
  input  logic        clk_rise,
  input  logic        clk_fall,

  // inputs
  input  logic [15:0] ad_in,
  input  logic        stop_n,
  input  logic        wait_n,
  input  logic        busreq_n,
  input  logic        nmi_n,
  input  logic        nvi_n,
  input  logic        vi_n,
  input  logic        segt_n,     // SEGT (Z8001) / SAT (Z8003); ignored when !SEGMENTED
  input  logic        abort_n,    // Z8003/Z8004 only; ignored when !VMPU
  input  logic        mi_n,

  // outputs
  output logic [15:0] ad_out,
  output logic        ad_drive,
  output logic        bus_drive,  // Low while the bus is granted: float the other outputs but /BUSACK and /MO
  output logic [6:0]  sn,         // SN6..SN0, meaningful only when SEGMENTED
  output logic        as_n,
  output logic        ds_n,
  output logic        mreq_n,
  output logic        r_w,        // 1 = read
  output logic        b_w,        // 1 = byte
  output logic        n_s,        // 1 = normal (user) mode
  output logic [3:0]  st,         // ST3..ST0, z8000_zbus_pkg codes
  output logic        busack_n,
  output logic        mo_n
);

  // ---- CLK pin: the rising-edge pulse is the clock enable ---------------------
  logic clk_en;
  assign clk_en = clk_rise;

  // STOP is sampled on the CLK fall and acted on at the next rise; a rise
  // in the fall's master clock sees that sample.
  logic stop_fq, stop_s;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)      stop_fq <= 1'b1;
    else if (clk_fall) stop_fq <= stop_n;
  end
  assign stop_s = (clk_en && clk_fall) ? stop_n : stop_fq;

  // ---- architectural registers ----------------------------------------------
  logic [15:0] fcw;
  logic [31:0] pc;          // Z8002: 16-bit; Z8001: seg[22:16]:offset[15:0]
  logic [31:0] psap;
  logic [15:0] refresh;
  logic [15:0] nspoff;
  logic [15:0] nspseg;
  logic        refresh_en;
  logic        halted;

  // ---- register file --------------------------------------------------------
  logic        rf_we;
  logic [1:0]  rf_wwidth;
  logic [3:0]  rf_wsel;
  logic [63:0] rf_wdata;
  logic [1:0]  rf_rwidth;
  logic [3:0]  rf_rsel;
  logic [63:0] rf_rdata;
  logic        rf_rbyte_b;
  logic [3:0]  rf_rsel_b;
  logic [15:0] rf_rdata_b, ex_wdata;
  logic [15:0][1:0] rf_nz;
  logic        ex_rf_we;
  logic [1:0]  ex_rf_wwidth;
  logic [3:0]  ex_rf_wsel;
  logic [1:0]  ex_rf_rwidth_a;
  logic [3:0]  ex_rf_rsel, ex_rf_rsel_b;
  logic        ex_rf_rbyte_b;

  z8000_regfile u_regfile (
    .clk     (clk),
    .clk_en  (clk_en),
    .we      (rf_we),
    .wwidth  (rf_wwidth),
    .wsel    (rf_wsel),
    .wdata   (rf_wdata),
    .rwidth  (rf_rwidth),
    .rsel    (rf_rsel),
    .rdata   (rf_rdata),
    .rbyte_b (rf_rbyte_b),
    .rsel_b  (rf_rsel_b),
    .rdata_b (rf_rdata_b),
    .nz      (rf_nz)
  );

  // ---- control and bus ------------------------------------------------------
  logic        fcw_we, pc_we, ex_fcw_we, ctl_we, ref_we;
  logic [15:0] ex_fcw_d, ctl_rdata, ctl_wd;
  logic [2:0]  ctl_rsel, ctl_sel;
  logic [15:0] fcw_d;
  logic [31:0] pc_d;
  logic [15:0] dec_w0;
  logic [3:0]  dec_w1_lo;
  ctrl_word_t  ctrl, ctrl_q;
  logic        ex_handles, ex_first, ex_last, ex_last2, ex_last_nx, ex_last2_nx, ex_to_last, ex_flags_we, ex_pc_we;
  logic [22:0] ex_pc_d;
  logic [15:0] ir_w0, ir_w1, ir_w2;
  logic [22:0] ir_ea;
  logic        ir_ea_long;
  logic [15:0] ex_flags, ex_flags_mask;
  logic        rf_pending, rf_now, rf_take, rf_keep, bus_lost;
  logic [8:0]  rf_row_in, rf_row_next, rf_cyc_row;
  logic [22:0] rf_addr;
  logic        bus_nodata;
  logic        bus_mem, bus_write, mem_take, int_take, opnd_take, ex_mem_byte;
  logic [22:0] ex_mem_addr;
  logic [3:0]  ex_mem_st;
  logic [15:0] ex_mem_wdata;
  logic        bus_abt_smp;
  logic        bus_req, bus_internal, bus_normal, bus_cyc_end, bus_cyc_end3, bus_done, bus_lock_nx;
  logic [22:0] bus_addr;
  logic [3:0]  bus_st, bus_len;
  logic        bus_unit, u_end3, u_end2, u_last;   // the serial unit's cycle ends
  logic [2:0]  bus_tail;
  logic [15:0] bus_rdata;
  logic        cc_met, more;
  logic [5:0]  iter;

  z8000_decode u_decode (
    .w0    (dec_w0),
    .w1_lo (dec_w1_lo),
    .ctrl  (ctrl)
  );

  // Decoded from the words as of the next edge: ctrl_q decodes the words in.
  // A trapping word, and the entry after it, decode as nothing.
  logic       kill_nx, seq_exc, af_done, trap_if1, trap_epa;
  logic [4:0] exc_vec;
  ctrl_word_t ctrl_k;
  assign trap_epa = ctrl.valid && ctrl.exec == CLS_EPU && !fcw[13];
  // An undefined word takes the privileged trap in either mode.
  assign trap_if1 = !ctrl.valid || (ctrl.priv && !fcw[14]) || trap_epa;
  assign ctrl_k   = kill_nx ? '0 : ctrl;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) ctrl_q <= '0;
    else if (clk_en)          ctrl_q <= ctrl_k;
  end

  // Sequencer inputs from the units.
  logic        md_take, blk_more, mult_more, mreq_more, halt_exit, ex_word;
  mc_path_e    md_path;
  logic [15:0] rf_count;
  // Interrupt requests.
  logic        smp_end, smp_elem, smp_iop, irq, irq_now, irq_take, seq_bound;
  logic [3:0]  irq_st;
  logic [15:0] exc_id;
  logic [8:0]  exc_pcoff;
  // The enables are judged as the next instruction starts, so an EI or DI
  // writing them on the last clock counts at this boundary.
  logic        vie, nvie;
  assign vie  = ex_flags_we && ex_flags_mask[12] ? ex_flags[12] : fcw[12];
  assign nvie = ex_flags_we && ex_flags_mask[11] ? ex_flags[11] : fcw[11];
  z8000_int_unit u_int (
    .clk       (clk),
    .clk_en    (clk_en),
    .reset_n   (reset_n),
    .nmi_n     (nmi_n),
    .nvi_n     (nvi_n),
    .vi_n      (vi_n),
    .segt_n    (segt_n || !SEGMENTED),
    .vie       (vie),
    .nvie      (nvie),
    .smp_end   (smp_end),
    .smp_elem  (smp_elem),
    .smp_halt  (smp_iop),
    .halt_on   (ctrl_q.valid && ctrl_q.exec == CLS_HALT),
    .take      (irq_take),
    .clr       (seq_bound),
    .irq       (irq),
    .irq_now   (irq_now),
    .st        (irq_st),
    .halt_exit (halt_exit)
  );

  // ---- multiply and divide --------------------------------------------------
  // The units move on the program's clocks (not a wait or a refresh) and
  // start on the IF1's T3 in every form; the first pass that reads the
  // source holds until it is in (operand not in), so a DA/X unit ends with
  // the program's last clock as an R one does. The destination quad is read
  // on port A as the unit starts. A register source is read on port B: a
  // word the clock after the start, a long's high word as it starts and its
  // low word the clock after; it is given and picks the program's path
  // there. A memory or immediate source is given on the edge its last word
  // arrives. The result and flags go in from the unit's registers the
  // clock after the last.
  logic        imm_take, imm_in, seq_in_rf, seq_rf_due, bus_twait, bus_held, bus_iop, bus_away;
  logic        bus_bound, ex_ph_hold;
  logic        md_mul, md_div, md_on, md_long, md_reg, md_imm, md_tick;
  logic        md_start, md_lda, md_data, md_arrive, md_src_hi, md_src_valid, md_pick_q, md_seen_q;
  logic        md_pend_q, md_mul_q, md_long_q, md_wb, md_rf_we;
  logic [3:0]  md_dst_q, md_flags;
  logic [15:0] md_src;
  logic [31:0] md_dst_w, m_product;
  logic [63:0] md_wdata, s_words;
  logic        m_flag_c, m_flag_z, d_dbz, d_ovf, d_wide, d_qneg, d_qzero;
  logic        s_done, s_fin, s_end3, s_end2, s_last;

  assign md_mul  = ctrl_q.valid && ctrl_q.exec == CLS_MUL;
  assign md_div  = ctrl_q.valid && ctrl_q.exec == CLS_DIV;
  assign md_on   = md_mul || md_div;
  assign md_long = ctrl_q.width == WIDTH_LONG;
  assign md_reg  = ctrl_q.src2 == SRC_REG;
  assign md_imm  = ctrl_q.src2 == SRC_IMM;
  assign md_tick = !seq_in_rf && !bus_twait && !bus_held;

  localparam logic [1:0] RF_BYTE = 2'd0, RF_WORD = 2'd1, RF_LONG = 2'd2, RF_QUAD = 2'd3;   // register file widths

  assign md_lda   = md_on && ex_first;
  assign md_start = md_lda && md_tick;

  // Port A reads the destination quad as the unit starts.
  assign rf_rwidth = md_lda ? RF_QUAD : sh_on ? sh_rwidth : mq_on ? RF_WORD : ex_rf_rwidth_a;
  assign rf_rsel   = md_lda ? {ir_w0[3:2], 2'b00} : sh_on || mq_on ? ir_w0[7:4] : ex_rf_rsel;

  // Operand words: immediate words, or the memory reads; a long's first
  // is its high word. Each goes to the unit as it is given.
  assign md_data      = md_on && (md_imm ? imm_take : opnd_take && !md_reg);
  assign md_arrive    = md_data && (!md_long || md_seen_q);
  assign md_src_hi    = md_long && (md_reg ? md_start : md_data && !md_seen_q);
  assign md_src_valid = md_reg ? md_pick_q : md_arrive;
  assign md_src       = md_reg ? rf_rdata_b : bus_rdata;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      md_pick_q <= 1'b0;
      md_seen_q <= 1'b0;
    end else if (clk_en) begin
      md_pick_q <= md_start && md_reg;
      if (ex_first)     md_seen_q <= 1'b0;
      else if (md_data) md_seen_q <= 1'b1;
    end
  end

  // A memory or immediate word is tested off the bus; a long's high word
  // keeps its test from the edge it is given. A register source is tested
  // the clock after the unit starts, from the register file's byte nonzero
  // bits, which are the registers as it started.
  logic       md_bz, md_hiz_q, md_mz, md_rz;
  logic [3:0] md_rs_q;
  logic [1:0] md_nz_hi, md_nz_lo;
  assign md_bz = bus_rdata == 16'h0000;
  assign md_mz = md_bz && (!md_long || md_hiz_q);
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      md_hiz_q <= 1'b0;
      md_rs_q  <= 4'd0;
    end else if (clk_en) begin
      if (md_src_hi && !md_reg)  md_hiz_q <= md_bz;
      if (md_start && md_reg)    md_rs_q  <= ir_w0[7:4];
    end
  end
  assign md_nz_hi = rf_nz[{md_rs_q[3:1], 1'b0}];
  assign md_nz_lo = rf_nz[{md_rs_q[3:1], 1'b1}];
  assign md_rz    = md_long ? (md_nz_hi | md_nz_lo) == 2'b00 : (md_rs_q[0] ? md_nz_lo : md_nz_hi) == 2'b00;

  // A multiplier picks the path as it is given: a register source's pick
  // lands in the IF1's tail (clock 3), where no refresh or wait runs, and
  // no cycle starts on its edge. A divide has one program, which the
  // unit's last cycle ends.
  assign md_take = md_mul && (md_pick_q || md_arrive);
  assign md_path = (md_reg ? md_rz : md_mz) ? MC_PATH_ZERO : MC_PATH_DEFAULT;

  // MULT: Rd+1 (RQ's low long for MULTL). DIV: RRd (RQd for DIVL).
  always_comb begin
    if (md_mul) md_dst_w = md_long ? rf_rdata[31:0] : {16'h0000, ir_w0[1] ? rf_rdata[15:0] : rf_rdata[47:32]};
    else        md_dst_w = ir_w0[1] ? rf_rdata[31:0] : rf_rdata[63:32];
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      md_pend_q <= 1'b0;
      md_mul_q  <= 1'b0;
      md_long_q <= 1'b0;
      md_dst_q  <= 4'd0;
    end else if (clk_en) if (md_start) begin
      md_pend_q <= 1'b1;
      md_mul_q  <= md_mul;
      md_long_q <= md_long;
      md_dst_q  <= ir_w0[3:0];
    end else if (md_wb || seq_bound) begin
      md_pend_q <= 1'b0;        // an abort ends the instruction unwritten
    end
  end

  // The result goes in on the unit's last clock, the program's last. Divide
  // by zero writes the dividend back; overflow, the unit's partial words.
  assign md_wb    = md_pend_q && (s_done || (s_fin && md_tick));
  assign md_rf_we = md_wb;
  always_comb begin
    md_wdata  = md_long_q ? s_words : {32'd0, s_words[63:32]};
    m_product = s_words[63:32];
    if (md_mul_q) begin
      if (md_long_q) md_flags = {m_flag_c, m_flag_z, s_words[63], 1'b0};
      else           md_flags = {m_product[31:15] != {17{m_product[31]}}, m_product == 32'd0, m_product[31], 1'b0};
    end else begin
      if (d_dbz)      md_flags = 4'b0101;
      else if (d_ovf) md_flags = 4'b0001;
      else            md_flags = {d_wide, d_qzero, d_qneg, d_wide};
    end
  end

  // ---- shifts ----------------------------------------------------------------
  // SLA/SLL and SDA/SDL, byte, word and long: one position per 3-clock
  // internal cycle, the unit starting as the first of them is taken. Port A
  // reads the destination throughout. A register count is read on port B
  // as the I3 before the positions is taken; that I3 forms its magnitude
  // and direction. The last position is in as the last I3 opens, so the
  // result and flags go in on the program's last clock. Each step waits
  // for the end of a cycle that is not followed by a refresh: the Fn (the
  // count word), then the count I3 for a register count.
  logic        sh_on, sh_reg, sh_start, sh_arm_q, sh_step, sh_cnt_ok_q, sh_pend_q, sh_wb;
  logic [1:0]  sh_rwidth, sh_wwidth_q;
  logic [3:0]  sh_dst_q;
  logic [15:0] sh_cnt_q, sh_flags, sh_fmask;
  logic [ALUOP_W-1:0] sh_op;

  assign sh_on     = ctrl_q.valid && ctrl_q.exec == CLS_SHIFT;
  assign sh_reg    = ctrl_q.count == SRC_REG;
  assign sh_rwidth = ctrl_q.width == WIDTH_BYTE ? RF_BYTE : ctrl_q.width == WIDTH_WORD ? RF_WORD : RF_LONG;
  assign rf_count  = sh_cnt_q;
  assign sh_step   = sh_on && sh_arm_q && bus_cyc_end && !seq_rf_due;
  assign sh_start  = sh_step && (!sh_reg || sh_cnt_ok_q);

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      sh_arm_q    <= 1'b0;
      sh_cnt_q    <= 16'h0000;
      sh_cnt_ok_q <= 1'b0;
    end else if (clk_en) if (ex_first) begin
      sh_arm_q    <= 1'b0;
      sh_cnt_ok_q <= 1'b0;
    end else begin
      if (sh_on && imm_take) sh_arm_q <= 1'b1;
      else if (sh_start)     sh_arm_q <= 1'b0;
      if (sh_step && sh_reg && !sh_cnt_ok_q) begin
        sh_cnt_q    <= rf_rdata_b;
        sh_cnt_ok_q <= 1'b1;
      end
    end
  end

  logic [15:0] sh_cnt;
  logic [5:0]  sh_n;
  // Static byte forms encode the count as 00|n8; only the low byte counts.
  assign sh_cnt = sh_reg                     ? rf_count :
                  ctrl_q.width == WIDTH_BYTE ? {{8{ir_w1[7]}}, ir_w1[7:0]} : ir_w1;
  // Legal counts are at most 32 (long), so six bits.
  assign sh_n   = sh_cnt[15] ? 6'd0 - sh_cnt[5:0] : sh_cnt[5:0];

  // A negative count shifts right.
  always_comb begin
    if (ctrl_q.alu_op == OP_SLA) sh_op = sh_cnt[15] ? OP_SRA : OP_SLA;
    else                         sh_op = sh_cnt[15] ? OP_SRL : OP_SLL;
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      sh_pend_q   <= 1'b0;
      sh_dst_q    <= 4'd0;
      sh_wwidth_q <= RF_BYTE;
    end else if (clk_en) if (sh_start) begin
      sh_pend_q   <= 1'b1;
      sh_dst_q    <= ir_w0[7:4];
      sh_wwidth_q <= sh_rwidth;
    end else if (sh_wb || seq_bound) begin
      sh_pend_q   <= 1'b0;
    end
  end
  assign sh_wb = sh_pend_q && ex_last;

  // One serial unit runs the multiplies, divides and shifts.
  z8000_serial u_serial (
    .clk         (clk),
    .clk_en      (clk_en),
    .reset_n     (reset_n),
    .tick        (md_tick),
    .start       (md_start || sh_start),
    .mul         (md_mul),
    .div         (md_div),
    .wide        (md_long),
    .dst         (md_on ? (md_div && md_long ? rf_rdata : {32'd0, md_dst_w}) : {32'd0, rf_rdata[31:0]}),
    .src_hi      (md_src_hi),
    .src_valid   (md_src_valid),
    .src         (md_src),
    .width       (ctrl_q.width),
    .op          (sh_op),
    .count       (sh_n),
    .done        (s_done),
    .fin         (s_fin),
    .words       (s_words),
    .flag_c      (m_flag_c),
    .flag_z      (m_flag_z),
    .more        (mult_more),
    .div_by_zero (d_dbz),
    .overflow    (d_ovf),
    .wide_quot   (d_wide),
    .quot_neg    (d_qneg),
    .quot_zero   (d_qzero),
    .sh_flags    (sh_flags),
    .sh_mask     (sh_fmask),
    .end3        (s_end3),
    .end2        (s_end2),
    .last        (s_last)
  );

  // ---- multi-micro: MSET, MRES, MBIT, MREQ -------------------------------------
  // MSET/MRES drive /MO and MBIT sets S if /MI is High as the last clock
  // opens. MREQ (F1+2 . n x I7 . I7) samples /MI as its word is taken: High
  // drives /MO Low and counts Rd down, one I7 each: port A reads Rd, which
  // each I7's first clock writes back less one through the execute unit's
  // step adder. Low clears S and Z and skips the count. As the last clock
  // opens /MI is sampled again: Low grants (S set), High withdraws (S clear,
  // /MO High); Z is set.
  logic        mp_on, mq_on, mq_go, mo_q, mq_req_q, mq_more_q, mq_dec_q, mq_wb, mq_end;
  logic [15:0] mq_cnt;      // Rd less one

  assign mp_on     = ctrl_q.valid && ctrl_q.exec == CLS_MULTI_PROC;
  assign mq_on     = mp_on && ctrl_q.mp_op == MPREQ;
  assign mreq_more = mq_more_q;
  assign mq_wb     = mq_on && mq_dec_q;
  assign mq_end    = mp_on && ex_to_last;
  assign mq_go     = ex_word && fcw[14] && ctrl.valid && ctrl.exec == CLS_MULTI_PROC && ctrl.mp_op == MPREQ;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      mo_q      <= 1'b1;
      mq_req_q  <= 1'b0;
      mq_more_q <= 1'b0;
      mq_dec_q  <= 1'b0;
    end else if (clk_en) begin
      mq_dec_q <= mq_on && int_take && more;
      // Only a word that runs: in normal mode MREQ traps and /MO holds.
      if (mq_go) begin
        mq_req_q <= mi_n;
        mo_q     <= !mi_n;
      end else if (mq_end) begin
        unique case (ctrl_q.mp_op)
          MPSET:   mo_q <= 1'b0;
          MPRES:   mo_q <= 1'b1;
          MPREQ:   if (mq_req_q && mi_n) mo_q <= 1'b1;
          default: ;
        endcase
      end
      if (mq_on && ex_first) mq_more_q <= mq_req_q && rf_rdata[15:0] != 16'h0000;
      else if (mq_wb)        mq_more_q <= mq_cnt != 16'h0000;
    end
  end

  // Port B reads a shift's count register, else the execute unit's pick.
  assign rf_rsel_b  = sh_on && sh_reg ? ir_w1[11:8] : ex_rf_rsel_b;
  assign rf_rbyte_b = sh_on && sh_reg ? 1'b0 : ex_rf_rbyte_b;

  assign rf_we     = md_rf_we || sh_wb || mq_wb || ex_rf_we;
  assign rf_wwidth = md_rf_we ? (md_long_q ? RF_QUAD : RF_LONG) : sh_wb ? sh_wwidth_q
                   : mq_wb ? RF_WORD : ex_rf_wwidth;
  assign rf_wsel   = md_rf_we ? md_dst_q : sh_wb ? sh_dst_q : mq_wb ? ir_w0[7:4] : ex_rf_wsel;
  assign rf_wdata  = md_rf_we ? md_wdata : sh_wb ? {32'd0, s_words[31:0]}
                   : mq_wb ? {48'd0, mq_cnt}
                   : {48'd0, ex_wdata};

  z8000_sequencer #(.SEGMENTED(SEGMENTED)) u_sequencer (
    .clk          (clk),
    .clk_en       (clk_en),
    .reset_n      (reset_n),
    .fcw_sys      (fcw[14]),
    .fcw_seg      (fcw[15]),
    .pc           (pc),
    .fcw_we       (fcw_we),
    .fcw_d        (fcw_d),
    .pc_we        (pc_we),
    .pc_d         (pc_d),
    .halted       (halted),
    .dec_w0       (dec_w0),
    .dec_w1_lo    (dec_w1_lo),
    .dec_valid    (ctrl_q.valid),
    .dec_exec     (ctrl_q.exec),
    .trap_if1     (trap_if1),
    .trap_epa     (trap_epa),
    .abt_hit      (VMPU && !abort_n && bus_abt_smp),
    .kill_nx      (kill_nx),
    .exc          (seq_exc),
    .af_done      (af_done),
    .exc_vec      (exc_vec),
    .exc_id       (exc_id),
    .exc_pcoff    (exc_pcoff),
    .irq          (irq),
    .irq_now      (irq_now),
    .irq_st       (irq_st),
    .smp_end      (smp_end),
    .smp_elem     (smp_elem),
    .smp_iop      (smp_iop),
    .irq_take     (irq_take),
    .bound        (seq_bound),
    .cc_met       (cc_met),
    .md_take      (md_take),
    .md_zero      (md_mul && md_arrive && md_mz),
    .md_path      (md_path),
    .more         (more),
    .unit_last    (u_last),
    .bus_iop      (bus_iop),
    .bus_away     (bus_away),
    .iter         (iter),
    .ex_handles   (ex_handles || sh_on || mp_on),
    .io_write     (ctrl_q.io_write || (ctrl_q.exec == CLS_EPU && ir_w0[3])),
    .ex_first     (ex_first),
    .ex_word      (ex_word),
    .ex_to_last   (ex_to_last),
    .ex_last2     (ex_last2),
    .ex_last      (ex_last),
    .ex_last2_nx  (ex_last2_nx),
    .ex_last_nx   (ex_last_nx),
    .ir_w0        (ir_w0),
    .ir_w1        (ir_w1),
    .ir_w2        (ir_w2),
    .ir_ea        (ir_ea),
    .ir_ea_long   (ir_ea_long),
    .mem_addr     (ex_mem_addr),
    .mem_st       (ex_mem_st),
    .mem_take     (mem_take),
    .int_take     (int_take),
    .opnd_take    (opnd_take),
    .imm_take     (imm_take),
    .imm_in       (imm_in),
    .in_rf        (seq_in_rf),
    .rf_due       (seq_rf_due),
    .rf_pending   (rf_pending),
    .rf_now       (rf_now),
    .rf_addr      (rf_addr),
    .rf_take      (rf_take),
    .rf_keep      (rf_keep),
    .stop_n       (stop_s),
    .bus_req      (bus_req),
    .bus_internal (bus_internal),
    .bus_addr     (bus_addr),
    .bus_st       (bus_st),
    .bus_normal   (bus_normal),
    .bus_mem      (bus_mem),
    .bus_nodata   (bus_nodata),
    .bus_write    (bus_write),
    .bus_len      (bus_len),
    .bus_unit     (bus_unit),
    .bus_tail     (bus_tail),
    .bus_cyc_end  (bus_cyc_end),
    .bus_cyc_end3 (bus_cyc_end3),
    .bus_done     (bus_done),
    .bus_rdata    (bus_rdata)
  );

  // The condition of the first word as of the next edge (JR's in w0[11:8]),
  // held from the IF1's T3 edge for the branch or TCC it picks the path of.
  logic cc_held_q;
  z8000_cond u_cond (
    .cc  (dec_w0[15:12] == 4'hE ? dec_w0[11:8] : dec_w0[3:0]),
    .c   (fcw[7]),
    .z   (fcw[6]),
    .s   (fcw[5]),
    .v   (fcw[4]),
    .met (cc_met)
  );
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)     cc_held_q <= 1'b0;
    else if (clk_en) if (ex_word) cc_held_q <= cc_met;
  end

  // The serial unit's cycle ends, for the instruction running it.
  assign u_end3 = (md_on || sh_on) && s_end3;
  assign u_end2 = md_div && s_end2;
  assign u_last = (md_on || sh_on) && s_last;

  // Whether the repeated part runs again after `iter` repetitions: LDM and
  // EPU transfers take their count from word 1; MULTL's frame and add
  // cycles follow while the multiplier says.
  always_comb begin
    more = 1'b0;
    unique case (ctrl_q.exec)
      CLS_LDM:        more = iter <= {2'b00, ir_w1[3:0]};
      CLS_EPU:        more = iter <= {2'b00, ir_w1[3:0]};
      CLS_BLOCK_TRANSFER, CLS_BLOCK_COMPARE, CLS_BLOCK_STRING, CLS_TRANSLATE, CLS_BLOCK_IO:
                      more = iter == 6'd0 || blk_more;
      CLS_MUL:        more = mult_more;
      CLS_MULTI_PROC: more = mreq_more;
      CLS_HALT:       more = !halt_exit;
      default:        ;
    endcase
  end

  // A block element's clock count holds through a refresh or a bus hold:
  // a cycle ends with a refresh or the bus away instead of its next cycle,
  // or a refresh runs.
  assign ex_ph_hold = bus_bound ? (!bus_cyc_end || seq_rf_due) : seq_in_rf;

  z8000_execute #(.SEGMENTED(SEGMENTED), .VMPU(VMPU)) u_execute (
    .clk        (clk),
    .clk_en     (clk_en),
    .reset_n    (reset_n),
    .w0         (ir_w0[11:0]),
    .ctrl_nx    (ctrl_k),
    .w0_nx      (dec_w0[11:0]),
    .alu_op     (ctrl_q.alu_op),
    .width      (ctrl_q.width),
    .src2       (ctrl_q.src2),
    .count      (ctrl_q.count),
    .dst        (ctrl_q.dst),
    .src1_nib   (ctrl_q.src1_nib),
    .src2_nib   (ctrl_q.src2_nib),
    .dst_nib    (ctrl_q.dst_nib),
    .w1         (ir_w1),
    .w2         (ir_w2),
    .handles    (ex_handles),
    .block_decr (ctrl_q.block_decr),
    .block_rept (ctrl_q.block_rept),
    .blk_more   (blk_more),
    .cc_held    (cc_held_q),
    .cnt_dec    (mq_wb),
    .cnt_val    (mq_cnt),
    .fcw_op     (ctrl_q.fcw_op),
    .fcw_mask   (ctrl_q.fcw_mask),
    .first      (ex_first),
    .to_last    (ex_to_last),
    .last2      (ex_last2),
    .last       (ex_last),
    .last2_nx   (ex_last2_nx),
    .last_nx    (ex_last_nx),
    .seg_mode   (SEGMENTED && fcw[15]),
    .pc_seg     (SEGMENTED ? pc[22:16] : 7'd0),
    .pc_off     (pc[15:0]),
    .cyc_end3   (bus_cyc_end3),
    .ea_word    (ir_ea),
    .ea_long    (ir_ea_long),
    .mem_take   (mem_take),
    .int_take   (int_take),
    .opnd_take  (opnd_take),
    .ph_hold    (ex_ph_hold),
    .imm_in     (imm_in),
    .rdata      (bus_rdata),
    .mem_addr   (ex_mem_addr),
    .mem_st     (ex_mem_st),
    .mem_byte   (ex_mem_byte),
    .mem_wdata  (ex_mem_wdata),
    .bus_lock_nx(bus_lock_nx),
    .rf_rwidth  (ex_rf_rwidth_a),
    .rf_rsel    (ex_rf_rsel),
    .rf_rdata   (rf_rdata[31:0]),
    .rf_rbyte_b (ex_rf_rbyte_b),
    .rf_rsel_b  (ex_rf_rsel_b),
    .rf_rdata_b (rf_rdata_b),
    .rf_we      (ex_rf_we),
    .rf_wwidth  (ex_rf_wwidth),
    .rf_wsel    (ex_rf_wsel),
    .rf_wdata   (ex_wdata),
    .pc_we      (ex_pc_we),
    .pc_d       (ex_pc_d),
    .fcw_c      (fcw[7]),
    .fcw_lo     (fcw[10:0]),
    .fcw_sn     (fcw[14]),
    .fcw        (fcw),
    .exc        (seq_exc),
    .af_done    (af_done),
    .exc_vec    (exc_vec),
    .psap       (psap[22:0]),
    .id_word    (exc_id),
    .exc_pcoff  (exc_pcoff),

    .fcw_we     (ex_fcw_we),
    .fcw_d      (ex_fcw_d),
    .ctl_rsel   (ctl_rsel),
    .ctl_rdata  (ctl_rdata),
    .ctl_we     (ctl_we),
    .ctl_sel    (ctl_sel),
    .ctl_wd     (ctl_wd),
    .flags_we   (ex_flags_we),
    .flags      (ex_flags),
    .flags_mask (ex_flags_mask)
  );

  // Control registers by LDCTL number: 2 FCW, 3 REFRESH, 4 PSAP segment,
  // 5 PSAP offset, 6 NSP segment, 7 NSP offset.
  always_comb begin
    unique case (ctl_rsel)
      3'd2:    ctl_rdata = fcw;
      3'd3:    ctl_rdata = refresh;
      3'd4:    ctl_rdata = {1'b0, psap[22:16], 8'h00};
      3'd5:    ctl_rdata = psap[15:0];
      3'd6:    ctl_rdata = nspseg;
      3'd7:    ctl_rdata = nspoff;
      default: ctl_rdata = 16'h0000;
    endcase
  end

  assign ref_we = ctl_we && ctl_sel == 3'd3;

  z8000_refresh u_refresh (
    .clk      (clk),
    .clk_en   (clk_en),
    .reset_n  (reset_n),
    .enable   (refresh_en),
    .rate     (refresh[14:9]),
    .row      (rf_row_in),
    .load     (ref_we && ctl_wd[15]),
    .load_rate(ctl_wd[14:9]),
    .take     (rf_take),
    .keep     (rf_keep),
    .lost     (bus_lost),
    .pending  (rf_pending),
    .now      (rf_now),
    .row_next (rf_row_next),
    .cyc_row  (rf_cyc_row)
  );

  // A refresh starting on a REFRESH write runs the written row. A write
  // loads bits 15:1 only; bit 0 is always 0, so AD0 is Low on a refresh.
  logic [8:0] ref_wrow;
  assign ref_wrow  = {ctl_wd[8:1], 1'b0};
  assign rf_row_in = ref_we ? ref_wrow : refresh[8:0];

  // Refresh addresses take the PC segment in nonsegmented mode.
  assign rf_addr = {(SEGMENTED && !fcw[15]) ? pc[22:16] : 7'd0, 7'd0, rf_cyc_row};

  // TSET's lock as of this edge: no grant as its read's T3 ends.
  logic lock_q;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)     lock_q <= 1'b0;
    else if (clk_en)  lock_q <= bus_lock_nx;
  end


  z8000_bus_unit #(.SEGMENTED(SEGMENTED)) u_bus (
    .clk            (clk),
    .clk_en         (clk_en),
    .clk_fall       (clk_fall),
    .reset_n        (reset_n),
    .req            (bus_req),
    .req_internal   (bus_internal),
    .req_addr       (bus_addr),
    .req_wdata      (ex_mem_wdata),
    .req_st         (bus_st),
    .req_write      (bus_write),
    .req_nodata     (bus_nodata),
    .req_byte       (bus_mem && ex_mem_byte),
    .req_odd        (ex_mem_addr[0]),
    .req_epu_drives (ctrl_q.valid && ctrl_q.exec == CLS_EPU && ctrl_q.epu_kind == EPU_MEM),
    .req_normal     (bus_normal),
    .req_len        (bus_len),
    .req_unit       (bus_unit),
    .unit_end3      (u_end3),
    .unit_end2      (u_end2),
    .unit_last      (u_last),
    .tail           (bus_tail),
    .lock           (lock_q),
    .busreq         (!busreq_n),
    .cyc_end        (bus_cyc_end),
    .cyc_bound      (bus_bound),
    .cyc_end3       (bus_cyc_end3),
    .twait          (bus_twait),
    .abt_smp        (bus_abt_smp),
    .held           (bus_held),
    .lost           (bus_lost),
    .away           (bus_away),
    .cyc_iop        (bus_iop),
    .done           (bus_done),
    .rdata          (bus_rdata),
    .wait_n         (wait_n),
    .ad_in          (ad_in),
    .ad_out         (ad_out),
    .ad_drive       (ad_drive),
    .sn             (sn),
    .as_n           (as_n),
    .ds_n           (ds_n),
    .mreq_n         (mreq_n),
    .r_w            (r_w),
    .b_w            (b_w),
    .n_s            (n_s),
    .st             (st),
    .busack_n       (busack_n),
    .bus_drive      (bus_drive)
  );

  assign mo_n     = mo_q;


  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      fcw <= 16'h0000;
      pc  <= 32'h0;
    end else if (clk_en) begin
      if (fcw_we)           fcw <= fcw_d;
      else if (ex_fcw_we)   fcw <= ex_fcw_d;
      else if (ex_flags_we) fcw <= (fcw & ~ex_flags_mask) | (ex_flags & ex_flags_mask);
      else if (md_wb)       fcw <= {fcw[15:8], md_flags, fcw[3:0]};
      else if (sh_wb)       fcw <= (fcw & ~sh_fmask) | (sh_flags & sh_fmask);
      else if (mq_end && ctrl_q.mp_op == MPBIT) fcw[5] <= mi_n;
      else if (mq_end && ctrl_q.mp_op == MPREQ) begin
        fcw[6] <= mq_req_q;
        fcw[5] <= mq_req_q && !mi_n;
      end
      if (ex_pc_we)         pc  <= {9'd0, ex_pc_d};
      else if (pc_we)       pc  <= pc_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      refresh <= 16'h0;
    end else if (clk_en) if (ref_we) begin
      refresh <= {ctl_wd[15:9], rf_take ? rf_row_next : ref_wrow};
    end else if (rf_take) begin
      refresh <= {refresh[15:9], rf_row_next};
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      psap       <= 32'h0;
      nspoff     <= 16'h0;
      nspseg     <= 16'h0;
      refresh_en <= 1'b0;
    end else if (clk_en) if (ctl_we) begin
      unique case (ctl_sel)
        3'd3:    refresh_en <= ctl_wd[15];
        3'd4:    psap[31:16] <= {9'd0, ctl_wd[14:8]};
        3'd5:    psap[15:0]  <= ctl_wd;
        3'd6:    nspseg      <= ctl_wd;
        3'd7:    nspoff      <= ctl_wd;
        default: ;
      endcase
    end
  end

  // Inputs and registers that later control units will consume.
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{rf_rdata[63:32], fcw[13:8], fcw[3:0], psap, refresh[15], nspoff, nspseg,
                       halted, ir_w0[15:12], sh_cnt[14:6],
                       ctrl_q.priv, ctrl_q.fcw_op, ctrl_q.fcw_mask, ctrl_q.stk_mode,
                       ctrl_q.br_mode, ctrl_q.io_spec};
  // verilator lint_on UNUSEDSIGNAL

  // synthesis translate_off
  // Unit and program in step; read by the testbench.
  // verilator lint_off UNUSEDSIGNAL
  logic check_q = 1'b0;
  // verilator lint_on UNUSEDSIGNAL
  logic [31:0] chk_src_q;
  logic        last_d1_q = 1'b0, sh_run_q = 1'b0, sh_prev_q = 1'b0;
  // CLK rises and falls in turn; a pulse pair in one master clock is a fall
  // then a rise.
  logic        pulse_seen_q = 1'b0, rose_q = 1'b0, pulse_bad_q = 1'b0;
  always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) pulse_seen_q <= 1'b0;
    else if (clk_en || clk_fall) begin
      if (pulse_seen_q && (clk_fall ? !rose_q : rose_q)) begin
        $display("%%Error: %m: two CLK %0s pulses with no %0s between", clk_fall ? "fall" : "rise",
                 clk_fall ? "rise" : "fall");
        pulse_bad_q <= 1'b1;
      end
      pulse_seen_q <= 1'b1;
      rose_q       <= clk_en;
    end
  always_ff @(posedge clk) if (clk_en) begin
    if (pulse_bad_q) check_q <= 1'b1;
    // Port A reads the destination as the unit starts: no operand address
    // is formed from it on that clock.
    if (md_lda && mem_take) begin
      $display("%%Error: %m: multiply/divide destination read on an operand address clock");
      check_q <= 1'b1;
    end
    if (md_data && !md_tick) begin
      $display("%%Error: %m: multiply/divide operand word on a held clock");
      check_q <= 1'b1;
    end
    // The interrupt unit sees an EI or DI's enables, so no other FCW write
    // may win that edge.
    if (ex_flags_we && (ex_flags_mask[12] || ex_flags_mask[11]) && (fcw_we || ex_fcw_we)) begin
      $display("%%Error: %m: EI/DI coincides with another FCW write");
      check_q <= 1'b1;
    end
    if (md_start && md_pend_q) begin
      $display("%%Error: %m: multiply/divide started twice");
      check_q <= 1'b1;
    end
    // The operands read through ports A and B are the registers as the
    // unit starts.
    if (md_start) begin
      chk_src_q <= md_long ? {u_regfile.r[{ir_w0[7:5], 1'b0}], u_regfile.r[{ir_w0[7:5], 1'b1}]}
                           : {16'h0000, u_regfile.r[ir_w0[7:4]]};
      if (rf_rdata != {u_regfile.r[{ir_w0[3:2], 2'b00}], u_regfile.r[{ir_w0[3:2], 2'b01}],
                       u_regfile.r[{ir_w0[3:2], 2'b10}], u_regfile.r[{ir_w0[3:2], 2'b11}]}) begin
        $display("%%Error: %m: multiply/divide destination read differs");
        check_q <= 1'b1;
      end
    end
    if (md_pick_q && !md_tick) begin
      $display("%%Error: %m: register source pick on a held clock");
      check_q <= 1'b1;
    end
    // The units end with the program: the write is on its last clock.
    // A late operand holds the unit, which then ends past the program.
    if (md_pend_q && s_done && !(s_fin && md_tick)) begin
      $display("%%Error: %m: multiply/divide write after the program's last clock");
      check_q <= 1'b1;
    end
    if (md_wb != (md_pend_q && ex_last)) begin
      $display("%%Error: %m: multiply/divide unit and program out of step");
      check_q <= 1'b1;
    end
    // A shift's last step ends with the program.
    sh_run_q <= sh_start || (sh_run_q && !s_done);
    if ((sh_run_q && s_done) != (last_d1_q && sh_prev_q)) begin
      $display("%%Error: %m: shift unit and program out of step");
      check_q <= 1'b1;
    end
    sh_prev_q <= sh_wb;
    last_d1_q <= ex_last;
    // The prescaler looks ahead from its registers, blind to a write.
    if (rf_take && ref_we && u_refresh.soon !=
        (ctl_wd[15] && u_refresh.div4_q == 2'd2 && ctl_wd[14:9] == 6'd1)) begin
      $display("%%Error: %m: refresh taken on a REFRESH write");
      check_q <= 1'b1;
    end
    if (u_bus.check_q) check_q <= 1'b1;
    // The zero tests are the operand the unit is given.
    if (md_mul && (md_arrive || md_pick_q) && (md_reg ? md_rz : md_mz) !=
        (u_serial.arrive ? md_src == 16'h0000 && (!u_serial.long_cur || u_serial.b_q[31:16] == 16'h0000)
                         : u_serial.b_q == 32'd0)) begin
      $display("%%Error: %m: multiply operand zero test differs");
      check_q <= 1'b1;
    end
    if (md_pick_q && {md_long ? u_serial.b_q[31:16] : 16'h0000, md_src} != chk_src_q) begin
      $display("%%Error: %m: multiply/divide register source read differs");
      check_q <= 1'b1;
    end
  end
  // synthesis translate_on

endmodule
