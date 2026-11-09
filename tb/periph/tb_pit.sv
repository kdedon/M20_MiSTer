// m20_pit: the boot ROM's counter set-up, the EC3 latch test (two latched
// reads 0x16..0x22 apart at the CPU's instruction timing), the count rate
// (one count per ce_pit), and the OUT0/OUT1/OUT2 periods (count 8 and 0x40
// square waves, 20 Hz NVI tick).
`timescale 1ns/1ps
`default_nettype none
module tb_pit;
  `include "tb_io.svh"

  localparam int CE = 39;                  // clk per ce_pit

  logic [7:0] pit_rdata;
  logic       out0, out1, out2;

  m20_pit dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .ce_pit    (ce_pit),
    .cs_pit    (cs_pit),
    .io_rd     (io_rd),
    .io_wr     (io_wr),
    .io_rd_end (io_rd_end),
    .io_wr_end (io_wr_end),
    .io_addr   (io_addr),
    .io_wdata  (io_wdata),
    .pit_rdata (pit_rdata),
    .pit_out0  (out0),
    .pit_out1  (out1),
    .pit_out2  (out2)
  );

  assign rd_mux = {8'hFF, pit_rdata};

  // Z8001 instruction lengths in CPU clocks; the I/O transaction is the
  // last 4 of them.
  localparam int T_OUTB_IR = 10, T_INB_IR = 10, T_NOP = 7, T_LDB = 7;

  task automatic outb(input int t, input logic [15:0] a, input logic [7:0] d);
    cpu(t - 4);
    io_write(a, {8'h00, d});
  endtask

  task automatic inb(input int t, input logic [15:0] a, output logic [7:0] d);
    cpu(t - 4);
    io_read8(a, d);
  endtask

  // ROM do_8253_chk: returns the difference of the two latched counts.
  task automatic do_8253_chk(input logic [15:0] ctr, input logic [7:0] latch, input logic [7:0] ctl,
                             input logic [15:0] cnt, output int diff);
    logic [7:0] l1, h1, l2, h2;
    outb(T_OUTB_IR, 16'h0127, ctl);
    cpu(T_LDB);
    outb(T_OUTB_IR, ctr, 8'hFF);
    outb(T_OUTB_IR, ctr, 8'hFF);
    cpu(T_NOP);
    outb(T_OUTB_IR, 16'h0127, latch);
    cpu(T_NOP);
    inb(T_INB_IR, ctr, l1);
    inb(T_INB_IR, ctr, h1);
    cpu(T_NOP);
    outb(T_OUTB_IR, 16'h0127, latch);
    cpu(T_NOP);
    inb(T_INB_IR, ctr, l2);
    inb(T_INB_IR, ctr, h2);
    outb(T_OUTB_IR, 16'h0127, ctl);
    cpu(T_NOP);
    outb(T_OUTB_IR, ctr, cnt[7:0]);
    outb(T_OUTB_IR, ctr, cnt[15:8]);
    diff = int'({h1, l1}) - int'({h2, l2});
  endtask

  // Period and high time of a counter output, in clk.

  task automatic period_clk(input int which, output longint p, output longint high);
    longint t0, t1, t2;
    logic o;
    do begin @(posedge clk); o = (which == 0) ? out0 : (which == 1) ? out1 : out2; end while (o);
    do begin @(posedge clk); o = (which == 0) ? out0 : (which == 1) ? out1 : out2; end while (!o);
    t0 = cyc;
    do begin @(posedge clk); o = (which == 0) ? out0 : (which == 1) ? out1 : out2; end while (o);
    t1 = cyc;
    do begin @(posedge clk); o = (which == 0) ? out0 : (which == 1) ? out1 : out2; end while (!o);
    t2 = cyc;
    p    = t2 - t0;
    high = t1 - t0;
  endtask

  int d;
  longint p, h;
  logic [7:0] l1, h1, l2, h2;

  initial begin
    reset_dut();

    // Keyboard baud clock.
    io_write(16'h0127, 16'h0076);
    io_write(16'h0123, 16'h0040);
    io_write(16'h0123, 16'h0000);
    // clock_init: ch2 mode 3 LSB/MSB, 0xF062.
    io_write(16'h0127, 16'h00B6);
    io_write(16'h0125, 16'h0062);
    io_write(16'h0125, 16'h00F0);

    // EC3, all three counters as the ROM runs them.
    do_8253_chk(16'h0121, 8'h00, 8'h36, 16'h0008, d);
    $display("EC3 ch0 latch difference 0x%0h", d);
    check_range("EC3 ch0 latch difference", d, 16'h16, 16'h22);
    do_8253_chk(16'h0123, 8'h40, 8'h76, 16'h0040, d);
    $display("EC3 ch1 latch difference 0x%0h", d);
    check_range("EC3 ch1 latch difference", d, 16'h16, 16'h22);
    do_8253_chk(16'h0125, 8'h80, 8'hB6, 16'hF062, d);
    $display("EC3 ch2 latch difference 0x%0h", d);
    check_range("EC3 ch2 latch difference", d, 16'h16, 16'h22);

    // Count rate: mode 2 counts down by one per ce_pit.  Latch commits
    // are 1000 ce_pit apart (each io_write commits 43 clk in, ends 5
    // later; each io_read takes 47).
    io_write(16'h0127, 16'h00B4);          // ch2 mode 2
    io_write(16'h0125, 16'h00FF);
    io_write(16'h0125, 16'h00FF);
    clocks(200);
    io_write(16'h0127, 16'h0080);          // latch ch2
    io_read8(16'h0125, l1);
    io_read8(16'h0125, h1);
    clocks(1000 * CE - 142);
    io_write(16'h0127, 16'h0080);
    io_read8(16'h0125, l2);
    io_read8(16'h0125, h2);
    d = int'({h1, l1}) - int'({h2, l2});
    check_range("one count per ce_pit (1000 ce_pit)", d, 999, 1001);

    // A latched value stays put while the counter runs.
    io_write(16'h0127, 16'h0080);
    clocks(100 * CE);
    io_read8(16'h0125, l1);
    io_read8(16'h0125, h1);
    io_write(16'h0127, 16'h0080);
    io_read8(16'h0125, l2);
    io_read8(16'h0125, h2);
    d = int'({h1, l1}) - int'({h2, l2});
    check_range("latch freezes the count", d, 102, 105);

    // ROM values: ch0 count 8, ch1 0x40 (mode 3), ch2 0xF062 (mode 2).
    io_write(16'h0127, 16'h0036);
    io_write(16'h0121, 16'h0008);
    io_write(16'h0121, 16'h0000);
    io_write(16'h0127, 16'h0076);
    io_write(16'h0123, 16'h0040);
    io_write(16'h0123, 16'h0000);
    io_write(16'h0127, 16'h00B4);
    io_write(16'h0125, 16'h0062);
    io_write(16'h0125, 16'h00F0);

    period_clk(0, p, h);
    check("OUT0 period (count 8, 9615 baud x16)", p, 8 * CE);
    check("OUT0 high half", h, 4 * CE);
    period_clk(1, p, h);
    check("OUT1 period (count 0x40, 1202 baud x16)", p, 64 * CE);
    check("OUT1 high half", h, 32 * CE);
    period_clk(2, p, h);
    check("OUT2 period (0xF062, 20.00 Hz)", p, 61538 * CE);
    check("OUT2 high time (low for one clock)", h, 61537 * CE);

    finish();
  end

  initial begin
    #500ms;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
