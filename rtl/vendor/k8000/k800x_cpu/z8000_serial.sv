// z8000_serial -- the serial arithmetic unit: MULT/MULTL, DIV/DIVL and
// the shifts as one microword set on one 16-bit adder and one pair rotate.
//
// The destination is held as words r0..r3 (Rd0..Rd3, high to low), loaded
// as the unit starts (the port A read) and written back on the program's
// last clock. Every clock is one pass of the adder (a word) or of the
// rotate (a register pair, left or right, a fill bit in; a shift's width
// taps its carry and sign), a latch, or a sequencer clock. A loop closes
// with DEC count and its branch; an inline branch, a routine's call and its
// return are 2 clocks each; a routine is call, three passes, return.
//
// Shared microwords:
//   DEC; BR      the loop head: MULT's 1-clock branch; MULTL's and the
//                shift's 2; DIV's 2 with frame 1's prologue between them
//   TEST B       Z latched (and the divisor's sign); B's first use
//   BRX          a 2-clock branch: the zero exits, MULTL's call into its
//                finish, DIVL's exit
//   NEG; SBC     a negate pair masked by K: DIV's entry and its zero exit
//                (the same two microwords), DIVL's 4-word entry; inside
//                routines the same pass with other words and masks
//   pair flags   CP hi against lo's sign, OR hi|lo, the flags: MULT's zero
//                finish on {Rd0,Rd1}, DIVL's on the quotient {Rd2,Rd3}
//
// MULT, accumulator {X, r0, r1}, multiplicand in r1: LD r0,#0; LD count,#16;
// 16 frames of DEC; BR; ADD B masked by r1[0] (the 16th subtracts), X =
// S^V; RRC {r0,r1}. Frame 1 tests B after its branch (clock 5); Z: BRX,
// LD r1,#0, pair flags.
// MULTL, accumulator {X, r0..r3}, A = (Ah + K) * 2^16 + s, s = int16(r3),
// K = s < 0: LD r0,#0; LD r1,#0; NEG r3 if negative (K); ADC r2,#0 with K
// (V kept as bit 16), LD count,#32; 32 frames of DEC; BR; ADD/ADC B masked
// into r1, r0 (frames 17-32, on the bits of Ah + K; frame 32 subtracts
// unless bit 16 is set); in frames 1-16 a 1 in |s| calls the add routine
// (ADD/SUB B_L, ADC/SBC B_H by K, latch X); RRC {r0,r1}; RRC {r2,r3}.
// Frame 1 tests B on clock 8. One finish for both paths, called by BRX
// from the loop's exit or the zero test: LD r2,#0; LD r3,#0 (both masked
// by Z); Z routine (OR r3|r2, |r1, |r0); C routine (CP r1, CPC r0 against
// r2's sign, latch C); flags, ending in line.
//
// DIV, restoring division on magnitudes, remainder in {X, r0}, quotient
// bits into r1; K the dividend's sign, Sd the divisor's, Q the latest bit.
// The divisor stays signed: a pass against |D| subtracts D when Sd is 0 and
// adds it when 1, and "fits" is the carry out. NEG r1; SBC r0, LD
// count,#16; 16 frames of DEC; BR; BR; RLC {r0,r1} Q in; SUB r0,|D| (Q);
// ADD r0,|D| unless Q. Frame 1's prologue between the branch's clocks:
// TEST B (clock 5); CP r1,|D| (the low half < |D|; the next address takes
// Z to the zero exit); CP r0,|D|, the trial of the unshifted high half: O
// if it fits, unless the remainder is 0, the quotient negative and the low
// half < |D| (-2^16); r0 kept if it fits and not O. Finish: RLC r1 Q in;
// NEG r1 by K^Sd (Z, S, the width latched); NEG r0 by K. Zero exit: BRX
// into NEG; SBC, the dividend back. Past the width O joins the loop
// condition DEC latches: frame 2 closes into the finish, whose RLC takes O
// into the zero exit's restore; the partial words stay.
// DIVL, remainder in {X, r0, r1}, quotient bits into r2:r3: NEG r3; SBC r2,
// r1, r0. Frame 0, three routines: LD count,#33, OR B_L,B_H (Z, clock 8),
// NEG B_L by B[31] (Sd) | SBC B_H by Sd, then by Z NEG r3, SBC r2, else CP
// r3,|D|_L, CPC r2,|D|_H | by Z SBC r1, SBC r0, latch the low half <
// |D|; Z returns to the exit. 33 frames: trial (SUB r1,|D|_L; SBC r0,|D|_H,
// Z of both; decide, frame 1 latches O as DIV's), restore (ADD, ADC unless
// the trial fit; Q), shift (RLC {r2,r3} Q in; RLC {X,r0,r1} C in; DEC
// count). Finish: quotient (NEG r3, SBC r2 by K^Sd; S), remainder (RRC
// {X,r0,r1}; NEG r1, SBC r0 by K), pair flags on {r2,r3} (its CP unread);
// BRX. Past the width the shift's return takes O to the exit.
// A quotient one bit too wide runs the normal routine: its stored sign
// disagrees with K^Sd, or, for -2^N, the first trial fits and its bit is
// dropped.
//
// Shifts: one position per 3-clock cycle, in {r2,r3} masked to the width:
// the position shifts as the cycle opens (the start edge shifts the first),
// then DEC and BR, whose second clock ends the cycle and shifts the next.
// A zero count runs one cycle, shifts nothing and leaves C. Flags: C the
// last bit out, Z, S; V (SLA) a sign change at any step.
//
// The result is final as the last clock's pass is written (`fin`); done
// the clock after. Nothing moves on a clock without `tick`, but a shift
// starts on its edge. B is given a word at a time, a long's high word
// first; the first pass that reads it holds until it is in.
// The unit gives each internal cycle's end two clocks ahead
// (`end3`; DIV's trial one ahead, `end2`) and the program's last cycle from
// its first clock (`last`), to the instruction that started it. `more`
// says another MULTL frame or add cycle follows the one in flight; held
// through a clock without `tick`.

module z8000_serial
  import z8000_ctrl_pkg::*;
(
  input  logic               clk,
  input  logic               clk_en,   // CLK rising edge seen this clock
  input  logic               reset_n,
  input  logic               tick,
  input  logic               start,
  input  logic               mul,         // MULT/MULTL; the instruction's class, held
  input  logic               div,         // DIV/DIVL; neither: a shift
  input  logic               wide,        // MULTL / DIVL
  input  logic [63:0]        dst,         // the destination as read
  input  logic               src_hi,      // a long's high word is given
  input  logic               src_valid,   // the last word is given
  input  logic [15:0]        src,
  input  logic [1:0]         width,       // shift: WIDTH_BYTE / WORD / LONG
  input  logic [ALUOP_W-1:0] op,          // shift: OP_SLL / SLA / SRL / SRA
  input  logic [5:0]         count,       // shift: 0..32
  output logic               done,
  output logic               fin,
  output logic [63:0]        words,       // r0..r3 as the last clock writes them
  output logic               flag_c,      // MULTL: from the finish routines
  output logic               flag_z,
  output logic               more,
  output logic               div_by_zero,
  output logic               overflow,
  output logic               wide_quot,
  output logic               quot_neg,
  output logic               quot_zero,
  output logic [15:0]        sh_flags,
  output logic [15:0]        sh_mask,
  output logic               end3,        // a cycle-end microword two clocks ahead
  output logic               end2,        // ... one clock ahead, from this pass
  output logic               last         // the internal cycle in flight is the program's last
);

  localparam logic [15:0] F_C = 16'h0080;
  localparam logic [15:0] F_Z = 16'h0040;
  localparam logic [15:0] F_S = 16'h0020;
  localparam logic [15:0] F_V = 16'h0010;

  // Micro-operations. R_* are routines: call (sub 0-1), passes (2-4),
  // return (5-6).
  typedef enum logic [5:0] {
    U_IDLE,
    U_DEC,     // DEC count; DIV: the exit condition latched
    U_BR,      // loop head branch (sub 0, 1)
    U_TEST,    // TEST B: Z, Sd latched
    U_BRX,     // 2-clock branch to `tgt_q`
    U_NEG,     // NEG r1 (wide: r3) by K
    U_SBC,     // SBC r0 by K, LD count (wide: SBC r2, r1, r0)
    M_LD0,     // LD r0,#0
    M_LD1,     // LD r1,#0
    M_NEGS,    // NEG r3 if negative, K latched
    M_ADCK,    // ADC r2 with K; LD count
    M_LDCNT,   // LD count
    M_ADDL,    // masked ADD/SUB B_L into r1 (MULT: B into r0)
    M_ADDH,    // masked ADC/SBC B_H into r0, X = S^V
    M_DECIDE,  // add routine call decision
    M_RRC01,   // RRC {r0,r1} with X in
    M_RRC23,   // RRC {r2,r3} with C in
    M_ZLD1,    // LD r1,#0 (MULTL: r2), masked by Z
    M_ZLD3,    // LD r3,#0, masked by Z
    M_FLAGS,   // flags
    D_CPL,     // CP r1,|D|: low half < |D|
    D_CP,      // CP r0,|D|: the trial; O latched
    D_RLC,     // RLC {r0,r1} with Q in
    D_SUB,     // SUB r0,|D|; Q latched
    D_ADD,     // ADD r0,|D| unless Q
    D_RLCQ,    // RLC r1 with Q in
    D_NEGQ,    // NEG r1 by K^Sd; Z, S latched
    D_NEGR,    // NEG r0 by K
    R_ADD,     // MULTL add routine
    R_Z,       // MULTL Z routine
    R_C,       // MULTL C routine
    R_PF,      // pair flags
    R_1,       // DIVL frame 0
    R_2,
    R_3,
    R_TRY,     // DIVL frame: trial, restore, shift
    R_RST,
    R_SHF,
    R_FQ,      // DIVL finish: quotient, remainder
    R_FR,
    U_DONE
  } uop_e;

  uop_e        u_q, u_d, tgt_q, tgt_d;
  logic [2:0]  sub_q, sub_d;       // clock within a uop
  logic [5:0]  cnt_q, cnt_d;       // loop count
  logic [15:0] r_q[4], r_d[4];
  logic [31:0] b_q, b_d;
  logic        mul_q, div_q, long_q, have_q, have_d;
  logic        x_q, x_d, c_q, c_d, v_q, v_d, k_q, k_d, z_q, z_d, bz_q, bz_d;
  logic        eq_q, eq_d, fc_q, fc_d;
  logic        q_q, q_d, f_q, f_d, sd_q, sd_d, o_q, o_d, od_q, od_d, w_q, w_d, l_q, l_d;
  logic        qneg_q, qneg_d, qzero_q, qzero_d;
  logic        zin_q, zin_d;       // DIV: the divisor came in as 0
  logic [1:0]  width_q;
  logic        left_q, arith_q, zn_q;
  logic        more_now, more_q;
  logic        ng_on, ng_first, ng_m, ng_c;   // the negate pass
  logic [2:0]  ng_w;               // 0-3 r0..r3, 4 B_L, 5 B_H

  // ---- mode and operand --------------------------------------------------------
  logic        div_cur, long_cur, sh_cur, arrive, hi_take, b_ok;
  logic [31:0] b_now;

  always_comb begin
    div_cur   = start ? div : div_q;
    long_cur  = start ? wide : long_q;
    sh_cur    = start ? !mul && !div : !mul_q && !div_q;
    arrive    = src_valid && (start || (!have_q && u_q != U_DONE && u_q != U_IDLE));
    hi_take   = src_hi && (start || (!have_q && u_q != U_DONE && u_q != U_IDLE));
    b_now     = arrive ? {long_cur ? b_q[31:16] : 16'h0000, src} : b_q;
    b_ok      = have_q;     // in from the clock after the edge that gives it
  end

  // ---- the adder ---------------------------------------------------------------
  logic [15:0] add_a, add_b, add_v;
  logic        add_sub, add_ci, add_c, add_x, fit;
  logic [16:0] add_s;

  logic [15:0] aa, bb;
  logic        ss, cc;

  always_comb begin
    aa    = ng_on ? 16'h0000 : add_a;
    bb    = !ng_on ? add_b : ng_w == 3'd4 ? b_q[15:0] : ng_w == 3'd5 ? b_q[31:16] : r_q[ng_w[1:0]];
    ss    = ng_on || add_sub;
    cc    = ng_on ? ng_first || !c_q : add_ci;
    add_s = {1'b0, aa} + {1'b0, ss ? ~bb : bb} + {16'd0, cc};
    add_v = add_s[15:0];
    add_c = add_s[16] ^ ss;        // borrow on a subtract
    fit   = add_s[16];             // a pass against |D| left no borrow
    // Sign of the 17-bit result: S ^ V.
    add_x = add_v[15] ^ ((aa[15] == (ss ? ~bb[15] : bb[15])) && (add_v[15] != aa[15]));
  end

  // ---- the pair rotate -----------------------------------------------------------
  // A shift's first position rotates the destination as read.
  logic [1:0]  w_cur;
  logic [31:0] wmask, sign, rot_in, rot_out;
  logic        rot_pair, rot_left, rot_fill, rot_sfill, rot_bit, rot_ovf;

  always_comb begin
    rot_pair = 1'b0; rot_left = 1'b0; rot_fill = 1'b0; rot_sfill = 1'b0;
    if (start) begin
      rot_left  = op == OP_SLL || op == OP_SLA;
      rot_sfill = op == OP_SRA;
    end else begin
      unique case (u_q)
        M_RRC01, R_FR: rot_fill = x_q;
        M_RRC23:       begin rot_pair = 1'b1; rot_fill = c_q; end
        D_RLC, D_RLCQ: begin rot_left = 1'b1; rot_fill = q_q; end
        R_SHF:         begin rot_left = 1'b1; rot_pair = sub_q == 3'd2; rot_fill = sub_q == 3'd2 ? q_q : c_q; end
        U_BR:          begin rot_pair = 1'b1; rot_left = left_q; rot_sfill = arith_q; end
        default: ;
      endcase
    end
  end

  always_comb begin
    w_cur = start ? width : width_q;
    if (!sh_cur) wmask = 32'hFFFF_FFFF;
    else unique case (w_cur)
      WIDTH_BYTE: wmask = 32'h0000_00FF;
      WIDTH_WORD: wmask = 32'h0000_FFFF;
      default:    wmask = 32'hFFFF_FFFF;
    endcase
    sign   = wmask & ~(wmask >> 1);
    rot_in = start ? (dst[31:0] & wmask) : rot_pair ? {r_q[2], r_q[3]} : {r_q[0], r_q[1]};
    if (rot_left) begin
      rot_out = {rot_in[30:0], rot_fill} & wmask;
      rot_bit = |(rot_in & sign);
    end else begin
      rot_out = {1'b0, rot_in[31:1]} | (rot_fill || (rot_sfill && |(rot_in & sign)) ? sign : 32'd0);
      rot_bit = rot_in[0];
    end
    rot_ovf = |((rot_out ^ rot_in) & sign);
  end

  // ---- loop terms ----------------------------------------------------------------
  logic bit_now, hi_frames, step_op, step_sub, rq_neg, o_pass, is_rt, hold, exit_q;
  logic [1:0] pf_hi;

  always_comb begin
    bit_now   = long_q ? r_q[3][0] : r_q[1][0];        // the multiplicand bit
    hi_frames = long_q && cnt_q < 6'd16;                // MULTL frames 17-32
    step_op   = bit_now && (!long_q || hi_frames);
    step_sub  = cnt_q == 6'd0 && (long_q ? !v_q : 1'b1);
    rq_neg    = k_q ^ sd_q;                             // quotient sign
    exit_q    = bz_q || o_q;                            // DIV: NEG; SBC as the exit's restore
    pf_hi     = long_q ? 2'd2 : 2'd0;                   // pair flags: the high word
    is_rt     = u_q == R_ADD || u_q == R_Z || u_q == R_C || u_q == R_PF || u_q == R_1 || u_q == R_2 ||
                u_q == R_3 || u_q == R_TRY || u_q == R_RST || u_q == R_SHF || u_q == R_FQ || u_q == R_FR;
  end

  // ---- the negate pass --------------------------------------------------------
  // NEG or SBC (from 0) of a word of r or B, written when its mask is set;
  // a pair's first word latches the borrow for its second. One micro-op for
  // every negate: the pair (or DIVL's quad) at a DIV/DIVL entry and DIV's
  // zero exit, DIVL's divisor, its low-half undo, quotient and remainder,
  // and the single words of MULTL's |s| and DIV's finish.
  always_comb begin
    ng_on = 1'b0; ng_w = 3'd0; ng_first = 1'b1; ng_m = 1'b0; ng_c = 1'b1;
    unique case (u_q)
      U_NEG:  begin ng_on = 1'b1; ng_w = long_q ? 3'd3 : 3'd1; ng_m = k_q; end
      U_SBC:  begin ng_on = 1'b1; ng_w = long_q ? 3'(3'd2 - sub_q) : 3'd0; ng_first = 1'b0; ng_m = k_q; end
      M_NEGS: begin ng_on = 1'b1; ng_w = 3'd3; ng_m = r_q[3][15]; ng_c = 1'b0; end
      D_NEGQ: begin ng_on = 1'b1; ng_w = 3'd1; ng_m = rq_neg; ng_c = 1'b0; end
      D_NEGR: begin ng_on = 1'b1; ng_w = 3'd0; ng_m = k_q; ng_c = 1'b0; end
      R_1:    if (sub_q == 3'd4) begin ng_on = 1'b1; ng_w = 3'd4; ng_m = b_q[31]; end
      R_2: begin
        if (sub_q == 3'd2) begin ng_on = 1'b1; ng_w = 3'd5; ng_first = 1'b0; ng_m = sd_q; end
        if ((sub_q == 3'd3 || sub_q == 3'd4) && bz_q) begin
          ng_on = 1'b1; ng_w = sub_q == 3'd3 ? 3'd3 : 3'd2; ng_first = sub_q == 3'd3; ng_m = k_q;
        end
      end
      R_3:    if ((sub_q == 3'd2 || sub_q == 3'd3) && bz_q) begin
                ng_on = 1'b1; ng_w = sub_q == 3'd2 ? 3'd1 : 3'd0; ng_first = 1'b0; ng_m = k_q;
              end
      R_FQ:   if (sub_q == 3'd2 || sub_q == 3'd3) begin
                ng_on = 1'b1; ng_w = sub_q == 3'd2 ? 3'd3 : 3'd2; ng_first = sub_q == 3'd2; ng_m = rq_neg;
              end
      R_FR:   if (sub_q == 3'd3 || sub_q == 3'd4) begin
                ng_on = 1'b1; ng_w = sub_q == 3'd3 ? 3'd1 : 3'd0; ng_first = sub_q == 3'd3; ng_m = k_q;
              end
      default: ;
    endcase
  end

  // ---- sequencer and datapath ------------------------------------------------------
  always_comb begin
    u_d = u_q; sub_d = sub_q; cnt_d = cnt_q; r_d = r_q; b_d = b_now; tgt_d = tgt_q;
    if (hi_take) b_d[31:16] = src;
    x_d = x_q; c_d = c_q; v_d = v_q; k_d = k_q; z_d = z_q; bz_d = bz_q; eq_d = eq_q; fc_d = fc_q;
    q_d = q_q; f_d = f_q; sd_d = sd_q; o_d = o_q; od_d = od_q; w_d = w_q; l_d = l_q;
    qneg_d = qneg_q; qzero_d = qzero_q;
    have_d = have_q || arrive;
    zin_d  = zin_q || (arrive && div_cur && !long_cur && src == 16'd0);
    add_a = 16'h0000; add_b = 16'h0000; add_sub = 1'b0; add_ci = 1'b0;
    o_pass = 1'b0;
    hold   = 1'b0;

    unique case (u_q)
      // ---- shared ----
      U_DEC: begin cnt_d = cnt_q - 6'd1; od_d = o_q; sub_d = 3'd0; u_d = U_BR; end
      U_BR: begin
        sub_d = 3'd1;
        if (sub_q == 3'd1 || (mul_q && !long_q)) begin
          sub_d = 3'd0;
          if (mul_q)               u_d = (cnt_q == (long_q ? 6'd31 : 6'd15)) ? U_TEST : M_ADDL;
          else if (div_q)          u_d = D_RLC;
          else if (cnt_q == 6'd0)  u_d = U_DONE;
          else begin
            {r_d[2], r_d[3]} = rot_out; c_d = rot_bit;
            if (left_q && rot_ovf) v_d = 1'b1;
            u_d = U_DEC;
          end
        end else if (div_q && cnt_q == 6'd15) begin
          sub_d = 3'd0; u_d = U_TEST;   // DIV frame 1's prologue
        end
      end
      // MULT branches on its own Z; DIV's next pass does.
      U_TEST: if (b_ok) begin
        bz_d = b_q == 32'd0;
        sd_d = b_q[15];
        if (div_q)                 u_d = D_CPL;
        else if (b_q == 32'd0)     begin tgt_d = M_ZLD1; u_d = U_BRX; end
        else                       u_d = long_q ? M_ADDH : M_ADDL;
      end
      U_BRX: begin
        sub_d = sub_q + 3'd1;
        if (sub_q == 3'd1) begin sub_d = 3'd0; u_d = tgt_q; end
      end
      U_NEG: u_d = U_SBC;
      U_SBC: begin
        sub_d = sub_q + 3'd1;
        if (!long_q) begin
          sub_d = 3'd0;
          if (exit_q) u_d = U_DONE;
          else begin cnt_d = 6'd16; u_d = U_DEC; end
        end else if (sub_q == 3'd2) begin
          sub_d = 3'd0; u_d = R_1;
        end
      end

      // ---- multiply ----
      M_LD0:   begin r_d[0] = 16'h0000; u_d = long_q ? M_LD1 : M_LDCNT; end
      M_LDCNT: begin cnt_d = 6'd16; u_d = U_DEC; end
      M_LD1:   begin r_d[1] = 16'h0000; u_d = M_NEGS; end
      M_NEGS: begin k_d = r_q[3][15]; u_d = M_ADCK; end
      M_ADCK: begin
        add_a = r_q[2]; add_ci = k_q;
        r_d[2] = add_v;
        v_d    = !r_q[2][15] && add_v[15];
        cnt_d  = 6'd32;
        u_d    = U_DEC;
      end
      M_ADDL: if (b_ok || !step_op) begin
        add_b = step_op ? b_q[15:0] : 16'h0000;
        add_sub = step_op && step_sub; add_ci = add_sub;
        if (long_q) begin
          add_a = r_q[1]; r_d[1] = add_v; c_d = add_c; u_d = M_ADDH;
        end else begin
          add_a = r_q[0]; r_d[0] = add_v; x_d = add_x; u_d = M_RRC01;
        end
      end
      M_ADDH: if (b_ok || !step_op) begin
        add_a = r_q[0]; add_b = step_op ? b_q[31:16] : 16'h0000;
        add_sub = step_op && step_sub; add_ci = add_sub ? !c_q : c_q;
        r_d[0] = add_v; x_d = add_x;
        u_d = M_DECIDE;
      end
      M_DECIDE: begin sub_d = 3'd0; u_d = (!hi_frames && bit_now) ? R_ADD : M_RRC01; end
      M_RRC01: begin
        {r_d[0], r_d[1]} = rot_out; c_d = rot_bit;
        if (long_q)             u_d = M_RRC23;
        else if (cnt_q == 6'd0) u_d = U_DONE;
        else                    u_d = U_DEC;
      end
      M_RRC23: begin
        {r_d[2], r_d[3]} = rot_out;
        sub_d = 3'd0;
        if (cnt_q == 6'd0) begin tgt_d = M_ZLD1; u_d = U_BRX; end
        else                     u_d = U_DEC;
      end
      M_ZLD1: begin
        if (bz_q) r_d[long_q ? 2'd2 : 2'd1] = 16'h0000;
        u_d   = long_q ? M_ZLD3 : R_PF;
        sub_d = 3'd0;
      end
      M_ZLD3: begin if (bz_q) r_d[3] = 16'h0000; sub_d = 3'd0; u_d = R_Z; end
      M_FLAGS: begin sub_d = 3'd0; u_d = U_DONE; end

      // ---- divide ----
      D_CPL: begin
        add_a = r_q[1]; add_b = b_q[15:0]; add_sub = !sd_q; add_ci = !sd_q;
        l_d = !fit;
        if (bz_q) begin tgt_d = U_NEG; u_d = U_BRX; end
        else            u_d = D_CP;
      end
      // |X| >= |D| x 2^16 is a fit here; a negative quotient also needs
      // |X| >= |D| x 2^16 + |D|, which fails only for remainder 0 and the
      // low half < |D|: -2^16, in range, its bit N dropped.
      D_CP: begin
        add_a = r_q[0]; add_b = b_q[15:0]; add_sub = !sd_q; add_ci = !sd_q;
        o_pass = fit && !(add_v == 16'h0000 && rq_neg && l_q);
        o_d = o_pass;
        w_d = fit && !o_pass;
        if (w_d) r_d[0] = add_v;
        sub_d = 3'd1;
        u_d   = U_BR;
      end
      D_RLC: begin
        {r_d[0], r_d[1]} = rot_out; x_d = rot_bit;
        u_d = D_SUB;
      end
      D_SUB: begin
        add_a = r_q[0]; add_b = b_q[15:0]; add_sub = !sd_q; add_ci = !sd_q;
        r_d[0] = add_v;
        q_d = x_q || fit;
        x_d = 1'b0;
        u_d = D_ADD;
      end
      D_ADD: begin
        add_a = r_q[0]; add_b = q_q ? 16'h0000 : b_q[15:0];
        add_sub = !q_q && sd_q; add_ci = add_sub;
        r_d[0] = add_v;
        u_d = (cnt_q == 6'd0 || od_q) ? D_RLCQ : U_DEC;
      end
      D_RLCQ: begin
        r_d[1] = rot_out[15:0];
        if (o_q) begin tgt_d = U_NEG; u_d = U_BRX; end
        else           u_d = D_NEGQ;
      end
      // A nonzero quotient stored with the wrong sign is one bit too wide.
      D_NEGQ: begin
        qzero_d = (r_q[1] == 16'h0000) && !w_q;
        qneg_d  = rq_neg && !qzero_d;
        w_d     = w_q || ((rq_neg ? add_v[15] : r_q[1][15]) != rq_neg && r_q[1] != 16'h0000);
        u_d     = D_NEGR;
      end
      D_NEGR: u_d = U_DONE;

      // ---- routines ----
      R_ADD, R_Z, R_C, R_PF, R_1, R_2, R_3, R_TRY, R_RST, R_SHF, R_FQ, R_FR: begin
        unique case (u_q)
          R_ADD: begin
            if (!b_ok && (sub_q == 3'd2 || sub_q == 3'd3)) hold = 1'b1;
            else if (sub_q == 3'd2) begin
              add_a = r_q[1]; add_b = b_q[15:0]; add_sub = k_q; add_ci = k_q;
              r_d[1] = add_v; c_d = add_c;
            end else if (sub_q == 3'd3) begin
              add_a = r_q[0]; add_b = b_q[31:16]; add_sub = k_q; add_ci = k_q ? !c_q : c_q;
              r_d[0] = add_v; c_d = add_x;
            end else if (sub_q == 3'd4) begin
              x_d = c_q;
            end
          end
          R_Z: begin
            if (sub_q == 3'd2) z_d = (r_q[3] | r_q[2]) == 16'h0000;
            if (sub_q == 3'd3) z_d = z_q && r_q[1] == 16'h0000;
            if (sub_q == 3'd4) z_d = z_q && r_q[0] == 16'h0000;
          end
          R_C: begin
            if (sub_q == 3'd2 || sub_q == 3'd3) begin
              add_a = sub_q == 3'd2 ? r_q[1] : r_q[0]; add_b = {16{r_q[2][15]}};
              add_sub = 1'b1; add_ci = sub_q == 3'd2 || !c_q;
              c_d  = add_c;
              eq_d = (sub_q == 3'd2 || eq_q) && add_v == 16'h0000;
            end
            if (sub_q == 3'd4) fc_d = !eq_q;
          end
          // CP hi against lo's sign; OR hi|lo; MULT: C, DIVL: Z, S, the width.
          R_PF: begin
            if (sub_q == 3'd2) begin
              add_a = r_q[pf_hi]; add_b = {16{r_q[pf_hi + 2'd1][15]}}; add_sub = 1'b1; add_ci = 1'b1;
              c_d  = add_c;
              eq_d = add_v == 16'h0000;
            end
            if (sub_q == 3'd3) z_d = (r_q[pf_hi] | r_q[pf_hi + 2'd1]) == 16'h0000;
            if (sub_q == 3'd4) begin
              if (mul_q) fc_d = !eq_q;
              else begin
                qzero_d = z_q && !w_q;
                qneg_d  = rq_neg && !qzero_d;
                w_d     = w_q || (qneg_q != rq_neg && !z_q);
              end
            end
          end
          R_1: begin
            if (sub_q == 3'd2) begin cnt_d = 6'd33; q_d = 1'b0; end
            if (sub_q == 3'd3) begin
              // OR B_L,B_H: the first divisor pass.
              if (b_ok) bz_d = b_q == 32'd0;
              else      hold = 1'b1;
            end
            if (sub_q == 3'd4) sd_d = b_q[31];
          end
          // Z: un-negate the low half; else compare it with |D|.
          R_2: begin
            if ((sub_q == 3'd3 || sub_q == 3'd4) && !bz_q) begin
              add_a = r_q[sub_q == 3'd3 ? 2'd3 : 2'd2]; add_b = sub_q == 3'd3 ? b_q[15:0] : b_q[31:16];
              add_sub = 1'b1; add_ci = sub_q == 3'd3 || !c_q;
              c_d = add_c;
            end
          end
          R_3: begin
            if (sub_q == 3'd4) l_d = c_q;
          end
          R_TRY: begin
            if (sub_q == 3'd2 || sub_q == 3'd3) begin
              add_a = r_q[sub_q == 3'd2 ? 2'd1 : 2'd0]; add_b = sub_q == 3'd2 ? b_q[15:0] : b_q[31:16];
              add_sub = 1'b1; add_ci = sub_q == 3'd2 || !c_q;
              r_d[sub_q == 3'd2 ? 2'd1 : 2'd0] = add_v;
              c_d = add_c;
              z_d = (sub_q == 3'd2 || z_q) && add_v == 16'h0000;
            end
            if (sub_q == 3'd4) begin
              f_d = x_q || !c_q; x_d = 1'b0;
              // Frame 1: as DIV's trial.
              if (cnt_q == 6'd33) begin
                o_pass = !c_q && !(z_q && rq_neg && l_q);
                o_d    = o_pass;
              end
            end
          end
          R_RST: begin
            if (sub_q == 3'd2 || sub_q == 3'd3) begin
              add_a = r_q[sub_q == 3'd2 ? 2'd1 : 2'd0];
              add_b = f_q ? 16'h0000 : (sub_q == 3'd2 ? b_q[15:0] : b_q[31:16]);
              add_ci = sub_q != 3'd2 && c_q;
              r_d[sub_q == 3'd2 ? 2'd1 : 2'd0] = add_v;
              c_d = add_c;
            end
            if (sub_q == 3'd4) q_d = f_q;
          end
          R_SHF: begin
            if (sub_q == 3'd2) begin {r_d[2], r_d[3]} = rot_out; c_d = rot_bit; end
            if (sub_q == 3'd3) begin {r_d[0], r_d[1]} = rot_out; x_d = rot_bit; end
            if (sub_q == 3'd4) begin cnt_d = cnt_q - 6'd1; od_d = o_q; end
          end
          R_FQ: begin
            if (sub_q == 3'd4) qneg_d = r_q[2][15];
          end
          // The bit dropped from r1 is the quotient's bit N.
          R_FR: begin
            if (sub_q == 3'd2) begin {r_d[0], r_d[1]} = rot_out; x_d = 1'b0; w_d = rot_bit; end
          end
          default: ;
        endcase
        sub_d = hold ? sub_q : sub_q + 3'd1;
        if (sub_q == 3'd6) begin
          sub_d = 3'd0;
          unique case (u_q)
            R_ADD: u_d = M_RRC01;
            R_Z:   u_d = R_C;
            R_C:   u_d = M_FLAGS;
            R_PF:  if (mul_q) u_d = U_DONE; else begin tgt_d = U_DONE; u_d = U_BRX; end
            R_1:   u_d = R_2;
            R_2:   u_d = R_3;
            R_3:   if (bz_q) begin tgt_d = U_DONE; u_d = U_BRX; end else u_d = R_TRY;
            R_TRY: u_d = R_RST;
            R_RST: u_d = R_SHF;
            R_SHF: if (od_q) begin tgt_d = U_DONE; u_d = U_BRX; end
                   else u_d = (cnt_q == 6'd0) ? R_FQ : R_TRY;
            R_FQ:  u_d = R_FR;
            default: u_d = R_PF;   // R_FR
          endcase
        end
      end
      default: ;
    endcase

    // The negate pass's write.
    if (ng_on) begin
      if (ng_c) c_d = add_c;
      if (ng_m) begin
        if (ng_w == 3'd4)      b_d[15:0]  = add_v;
        else if (ng_w == 3'd5) b_d[31:16] = add_v;
        else                   r_d[ng_w[1:0]] = add_v;
      end
    end

    if (start) begin
      r_d[0] = wide ? dst[63:48] : dst[31:16];
      r_d[1] = wide ? dst[47:32] : dst[15:0];
      r_d[2] = dst[31:16];
      r_d[3] = dst[15:0];
      k_d    = wide ? dst[63] : dst[31];   // the dividend's sign
      u_d    = mul ? M_LD0 : div ? U_NEG : U_DEC;
      sub_d  = 3'd0;
      cnt_d  = 6'd0;
      x_d = 1'b0; c_d = 1'b0; v_d = 1'b0; bz_d = 1'b0;
      q_d = 1'b0; f_d = 1'b0; sd_d = 1'b0; o_d = 1'b0; od_d = 1'b0; w_d = 1'b0; l_d = 1'b0;
      qneg_d = 1'b0; qzero_d = 1'b0;
      have_d = arrive;
      zin_d  = arrive && div && !wide && src == 16'd0;
      if (sh_cur) begin
        // The first position shifts on the start edge; a zero count none.
        cnt_d = (count == 6'd0) ? 6'd1 : count;
        {r_d[2], r_d[3]} = dst[31:0] & wmask;
        if (count != 6'd0) begin
          {r_d[2], r_d[3]} = rot_out; c_d = rot_bit;
          v_d = rot_left && rot_ovf;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      u_q <= U_IDLE; tgt_q <= U_IDLE; sub_q <= 3'd0; cnt_q <= 6'd0;
      r_q[0] <= 16'h0; r_q[1] <= 16'h0; r_q[2] <= 16'h0; r_q[3] <= 16'h0;
      b_q <= 32'd0; have_q <= 1'b0; mul_q <= 1'b0; div_q <= 1'b0; long_q <= 1'b0;
      x_q <= 1'b0; c_q <= 1'b0; v_q <= 1'b0; k_q <= 1'b0; z_q <= 1'b0; bz_q <= 1'b0;
      eq_q <= 1'b0; fc_q <= 1'b0;
      q_q <= 1'b0; f_q <= 1'b0; sd_q <= 1'b0; o_q <= 1'b0; od_q <= 1'b0; w_q <= 1'b0; l_q <= 1'b0;
      qneg_q <= 1'b0; qzero_q <= 1'b0; zin_q <= 1'b0;
      width_q <= WIDTH_NONE; left_q <= 1'b0; arith_q <= 1'b0; zn_q <= 1'b0;
    end else if (clk_en) if (tick || start) begin
      u_q <= u_d; tgt_q <= tgt_d; sub_q <= sub_d; cnt_q <= cnt_d; r_q <= r_d;
      b_q <= b_d; have_q <= have_d;
      x_q <= x_d; c_q <= c_d; v_q <= v_d; k_q <= k_d; z_q <= z_d; bz_q <= bz_d;
      eq_q <= eq_d; fc_q <= fc_d;
      q_q <= q_d; f_q <= f_d; sd_q <= sd_d; o_q <= o_d; od_q <= od_d; w_q <= w_d; l_q <= l_d;
      qneg_q <= qneg_d; qzero_q <= qzero_d; zin_q <= zin_d;
      if (start) begin
        mul_q <= mul; div_q <= div; long_q <= wide;
        width_q <= width;
        left_q  <= op == OP_SLL || op == OP_SLA;
        arith_q <= op == OP_SLA || op == OP_SRA;
        zn_q    <= count == 6'd0;
      end
    end
  end

  // ---- outputs ------------------------------------------------------------------
  // The last clock's pass touches one word, DIV's negate of r0, or MULT's
  // rotate of {r0,r1}; the other words are as they stand.
  logic        fin_add, fin_rot;
  logic [31:0] sh_sign, sh_val;

  always_comb begin
    done    = (u_q == U_DONE);
    fin     = (u_q != U_DONE && u_q != U_IDLE && u_d == U_DONE && !start);
    fin_add = (u_q == D_NEGR || u_q == U_SBC) && k_q && !long_q;
    fin_rot = (u_q == M_RRC01);
    words[63:48] = fin_add ? add_v : fin_rot ? {x_q, r_q[0][15:1]} : r_q[0];
    words[47:32] = fin_rot ? {r_q[0][0], r_q[1][15:1]} : r_q[1];
    words[31:0]  = {r_q[2], r_q[3]};
    flag_c      = fc_q;
    flag_z      = z_q;
    div_by_zero = bz_q;
    overflow    = o_q;
    wide_quot   = w_q;
    quot_neg    = qneg_q;
    quot_zero   = qzero_q;

    unique case (width_q)
      WIDTH_BYTE: sh_sign = 32'h0000_0080;
      WIDTH_WORD: sh_sign = 32'h0000_8000;
      default:    sh_sign = 32'h8000_0000;
    endcase
    sh_val   = {r_q[2], r_q[3]};
    sh_flags = 16'h0000;
    if (sh_val == 32'd0)          sh_flags = sh_flags | F_Z;
    if (|(sh_val & sh_sign))      sh_flags = sh_flags | F_S;
    if (c_q)                      sh_flags = sh_flags | F_C;
    if (arith_q && left_q && v_q) sh_flags = sh_flags | F_V;
    sh_mask = F_Z | F_S;
    if (!zn_q)   sh_mask = sh_mask | F_C;
    if (arith_q) sh_mask = sh_mask | F_V;

    // In MULTL's frame loop, short of frame 32's body (its DEC leaves the count 0).
    more_now = mul_q && long_q && cnt_q != 6'd0 &&
               (u_q == U_DEC || u_q == U_BR || u_q == U_TEST || u_q == M_ADDL || u_q == M_ADDH ||
                u_q == M_DECIDE || u_q == R_ADD || u_q == M_RRC01 || u_q == M_RRC23);
    more     = tick ? more_now : more_q;
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)  more_q <= 1'b0;
    else if (clk_en) if (tick) more_q <= more_now;
  end

  // ---- cycle ends ---------------------------------------------------------------
  // MULT: RRC {r0,r1}; the zero path's from TEST and the pair flags.
  // MULTL: the add routine's second call clock and RRC {r2,r3}; the
  // finish's from the C routine, the zero path's last from its first pass.
  // DIV: the second loop branch clock (frame 1's one ahead, from the
  // trial); past the width frame 1's SUB and RLCQ; the program on NEGR or
  // the exit's SBC. The zero exit's last from the divisor latch's zero.
  // DIVL: each routine call's second clock; the program on the exit's.
  // Shift: each position's second branch clock.
  logic e3, e2, el, mine;

  always_comb begin
    e3 = 1'b0; e2 = 1'b0; el = 1'b0;
    if (mul_q && !long_q) begin
      e3 = (u_q == U_BR && cnt_q != 6'd15) || (u_q == U_TEST && b_ok) || (u_q == R_PF && sub_q == 3'd4);
      el = (u_q == U_DEC && cnt_q == 6'd1) || (cnt_q == 6'd0 && (u_q == U_BR || u_q == M_ADDL || u_q == M_RRC01)) ||
           (u_q == R_PF && sub_q >= 3'd3);
    end else if (mul_q) begin
      e3 = u_q == M_DECIDE || (u_q == R_ADD && sub_q == 3'd6) || (u_q == R_C && sub_q == 3'd5);
      el = u_q == M_FLAGS || (u_q == R_C && (sub_q >= 3'd5 || (sub_q >= 3'd1 && bz_q)));
    end else if (div_q && !long_q) begin
      e3 = (u_q == U_DEC && cnt_q != 6'd16 && !o_q) ||
           (u_q == U_BR && sub_q == 3'd1 && o_q && cnt_q == 6'd15) ||
           (u_q == D_SUB && o_q && cnt_q == 6'd14) ||
           (u_q == D_RLCQ && !o_q) || (u_q == U_BRX && sub_q == 3'd1);
      el = zin_q || u_q == U_BRX || ((u_q == U_NEG || u_q == U_SBC) && exit_q) ||
           u_q == D_NEGQ || u_q == D_NEGR || (u_q == D_RLCQ && !o_q) ||
           (cnt_q == 6'd0 && (u_q == D_RLC || u_q == D_SUB || u_q == D_ADD));
      e2 = u_q == D_CP && !o_pass;
    end else if (div_q) begin
      e3 = (u_q == U_SBC && sub_q == 3'd2) || (is_rt && sub_q == 3'd6);
      el = (sub_q >= 3'd2 && ((u_q == R_3 && bz_q) || (u_q == R_SHF && o_q) || u_q == R_PF)) || u_q == U_BRX;
    end else begin
      e3 = u_q == U_DEC;
      el = (u_q == U_DEC && cnt_q == 6'd1) || (u_q == U_BR && cnt_q == 6'd0);
    end
    mine = mul == mul_q && div == div_q;
    end3 = e3 && mine;
    end2 = e2 && mine;
    last = el && mine;
  end

endmodule
