// m20_kbd: 1200 baud 8N2 frames, the 0x03 / 0x0A / 0x80 commands, make
// codes with the modifier offsets, replies before queued keys, no
// transmission while a host byte is arriving, and FIFO overflow.
`timescale 1ns/1ps
`default_nettype none
module tb_kbd;
  `include "tb_io.svh"

  localparam int BIT = 48_000_000 / 1200;

  logic [10:0] ps2_key = 11'd0;
  logic [3:0]  layout = 4'h0;
  logic        host_txd = 1'b1;          // M20 -> keyboard
  logic        kbd_rxd;                  // keyboard -> M20
  logic        beep, overflow;

  m20_kbd dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .ps2_key      (ps2_key),
    .kbd_layout   (layout),
    .kbd_txd      (host_txd),
    .kbd_rxd      (kbd_rxd),
    .beep         (beep),
    .kbd_overflow (overflow)
  );

  assign rd_mux = 16'hFFFF;

  // ---- host UART receiver: collects bytes, checks start/stop bits.
  logic [7:0] rxq[$];
  longint     rx_start[$];
  initial begin
    forever begin
      logic [7:0] v;
      longint t;
      @(negedge kbd_rxd);
      t = cyc;
      repeat (BIT / 2) @(posedge clk);
      if (kbd_rxd !== 1'b0) begin errors++; $display("FAIL start bit glitch"); end
      for (int i = 0; i < 8; i++) begin repeat (BIT) @(posedge clk); v[i] = kbd_rxd; end
      repeat (BIT) @(posedge clk);
      if (kbd_rxd !== 1'b1) begin errors++; $display("FAIL stop bit 1"); end
      repeat (BIT) @(posedge clk);
      if (kbd_rxd !== 1'b1) begin errors++; $display("FAIL stop bit 2"); end
      rxq.push_back(v);
      rx_start.push_back(t);
    end
  end

  // Host frame, 8N2, LSB first.  Inline waits: this runs beside key(),
  // and Verilator 5.020 shares a task's repeat count between processes.
  task automatic host_send(input logic [7:0] v);
    host_txd <= 1'b0;
    repeat (BIT) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
      host_txd <= v[i];
      repeat (BIT) @(posedge clk);
    end
    host_txd <= 1'b1;
    repeat (2 * BIT) @(posedge clk);
  endtask

  task automatic key(input logic ext, input logic [7:0] code, input logic pressed);
    @(posedge clk);
    ps2_key <= {~ps2_key[10], pressed, ext, code};
    clocks(2000);
  endtask

  task automatic tap(input logic ext, input logic [7:0] code);
    key(ext, code, 1'b1);
    key(ext, code, 1'b0);
  endtask

  // Expect exactly these bytes (and nothing else) within the window.
  task automatic expect_bytes(input string what, input logic [7:0] exp[$], input int frames);
    clocks(frames * 12 * BIT);
    check({what, " byte count"}, rxq.size(), exp.size());
    foreach (exp[i]) begin
      if (rxq.size() == 0) break;
      check({what, " byte"}, rxq.pop_front(), exp[i]);
    end
    rxq.delete();
    rx_start.delete();
  endtask

  longint t0, half;
  int     beep_rises;
  always @(posedge beep) beep_rises++;

  initial begin
    reset_dut();
    check("line idle", kbd_rxd, 1);

    // ---- commands
    host_send(8'h03);
    expect_bytes("0x03 -> 0x0F (Italian, OK)", '{8'h0F}, 2);
    layout <= 4'h3;
    host_send(8'h03);
    expect_bytes("0x03 -> layout nibble", '{8'h3F}, 2);
    layout <= 4'h0;
    host_send(8'h80);
    expect_bytes("0x80 -> 0x80", '{8'h80}, 2);
    host_send(8'h55);
    expect_bytes("unknown command, no reply", '{}, 2);

    // ---- bell: 3100 Hz for 50 ms, no reply
    beep_rises = 0;
    host_send(8'h0A);
    @(posedge beep);
    t0 = cyc;
    @(negedge beep);
    half = cyc - t0;
    clocks(60 * 48_000);
    check_range("bell half period (3100 Hz)", half, 48_000_000 / 6200 - 1, 48_000_000 / 6200 + 1);
    check_range("bell cycles in 50 ms", beep_rises, 154, 156);
    check("bell, line stayed idle", kbd_rxd, 1);
    check("bell off after 50 ms", beep, 0);
    expect_bytes("bell, no reply", '{}, 1);

    // ---- make codes ('D' = 0x05, 'L' = 0x0D)
    tap(1'b0, 8'h23);                      // D
    tap(1'b0, 8'h4B);                      // L
    tap(1'b0, 8'h76);                      // Esc -> RESET 0x00
    tap(1'b0, 8'h1D);                      // W -> w 0x1B
    tap(1'b0, 8'h3A);                      // M -> m 0x2A
    tap(1'b0, 8'h45);                      // 0 -> 0x1C
    tap(1'b0, 8'h29);                      // space 0xC0
    tap(1'b1, 8'h5A);                      // KP Enter -> 00 0xC6
    tap(1'b1, 8'h4A);                      // KP / 0xD3
    tap(1'b0, 8'h04);                      // F3: unmapped
    expect_bytes("make codes", '{8'h05, 8'h0D, 8'h00, 8'h1B, 8'h2A, 8'h1C, 8'hC0, 8'hC6, 8'hD3}, 10);

    // ---- modifiers (offsets mod 256)
    key(1'b0, 8'h12, 1'b1); tap(1'b0, 8'h1C); key(1'b0, 8'h12, 1'b0);   // LShift a -> 0x32
    key(1'b0, 8'h59, 1'b1); tap(1'b0, 8'h7D); key(1'b0, 8'h59, 1'b0);   // RShift KP9 -> 0xFF
    key(1'b0, 8'h14, 1'b1); tap(1'b0, 8'h1C); key(1'b0, 8'h14, 1'b0);   // LCtrl a -> 0x62
    key(1'b1, 8'h14, 1'b1); tap(1'b1, 8'h4A); key(1'b1, 8'h14, 1'b0);   // RCtrl KP/ -> 0x33
    key(1'b0, 8'h0D, 1'b1); tap(1'b0, 8'h1C); key(1'b0, 8'h0D, 1'b0);   // COMMAND a -> 0x92
    key(1'b0, 8'h12, 1'b1); key(1'b0, 8'h59, 1'b1); tap(1'b0, 8'h1C);
    key(1'b0, 8'h59, 1'b0); key(1'b0, 8'h12, 1'b0);                     // both shifts -> 0x32
    key(1'b0, 8'h12, 1'b1); key(1'b0, 8'h14, 1'b1); tap(1'b0, 8'h1C);
    key(1'b0, 8'h14, 1'b0); key(1'b0, 8'h12, 1'b0);                     // shift+ctrl -> 0x02
    tap(1'b0, 8'h1C);                                                   // released: 0x02
    expect_bytes("modifier offsets", '{8'h32, 8'hFF, 8'h62, 8'h33, 8'h92, 8'h32, 8'h02, 8'h02}, 9);

    // ---- half duplex and reply priority: a key pressed while 0x80 arrives
    fork
      host_send(8'h80);
      begin clocks(3 * BIT); tap(1'b0, 8'h23); end
    join
    clocks(1);
    check("nothing sent while the host byte arrives", rxq.size(), 0);
    expect_bytes("reply before key", '{8'h80, 8'h05}, 3);

    // ---- FIFO: 1 in the shifter + 8 queued; the 10th is dropped
    for (int i = 0; i < 10; i++) key(1'b0, 8'h16 + 8'(i == 9 ? 8 : 0), 1'b1);
    check("overflow flag", overflow, 1);
    expect_bytes("9 of 10 rapid keys", '{8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1D}, 10);

    finish();
  end

  initial begin
    #2s;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
