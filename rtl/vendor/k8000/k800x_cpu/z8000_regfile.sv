// z8000_regfile -- 16 x 16-bit general registers.
//
// Encoding (Z8000 CPU Reference Manual sec 6.6):
//   byte  sel 0-7  = RH0..RH7 = HIGH byte of R0..R7
//   byte  sel 8-15 = RL0..RL7 = LOW  byte of R0..R7
//   word  sel 0-15 = R0..R15
//   long  sel & 0xE = RRn: R[n] is the HIGH word, R[n+1] the low word
//   quad  sel & 0xC = RQn: R[n] high ... R[n+3] low
// Port A reads any width; port B a byte or word only.
//
// The testbench reads and pokes `r` by name; keep it.
//
// `r` has no reset: the Z8000 leaves the general registers undefined.
// Reads come straight off `r`, so a read in a write cycle sees the old value.
//
// `nz` holds each byte's nonzero bit ([1] high, [0] low) as `r` stood the
// clock before, so a register's zero test needs no read.

module z8000_regfile (
  input  logic        clk,
  input  logic        clk_en,   // CLK rising edge seen this clock
  input  logic        we,
  input  logic [1:0]  wwidth,   // 0=byte 1=word 2=long 3=quad
  input  logic [3:0]  wsel,
  input  logic [63:0] wdata,    // right-aligned: byte in [7:0], word [15:0], long [31:0], quad [63:0]
  input  logic [1:0]  rwidth,
  input  logic [3:0]  rsel,
  output logic [63:0] rdata,    // right-aligned like wdata; unused upper bits zero
  input  logic        rbyte_b,  // 1 = byte, 0 = word
  input  logic [3:0]  rsel_b,
  output logic [15:0] rdata_b,
  output logic [15:0][1:0] nz
);

  localparam logic [1:0] W_BYTE = 2'd0;
  localparam logic [1:0] W_WORD = 2'd1;
  localparam logic [1:0] W_LONG = 2'd2;

  logic [15:0] r   [16];
  logic [15:0] r_d [16];

  // Byte writes touch only their half; long/quad ignore the low sel bits.
  always_comb begin
    r_d = r;
    unique case (wwidth)
      W_BYTE: begin
        if (wsel[3]) r_d[{1'b0, wsel[2:0]}][7:0]  = wdata[7:0];
        else         r_d[{1'b0, wsel[2:0]}][15:8] = wdata[7:0];
      end
      W_WORD: r_d[wsel] = wdata[15:0];
      W_LONG: begin
        r_d[{wsel[3:1], 1'b0}] = wdata[31:16];
        r_d[{wsel[3:1], 1'b1}] = wdata[15:0];
      end
      default: begin
        r_d[{wsel[3:2], 2'b00}] = wdata[63:48];
        r_d[{wsel[3:2], 2'b01}] = wdata[47:32];
        r_d[{wsel[3:2], 2'b10}] = wdata[31:16];
        r_d[{wsel[3:2], 2'b11}] = wdata[15:0];
      end
    endcase
  end

  always_ff @(posedge clk) if (clk_en) begin
    if (we) r <= r_d;
    for (int i = 0; i < 16; i++) nz[i] <= {r[i][15:8] != 8'h00, r[i][7:0] != 8'h00};
  end

  // Byte reads: RH/RL n is the high or low half of R n, n < 8.
  logic [3:0] bsel_a, bsel_b;
  assign bsel_a = {1'b0, rsel[2:0]};
  assign bsel_b = {1'b0, rsel_b[2:0]};

  always_comb begin
    rdata = 64'd0;
    unique case (rwidth)
      W_BYTE: rdata[7:0] = rsel[3] ? r[bsel_a][7:0] : r[bsel_a][15:8];
      W_WORD: rdata[15:0] = r[rsel];
      W_LONG: rdata[31:0] = {r[{rsel[3:1], 1'b0}], r[{rsel[3:1], 1'b1}]};
      default: rdata = {r[{rsel[3:2], 2'b00}], r[{rsel[3:2], 2'b01}],
                        r[{rsel[3:2], 2'b10}], r[{rsel[3:2], 2'b11}]};
    endcase
  end

  always_comb begin
    if (rbyte_b) rdata_b = {8'h00, rsel_b[3] ? r[bsel_b][7:0] : r[bsel_b][15:8]};
    else         rdata_b = r[rsel_b];
  end

endmodule
