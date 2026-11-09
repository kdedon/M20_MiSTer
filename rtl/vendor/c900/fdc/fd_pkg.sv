// C900 5.25" floppy media primitives for the drive emulator: zoned
// geometry, image LBA of a cylinder, the 4-to-5 GCR code and the
// on-media sector layout CMD_FORMAT writes (one stream byte = 10
// recorded bits):
//
//   SYNC (40 ones) 08 CYL SEC XOR, GAP1 14 x 00, SYNC (40 ones) 07,
//   512 data bytes, XOR, GAP2 G x 00   = 540 + G stream bytes per slot,
//
// slots in sector order from the revolution origin; the last slot's
// 00 bytes run on to the end of the revolution (300 RPM).  G is set by
// the format's speed check: 16 + (C - K) / spt, where C is the bytes
// it counts in a revolution less the sync (9226 8566 7995 7495 at
// nominal speed) with the low byte dropped, K = 8908 8352 7794 7238.
`default_nettype none

package fd_pkg;

  localparam logic [20:0] RevTicksNom = 21'd1_200_000;   // 200 ms of the 6 MHz _CLK
  localparam int unsigned MaxBits   = 92308;             // longest track (13-tick cells)
  // raw record: 16 cells per 32-bit word, 128 words per 512-byte block
  localparam int unsigned RawBlocks = ((MaxBits + 15) / 16 + 127) / 128;   // 46

  // zone 0..3 = tracks 0-38, 39-52, 53-63, 64-79
  function automatic logic [1:0] zone_of(input logic [6:0] t);
    if (t <= 7'd38)      zone_of = 2'd0;
    else if (t <= 7'd52) zone_of = 2'd1;
    else if (t <= 7'd63) zone_of = 2'd2;
    else                 zone_of = 2'd3;
  endfunction

  function automatic logic [4:0] spt_of(input logic [1:0] z);
    spt_of = 5'd16 - {3'd0, z};
  endfunction

  // _CLK ticks per bit cell: 13 14 15 16
  function automatic logic [4:0] cell_of(input logic [1:0] z);
    cell_of = 5'd13 + {3'd0, z};
  endfunction

  // stream bytes per slot, 540 + G: G = 35 22 26 30
  function automatic logic [9:0] slot_bytes_of(input logic [1:0] z);
    case (z)
      2'd0:    slot_bytes_of = 10'd575;
      2'd1:    slot_bytes_of = 10'd562;
      2'd2:    slot_bytes_of = 10'd566;
      default: slot_bytes_of = 10'd570;
    endcase
  endfunction

  function automatic logic [12:0] slot_bits_of(input logic [1:0] z);
    case (z)
      2'd0:    slot_bits_of = 13'd5750;
      2'd1:    slot_bits_of = 13'd5620;
      2'd2:    slot_bits_of = 13'd5660;
      default: slot_bits_of = 13'd5700;
    endcase
  endfunction

  // bits per revolution: ceil(1.2M / cell)
  function automatic logic [16:0] nbits_of(input logic [1:0] z);
    case (z)
      2'd0:    nbits_of = 17'd92308;
      2'd1:    nbits_of = 17'd85715;
      2'd2:    nbits_of = 17'd80000;
      default: nbits_of = 17'd75000;
    endcase
  endfunction

  function automatic logic [20:0] rev_of(input logic [1:0] z);
    case (z)
      2'd0:    rev_of = 21'd1_200_004;
      2'd1:    rev_of = 21'd1_200_010;
      default: rev_of = 21'd1_200_000;
    endcase
  endfunction

  // Image block of cylinder t, side 0 sector 0 (side-major per cylinder):
  // 32 blocks per cylinder to 39, then 30, 28 from 54, 26 from 65.  A
  // table, so it costs a 7-input lookup and no adders.
  function automatic logic [11:0] lba_of(input logic [6:0] t);
    case (t)
      7'd0: lba_of = 12'd0;     7'd1: lba_of = 12'd32;    7'd2: lba_of = 12'd64;    7'd3: lba_of = 12'd96;    7'd4: lba_of = 12'd128;
      7'd5: lba_of = 12'd160;   7'd6: lba_of = 12'd192;   7'd7: lba_of = 12'd224;   7'd8: lba_of = 12'd256;   7'd9: lba_of = 12'd288;
      7'd10: lba_of = 12'd320;  7'd11: lba_of = 12'd352;  7'd12: lba_of = 12'd384;  7'd13: lba_of = 12'd416;  7'd14: lba_of = 12'd448;
      7'd15: lba_of = 12'd480;  7'd16: lba_of = 12'd512;  7'd17: lba_of = 12'd544;  7'd18: lba_of = 12'd576;  7'd19: lba_of = 12'd608;
      7'd20: lba_of = 12'd640;  7'd21: lba_of = 12'd672;  7'd22: lba_of = 12'd704;  7'd23: lba_of = 12'd736;  7'd24: lba_of = 12'd768;
      7'd25: lba_of = 12'd800;  7'd26: lba_of = 12'd832;  7'd27: lba_of = 12'd864;  7'd28: lba_of = 12'd896;  7'd29: lba_of = 12'd928;
      7'd30: lba_of = 12'd960;  7'd31: lba_of = 12'd992;  7'd32: lba_of = 12'd1024; 7'd33: lba_of = 12'd1056; 7'd34: lba_of = 12'd1088;
      7'd35: lba_of = 12'd1120; 7'd36: lba_of = 12'd1152; 7'd37: lba_of = 12'd1184; 7'd38: lba_of = 12'd1216; 7'd39: lba_of = 12'd1248;
      7'd40: lba_of = 12'd1278; 7'd41: lba_of = 12'd1308; 7'd42: lba_of = 12'd1338; 7'd43: lba_of = 12'd1368; 7'd44: lba_of = 12'd1398;
      7'd45: lba_of = 12'd1428; 7'd46: lba_of = 12'd1458; 7'd47: lba_of = 12'd1488; 7'd48: lba_of = 12'd1518; 7'd49: lba_of = 12'd1548;
      7'd50: lba_of = 12'd1578; 7'd51: lba_of = 12'd1608; 7'd52: lba_of = 12'd1638; 7'd53: lba_of = 12'd1668; 7'd54: lba_of = 12'd1696;
      7'd55: lba_of = 12'd1724; 7'd56: lba_of = 12'd1752; 7'd57: lba_of = 12'd1780; 7'd58: lba_of = 12'd1808; 7'd59: lba_of = 12'd1836;
      7'd60: lba_of = 12'd1864; 7'd61: lba_of = 12'd1892; 7'd62: lba_of = 12'd1920; 7'd63: lba_of = 12'd1948; 7'd64: lba_of = 12'd1976;
      7'd65: lba_of = 12'd2002; 7'd66: lba_of = 12'd2028; 7'd67: lba_of = 12'd2054; 7'd68: lba_of = 12'd2080; 7'd69: lba_of = 12'd2106;
      7'd70: lba_of = 12'd2132; 7'd71: lba_of = 12'd2158; 7'd72: lba_of = 12'd2184; 7'd73: lba_of = 12'd2210; 7'd74: lba_of = 12'd2236;
      7'd75: lba_of = 12'd2262; 7'd76: lba_of = 12'd2288; 7'd77: lba_of = 12'd2314; 7'd78: lba_of = 12'd2340; 7'd79: lba_of = 12'd2366;
      default: lba_of = 12'd0;
    endcase
  endfunction

  function automatic logic [4:0] gcr_enc(input logic [3:0] v);
    case (v)
      4'h0: gcr_enc = 5'b01010;  4'h1: gcr_enc = 5'b01011;  4'h2: gcr_enc = 5'b10010;  4'h3: gcr_enc = 5'b10011;
      4'h4: gcr_enc = 5'b01110;  4'h5: gcr_enc = 5'b01111;  4'h6: gcr_enc = 5'b10110;  4'h7: gcr_enc = 5'b10111;
      4'h8: gcr_enc = 5'b01001;  4'h9: gcr_enc = 5'b11001;  4'hA: gcr_enc = 5'b11010;  4'hB: gcr_enc = 5'b11011;
      4'hC: gcr_enc = 5'b01101;  4'hD: gcr_enc = 5'b11101;  4'hE: gcr_enc = 5'b11110;  default: gcr_enc = 5'b10101;
    endcase
  endfunction

  // {valid, nibble}
  function automatic logic [4:0] gcr_dec(input logic [4:0] q);
    case (q)
      5'b01010: gcr_dec = 5'h10;  5'b01011: gcr_dec = 5'h11;  5'b10010: gcr_dec = 5'h12;  5'b10011: gcr_dec = 5'h13;
      5'b01110: gcr_dec = 5'h14;  5'b01111: gcr_dec = 5'h15;  5'b10110: gcr_dec = 5'h16;  5'b10111: gcr_dec = 5'h17;
      5'b01001: gcr_dec = 5'h18;  5'b11001: gcr_dec = 5'h19;  5'b11010: gcr_dec = 5'h1A;  5'b11011: gcr_dec = 5'h1B;
      5'b01101: gcr_dec = 5'h1C;  5'b11101: gcr_dec = 5'h1D;  5'b11110: gcr_dec = 5'h1E;  5'b10101: gcr_dec = 5'h1F;
      default:  gcr_dec = 5'h00;
    endcase
  endfunction

  function automatic logic [9:0] gcr_byte(input logic [7:0] v);
    gcr_byte = {gcr_enc(v[7:4]), gcr_enc(v[3:0])};
  endfunction

  // Stream byte n of a slot: sync bytes are 0..3 and 22..25; data 27..538;
  // 540 on are 00.
  function automatic logic is_sync(input logic [9:0] n);
    is_sync = n < 10'd4 || (n >= 10'd22 && n < 10'd26);
  endfunction
  function automatic logic is_data(input logic [9:0] n);
    is_data = n >= 10'd27 && n < 10'd539;
  endfunction

  // Non-data stream byte (sync bytes return 0 and are handled as ones).
  function automatic logic [7:0] slot_byte(input logic [9:0] n, input logic [6:0] t, input logic [3:0] s,
                                           input logic [7:0] ck);
    case (n)
      10'd4:   slot_byte = 8'h08;
      10'd5:   slot_byte = {1'b0, t};
      10'd6:   slot_byte = {4'd0, s};
      10'd7:   slot_byte = 8'h08 ^ {1'b0, t} ^ {4'd0, s};
      10'd26:  slot_byte = 8'h07;
      10'd539: slot_byte = ck;
      default: slot_byte = 8'h00;
    endcase
  endfunction

endpackage

`default_nettype wire
