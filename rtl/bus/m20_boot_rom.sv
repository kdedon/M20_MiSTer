// ROM0: the boot EPROM pair U54 (H, D15-D8) / U65 (L, D7-D0) and the three
// extension pairs U55/U66, U56/U67, U57/U68, selected by U36 O0, O4, O5, O6
// (PROM blocks ROM0 0000, 10000, 14000, 18000).  CPU A1-A13 address a
// pair; each socket is a 16 KB block.  The sockets take 2732s or 2764s: an
// image of 8 KB or less ignores A13, so it appears twice in its block.
//
// Loader (byte 2k = word k bits 15:8, byte 2k+1 = bits 7:0):
//   boot.rom   ld_ext = 0, up to 16 KB into U54/U65
//   extension  ld_ext = 1, up to 48 KB, 16 KB per socket from U55/U66;
//              sockets past the image end read 0xFFFF
// ld_start (download begins) forgets the previous image's size.
// Read is registered.
`default_nettype none
module m20_boot_rom (
  input  logic        clk,
  input  logic [2:0]  blk,        // U36 select: 0 boot, 4-6 extension, others empty
  input  logic [13:1] addr,       // CPU word address A13-A1
  output logic [15:0] q,
  input  logic        ld_start,
  input  logic        ld_ext,
  input  logic        ld_we,
  input  logic [15:0] ld_addr,
  input  logic [7:0]  ld_data
);
  (* ramstyle = "M10K" *) logic [7:0] rom_h [0:32767];
  (* ramstyle = "M10K" *) logic [7:0] rom_l [0:32767];
  logic [7:0] q_h, q_l;

  // Per socket (0 boot, 1-3 extension): image loaded, image above 8 KB.
  // Kept across machine resets; the boot socket counts as fitted.  Power-up
  // value 0 (no extension image).
  logic [3:1] fitted_q = 3'b000;
  logic [3:0] big_q    = 4'b0000;

  logic [1:0] ld_sock;
  logic       ld_ok;
  assign ld_sock = ld_ext ? ld_addr[15:14] + 2'd1 : 2'd0;
  assign ld_ok   = ld_ext ? (ld_addr[15:14] != 2'd3) : (ld_addr[15:14] == 2'd0);

  always_ff @(posedge clk) begin
    if (ld_start && ld_ext)            fitted_q <= 3'b000;
    else if (ld_we && ld_ok && ld_ext) fitted_q[ld_sock] <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (ld_start) begin
      if (ld_ext) big_q[3:1] <= 3'b000;
      else        big_q[0]   <= 1'b0;
    end else if (ld_we && ld_ok && ld_addr[13]) begin
      big_q[ld_sock] <= 1'b1;
    end
  end

  logic [1:0] sock;
  logic       sock_ok;
  always_comb begin
    sock    = 2'd0;
    sock_ok = 1'b1;
    unique case (blk)
      3'd0:    sock = 2'd0;
      3'd4:    sock = 2'd1;
      3'd5:    sock = 2'd2;
      3'd6:    sock = 2'd3;
      default: sock_ok = 1'b0;
    endcase
  end

  logic [14:0] ra, wa;
  assign ra = {sock, addr[13] & big_q[sock], addr[12:1]};
  assign wa = {ld_sock, ld_addr[13:1]};

  always_ff @(posedge clk) begin
    if (ld_we && ld_ok && !ld_addr[0]) rom_h[wa] <= ld_data;
    q_h <= rom_h[ra];
  end
  always_ff @(posedge clk) begin
    if (ld_we && ld_ok && ld_addr[0]) rom_l[wa] <= ld_data;
    q_l <= rom_l[ra];
  end

  // Empty socket: nothing drives the bus.
  logic empty_q;
  logic [3:0] fitted;
  assign fitted = {fitted_q, 1'b1};
  always_ff @(posedge clk) empty_q <= !sock_ok || !fitted[sock];

  assign q = empty_q ? 16'hFFFF : {q_h, q_l};
endmodule
`default_nettype wire
