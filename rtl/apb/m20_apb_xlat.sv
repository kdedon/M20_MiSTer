// APB 1086 address translator (PL40): 8086 A19-A14 -> M20 bus SN3-SN0, A15,
// A14 for a program-reference (I-space) cycle, local ROM, or no cycle.
//
//   8086 page  A19-16 A15-14   bus
//   00000      0      q        SN 0, q
//   10000      1      q        SN 2, q
//   20000      2      q        SN 8 + A15, {1, A14}
//   30000      3..7   q        SN n + 8, q      (7C000-7FFFF: none)
//   80000      8..D   -        none
//   E0000      E      q        SN 3, q          (video planes)
//   F0000      F      0 / 1    SN 0 / SN 3, A15 = A14 = 0
//   F8000      F      2        none
//   FC000      F      3        local ROM
`default_nettype none
module m20_apb_xlat (
  input  logic [19:14] a,
  output logic [3:0]   sn,
  output logic         a15,
  output logic         a14,
  output logic         bus,     // run an M20 bus cycle
  output logic         rom      // local ROM
);
  logic [3:0] n;
  logic [1:0] q;
  assign n = a[19:16];
  assign q = a[15:14];

  always_comb begin
    sn  = 4'd0;
    {a15, a14} = q;
    bus = 1'b1;
    rom = 1'b0;
    case (n)
      4'h0: sn = 4'd0;
      4'h1: sn = 4'd2;
      4'h2: begin
        sn  = {3'b100, q[1]};
        a15 = 1'b1;
      end
      4'h3, 4'h4, 4'h5, 4'h6: sn = n + 4'd8;
      4'h7: begin
        sn  = 4'hF;
        bus = q != 2'd3;
      end
      4'hE: sn = 4'd3;
      4'hF: begin
        sn  = q[0] ? 4'd3 : 4'd0;
        {a15, a14} = 2'b00;
        bus = !q[1];
        rom = q == 2'd3;
      end
      default: bus = 1'b0;
    endcase
  end
endmodule
`default_nettype wire
