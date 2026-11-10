// m20_pic: the boot ROM's 8259 set-up, the IMR readback test, the
// two-pulse VI acknowledge (vector n on AD1-AD8, AD0 = 0), specific EOI,
// priority with IR5 lowest, and edge triggering.
`timescale 1ns/1ps
`default_nettype none
module tb_pic;
  `include "tb_io.svh"

  logic [15:0] pic_rdata;
  logic        pic_int;
  logic        ir_fdc = 1'b0, ir_ser = 1'b0, ir_kbd_rx = 1'b0, ir_kbd_tx = 1'b0, ir_ppi = 1'b0;

  m20_pic dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .cs_pic       (cs_pic),
    .io_rd        (io_rd),
    .io_wr        (io_wr),
    .io_rd_end    (io_rd_end),
    .io_wr_end    (io_wr_end),
    .io_addr      (io_addr),
    .io_wdata     (io_wdata),
    .pic_rdata    (pic_rdata),
    .pic_inta_n   (pic_inta_n),
    .pic_int      (pic_int),
    .ir_fdc       (ir_fdc),
    .ir_comvi1    (1'b0),
    .ir_comvi2    (1'b0),
    .ir_ser_rxrdy (ir_ser),
    .ir_kbd_rxrdy (ir_kbd_rx),
    .ir_kbd_txrdy (ir_kbd_tx),
    .ir_ppi       (ir_ppi),
    .ir_sysint    (1'b0),
    .cas          ()
  );

  assign rd_mux = pic_rdata;

  // Expected identifier word for vector n (ICW2 = 0): {7'h7F, n, 1'b0}.
  function automatic logic [15:0] ident(input int n);
    return {7'h7F, 8'(n), 1'b0};
  endfunction

  task automatic ack(input int n, input string what);
    logic [15:0] id, lw;
    inta_cycle(id, lw);
    check({what, " identifier at /DS rise"}, id, ident(n));
    check({what, " identifier while /INTA low"}, lw, ident(n));
    check({what, " identifier low byte"}, id[7:0], 2 * n);
  endtask

  task automatic read_isr(output logic [7:0] isr);
    logic [15:0] w;
    io_write(16'h0140, 16'h0016);          // OCW3 0x0B: read ISR
    io_read(16'h0140, w);
    isr = w[8:1];
    io_write(16'h0140, 16'h0014);          // OCW3 0x0A: read IRR
  endtask

  logic [15:0] w;
  logic [7:0]  isr;

  initial begin
    reset_dut();

    // ICW1-4, OCW2, OCW1 = 0xEF.
    io_write(16'h0140, 16'h0022);
    io_write(16'h0142, 16'h0000);
    io_write(16'h0142, 16'h010C);
    io_write(16'h0142, 16'h0022);
    io_write(16'h0140, 16'h018A);
    io_write(16'h0142, 16'h01DE);
    io_read(16'h0142, w);
    check("IMR after init", w, 16'hFFDF);  // {7F, EF, 1}
    check("no interrupt after init", pic_int, 0);

    // IMR write/readback 0x000..0x1FE step 2, masked with 0x1FE.
    for (int r3 = 0; r3 < 16'h200; r3 += 2) begin
      io_write(16'h0142, 16'(r3));
      io_read(16'h0142, w);
      check("IMR readback & 0x1FE", w & 16'h01FE, r3);
      check("IMR readback high bits and AD0", w & 16'hFE01, 16'hFE01);
    end
    io_write(16'h0142, 16'h01DE);          // IR4 only

    // Masked request: no interrupt.
    ir_ser <= 1'b1;
    clocks(20);
    check("IR3 masked", pic_int, 0);
    ir_ser <= 1'b0;

    // Keyboard RxRDY -> IR4 -> VI -> identifier 0x0008.
    ir_kbd_rx <= 1'b1;
    clocks(4);
    check("IR4 raises INT", pic_int, 1);
    ack(4, "IR4");
    check("INT drops after acknowledge", pic_int, 0);
    read_isr(isr);
    check("ISR during service", isr, 8'h10);
    ir_kbd_rx <= 1'b0;                     // handler reads 0xA1
    io_write(16'h0140, 16'h00C8);          // specific EOI IR4
    read_isr(isr);
    check("ISR after EOI", isr, 8'h00);

    // Edge trigger: a level held high does not re-request.
    ir_kbd_rx <= 1'b1;
    clocks(4);
    check("second edge raises INT", pic_int, 1);
    ack(4, "IR4 again");
    io_write(16'h0140, 16'h00C8);
    clocks(20);
    check("held level gives no new request", pic_int, 0);
    ir_kbd_rx <= 1'b0;

    // The keyboard's 0x0F reply raises IR4 with VI off and
    // is polled away; INT must drop, so a later VI is not a stale IR7.
    clocks(4);
    ir_kbd_rx <= 1'b1;
    clocks(4);
    check("polled reply raises INT", pic_int, 1);
    ir_kbd_rx <= 1'b0;
    clocks(4);
    check("INT drops when the request is withdrawn", pic_int, 0);
    ir_kbd_rx <= 1'b1;
    clocks(4);
    io_write(16'h0142, 16'h01FE);          // mask IR4
    check("INT drops when masked", pic_int, 0);
    io_write(16'h0142, 16'h01DE);          // unmask: still pending (edge seen)
    check("INT back on unmask", pic_int, 1);
    ack(4, "IR4 after unmask");
    io_write(16'h0140, 16'h00C8);
    ir_kbd_rx <= 1'b0;

    // Priority (OCW2 bottom = IR5): IR3 before IR4; then IR6 above IR0.
    io_write(16'h0142, 16'h01CE);          // IR3 + IR4
    ir_ser    <= 1'b1;
    ir_kbd_rx <= 1'b1;
    clocks(4);
    check("IR3+IR4 INT", pic_int, 1);
    ack(3, "IR3 first");
    check("IR4 waits behind IR3 in service", pic_int, 0);
    io_write(16'h0140, 16'h00C6);          // specific EOI IR3
    clocks(4);
    check("IR4 after EOI IR3", pic_int, 1);
    ack(4, "IR4 second");
    io_write(16'h0140, 16'h00C8);
    ir_ser    <= 1'b0;
    ir_kbd_rx <= 1'b0;

    io_write(16'h0142, 16'h0000);          // all unmasked
    ir_fdc <= 1'b1;
    ir_ppi <= 1'b1;
    clocks(4);
    ack(6, "IR6 above IR0");
    io_write(16'h0140, 16'h00CC);          // specific EOI IR6
    clocks(4);
    ack(0, "IR0");
    io_write(16'h0140, 16'h00C0);
    ir_kbd_tx <= 1'b1;
    clocks(4);
    ack(5, "IR5");
    io_write(16'h0140, 16'h00CA);
    clocks(10);
    check("all serviced", pic_int, 0);

    // Normal reads drive AD0 = 1.
    io_read(16'h0142, w);
    check("IMR read, AD0 floats high", w, 16'hFE01);

    finish();
  end

  initial begin
    #50ms;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
