// i8251A USART, asynchronous modes only.
// Keyboard U22 at 0xA1/0xA3, RS-232 U131 at 0xC1/0xC3; C/D = CPU A1.
//
// Mode instruction after reset, then (sync modes) one or two sync
// characters, then commands.  Command bit 6 (IR) returns to the mode
// state, so the ROM's 0, 0, 0, 0x40 lands in a known state from either
// starting point.  Sync mode (B = 00) is accepted but stays idle.
//   mode:    [1:0] B 01 x1, 10 x16, 11 x64   [3:2] L 5..8 bits
//            [4] PEN   [5] EP (1 even)       [7:6] S 01 1, 10 1.5, 11 2
//   command: [0] TxEN [1] DTR [2] RxE [3] SBRK [4] ER [5] RTS [6] IR [7] EH
//   status:  [0] TxRDY (buffer empty, not gated)  [1] RxRDY  [2] TxEMPTY
//            [3] PE  [4] OE  [5] FE  [6] SYNDET/BRKDET  [7] DSR
// After reset and command 0x37 the status is 0x05 | DSR.
//
// TxC and RxC are levels sampled on ce_usart (2 MHz CLK): transmit on TxC
// falling edges, receive on RxC rising edges.  The receiver finds the
// start bit's middle after half a bit (x16/x64) and checks one stop bit.
// BRKDET sets after two all-zero characters with framing errors and
// clears when RxD is high at a sample.
//
// Writes are captured while cs && io_wr and committed at io_wr_end; a
// data read clears RxRDY at io_rd_end.  TxRDY pin = empty & TxEN & !CTS.
`default_nettype none
module i8251 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        ce_usart,
  // I/O bus
  input  logic        cs,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [7:0]  rdata,
  // serial side
  input  logic        txc,
  input  logic        rxc,
  input  logic        rxd,
  output logic        txd,
  input  logic        cts_n,
  input  logic        dsr_n,
  output logic        dtr_n,
  output logic        rts_n,
  // status pins
  output logic        txrdy,
  output logic        rxrdy,
  output logic        txempty,
  output logic        syndet
);

  // ---------------------------------------------------------------- bus
  // Write held from the strobe to its commit.
  logic       wr_pend_q, wr_cd_q;
  logic [7:0] wr_data_q;
  logic       rd_pend_q, rd_cd_q;

  always_ff @(posedge clk) begin
    if (!rst_n)              wr_pend_q <= 1'b0;
    else if (io_wr_end)      wr_pend_q <= 1'b0;
    else if (cs && io_wr)    wr_pend_q <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (cs && io_wr) begin
      wr_cd_q   <= io_addr[1];
      wr_data_q <= io_wdata[7:0];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n)              rd_pend_q <= 1'b0;
    else if (io_rd_end)      rd_pend_q <= 1'b0;
    else if (cs && io_rd)    rd_pend_q <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (cs && io_rd) rd_cd_q <= io_addr[1];
  end

  wire wr_commit = io_wr_end & wr_pend_q;
  wire ctl_wr    = wr_commit &  wr_cd_q;
  wire dat_wr    = wr_commit & ~wr_cd_q;
  wire dat_rd    = io_rd_end & rd_pend_q & ~rd_cd_q;

  // ------------------------------------------------- mode / command FSM
  typedef enum logic [1:0] {CtlMode, CtlSync1, CtlSync2, CtlCmd} ctl_e;
  ctl_e       ctl_q;
  logic [7:0] mode_q, cmd_q;

  wire ireset = ctl_wr & (ctl_q == CtlCmd) & wr_data_q[6];
  wire err_rst = ctl_wr & (ctl_q == CtlCmd) & wr_data_q[4];

  always_ff @(posedge clk) begin
    if (!rst_n || ireset) begin
      ctl_q  <= CtlMode;
      mode_q <= 8'h00;
      cmd_q  <= 8'h00;
    end else if (ctl_wr) begin
      unique case (ctl_q)
        CtlMode: begin
          mode_q <= wr_data_q;
          ctl_q  <= (wr_data_q[1:0] == 2'b00) ? CtlSync1 : CtlCmd;
        end
        CtlSync1: ctl_q <= mode_q[7] ? CtlCmd : CtlSync2;
        CtlSync2: ctl_q <= CtlCmd;
        CtlCmd:   cmd_q <= wr_data_q;
        default:  ctl_q <= CtlMode;
      endcase
    end
  end

  wire async_on = (ctl_q == CtlCmd) & (mode_q[1:0] != 2'b00);
  wire txen     = cmd_q[0];
  wire rxe      = cmd_q[2];
  wire sbrk     = cmd_q[3];
  wire pen      = mode_q[4];
  wire ep       = mode_q[5];
  wire [2:0] last_bit = {1'b1, mode_q[3:2]};        // nbits - 1 (5..8 bits)

  logic [6:0] blen;                                 // clock edges per bit
  logic [7:0] slen;                                 // clock edges of stop
  always_comb begin
    unique case (mode_q[1:0])
      2'b01:   blen = 7'd1;
      2'b10:   blen = 7'd16;
      2'b11:   blen = 7'd64;
      default: blen = 7'd16;
    endcase
    unique case (mode_q[7:6])
      2'b10:   slen = {1'b0, blen} + {2'b00, blen[6:1]};
      2'b11:   slen = {blen, 1'b0};
      default: slen = {1'b0, blen};
    endcase
  end

  assign dtr_n = ~cmd_q[1];
  assign rts_n = ~cmd_q[5];

  // ------------------------------------------------------- clock edges
  logic txc_s, rxc_s;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      txc_s <= 1'b1;
      rxc_s <= 1'b1;
    end else if (ce_usart) begin
      txc_s <= txc;
      rxc_s <= rxc;
    end
  end
  wire tx_tick = ce_usart &  txc_s & ~txc;
  wire rx_tick = ce_usart & ~rxc_s &  rxc;

  // -------------------------------------------------------- transmitter
  typedef enum logic [2:0] {TxIdle, TxStart, TxData, TxPar, TxStop} tx_e;
  tx_e        tx_q;
  logic [7:0] tx_buf_q, tx_sh_q;
  logic       tx_full_q, tx_line_q, tx_par_q;
  logic [2:0] tx_bit_q;
  logic [7:0] tx_cnt_q;

  wire tx_go    = tx_full_q & txen & ~cts_n & async_on;
  wire tx_bend  = tx_cnt_q == {1'b0, blen} - 8'd1;
  wire tx_load  = tx_tick & tx_go &
                  ((tx_q == TxIdle) | ((tx_q == TxStop) & (tx_cnt_q == slen - 8'd1)));

  always_ff @(posedge clk) begin
    if (!rst_n || ireset)  tx_full_q <= 1'b0;
    else if (dat_wr)       tx_full_q <= 1'b1;
    else if (tx_load)      tx_full_q <= 1'b0;
  end

  always_ff @(posedge clk) begin
    if (dat_wr) tx_buf_q <= wr_data_q;
  end

  always_ff @(posedge clk) begin
    if (!rst_n || ireset) begin
      tx_q      <= TxIdle;
      tx_line_q <= 1'b1;
      tx_cnt_q  <= 8'd0;
      tx_bit_q  <= 3'd0;
      tx_par_q  <= 1'b0;
      tx_sh_q   <= 8'h00;
    end else if (tx_load) begin
      tx_q      <= TxStart;
      tx_line_q <= 1'b0;
      tx_cnt_q  <= 8'd0;
      tx_bit_q  <= 3'd0;
      tx_par_q  <= 1'b0;
      tx_sh_q   <= tx_buf_q;
    end else if (tx_tick) begin
      tx_cnt_q <= tx_cnt_q + 8'd1;
      unique case (tx_q)
        TxIdle: begin
          tx_cnt_q  <= 8'd0;
          tx_line_q <= 1'b1;
        end
        TxStart: if (tx_bend) begin
          tx_q      <= TxData;
          tx_cnt_q  <= 8'd0;
          tx_line_q <= tx_sh_q[0];
        end
        TxData: if (tx_bend) begin
          tx_cnt_q <= 8'd0;
          tx_par_q <= tx_par_q ^ tx_sh_q[0];
          tx_sh_q  <= {1'b0, tx_sh_q[7:1]};
          if (tx_bit_q == last_bit) begin
            tx_q      <= pen ? TxPar : TxStop;
            tx_line_q <= pen ? ~(tx_par_q ^ tx_sh_q[0] ^ ep) : 1'b1;
          end else begin
            tx_bit_q  <= tx_bit_q + 3'd1;
            tx_line_q <= tx_sh_q[1];
          end
        end
        TxPar: if (tx_bend) begin
          tx_q      <= TxStop;
          tx_cnt_q  <= 8'd0;
          tx_line_q <= 1'b1;
        end
        TxStop: if (tx_cnt_q == slen - 8'd1) begin
          tx_q     <= TxIdle;
          tx_cnt_q <= 8'd0;
        end
        default: tx_q <= TxIdle;
      endcase
    end
  end

  assign txd     = tx_line_q & ~sbrk;
  assign txempty = ~tx_full_q & (tx_q == TxIdle);
  assign txrdy   = ~tx_full_q & txen & ~cts_n;

  // ----------------------------------------------------------- receiver
  typedef enum logic [2:0] {RxIdle, RxStart, RxData, RxPar, RxStop} rx_e;
  rx_e        rx_q;
  logic [7:0] rx_sh_q, rx_data_q;
  logic [2:0] rx_bit_q;
  logic [6:0] rx_cnt_q;
  logic       rx_par_q, rx_perr_q, rx_pbit_q;
  logic       rxrdy_q, pe_q, oe_q, fe_q, brk_q, brk1_q;

  wire rx_run  = rxe & async_on;
  wire rx_samp = rx_tick & (rx_cnt_q == blen);
  wire rx_done = rx_samp & (rx_q == RxStop);

  logic [7:0] rx_char;                              // received bits, LSB aligned
  always_comb begin
    unique case (mode_q[3:2])
      2'b00:   rx_char = {3'b000,  rx_sh_q[7:3]};
      2'b01:   rx_char = {2'b00,   rx_sh_q[7:2]};
      2'b10:   rx_char = {1'b0,    rx_sh_q[7:1]};
      default: rx_char = rx_sh_q;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n || ireset) begin
      rx_q      <= RxIdle;
      rx_cnt_q  <= 7'd0;
      rx_bit_q  <= 3'd0;
      rx_sh_q   <= 8'h00;
      rx_par_q  <= 1'b0;
      rx_perr_q <= 1'b0;
      rx_pbit_q <= 1'b0;
    end else if (rx_tick) begin
      if (!rx_run) begin
        rx_q <= RxIdle;
      end else begin
        rx_cnt_q <= rx_cnt_q + 7'd1;
        unique case (rx_q)
          RxIdle: if (!rxd) begin
            rx_q      <= (blen == 7'd1) ? RxData : RxStart;
            rx_cnt_q  <= 7'd1;
            rx_bit_q  <= 3'd0;
            rx_par_q  <= 1'b0;
            rx_perr_q <= 1'b0;
            rx_pbit_q <= 1'b0;
          end else begin
            rx_cnt_q  <= 7'd0;
          end
          RxStart: if (rx_cnt_q == {1'b0, blen[6:1]}) begin
            rx_q     <= rxd ? RxIdle : RxData;
            rx_cnt_q <= 7'd1;
          end
          RxData: if (rx_samp) begin
            rx_cnt_q <= 7'd1;
            rx_sh_q  <= {rxd, rx_sh_q[7:1]};
            rx_par_q <= rx_par_q ^ rxd;
            if (rx_bit_q == last_bit) rx_q <= pen ? RxPar : RxStop;
            else                      rx_bit_q <= rx_bit_q + 3'd1;
          end
          RxPar: if (rx_samp) begin
            rx_cnt_q  <= 7'd1;
            rx_perr_q <= (rx_par_q ^ rxd) == ep;
            rx_pbit_q <= rxd;
            rx_q      <= RxStop;
          end
          RxStop: if (rx_samp) begin
            rx_cnt_q <= 7'd0;
            rx_q     <= RxIdle;
          end
          default: rx_q <= RxIdle;
        endcase
      end
    end
  end

  // A character is complete at the middle of its first stop bit.
  wire rx_zero = (rx_char == 8'h00) & ~(pen & rx_pbit_q);

  always_ff @(posedge clk) begin
    if (!rst_n)       rx_data_q <= 8'h00;
    else if (rx_done) rx_data_q <= rx_char;
  end

  always_ff @(posedge clk) begin
    if (!rst_n || ireset)  rxrdy_q <= 1'b0;
    else if (rx_done)      rxrdy_q <= 1'b1;
    else if (dat_rd)       rxrdy_q <= 1'b0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n || ireset || err_rst) begin
      pe_q <= 1'b0;
      oe_q <= 1'b0;
      fe_q <= 1'b0;
    end else if (rx_done) begin
      pe_q <= pe_q | (pen & rx_perr_q);
      oe_q <= oe_q | rxrdy_q;
      fe_q <= fe_q | ~rxd;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n || ireset) begin
      brk1_q <= 1'b0;
      brk_q  <= 1'b0;
    end else if (rx_done && !rxd && rx_zero) begin
      brk1_q <= 1'b1;
      brk_q  <= brk_q | brk1_q;
    end else if (rx_tick && rxd) begin
      brk1_q <= 1'b0;
      brk_q  <= 1'b0;
    end
  end

  assign rxrdy  = rxrdy_q;
  assign syndet = brk_q;

  // ------------------------------------------------------------- read
  wire [7:0] status = {~dsr_n, brk_q, fe_q, oe_q, pe_q, txempty, rxrdy_q, ~tx_full_q};
  assign rdata = io_addr[1] ? status : rx_data_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, io_addr[15:2], io_addr[0], io_wdata[15:8], cmd_q[7], cmd_q[6], cmd_q[4]};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
