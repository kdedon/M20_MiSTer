// z8000_cond -- condition code: whether the FCW flags meet a 4-bit code.
//
//   0 F    1 LT   2 LE   3 ULE  4 OV/PE  5 MI  6 Z/EQ   7 C/ULT
//   8 T    9 GE   A GT   B UGT  C NOV/PO D PL  E NZ/NE  F NC/UGE
//
// Codes 8-F are the complements of 0-7.

module z8000_cond (
  input  logic [3:0] cc,
  input  logic       c,
  input  logic       z,
  input  logic       s,
  input  logic       v,     // P/V
  output logic       met
);

  logic f;

  always_comb begin
    unique case (cc[2:0])
      3'd0:    f = 1'b0;
      3'd1:    f = s ^ v;
      3'd2:    f = z | (s ^ v);
      3'd3:    f = c | z;
      3'd4:    f = v;
      3'd5:    f = s;
      3'd6:    f = z;
      default: f = c;
    endcase
  end

  assign met = f ^ cc[3];

endmodule
