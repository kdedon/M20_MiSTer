// M20 keyboard unit, high-level model of its 8048.  Talks to the keyboard
// 8251 only through kbd_txd / kbd_rxd: 1200 baud, 8 data, 2 stop, no parity.
//
// Commands (one byte from the M20):
//   0x03  reply {layout, 4'hF}: high nibble = national layout (0 Italian,
//         1 German, 3 UK, 4 US), low nibble nonzero = self-test OK
//   0x0A  bell: `beep` toggles at 3100 Hz for BEEP_MS, no reply
//   0x80  reply 0x80 (the ROM's VI test)
//   other ignored
// Half duplex: a byte to the M20 starts only while none is being received
// (including its second stop bit).  Replies go before queued keys.
//
// Each press of a mapped key queues one make code; no break codes.
// Modifiers are not sent; they offset the make code, mod 256: COMMAND
// alone +0x90, CTRL alone +0x60, SHIFT(s) alone +0x30, any other mix +0.
// A press while the FIFO is full is dropped and sets kbd_overflow.
//
// Make codes are M20 key numbers: row*8 + column for rows 0-5,
// 0xC0 + (row-6)*8 + column for rows 6-8.  Letters, digits, W, Z, M and
// , ; . map by legend on the Italian (QZERTY) layout, others by position.
//
//   PC key        set 2   M20   legend (unshifted / shifted)
//   Esc           76      00    RESET
//   ISO <>, LAlt  61, 11  01    < >
//   A..L          ...     02-0D a b c d e f g h i j k l
//   ,             41      0E    , ?
//   N..V          ...     0F-17 n o p q r s t u v
//   Z             1A      18    z
//   X             22      19    x
//   Y             35      1A    y
//   W             1D      1B    w
//   0..9          45..46  1C-25 a-grave/0 pound/1 e-acute/2 "/3 '/4 (/5
//                               _/6 e-grave/7 ^/8 c-cedilla/9
//   -             4E      26    ) degree
//   =             55      27    - +
//   [             54      28    i-grave =
//   ]             5B      29    $ &
//   M             3A      2A    m
//   '             52      2B    u-grave %
//   `             0E      2C    * section
//   ;             4C      2D    ; .
//   .             49      2E    : /
//   /             4A      2F    o-grave !
//   Space         29      C0
//   Enter         5A      C1
//   \, F1         5D, 05  C2    S1
//   Backspace, F2 66, 06  C3    S2
//   KP . 0        71 70   C4 C5
//   KP Enter      E0 5A   C6    00
//   KP 1..9       69 72 7A 6B 73 74 6C 75 7D   C7-CF
//   KP + - *      79 7B 7C      D0 D1 D2
//   KP /          E0 4A   D3
//   Tab           0D      COMMAND modifier
//   LCtrl, RCtrl  14, E0 14     CTRL modifier
//   LShift RShift 12, 59        SHIFT modifier
//
// Layouts 3 (UK) and 4 (US) target the PCOS ASCII table, shared by both:
//   key   01 02-1B 1C-25 26 27 28 29 2A 2B 2C 2D 2E 2F
//   plain \  a-z   0-9   -  ^  @  [  ;  :  ]  ,  .  /
//   shift |  A-Z   _!"#$%&'() = ~ `  {  +  *  }  <  >  ?
// Character keys then send the M20 key and shift state that give the
// PC legend (US Shift+2 sends 28, "@"); CTRL and COMMAND apply to the
// key carrying the unshifted legend.  \ is a character key; F1 stays S1.
// UK has no pound sign or not-sign: Shift+3 gives #, Shift+` gives `.
//
// Layout 1 (German) maps a QWERTZ PC keyboard by position.  Keys whose
// M20 code differs from the Italian map:
//   PC key (US name)  W   Z   Y   M   ;   '   ,   .   /
//   M20               18  1B  1A  0E  2A  2B  2D  2E  2F
//   legend            w   y   z   m   o-uml a-uml ,; .: -_
// The M20 lacks the degree sign and has ^ on Shift+#, ' on the acute key:
// ^ (and Shift+^) sends Shift+2C, # sends 2C, Shift+# sends 27 (').
`default_nettype none
module m20_kbd #(
  parameter int CLK_HZ  = 48_000_000,
  parameter int BAUD    = 1200,
  parameter int BEEP_HZ = 3100,
  parameter int BEEP_MS = 50
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [10:0] ps2_key,
  input  logic [3:0]  kbd_layout,     // national layout jumpers P14-P17: 0 IT, 1 DE, 3 UK, 4 US
  input  logic        kbd_txd,        // from the keyboard 8251 TxD
  output logic        kbd_rxd,        // to the keyboard 8251 RxD
  output logic        beep,
  output logic        kbd_overflow
);

  localparam int BIT_CLK  = CLK_HZ / BAUD;
  localparam int HALF_CLK = BIT_CLK / 2;
  localparam int BW       = $clog2(BIT_CLK + 1);
  localparam int TONE_CLK = CLK_HZ / (2 * BEEP_HZ);
  localparam int TW       = $clog2(TONE_CLK + 1);
  localparam int BEEP_CLK = (CLK_HZ / 1000) * BEEP_MS;
  localparam int LW       = $clog2(BEEP_CLK + 1);
  localparam int BIT_M1   = BIT_CLK - 1;
  localparam int HALF_M1  = HALF_CLK - 1;
  localparam int TONE_M1  = TONE_CLK - 1;
  localparam logic [BW-1:0] BIT_END  = BIT_M1[BW-1:0];
  localparam logic [BW-1:0] HALF_END = HALF_M1[BW-1:0];
  localparam logic [TW-1:0] TONE_END = TONE_M1[TW-1:0];
  localparam logic [LW-1:0] BELL_LEN = BEEP_CLK[LW-1:0];

  // ---------------------------------------------- receiver (from M20)
  typedef enum logic [2:0] {RIdle, RStart, RData, RStop, RGap} rx_e;
  rx_e          rx_q;
  logic [BW-1:0] rx_cnt_q;
  logic [2:0]   rx_bit_q;
  logic [7:0]   rx_sh_q;
  logic         line_q;
  logic         cmd_v;                    // one-clock: command byte received

  always_ff @(posedge clk) begin
    if (!rst_n) line_q <= 1'b1;
    else        line_q <= kbd_txd;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rx_q     <= RIdle;
      rx_cnt_q <= '0;
      rx_bit_q <= 3'd0;
      rx_sh_q  <= 8'h00;
    end else begin
      rx_cnt_q <= rx_cnt_q + 1'b1;
      unique case (rx_q)
        RIdle: begin
          rx_cnt_q <= '0;
          if (!line_q) rx_q <= RStart;
        end
        RStart: if (rx_cnt_q == HALF_END) begin
          rx_cnt_q <= '0;
          rx_bit_q <= 3'd0;
          rx_q     <= line_q ? RIdle : RData;
        end
        RData: if (rx_cnt_q == BIT_END) begin
          rx_cnt_q <= '0;
          rx_sh_q  <= {line_q, rx_sh_q[7:1]};
          rx_bit_q <= rx_bit_q + 3'd1;
          if (rx_bit_q == 3'd7) rx_q <= RStop;
        end
        RStop: if (rx_cnt_q == BIT_END) begin
          rx_cnt_q <= '0;
          rx_q     <= line_q ? RGap : RIdle;
        end
        RGap: if (rx_cnt_q == BIT_END) rx_q <= RIdle;
        default: rx_q <= RIdle;
      endcase
    end
  end

  assign cmd_v = (rx_q == RStop) & (rx_cnt_q == BIT_END) & line_q;

  // ------------------------------------------------------- commands
  logic       rep_v_q;
  logic [7:0] rep_q;
  logic       tx_start;
  logic       tx_from_rep;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rep_v_q <= 1'b0;
      rep_q   <= 8'h00;
    end else if (cmd_v && (rx_sh_q == 8'h03 || rx_sh_q == 8'h80)) begin
      rep_v_q <= 1'b1;
      rep_q   <= (rx_sh_q == 8'h03) ? {kbd_layout, 4'hF} : 8'h80;
    end else if (tx_start && tx_from_rep) begin
      rep_v_q <= 1'b0;
    end
  end

  // ----------------------------------------------------------- bell
  logic [LW-1:0] bell_q;
  logic [TW-1:0] tone_cnt_q;
  logic          tone_q;

  always_ff @(posedge clk) begin
    if (!rst_n)                        bell_q <= '0;
    else if (cmd_v && rx_sh_q == 8'h0A) bell_q <= BELL_LEN;
    else if (bell_q != '0)             bell_q <= bell_q - 1'b1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n || bell_q == '0) begin
      tone_cnt_q <= '0;
      tone_q     <= 1'b0;
    end else if (tone_cnt_q == TONE_END) begin
      tone_cnt_q <= '0;
      tone_q     <= ~tone_q;
    end else begin
      tone_cnt_q <= tone_cnt_q + 1'b1;
    end
  end

  assign beep = tone_q;

  // ----------------------------------------------------- PS/2 events
  logic       tog_q;
  logic [4:0] mod_q;                      // {LShift, RShift, RCtrl, LCtrl, Command}

  wire       ev    = ps2_key[10] != tog_q;
  wire       press = ps2_key[9];
  wire [8:0] key   = ps2_key[8:0];

  always_ff @(posedge clk) begin
    if (!rst_n) tog_q <= 1'b0;
    else        tog_q <= ps2_key[10];
  end

  logic [4:0] mod_hit;
  always_comb begin
    mod_hit = 5'b00000;
    unique case (key)
      9'h00D:  mod_hit = 5'b00001;
      9'h014:  mod_hit = 5'b00010;
      9'h114:  mod_hit = 5'b00100;
      9'h059:  mod_hit = 5'b01000;
      9'h012:  mod_hit = 5'b10000;
      default: mod_hit = 5'b00000;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n)  mod_q <= 5'b00000;
    else if (ev) mod_q <= press ? (mod_q | mod_hit) : (mod_q & ~mod_hit);
  end

  // 0x01 COMMAND, 0x02 CTRL, 0x04 RSHIFT, 0x08 LSHIFT
  wire [3:0] mods = {mod_q[4], mod_q[3], mod_q[2] | mod_q[1], mod_q[0]};
  logic [7:0] mod_off;
  always_comb begin
    unique case (mods)
      4'h1:              mod_off = 8'h90;
      4'h2:              mod_off = 8'h60;
      4'h4, 4'h8, 4'hC:  mod_off = 8'h30;
      default:           mod_off = 8'h00;
    endcase
  end

  localparam logic [3:0] LAY_DE = 4'd1;
  wire german = kbd_layout == LAY_DE;

  logic       map_hit;
  logic [7:0] map_code;
  always_comb begin
    map_hit  = 1'b1;
    map_code = 8'h00;
    unique case (key)
      9'h076: map_code = 8'h00;   // Esc       RESET
      9'h061: map_code = 8'h01;   // ISO <>
      9'h011: map_code = 8'h01;   // LAlt      <>
      9'h01C: map_code = 8'h02;   // A
      9'h032: map_code = 8'h03;   // B
      9'h021: map_code = 8'h04;   // C
      9'h023: map_code = 8'h05;   // D
      9'h024: map_code = 8'h06;   // E
      9'h02B: map_code = 8'h07;   // F
      9'h034: map_code = 8'h08;   // G
      9'h033: map_code = 8'h09;   // H
      9'h043: map_code = 8'h0A;   // I
      9'h03B: map_code = 8'h0B;   // J
      9'h042: map_code = 8'h0C;   // K
      9'h04B: map_code = 8'h0D;   // L
      9'h041: map_code = 8'h0E;   // ,
      9'h031: map_code = 8'h0F;   // N
      9'h044: map_code = 8'h10;   // O
      9'h04D: map_code = 8'h11;   // P
      9'h015: map_code = 8'h12;   // Q
      9'h02D: map_code = 8'h13;   // R
      9'h01B: map_code = 8'h14;   // S
      9'h02C: map_code = 8'h15;   // T
      9'h03C: map_code = 8'h16;   // U
      9'h02A: map_code = 8'h17;   // V
      9'h01A: map_code = 8'h18;   // Z
      9'h022: map_code = 8'h19;   // X
      9'h035: map_code = 8'h1A;   // Y
      9'h01D: map_code = 8'h1B;   // W
      9'h045: map_code = 8'h1C;   // 0
      9'h016: map_code = 8'h1D;   // 1
      9'h01E: map_code = 8'h1E;   // 2
      9'h026: map_code = 8'h1F;   // 3
      9'h025: map_code = 8'h20;   // 4
      9'h02E: map_code = 8'h21;   // 5
      9'h036: map_code = 8'h22;   // 6
      9'h03D: map_code = 8'h23;   // 7
      9'h03E: map_code = 8'h24;   // 8
      9'h046: map_code = 8'h25;   // 9
      9'h04E: map_code = 8'h26;   // -
      9'h055: map_code = 8'h27;   // =
      9'h054: map_code = 8'h28;   // [
      9'h05B: map_code = 8'h29;   // ]
      9'h03A: map_code = 8'h2A;   // M
      9'h052: map_code = 8'h2B;   // '
      9'h00E: map_code = 8'h2C;   // `
      9'h04C: map_code = 8'h2D;   // ;
      9'h049: map_code = 8'h2E;   // .
      9'h04A: map_code = 8'h2F;   // /
      9'h029: map_code = 8'hC0;   // Space
      9'h05A: map_code = 8'hC1;   // Enter
      9'h05D: map_code = 8'hC2;   // \         S1
      9'h005: map_code = 8'hC2;   // F1        S1
      9'h066: map_code = 8'hC3;   // Backspace S2
      9'h006: map_code = 8'hC3;   // F2        S2
      9'h071: map_code = 8'hC4;   // KP .
      9'h070: map_code = 8'hC5;   // KP 0
      9'h15A: map_code = 8'hC6;   // KP Enter  00
      9'h069: map_code = 8'hC7;   // KP 1
      9'h072: map_code = 8'hC8;   // KP 2
      9'h07A: map_code = 8'hC9;   // KP 3
      9'h06B: map_code = 8'hCA;   // KP 4
      9'h073: map_code = 8'hCB;   // KP 5
      9'h074: map_code = 8'hCC;   // KP 6
      9'h06C: map_code = 8'hCD;   // KP 7
      9'h075: map_code = 8'hCE;   // KP 8
      9'h07D: map_code = 8'hCF;   // KP 9
      9'h079: map_code = 8'hD0;   // KP +
      9'h07B: map_code = 8'hD1;   // KP -
      9'h07C: map_code = 8'hD2;   // KP *
      9'h14A: map_code = 8'hD3;   // KP /
      default: map_hit = 1'b0;
    endcase
    if (german) begin
      unique case (key)
        9'h01D:  map_code = 8'h18;   // W
        9'h01A:  map_code = 8'h1B;   // Y
        9'h035:  map_code = 8'h1A;   // Z
        9'h03A:  map_code = 8'h0E;   // M
        9'h04C:  map_code = 8'h2A;   // o-umlaut
        9'h052:  map_code = 8'h2B;   // a-umlaut
        9'h041:  map_code = 8'h2D;   // , ;
        9'h049:  map_code = 8'h2E;   // . :
        9'h04A:  map_code = 8'h2F;   // - _
        default: ;
      endcase
    end
  end

  // English legends as table codes: M20 key, +0x30 when shifted.
  localparam logic [3:0] LAY_UK = 4'd3;
  localparam logic [3:0] LAY_US = 4'd4;
  wire english = (kbd_layout == LAY_UK) | (kbd_layout == LAY_US);
  wire uk      = kbd_layout == LAY_UK;

  logic       en_hit;
  logic [6:0] en_lo, en_hi;               // unshifted / shifted legend
  always_comb begin
    en_hit = 1'b1;
    en_lo  = 7'h00;
    en_hi  = 7'h00;
    unique case (key)
      9'h01C: en_lo = 7'h02;              // A
      9'h032: en_lo = 7'h03;              // B
      9'h021: en_lo = 7'h04;              // C
      9'h023: en_lo = 7'h05;              // D
      9'h024: en_lo = 7'h06;              // E
      9'h02B: en_lo = 7'h07;              // F
      9'h034: en_lo = 7'h08;              // G
      9'h033: en_lo = 7'h09;              // H
      9'h043: en_lo = 7'h0A;              // I
      9'h03B: en_lo = 7'h0B;              // J
      9'h042: en_lo = 7'h0C;              // K
      9'h04B: en_lo = 7'h0D;              // L
      9'h03A: en_lo = 7'h0E;              // M
      9'h031: en_lo = 7'h0F;              // N
      9'h044: en_lo = 7'h10;              // O
      9'h04D: en_lo = 7'h11;              // P
      9'h015: en_lo = 7'h12;              // Q
      9'h02D: en_lo = 7'h13;              // R
      9'h01B: en_lo = 7'h14;              // S
      9'h02C: en_lo = 7'h15;              // T
      9'h03C: en_lo = 7'h16;              // U
      9'h02A: en_lo = 7'h17;              // V
      9'h01D: en_lo = 7'h18;              // W
      9'h022: en_lo = 7'h19;              // X
      9'h035: en_lo = 7'h1A;              // Y
      9'h01A: en_lo = 7'h1B;              // Z
      9'h045: begin en_lo = 7'h1C; en_hi = 7'h55; end                  // 0 )
      9'h016: begin en_lo = 7'h1D; en_hi = 7'h4D; end                  // 1 !
      9'h01E: begin en_lo = 7'h1E; en_hi = uk ? 7'h4E : 7'h28; end     // 2 " @
      9'h026: begin en_lo = 7'h1F; en_hi = 7'h4F; end                  // 3 #
      9'h025: begin en_lo = 7'h20; en_hi = 7'h50; end                  // 4 $
      9'h02E: begin en_lo = 7'h21; en_hi = 7'h51; end                  // 5 %
      9'h036: begin en_lo = 7'h22; en_hi = 7'h27; end                  // 6 ^
      9'h03D: begin en_lo = 7'h23; en_hi = 7'h52; end                  // 7 &
      9'h03E: begin en_lo = 7'h24; en_hi = 7'h5B; end                  // 8 *
      9'h046: begin en_lo = 7'h25; en_hi = 7'h54; end                  // 9 (
      9'h04E: begin en_lo = 7'h26; en_hi = 7'h4C; end                  // - _
      9'h055: begin en_lo = 7'h56; en_hi = 7'h5A; end                  // = +
      9'h054: begin en_lo = 7'h29; en_hi = 7'h59; end                  // [ {
      9'h05B: begin en_lo = 7'h2C; en_hi = 7'h5C; end                  // ] }
      9'h04C: begin en_lo = 7'h2A; en_hi = 7'h2B; end                  // ; :
      9'h052: begin en_lo = 7'h53; en_hi = uk ? 7'h28 : 7'h4E; end     // ' @ "
      9'h00E: begin en_lo = 7'h58; en_hi = uk ? 7'h58 : 7'h57; end     // ` ~
      9'h05D: begin en_lo = uk ? 7'h4F : 7'h01; en_hi = uk ? 7'h57 : 7'h31; end  // # ~, \ |
      9'h061: begin en_lo = 7'h01; en_hi = 7'h31; end                  // ISO \ |
      9'h041: begin en_lo = 7'h2D; en_hi = 7'h5D; end                  // , <
      9'h049: begin en_lo = 7'h2E; en_hi = 7'h5E; end                  // . >
      9'h04A: begin en_lo = 7'h2F; en_hi = 7'h5F; end                  // / ?
      default: en_hit = 1'b0;
    endcase
    if (en_hit && en_hi == 7'h00) en_hi = en_lo + 7'h30;
    if (german) begin
      en_hit = 1'b1;
      unique case (key)
        9'h00E:  begin en_lo = 7'h5C; en_hi = 7'h5C; end           // ^
        9'h05D:  begin en_lo = 7'h2C; en_hi = 7'h27; end           // # '
        default: en_hit = 1'b0;
      endcase
    end
  end

  // Plain and SHIFT send the legend's code as is; CTRL and COMMAND add
  // their offset to the key under the unshifted legend.
  wire       en_key  = (english | german) & en_hit;
  wire       shift_m = (mods == 4'h4) | (mods == 4'h8) | (mods == 4'hC);
  wire [6:0] en_lo_k = (en_lo >= 7'h30) ? en_lo - 7'h30 : en_lo;
  logic [7:0] code;
  always_comb begin
    if (!en_key)            code = map_code + mod_off;
    else if (shift_m)       code = {1'b0, en_hi};
    else if (mods == 4'h0)  code = {1'b0, en_lo};
    else                    code = {1'b0, en_lo_k} + mod_off;
  end

  // --------------------------------------------------------- key FIFO
  // Depth 8: the line drains a byte per 9.2 ms, well above typing rates;
  // the FIFO only absorbs bursts while a reply or a host byte holds the line.
  localparam int AW = 3;
  logic [7:0]  fifo_q [0:(1<<AW)-1];
  logic [AW:0] wp_q, rp_q;

  wire fifo_full  = wp_q == (rp_q ^ {1'b1, {AW{1'b0}}});
  wire fifo_empty = wp_q == rp_q;
  wire key_v      = ev & press & (map_hit | en_key);
  wire push       = key_v & ~fifo_full;
  wire pop        = tx_start & ~tx_from_rep;

  always_ff @(posedge clk) begin
    if (push) fifo_q[wp_q[AW-1:0]] <= code;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wp_q <= '0;
      rp_q <= '0;
    end else begin
      if (push) wp_q <= wp_q + 1'b1;
      if (pop)  rp_q <= rp_q + 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n)                 kbd_overflow <= 1'b0;
    else if (key_v && fifo_full) kbd_overflow <= 1'b1;
  end

  // ------------------------------------------- transmitter (to M20)
  logic          tx_busy_q;
  logic [10:0]   tx_sh_q;                 // {stop, stop, data[7:0], start}, LSB first
  logic [3:0]    tx_bit_q;
  logic [BW-1:0] tx_cnt_q;

  assign tx_from_rep = rep_v_q;
  assign tx_start    = ~tx_busy_q & (rx_q == RIdle) & (rep_v_q | ~fifo_empty);
  wire [7:0] tx_byte = rep_v_q ? rep_q : fifo_q[rp_q[AW-1:0]];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tx_busy_q <= 1'b0;
      tx_sh_q   <= 11'h7FF;
      tx_bit_q  <= 4'd0;
      tx_cnt_q  <= '0;
    end else if (tx_start) begin
      tx_busy_q <= 1'b1;
      tx_sh_q   <= {2'b11, tx_byte, 1'b0};
      tx_bit_q  <= 4'd0;
      tx_cnt_q  <= '0;
    end else if (tx_busy_q) begin
      if (tx_cnt_q == BIT_END) begin
        tx_cnt_q <= '0;
        tx_sh_q  <= {1'b1, tx_sh_q[10:1]};
        tx_bit_q <= tx_bit_q + 4'd1;
        if (tx_bit_q == 4'd10) tx_busy_q <= 1'b0;
      end else begin
        tx_cnt_q <= tx_cnt_q + 1'b1;
      end
    end
  end

  assign kbd_rxd = tx_busy_q ? tx_sh_q[0] : 1'b1;

endmodule
`default_nettype wire
