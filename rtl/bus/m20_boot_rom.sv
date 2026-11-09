// ROM0: the two 2732 boot EPROMs U54 (H, D15-D8) and U65 (L, D7-D0).
// CPU A1-A12 address both; A13 is ignored, so the 4K-word image appears
// twice in a 16 KB block.
// Loaded from boot.rom (ioctl index 0): byte 2k is the H EPROM byte k (word k
// bits 15:8), byte 2k+1 the L EPROM byte k.  Read is registered.
`default_nettype none
module m20_boot_rom (
  input  logic        clk,
  input  logic [12:1] addr,       // CPU word address A12-A1
  output logic [15:0] q,
  input  logic        ld_we,
  input  logic [12:0] ld_addr,
  input  logic [7:0]  ld_data
);
  (* ramstyle = "M10K" *) logic [7:0] rom_h [0:4095];
  (* ramstyle = "M10K" *) logic [7:0] rom_l [0:4095];
  logic [7:0] q_h, q_l;

  always_ff @(posedge clk) begin
    if (ld_we && !ld_addr[0]) rom_h[ld_addr[12:1]] <= ld_data;
    q_h <= rom_h[addr];
  end
  always_ff @(posedge clk) begin
    if (ld_we && ld_addr[0]) rom_l[ld_addr[12:1]] <= ld_data;
    q_l <= rom_l[addr];
  end
  assign q = {q_h, q_l};
endmodule
`default_nettype wire
