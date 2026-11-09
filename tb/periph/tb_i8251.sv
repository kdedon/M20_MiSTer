// i8251 against the 8251A data sheet and the boot ROM: the ROM's
// 0,0,0,0x40 / 0xCE / 0x27 set-up from reset and from command state,
// status 0x05 after command 0x37, then frames on TxD (start/stop bit
// lengths for 1, 1.5 and 2 stops), loopback in x1/x16/x64, 5-bit chars,
// parity, framing, overrun, break detect, CTS gating and SBRK.
// TxC = RxC is a square wave of 8 ce_pit (the RS-232 rate, 9615 baud x16).
`timescale 1ns/1ps
`default_nettype none
module tb_i8251;
  `include "tb_io.svh"

  localparam int TC = 8 * 39;              // TxC/RxC period in clk

  logic [7:0] rdata;
  logic       txc = 1'b1;
  logic       txd, rxd, dtr_n, rts_n, txrdy, rxrdy, txempty, syndet;
  logic       cts_n = 1'b0, dsr_n = 1'b1;
  logic       loop = 1'b1, tb_rxd = 1'b1;

  int tcnt = 0;
  always @(posedge clk) begin
    if (tcnt == TC / 2 - 1) begin
      tcnt <= 0;
      txc  <= ~txc;
    end else begin
      tcnt <= tcnt + 1;
    end
  end

  assign rxd = loop ? txd : tb_rxd;

  i8251 dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .ce_usart  (ce_usart),
    .cs        (cs_ser),
    .io_rd     (io_rd),
    .io_wr     (io_wr),
    .io_rd_end (io_rd_end),
    .io_wr_end (io_wr_end),
    .io_addr   (io_addr),
    .io_wdata  (io_wdata),
    .rdata     (rdata),
    .txc       (txc),
    .rxc       (txc),
    .rxd       (rxd),
    .txd       (txd),
    .cts_n     (cts_n),
    .dsr_n     (dsr_n),
    .dtr_n     (dtr_n),
    .rts_n     (rts_n),
    .txrdy     (txrdy),
    .rxrdy     (rxrdy),
    .txempty   (txempty),
    .syndet    (syndet)
  );

  assign rd_mux = {8'hFF, rdata};

  localparam logic [15:0] DAT = 16'h00C1, CTL = 16'h00C3;

  logic [7:0] b;

  task automatic ctl(input logic [7:0] v);
    io_write(CTL, {8'h00, v});
  endtask

  task automatic status(output logic [7:0] s);
    io_read8(CTL, s);
  endtask

  // ROM ini_tests_ok sequence for one chip.
  task automatic rom_init();
    ctl(8'h00); ctl(8'h00); ctl(8'h00);
    ctl(8'h40);
    ctl(8'hCE);
    ctl(8'h27);
    io_read8(DAT, b);
  endtask

  task automatic wait_rxrdy(input int frames, input int bitlen);
    longint t0 = cyc;
    while (!rxrdy && cyc - t0 < longint'(frames) * 12 * bitlen * TC) @(posedge clk);
  endtask

  // Send one byte by loopback and read it back; check status on the way.
  task automatic loop_byte(input logic [7:0] v, input logic [7:0] exp, input int bitlen, input string what);
    logic [7:0] s;
    io_write(DAT, {8'h00, v});
    wait_rxrdy(2, bitlen);
    check({what, " RxRDY pin"}, rxrdy, 1);
    status(s);
    check({what, " RxRDY status"}, s[1], 1);
    io_read8(DAT, b);
    check({what, " data"}, b, exp);
    status(s);
    check({what, " RxRDY cleared by data read"}, s[1], 0);
    check({what, " no PE/OE/FE"}, s[5:3], 3'b000);
  endtask

  // Frame length on TxD: falling edge to falling edge of two back-to-back
  // 0xFF characters, and the start bit length.
  task automatic frame_len(output longint frame, output longint start);
    longint t0, t1, t2;
    fork
      begin
        @(negedge txd); t0 = cyc;
        @(posedge txd); t1 = cyc;
        @(negedge txd); t2 = cyc;
      end
      begin
        io_write(DAT, 16'h00FF);
        wait (!txd);                       // shifter has the first
        io_write(DAT, 16'h00FF);
      end
    join
    frame = t2 - t0;
    start = t1 - t0;
    wait (txempty);
    clocks(TC * 16);
    io_read8(DAT, b);
    status(b);
    ctl(8'h37);                            // clear the overrun
  endtask

  // Drive one frame on tb_rxd (x16, 8 data, LSB first).
  task automatic send_frame(input logic [7:0] v, input logic par_en, input logic par, input logic stop);
    tb_rxd <= 1'b0; clocks(16 * TC);
    for (int i = 0; i < 8; i++) begin tb_rxd <= v[i]; clocks(16 * TC); end
    if (par_en) begin tb_rxd <= par; clocks(16 * TC); end
    tb_rxd <= stop; clocks(16 * TC);
    tb_rxd <= 1'b1; clocks(16 * TC);
  endtask

  logic [7:0] s;
  longint fr, st;

  initial begin
    reset_dut();

    // ---- from hardware reset (mode state).
    $display("[%0t] App. D #8, #19: from hardware reset (mode state).", $time);
    check("TxD marking after reset", txd, 1);
    rom_init();
    check("DTR after 0x27", dtr_n, 0);
    check("RTS after 0x27", rts_n, 0);
    ctl(8'h37);
    status(s);
    check("EC4: status & 0x7D == 0x05", s & 8'h7D, 8'h05);
    // Dummy data read, then status & 0x7F == 0x05.
    io_read8(DAT, b);
    status(s);
    check("EC5: status & 0x7F == 0x05", s & 8'h7F, 8'h05);
    check("DSR bit (DSR inactive)", s[7], 0);
    dsr_n <= 1'b0;
    clocks(2);
    status(s);
    check("DSR bit (DSR active)", s[7], 1);
    dsr_n <= 1'b1;
    check("TxRDY pin", txrdy, 1);
    check("TxEMPTY pin", txempty, 1);

    // ---- loopback 8N2 x16
    $display("[%0t] loopback 8N2 x16", $time);
    loop_byte(8'h55, 8'h55, 16, "8N2 0x55");
    loop_byte(8'hA3, 8'hA3, 16, "8N2 0xA3");
    loop_byte(8'h00, 8'h00, 16, "8N2 0x00");
    loop_byte(8'hFF, 8'hFF, 16, "8N2 0xFF");

    // TxRDY / TxEMPTY across one character.
    io_write(DAT, 16'h0042);
    check("TxEMPTY low with data", txempty, 0);
    wait (!txd);
    check("TxRDY again once the shifter took it", txrdy, 1);
    check("TxEMPTY low while shifting", txempty, 0);
    wait (txempty);
    io_read8(DAT, b);
    check("0x42", b, 8'h42);

    // ---- stop-bit lengths
    $display("[%0t] stop-bit lengths", $time);
    frame_len(fr, st);
    check("start bit = 16 TxC", st, 16 * TC);
    check("8N2 frame = 11 bits", fr, 11 * 16 * TC);
    ctl(8'h40); ctl(8'h8E); ctl(8'h37);    // 1.5 stops
    frame_len(fr, st);
    check("8N1.5 frame = 10.5 bits", fr, 21 * 8 * TC);
    ctl(8'h40); ctl(8'h4E); ctl(8'h37);    // 1 stop
    frame_len(fr, st);
    check("8N1 frame = 10 bits", fr, 10 * 16 * TC);

    // ---- ROM init from command state (no hardware reset).
    $display("[%0t] ROM init from command state (no hardware reset).", $time);
    rom_init();
    ctl(8'h37);
    status(s);
    check("re-init from command state: status", s & 8'h7F, 8'h05);
    frame_len(fr, st);
    check("re-init gives 8N2 again", fr, 11 * 16 * TC);

    // ---- x64 and x1
    $display("[%0t] x64 and x1", $time);
    ctl(8'h40); ctl(8'hCF); ctl(8'h37);
    loop_byte(8'h3C, 8'h3C, 64, "x64 0x3C");
    ctl(8'h40); ctl(8'hCD); ctl(8'h37);
    loop_byte(8'hC5, 8'hC5, 1, "x1 0xC5");
    frame_len(fr, st);
    check("x1 frame = 11 TxC", fr, 11 * TC);

    // ---- 5-bit characters, 1 stop
    $display("[%0t] 5-bit characters, 1 stop", $time);
    ctl(8'h40); ctl(8'h42); ctl(8'h37);
    loop_byte(8'h1F, 8'h1F, 16, "5-bit 0x1F");
    loop_byte(8'hEA, 8'h0A, 16, "5-bit 0xEA");

    // ---- parity: even (0x7E) and odd (0x5E) loopback
    $display("[%0t] parity: even (0x7E) and odd (0x5E) loopback", $time);
    ctl(8'h40); ctl(8'h7E); ctl(8'h37);
    loop_byte(8'h01, 8'h01, 16, "even parity 0x01");
    loop_byte(8'h03, 8'h03, 16, "even parity 0x03");
    ctl(8'h40); ctl(8'h5E); ctl(8'h37);
    loop_byte(8'h01, 8'h01, 16, "odd parity 0x01");
    loop_byte(8'h03, 8'h03, 16, "odd parity 0x03");

    // ---- errors on a driven line (even parity, 1 stop)
    $display("[%0t] errors on a driven line (even parity, 1 stop)", $time);
    ctl(8'h40); ctl(8'h7E); ctl(8'h37);
    loop <= 1'b0;
    clocks(16 * TC);
    send_frame(8'h01, 1'b1, 1'b0, 1'b1);   // wrong parity bit
    status(s);
    check("PE on bad parity", s[3], 1);
    io_read8(DAT, b);
    check("data with PE", b, 8'h01);
    ctl(8'h37);                            // ER
    status(s);
    check("ER clears PE", s[5:3], 3'b000);
    send_frame(8'h81, 1'b1, 1'b0, 1'b0);   // good parity, stop bit low
    status(s);
    check("FE on low stop bit", s[5], 1);
    check("no PE with good parity", s[3], 0);
    io_read8(DAT, b);
    ctl(8'h37);
    send_frame(8'h11, 1'b1, 1'b0, 1'b1);
    send_frame(8'h22, 1'b1, 1'b0, 1'b1);   // not read in between
    status(s);
    check("OE on second unread char", s[4], 1);
    io_read8(DAT, b);
    check("overrun keeps the newest", b, 8'h22);
    ctl(8'h37);
    status(s);
    check("ER clears OE", s[5:3], 3'b000);

    // ---- break detect: line low for more than two frames
    $display("[%0t] break detect: line low for more than two frames", $time);
    tb_rxd <= 1'b0;
    clocks(3 * 11 * 16 * TC);
    check("BRKDET pin", syndet, 1);
    status(s);
    check("BRKDET status", s[6], 1);
    tb_rxd <= 1'b1;
    clocks(2 * TC);
    check("BRKDET clears with RxD high", syndet, 0);
    clocks(16 * TC);
    io_read8(DAT, b);
    ctl(8'h37);
    loop <= 1'b1;

    // ---- CTS gating: data waits, TxRDY pin low, status bit 0 shows the buffer
    $display("[%0t] CTS gating: data waits, TxRDY pin low, status bit 0 shows the buffer", $time);
    ctl(8'h40); ctl(8'hCE); ctl(8'h37);
    cts_n <= 1'b1;
    clocks(2);
    check("TxRDY pin low with CTS inactive", txrdy, 0);
    io_write(DAT, 16'h005A);
    clocks(40 * TC);
    check("no transmission without CTS", txd, 1);
    status(s);
    check("TxRDY status (buffer full)", s[0], 0);
    cts_n <= 1'b0;
    wait_rxrdy(2, 16);
    io_read8(DAT, b);
    check("sent once CTS active", b, 8'h5A);

    // ---- SBRK and TxEN
    $display("[%0t] SBRK and TxEN", $time);
    ctl(8'h3F);
    clocks(2);
    check("SBRK holds TxD low", txd, 0);
    ctl(8'h36);
    check("TxRDY pin low with TxEN off", txrdy, 0);
    check("TxD marking", txd, 1);
    ctl(8'h37);
    io_read8(DAT, b);
    ctl(8'h37);

    // ---- internal reset: back to mode state, status clean
    $display("[%0t] internal reset: back to mode state, status clean", $time);
    ctl(8'h40);
    status(s);
    check("after IR: status & 0x7F", s & 8'h7F, 8'h05);
    check("after IR: DTR inactive", dtr_n, 1);

    finish();
  end

  initial begin
    #500ms;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
