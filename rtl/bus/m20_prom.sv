// U44 mapping PROM, N82S181 1K x 8.
// Address pins as on the board: A0 A14, A1 A15, A2-A4 SN0-SN2, A5 ST2,
// A6 SN3, A7 32^128, A8 BW^COL, A9 COL4^8.  Data: O7 *ROM, O6 *SRAM,
// O5 *DRAM, O4-O2 TSN2-TSN0, O1 TA15, O0 TA14.  The read is registered (one clock after
// the inputs); the caller applies the enables (*CE2 = ST1, CE3 = ST3).
`default_nettype none
module m20_prom #(
  parameter INIT_FILE = "rtl/bus/m20_prom.hex"
) (
  input  logic       clk,
  input  logic       a14,
  input  logic       a15,
  input  logic [3:0] sn,        // SN3-SN0
  input  logic       st2,       // 1 = instruction space
  input  logic       j_32_128,  // port 0x21 D6
  input  logic       j_bw,      // port 0x21 D7
  input  logic       j_col48,   // port 0x21 D5
  output logic [7:0] q
);
  logic [9:0] addr;
  assign addr = {j_col48, j_bw, j_32_128, sn[3], st2, sn[2:0], a15, a14};

  (* ramstyle = "M10K" *) logic [7:0] rom [0:1023];
  initial $readmemh(INIT_FILE, rom);

  always_ff @(posedge clk) q <= rom[addr];
endmodule
`default_nettype wire
