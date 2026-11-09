// z8000_alu -- combinational 16-bit ALU.
//
// Implements what the CPU issues to it: ADD/ADC/SUB/SBC/CP, AND/OR/XOR/COM/
// NEG/TEST, INC/DEC by 1-16, RL/RR/RLC/RRC by 1 or 2 (b[1] selects 2),
// BIT/SET/RES on bit b[3:0], TSET, LD and DAB, at byte or word width.
// Multi-bit shifts and sign extension run in their own units. Operands
// arrive already masked to the operation width (byte ops get the byte).
//
// A long ADD/SUB/CP/TEST/LD is two word passes, low word first:
//   low  pass: the op itself (CP runs as SUB), cin = C flag
//   high pass: ADD/ADC -> ADC, SUB/SBC/CP -> SBC, TEST/LD unchanged,
//              cin = C from the low pass
//   result {high, low}; Z = Z_low & Z_high; every other flag and the mask
//   come from the high pass. TEST and LD passes are independent of order.
//
// One adder serves the arithmetic: subtraction is a + ~b + 1 (or + ~C for
// SBC), so C is the inverted carry-out. Carry into bit k is
// a[k] ^ b[k] ^ sum[k] (H uses k = 4); V = ~(a[msb] ^ b[msb]) & (a[msb] ^ sum[msb]).
//
// Flag bit positions == FCW: C=bit7 Z=6 S=5 P/V=4 D=3 H=2. flags_mask is the
// set of flags the op writes; flags outside it are don't-care. Width is
// byte when WIDTH_BYTE, word otherwise.

module z8000_alu
  import z8000_ctrl_pkg::*;
(
  input  logic [ALUOP_W-1:0] op,
  input  logic [1:0]         width,   // WIDTH_BYTE / WIDTH_WORD
  input  logic [15:0]        a,       // destination / first operand
  input  logic [15:0]        b,       // source / second operand (count, bit number, ...)
  input  logic               cin,     // incoming C flag (ADC/SBC/RLC/RRC/DAB, long high pass)
  output logic [15:0]        value,
  output logic [15:0]        flags,
  output logic [15:0]        flags_mask
);

  localparam logic [15:0] F_C = 16'h0080;
  localparam logic [15:0] F_Z = 16'h0040;
  localparam logic [15:0] F_S = 16'h0020;
  localparam logic [15:0] F_V = 16'h0010;
  localparam logic [15:0] F_D = 16'h0008;
  localparam logic [15:0] F_H = 16'h0004;

  logic        is_byte;
  logic [15:0] wmask, sign, x;

  assign is_byte = (width == WIDTH_BYTE);
  assign wmask   = is_byte ? 16'h00FF : 16'hFFFF;
  assign sign    = is_byte ? 16'h0080 : 16'h8000;
  assign x       = a & wmask;

  // m selects the sign bit.
  function automatic logic msb(input logic [15:0] v, input logic [15:0] m);
    return |(v & m);
  endfunction

  // Z and S of a masked result; P is the parity of its low byte.
  function automatic logic [15:0] zsp(input logic [15:0] v, input logic [15:0] m);
    return ((v == 16'h0000) ? F_Z : 16'h0000) | (msb(v, m) ? F_S : 16'h0000)
         | ((~^v[7:0]) ? F_V : 16'h0000);
  endfunction

  // ---- adder ----------------------------------------------------------------
  logic        sub_op, add_cin, cout, half, ovf;
  logic [15:0] add_a, add_b, sum_v;
  logic [16:0] sum;

  always_comb begin
    sub_op = (op == OP_SUB) || (op == OP_SBC) || (op == OP_CP) || (op == OP_DEC) || (op == OP_NEG);
    add_a  = (op == OP_NEG) ? 16'h0000 : x;
    add_b  = ((op == OP_NEG) ? ~a : sub_op ? ~b : b) & wmask;
    unique case (op)
      OP_ADC:  add_cin = cin;
      OP_SBC:  add_cin = ~cin;
      default: add_cin = sub_op;
    endcase
    sum   = {1'b0, add_a} + {1'b0, add_b} + {16'h0000, add_cin};
    sum_v = sum[15:0] & wmask;
    cout  = is_byte ? sum[8] : sum[16];
    half  = add_a[4] ^ add_b[4] ^ sum[4];
    ovf   = ~(msb(add_a, sign) ^ msb(add_b, sign)) & (msb(add_a, sign) ^ msb(sum_v, sign));
  end

  // ---- rotates by 1 or 2 ----------------------------------------------------
  // RLC/RRC rotate through C; each step returns {carry out, value}.
  function automatic logic [16:0] rot1(input logic [15:0] v, input logic c,
                                       input logic byt, input logic lft, input logic thr);
    logic co, in_bit;
    logic [15:0] o;
    if (lft) begin
      co     = byt ? v[7] : v[15];
      in_bit = thr ? c : co;
      o      = byt ? {8'h00, v[6:0], in_bit} : {v[14:0], in_bit};
    end else begin
      co     = v[0];
      in_bit = thr ? c : co;
      o      = byt ? {8'h00, in_bit, v[7:1]} : {in_bit, v[15:1]};
    end
    return {co, o};
  endfunction

  logic        left, thru, rc1, rc2, rc;
  logic [15:0] r1, r2, rv;

  always_comb begin
    left      = (op == OP_RL) || (op == OP_RLC);
    thru      = (op == OP_RLC) || (op == OP_RRC);
    {rc1, r1} = rot1(x, cin, is_byte, left, thru);
    {rc2, r2} = rot1(r1, rc1, is_byte, left, thru);
    rv        = b[1] ? r2 : r1;
    rc        = b[1] ? rc2 : rc1;
  end

  // ---- DAB ------------------------------------------------------------------
  // b[0] = H and b[1] = D from the preceding op; table per Ref Manual p.85.
  logic [7:0] dab_v;
  logic       dab_c, add06, add60;

  always_comb begin
    add06 = (a[3:0] > 4'd9) || b[0];
    add60 = cin || (a[7:4] > 4'd9) || (a[7:4] == 4'd9 && a[3:0] > 4'd9);
    if (b[1]) begin
      unique case ({cin, b[0]})
        2'b00:   dab_v = a[7:0];
        2'b01:   dab_v = a[7:0] + 8'hFA;
        2'b10:   dab_v = a[7:0] + 8'hA0;
        default: dab_v = a[7:0] + 8'h9A;
      endcase
      dab_c = cin;
    end else begin
      dab_v = a[7:0] + (add06 ? 8'h06 : 8'h00) + (add60 ? 8'h60 : 8'h00);
      dab_c = add60;
    end
  end

  // ---- bit ops --------------------------------------------------------------
  logic [15:0] bitm;
  assign bitm = 16'h0001 << b[3:0];

  // ---- result select --------------------------------------------------------
  logic [15:0] lv, arith_f;

  always_comb begin
    value      = 16'h0000;
    flags      = 16'h0000;
    flags_mask = 16'h0000;
    lv         = 16'h0000;
    arith_f    = (zsp(sum_v, sign) & ~F_V) | (ovf ? F_V : 16'h0000)
               | ((cout ^ sub_op) ? F_C : 16'h0000) | ((half ^ sub_op) ? F_H : 16'h0000)
               | (sub_op ? F_D : 16'h0000);

    unique case (op)
      OP_ADD, OP_ADC, OP_SUB, OP_SBC: begin
        value      = sum_v;
        flags      = arith_f;
        flags_mask = F_C | F_Z | F_S | F_V | (is_byte ? (F_D | F_H) : 16'h0000);
      end
      OP_CP: begin
        value      = sum_v;
        flags      = arith_f & ~(F_D | F_H);
        flags_mask = F_C | F_Z | F_S | F_V;
      end
      OP_NEG: begin
        value      = sum_v;
        flags      = arith_f;
        flags_mask = F_C | F_Z | F_S | F_V;
      end
      OP_INC, OP_DEC: begin
        value      = sum_v;
        flags      = arith_f;
        flags_mask = F_Z | F_S | F_V;
      end
      OP_AND, OP_OR, OP_XOR, OP_COM, OP_TEST: begin
        unique case (op)
          OP_AND:  lv = x & b;
          OP_OR:   lv = x | (b & wmask);
          OP_XOR:  lv = x ^ (b & wmask);
          OP_COM:  lv = ~x & wmask;
          default: lv = x;
        endcase
        value      = lv;
        flags      = zsp(lv, sign);
        flags_mask = F_Z | F_S | (is_byte ? F_V : 16'h0000);
      end
      OP_RL, OP_RR, OP_RLC, OP_RRC: begin
        value      = rv;
        flags      = (rc ? F_C : 16'h0000) | (zsp(rv, sign) & ~F_V)
                   | (msb(rv ^ x, sign) ? F_V : 16'h0000);
        flags_mask = F_C | F_Z | F_S | F_V;
      end
      OP_DAB: begin
        value      = {8'h00, dab_v};
        flags      = (zsp({8'h00, dab_v}, 16'h0080) & ~F_V) | (dab_c ? F_C : 16'h0000);
        flags_mask = F_C | F_Z | F_S;
      end
      OP_LD:   value = b;
      OP_BIT: begin
        value      = a;
        flags      = ((a & bitm) == 16'h0000) ? F_Z : 16'h0000;
        flags_mask = F_Z;
      end
      OP_SET:  value = a | bitm;
      OP_RES:  value = a & ~bitm;
      OP_TSET: begin
        value      = wmask;
        flags      = msb(a, sign) ? F_S : 16'h0000;
        flags_mask = F_S;
      end
      default: ;
    endcase
  end

endmodule
