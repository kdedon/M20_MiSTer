// RS-232 U131 (J7) and the MiSTer UART routing.
// TxC = RxC = 8253 OUT0 (jumpers R/S internal).  The TxRDY pin goes to
// 8259 IR5 (JP4 in the RS-232 position).
//
// The UART goes to one port, picked by ser_sel (0 J7, 1 twin A, 2 twin B);
// the others see an idle line.  Every port sees CTS and DSR asserted: the
// HPS UART's RTS/DTR are not a handshake the M20 software can rely on, and
// the 8251 holds its transmitter while CTS is inactive.  A twin channel
// picked with the card out leaves the UART idle.
`default_nettype none
module m20_rs232 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        ce_usart,
  input  logic        cfg_twin,
  input  logic [1:0]  ser_sel,
  // I/O bus
  input  logic        cs_ser,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [7:0]  ser_rdata,
  output logic        ser_rxrdy,
  output logic        ser_txrdy,
  input  logic        txc,
  // MiSTer UART
  input  logic        ser_rxd,
  output logic        ser_txd,
  output logic        ser_rts_n,
  output logic        ser_dtr_n,
  // twin card channels
  output logic [1:0]  tw_rxd,
  output logic [1:0]  tw_cts_n,
  output logic [1:0]  tw_dsr_n,
  input  logic [1:0]  tw_txd,
  input  logic [1:0]  tw_rts_n,
  input  logic [1:0]  tw_dtr_n
);

  logic [2:0] on_uart;
  assign on_uart = {ser_sel == 2'd2, ser_sel == 2'd1, ser_sel == 2'd0};

  logic mb_txd, mb_rts_n, mb_dtr_n;
  logic ser_txempty, ser_syndet;
  i8251 u_ser_usart (
    .clk, .rst_n, .ce_usart, .cs(cs_ser), .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .rdata(ser_rdata), .txc, .rxc(txc),
    .rxd(on_uart[0] ? ser_rxd : 1'b1), .txd(mb_txd),
    .cts_n(1'b0), .dsr_n(1'b0), .dtr_n(mb_dtr_n), .rts_n(mb_rts_n),
    .txrdy(ser_txrdy), .rxrdy(ser_rxrdy), .txempty(ser_txempty), .syndet(ser_syndet)
  );

  assign tw_rxd   = {on_uart[2] ? ser_rxd : 1'b1, on_uart[1] ? ser_rxd : 1'b1};
  assign tw_cts_n = 2'b00;
  assign tw_dsr_n = 2'b00;

  always_comb begin
    ser_txd   = mb_txd;
    ser_rts_n = mb_rts_n;
    ser_dtr_n = mb_dtr_n;
    if (!on_uart[0]) begin
      ser_txd   = !cfg_twin || (on_uart[1] ? tw_txd[0]   : tw_txd[1]);
      ser_rts_n = !cfg_twin || (on_uart[1] ? tw_rts_n[0] : tw_rts_n[1]);
      ser_dtr_n = !cfg_twin || (on_uart[1] ? tw_dtr_n[0] : tw_dtr_n[1]);
    end
  end

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, ser_txempty, ser_syndet};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
