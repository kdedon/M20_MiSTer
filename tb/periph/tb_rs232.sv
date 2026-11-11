// m20_rs232 with the 8253 as in the core: OUT0 (count 8, mode 3) clocks
// U131, the ROM's 8251 set-up for 9600 8N1 x16, then bytes written to the
// data port must appear on ser_txd and a frame on ser_rxd must be read
// back.  The port has no CTS/DSR input, so the level the MiSTer leaves on
// UART_CTS/UART_DSR (high while Linux has RTS/DTR off) cannot hold the
// transmitter; status reads DSR asserted.
//
// Then PCOS/OLITERM's RS-232 driver at 4800 8N2: reset 0,0,0,0x40, mode
// 0xCE, command 0x00, IMR 0xC7 (IR3-IR5), and an interrupt-driven
// transmitter: TxEN raises the TxRDY pin, 8259 IR5 interrupts, the
// handler reads status bit 0, writes the next byte and sends a specific
// EOI 0x65 (byte 0xCA on D1-D8); with the queue empty it drops TxEN.
// The 8259 is wired as in the core (IR3 RxRDY, IR5 TxRDY).
`timescale 1ns/1ps
`default_nettype none
module tb_rs232;
  `include "tb_io.svh"

  localparam real BIT_NS = 1.0e9 / 9600.0;
  localparam real B48_NS = 1.0e9 / 4800.0;

  logic [7:0] pit_rdata, ser_rdata;
  logic       pit_out0, pit_out1, pit_out2;
  logic       ser_rxrdy, ser_txrdy, ser_txd, ser_rts_n, ser_dtr_n;
  logic [15:0] pic_rdata;
  logic       pic_int;
  logic       ser_rxd = 1'b1;
  logic       cfg_twin = 1'b0;
  logic [1:0] ser_sel = 2'd0;
  logic [1:0] tw_rxd, tw_cts_n, tw_dsr_n;

  m20_pit u_pit (
    .clk, .rst_n, .ce_pit, .cs_pit, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pit_rdata, .pit_out0, .pit_out1, .pit_out2
  );

  m20_rs232 dut (
    .clk, .rst_n, .ce_usart, .cfg_twin, .ser_sel,
    .cs_ser, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .ser_rdata, .ser_rxrdy, .ser_txrdy, .txc(pit_out0),
    .ser_rxd, .ser_txd, .ser_rts_n, .ser_dtr_n,
    .tw_rxd, .tw_cts_n, .tw_dsr_n,
    .tw_txd(2'b11), .tw_rts_n(2'b11), .tw_dtr_n(2'b11)
  );

  m20_pic u_pic (
    .clk, .rst_n, .cs_pic, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pic_rdata, .pic_inta_n, .pic_int,
    .ir_fdc(1'b0), .ir_comvi1(1'b0), .ir_comvi2(1'b0), .ir_ser_rxrdy(ser_rxrdy),
    .ir_kbd_rxrdy(1'b0), .ir_ser_txrdy(ser_txrdy), .ir_ppi(1'b0), .ir_sysint(1'b0),
    .cas()
  );

  assign rd_mux = (cs_pic || !pic_inta_n) ? pic_rdata : {8'hFF, cs_pit ? pit_rdata : ser_rdata};

  localparam logic [15:0] DAT = 16'h00C1, CTL = 16'h00C3;

  // Host receiver at 9600 8N1, sampling at bit middles.
  task automatic host_rx(output logic [7:0] b, output logic stop);
    @(negedge ser_txd);
    #(BIT_NS / 2.0);
    check("start bit low at its middle", ser_txd, 0);
    for (int i = 0; i < 8; i++) begin
      #(BIT_NS);
      b[i] = ser_txd;
    end
    #(BIT_NS);
    stop = ser_txd;
  endtask

  task automatic host_tx(input logic [7:0] b);
    ser_rxd = 1'b0;
    #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      ser_rxd = b[i];
      #(BIT_NS);
    end
    ser_rxd = 1'b1;
    #(BIT_NS);
  endtask

  // Host receiver at 4800 8N2: both stop bits must be marking.
  task automatic host_rx2(output logic [7:0] b, output logic [1:0] stop);
    @(negedge ser_txd);
    #(B48_NS / 2.0);
    check("4800 start bit low at its middle", ser_txd, 0);
    for (int i = 0; i < 8; i++) begin
      #(B48_NS);
      b[i] = ser_txd;
    end
    #(B48_NS);
    stop[0] = ser_txd;
    #(B48_NS);
    stop[1] = ser_txd;
  endtask

  localparam int NMSG = 5;
  localparam logic [7:0] MSG [NMSG] = '{8'h4F, 8'h4C, 8'h49, 8'h0D, 8'h0A};
  int  tx_next = 0, n_irq = 0;
  bit  isr_on = 0;

  // OLITERM's IR5 handler: INTA, status, data or TxEN off, EOI.
  task automatic isr_ir5();
    logic [15:0] id, lw;
    logic [7:0]  s;
    inta_cycle(id, lw);
    check("IR5 identifier (vector 5)", lw, 16'hFE0A);
    io_read8(CTL, s);
    if (s[0]) begin
      if (tx_next < NMSG) begin
        io_write(DAT, {8'h00, MSG[tx_next]});
        tx_next++;
      end else begin
        io_write(CTL, 16'h0026);             // TxEN off, DTR RxE RTS kept
      end
    end
    io_write(16'h0140, 16'hCACA);            // specific EOI IR5
    n_irq++;
  endtask

  // The handler runs while isr_on; the main thread leaves the bus alone.
  initial forever begin
    @(posedge clk);
    if (isr_on && pic_int) isr_ir5();
  end

  realtime t_fall, t_rise;
  logic [7:0] st, rx;
  logic [7:0] got;
  logic       stop;

  initial begin
    reset_dut();
    check("ser_txd marking after reset", ser_txd, 1);

    // 8253 counter 0: LSB/MSB, mode 3, count 8
    io_write(16'h0127, 16'h0036);
    io_write(16'h0121, 16'h0008);
    io_write(16'h0121, 16'h0000);

    // ROM set-up: 0,0,0,0x40, mode 0x4E (x16, 8 bits, no parity, 1 stop),
    // command 0x37 (TxEN, DTR, RxE, ER, RTS)
    io_write(CTL, 16'h0000);
    io_write(CTL, 16'h0000);
    io_write(CTL, 16'h0000);
    io_write(CTL, 16'h0040);
    io_write(CTL, 16'h004E);
    io_write(CTL, 16'h0037);
    io_read8(CTL, st);
    check("status: TxRDY, TxEMPTY, DSR", st, 8'h85);
    check("RTS out asserted", ser_rts_n, 0);
    check("DTR out asserted", ser_dtr_n, 0);

    // start bit length from 0x55 (bit 0 = 1)
    fork
      io_write(DAT, 16'h0055);
      begin
        @(negedge ser_txd); t_fall = $realtime;
        @(posedge ser_txd); t_rise = $realtime;
      end
    join
    check_range("start bit ns", longint'(t_rise - t_fall),
                longint'(BIT_NS * 0.98), longint'(BIT_NS * 1.02));
    wait (ser_txd);
    #(BIT_NS * 10.0);

    for (int i = 0; i < 4; i++) begin
      logic [7:0] tx;
      tx = (i == 0) ? 8'h41 : (i == 1) ? 8'hA3 : (i == 2) ? 8'h0D : 8'h00;
      fork
        io_write(DAT, {8'h00, tx});
        host_rx(got, stop);
      join
      check($sformatf("host got byte %0d", i), got, tx);
      check($sformatf("stop bit %0d", i), stop, 1);
    end

    // host -> M20
    host_tx(8'h5A);
    clocks(100);
    check("RxRDY after host frame", ser_rxrdy, 1);
    io_read8(DAT, rx);
    check("M20 read host byte", rx, 8'h5A);

    // twin A picked with the card out: UART idle, U131 sees a marking line
    ser_sel = 2'd1;
    clocks(10);
    check("twin A without card: ser_txd idle", ser_txd, 1);
    check("twin lines: CTS/DSR asserted", {tw_cts_n, tw_dsr_n}, 4'b0000);

    // ---- OLITERM at 4800 8N2, interrupt-driven
    ser_sel = 2'd0;
    // ROM 8259 set-up, then the driver's EOIs for IR5 and IR3
    io_write(16'h0140, 16'h0022);
    io_write(16'h0142, 16'h0000);
    io_write(16'h0142, 16'h010C);
    io_write(16'h0142, 16'h0022);
    io_write(16'h0140, 16'h018A);
    io_write(16'h0142, 16'h01CE);
    io_write(16'h0140, 16'hCACA);
    io_write(16'h0140, 16'hC6C6);
    io_write(CTL, 16'h0000);
    io_write(CTL, 16'h0000);
    io_write(CTL, 16'h0000);
    io_write(CTL, 16'h0040);
    io_write(16'h0127, 16'h0036);            // counter 0: count 16 (4800 x16)
    io_write(16'h0121, 16'h0010);
    io_write(16'h0121, 16'h0000);
    io_write(CTL, 16'h00CE);                 // x16, 8 bits, no parity, 2 stop
    io_write(CTL, 16'h0000);
    io_read8(DAT, rx);
    io_read8(CTL, st);
    check("cmd 0x00: status TxRDY ignores TxEN (0x85)", st, 8'h85);
    check("cmd 0x00: TxRDY pin low", ser_txrdy, 0);
    io_write(16'h0142, 16'hFF8F);            // IMR 0xC7: IR3, IR4, IR5
    io_write(CTL, 16'h0022);                 // RTS, DTR
    io_write(CTL, 16'h0026);                 // + RxE
    clocks(200);
    check("no INT before TxEN", pic_int, 0);
    check("TxD marking before TxEN", ser_txd, 1);

    isr_on = 1;
    fork
      io_write(CTL, 16'h0027);               // TxEN
      for (int i = 0; i < NMSG; i++) begin
        logic [1:0] st2;
        host_rx2(got, st2);
        check($sformatf("OLITERM byte %0d", i), got, MSG[i]);
        check($sformatf("OLITERM stop bits %0d", i), st2, 2'b11);
      end
    join
    wait (n_irq == NMSG + 1);
    #(B48_NS * 2.0);                         // last stop bit out
    isr_on = 0;
    check("OLITERM: TxRDY pin low after TxEN off", ser_txrdy, 0);
    check("OLITERM: no INT pending", pic_int, 0);
    io_read8(CTL, st);
    check("OLITERM: status TxRDY, TxEMPTY, DSR", st, 8'h85);

    // byte written with TxEN off waits; TxEN sends it
    io_write(DAT, 16'h0033);
    #(B48_NS * 3.0);
    check("TxEN off: line held marking", ser_txd, 1);
    io_read8(CTL, st);
    check("TxEN off with data: TxRDY, TxEMPTY clear", st[2:0], 3'b000);
    fork
      io_write(CTL, 16'h0026 | 16'h0001);
      begin
        logic [1:0] st2;
        host_rx2(got, st2);
        check("pending byte sent on TxEN", got, 8'h33);
        check("pending byte stop bits", st2, 2'b11);
      end
    join

    // SBRK holds TxD low (space); clearing it returns to marking
    wait (dut.u_ser_usart.txempty);
    io_write(CTL, 16'h002F);
    clocks(10);
    check("SBRK: TxD space", ser_txd, 0);
    io_write(CTL, 16'h0027);
    clocks(10);
    check("SBRK off: TxD marking", ser_txd, 1);

    // internal reset mid-character, new mode, transmit again
    io_write(DAT, 16'h00C3);
    @(negedge ser_txd);
    #(B48_NS * 3.0);
    io_write(CTL, 16'h0040);
    clocks(10);
    check("IR mid-character: TxD marking", ser_txd, 1);
    io_write(CTL, 16'h00CE);
    io_write(CTL, 16'h0027);
    fork
      io_write(DAT, 16'h005A);
      begin
        logic [1:0] st2;
        host_rx2(got, st2);
        check("after IR: byte", got, 8'h5A);
        check("after IR: stop bits", st2, 2'b11);
      end
    join

    finish();
  end

  initial begin
    #(BIT_NS * 1500.0);
    $fatal(1, "timeout: TxD stalled (%0d of %0d checks failed so far)", errors, checks);
  end

  logic unused_tb;
  assign unused_tb = &{1'b0, pit_out1, pit_out2, tw_rxd};

endmodule
`default_nettype wire
