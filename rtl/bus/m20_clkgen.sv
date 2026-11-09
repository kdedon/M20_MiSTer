// M20 clock enables (U12, U29, U28).
//
// U12 16 MHz oscillator: ce16 = clk / 3.  From it:
//   ce_pit   16 MHz / 13 = 1.230769 MHz   (i8253 CLK, all channels)
//   ce_usart 16 MHz / 8  = 2 MHz          (i8251A CLK)
//   ce_fdc   16 MHz / 16 = 1 MHz          (FD1797 CLK)
// U29 74LS163 counts ce16; its Q1 is SCLOCK, the 4 MHz Z8001 CLK.  CEP/CET
// (U28) stop the count while `hold` is High, which stretches the CPU clock
// in 62.5 ns steps.  cpu_clk_rise / cpu_clk_fall are one-clock pulses at
// the SCLOCK edges; q is the counter (Q1 Q0) for the caller's hold terms.
// The other enables free-run from the oscillator.
`default_nettype none
module m20_clkgen (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       hold,          // freeze U29 at the next ce16
  output logic       ce16,
  output logic       ce_pit,
  output logic       ce_usart,
  output logic       ce_fdc,
  output logic       cpu_clk_rise,
  output logic       cpu_clk_fall,
  output logic [1:0] q              // U29 Q1 Q0
);
  localparam logic [1:0] DIV3_LAST  = 2'd2;
  localparam logic [3:0] PIT_LAST   = 4'd12;

  // Phase of clk / 3.
  logic [1:0] div3_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                  div3_q <= 2'd0;
    else if (div3_q == DIV3_LAST) div3_q <= 2'd0;
    else                         div3_q <= div3_q + 2'd1;
  end
  assign ce16 = (div3_q == DIV3_LAST);

  // Ce16 / 13 phase.
  logic [3:0] div13_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                       div13_q <= 4'd0;
    else if (ce16 && div13_q == PIT_LAST) div13_q <= 4'd0;
    else if (ce16)                    div13_q <= div13_q + 4'd1;
  end
  assign ce_pit = ce16 && (div13_q == PIT_LAST);

  // Ce16 / 16 phase; bit 2:0 also gives / 8.
  logic [3:0] div16_q;
  always_ff @(posedge clk) begin
    if (!rst_n)    div16_q <= 4'd0;
    else if (ce16) div16_q <= div16_q + 4'd1;
  end
  assign ce_usart = ce16 && (div16_q[2:0] == 3'd7);
  assign ce_fdc   = ce16 && (div16_q == 4'd15);

  // U29 Q1 Q0.
  logic [1:0] u29_q;
  logic       u29_en;
  assign u29_en = ce16 && !hold;
  always_ff @(posedge clk) begin
    if (!rst_n)      u29_q <= 2'd0;
    else if (u29_en) u29_q <= u29_q + 2'd1;
  end
  assign cpu_clk_rise = u29_en && (u29_q == 2'b01);
  assign cpu_clk_fall = u29_en && (u29_q == 2'b11);
  assign q            = u29_q;
endmodule
`default_nettype wire
