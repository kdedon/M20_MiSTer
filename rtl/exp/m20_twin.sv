// G0221 twin RS-232 card: two i8251A (channels A and B), an i8253 baud
// timer and a slave i8259A whose INT drives *SYSINT (master IR7).
//
// Decode (74LS138): A15-A12 = 0, A11 = 1, A7-A5 picks the device; A0,
// A3, A4, A8-A10 are not decoded.
//   0x801/0x803   8251 A, C/D = A1
//   0x821/0x823   8251 B
//   0x840/0x842   8259A on D1-D8, A0 = A1 (word I/O)
//   0x861-0x867   8253, A1-A0 = A2-A1
//   0x881         modem status (read): D0 SDET A, D1 BUSY A, D2 SDET B,
//                 D3 BUSY B (receiver outputs, 1 = idle), D4/D6 = 1, D5/D7 = 0
// 8253: every CLK from the card's 16 MHz oscillator through a 74LS163,
// taken as / 13 (ce_pit), GATEs high.  OUT0 -> 8251 A TxC/RxC, OUT1 ->
// 8251 B TxC/RxC, OUT2 not jumpered.
// Slave 8259 inputs: IR0 RxRDY A, IR1 TxRDY A, IR2 RxRDY B, IR3 TxRDY B;
// IR4-IR7 grounded.
//
// cs / cs16 cover the strobe and its end clock (mainboard read mux).
`default_nettype none
module m20_twin (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,             // card fitted
  input  logic        ce_pit,
  input  logic        ce_usart,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic        cs,             // byte port: rdata
  output logic [7:0]  rdata,
  output logic        cs16,           // 8259: pic_rdata
  output logic [15:0] pic_rdata,      // also the vector word in an acknowledge
  input  logic        pic_inta_n,
  input  logic [2:0]  cas,
  output logic        sysint,
  // channels A (0) and B (1)
  input  logic [1:0]  rxd,
  output logic [1:0]  txd,
  input  logic [1:0]  cts_n,
  input  logic [1:0]  dsr_n,
  output logic [1:0]  rts_n,
  output logic [1:0]  dtr_n
);

  logic strobe, board;
  assign strobe = io_rd || io_wr || io_rd_end || io_wr_end;
  assign board  = en && strobe && io_addr[15:11] == 5'b00001;

  logic [1:0] cs_usart;
  logic       cs_pit, cs_modem;
  assign cs_usart[0] = board && io_addr[7:5] == 3'd0;
  assign cs_usart[1] = board && io_addr[7:5] == 3'd1;
  assign cs16        = board && io_addr[7:5] == 3'd2;
  assign cs_pit      = board && io_addr[7:5] == 3'd3;
  assign cs_modem    = board && io_addr[7:5] == 3'd4;
  assign cs          = |cs_usart || cs_pit || cs_modem;

  // ---- baud timer ----
  logic [7:0] pit_rdata;
  logic       out0, out1, out2;
  m20_pit u_pit (
    .clk, .rst_n, .ce_pit, .cs_pit, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pit_rdata, .pit_out0(out0), .pit_out1(out1), .pit_out2(out2)
  );

  // ---- USARTs ----
  logic [1:0][7:0] u_rdata;
  logic [1:0]      txrdy, rxrdy, txempty, syndet;
  logic [1:0]      bclk;
  assign bclk = {out1, out0};

  genvar g;
  generate
    for (g = 0; g < 2; g++) begin : g_ch
      i8251 u_usart (
        .clk, .rst_n, .ce_usart, .cs(cs_usart[g]), .io_rd, .io_wr, .io_rd_end, .io_wr_end,
        .io_addr, .io_wdata, .rdata(u_rdata[g]), .txc(bclk[g]), .rxc(bclk[g]),
        .rxd(rxd[g]), .txd(txd[g]), .cts_n(cts_n[g]), .dsr_n(dsr_n[g]),
        .dtr_n(dtr_n[g]), .rts_n(rts_n[g]),
        .txrdy(txrdy[g]), .rxrdy(rxrdy[g]), .txempty(txempty[g]), .syndet(syndet[g])
      );
    end
  endgenerate

  // ---- interrupts ----
  logic irq;
  m20_xpic u_pic (
    .clk, .rst_n, .cs(cs16), .io_rd, .io_wr, .io_addr, .io_wdata, .rdata(pic_rdata),
    .pic_inta_n, .cas, .ir({4'b0000, txrdy[1], rxrdy[1], txrdy[0], rxrdy[0]}), .irq
  );
  assign sysint = en && irq;

  // ---- read mux ----
  always_comb begin
    rdata = 8'hFF;
    unique case (1'b1)
      cs_usart[0]: rdata = u_rdata[0];
      cs_usart[1]: rdata = u_rdata[1];
      cs_pit:      rdata = pit_rdata;
      cs_modem:    rdata = 8'h5F;
      default:     rdata = 8'hFF;
    endcase
  end

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, out2, txempty, syndet};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
