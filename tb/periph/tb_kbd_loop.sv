// Keyboard path end to end, as the boot ROM drives it: 8253 ch1 (count
// 0x40) clocks the keyboard 8251, whose TxD/RxD run to m20_kbd at 1200
// baud 8N2; RxRDY is IR4 and TxRDY IR5 on the 8259.
//   EK0/EK1: 0x03 -> reply polled within 0x2800 tries, = 0x0F
//   bell:    0x0A twice through send_to_keyb, beep sounds, no reply
//   E11:     0x80 -> reply by interrupt within 0x3000 loops: RxRDY -> IR4
//            -> INT, two-pulse acknowledge gives identifier 0xFE08 (low
//            byte 0x08 = vector 4), vec_int4 reads 0x80 and sends EOI 0xC8
// CPU instruction times are Z8001 clocks (12 clk each).
`timescale 1ns/1ps
`default_nettype none
module tb_kbd_loop;
  `include "tb_io.svh"

  logic [15:0] pic_rdata;
  logic [7:0]  pit_rdata, kbd_rdata;
  logic        pic_int;
  logic        out0, out1, out2;
  logic        m20_txd, kbd_line;
  logic        kbd_txrdy, kbd_rxrdy, kbd_txempty, kbd_syndet, kbd_dtr_n, kbd_rts_n;
  logic        beep, overflow;

  m20_pit u_pit (
    .clk (clk), .rst_n (rst_n), .ce_pit (ce_pit),
    .cs_pit (cs_pit), .io_rd (io_rd), .io_wr (io_wr), .io_rd_end (io_rd_end), .io_wr_end (io_wr_end),
    .io_addr (io_addr), .io_wdata (io_wdata), .pit_rdata (pit_rdata),
    .pit_out0 (out0), .pit_out1 (out1), .pit_out2 (out2)
  );

  i8251 u_kbd_usart (
    .clk (clk), .rst_n (rst_n), .ce_usart (ce_usart),
    .cs (cs_kbd), .io_rd (io_rd), .io_wr (io_wr), .io_rd_end (io_rd_end), .io_wr_end (io_wr_end),
    .io_addr (io_addr), .io_wdata (io_wdata), .rdata (kbd_rdata),
    .txc (out1), .rxc (out1), .rxd (kbd_line), .txd (m20_txd),
    .cts_n (1'b0), .dsr_n (1'b1), .dtr_n (kbd_dtr_n), .rts_n (kbd_rts_n),
    .txrdy (kbd_txrdy), .rxrdy (kbd_rxrdy), .txempty (kbd_txempty), .syndet (kbd_syndet)
  );

  m20_kbd u_kbd (
    .clk (clk), .rst_n (rst_n), .ps2_key (11'd0), .kbd_layout (4'h0),
    .kbd_txd (m20_txd), .kbd_rxd (kbd_line), .beep (beep), .kbd_overflow (overflow)
  );

  m20_pic u_pic (
    .clk (clk), .rst_n (rst_n),
    .cs_pic (cs_pic), .io_rd (io_rd), .io_wr (io_wr), .io_rd_end (io_rd_end), .io_wr_end (io_wr_end),
    .io_addr (io_addr), .io_wdata (io_wdata), .pic_rdata (pic_rdata),
    .pic_inta_n (pic_inta_n), .pic_int (pic_int),
    .ir_fdc (1'b0), .ir_ser_rxrdy (1'b0), .ir_kbd_rxrdy (kbd_rxrdy), .ir_kbd_txrdy (kbd_txrdy),
    .ir_ppi (1'b0)
  );

  always_comb begin
    unique case (io_addr[8:5])
      4'b1010: rd_mux = pic_rdata;
      4'b0101: rd_mux = {8'hFF, kbd_rdata};
      4'b1001: rd_mux = {8'hFF, pit_rdata};
      default: rd_mux = 16'hFFFF;
    endcase
  end

  localparam int T_IO_DA = 12, T_IO_IR = 10, T_LD = 7, T_NOP = 7;

  task automatic outb(input int t, input logic [15:0] a, input logic [7:0] d);
    cpu(t - 4);
    io_write(a, {8'h00, d});
  endtask

  task automatic outw(input int t, input logic [15:0] a, input logic [15:0] d);
    cpu(t - 4);
    io_write(a, d);
  endtask

  task automatic inb(input int t, input logic [15:0] a, output logic [7:0] d);
    cpu(t - 4);
    io_read8(a, d);
  endtask

  // ROM send_to_keyb: poll TxRDY (0xA3 bit 0), then write 0xA1.
  task automatic send_to_keyb(input logic [7:0] v);
    logic [7:0] s;
    do begin
      inb(T_IO_DA, 16'h00A3, s);
      cpu(4 + 6);
    end while (!s[0]);
    outb(T_IO_DA, 16'h00A1, v);
  endtask

  logic [7:0]  s, b;
  logic [15:0] id, lw;
  int          tries;
  logic        got;

  initial begin
    reset_dut();

    // 8253 ch1 mode 3, count 0x40 (and ch0 count 8).
    outb(T_IO_DA, 16'h0127, 8'h76);
    outb(T_IO_DA, 16'h0123, 8'h40);
    outb(T_IO_DA, 16'h0123, 8'h00);
    outb(T_IO_DA, 16'h0127, 8'h36);
    outb(T_IO_DA, 16'h0121, 8'h08);
    outb(T_IO_DA, 16'h0121, 8'h00);

    // 8251: 0, 0, 0, 0x40, 0xCE, 0x27, dummy data read.
    for (int i = 0; i < 3; i++) begin cpu(T_NOP); outb(T_IO_IR, 16'h00A3, 8'h00); end
    cpu(T_LD); cpu(T_NOP); outb(T_IO_IR, 16'h00A3, 8'h40);
    cpu(T_LD); cpu(T_NOP); outb(T_IO_IR, 16'h00A3, 8'hCE);
    cpu(T_LD); cpu(T_NOP); outb(T_IO_IR, 16'h00A3, 8'h27);
    inb(T_IO_DA, 16'h00A1, b);

    // 8259 set-up, OCW1 = 0xEF (IR4 only).
    outw(T_IO_IR, 16'h0140, 16'h0022);
    outw(T_IO_IR, 16'h0142, 16'h0000);
    outw(T_IO_IR, 16'h0142, 16'h010C);
    outw(T_IO_IR, 16'h0142, 16'h0022);
    outw(T_IO_IR, 16'h0140, 16'h018A);
    outw(T_IO_IR, 16'h0142, 16'h01DE);

    // EC4.
    outb(T_IO_DA, 16'h00A3, 8'h37);
    cpu(T_NOP);
    inb(T_IO_DA, 16'h00A3, s);
    check("EC4 status & 0x7D", s & 8'h7D, 8'h05);

    // EK0/EK1: 0x03, poll RxRDY up to 0x2800 times.
    inb(T_IO_DA, 16'h00A3, s);
    if (s[1]) inb(T_IO_DA, 16'h00A1, b);
    outb(T_IO_DA, 16'h00A1, 8'h03);
    tries = 0;
    got = 1'b0;
    while (tries < 16'h2800 && !got) begin
      tries++;
      cpu(4 + 6);
      inb(T_IO_DA, 16'h00A3, s);
      cpu(4 + 6);
      got = s[1];
    end
    check("EK0: reply within 0x2800 polls", got, 1);
    $display("0x03 reply after %0d polls", tries);
    inb(T_IO_DA, 16'h00A1, b);
    check("EK1: reply 0x0F", b, 8'h0F);
    check("reply is not the loopback code 0x03", b == 8'h03, 0);
    check("low nibble nonzero (self-test OK)", b[3:0] != 4'h0, 1);
    check("layout nibble 0 (Italian)", b[7:4], 4'h0);
    clocks(8);
    check("polled reply leaves no INT pending", pic_int, 0);

    // Bell twice; no reply comes back.
    for (int i = 0; i < 2; i++) begin
      cpu(1000);                           // ROM: djnz delay (shortened)
      send_to_keyb(8'h0A);
      tries = 0;
      while (!beep && tries < 30 * 48_000) begin @(posedge clk); tries++; end
      check("bell sounds after 0x0A", beep, 1);
    end
    clocks(30 * 48_000);
    inb(T_IO_DA, 16'h00A3, s);
    check("no reply to 0x0A", s[1], 0);
    check("no INT after the bells", pic_int, 0);

    // E11: 0x80, `ei vi`, wait up to 0x3000 loops for vec_int4.
    send_to_keyb(8'h80);
    tries = 0;
    got = 1'b0;
    b = 8'h00;                             // clrb rl0
    while (tries < 16'h3000 && b != 8'h80) begin
      tries++;
      cpu(7 + 11);                         // cpb rl0,#0x80 ; djnz
      if (pic_int) begin
        check("IR4 source: keyboard RxRDY", kbd_rxrdy, 1);
        io_addr = 16'h0140;
        inta_cycle(id, lw);
        check("identifier word (vector 4 on AD1-AD8, AD0 = 0)", id, 16'hFE08);
        check("identifier low byte", id[7:0], 8'h08);
        check("INT released by the acknowledge", pic_int, 0);
        // vec_int4
        inb(T_IO_DA, 16'h00A1, b);
        cpu(T_LD);
        outw(T_IO_DA, 16'h0140, 16'h00C8);
        cpu(13);                           // iret
        got = 1'b1;
      end
    end
    check("E11: VI taken", got, 1);
    check("E11: vec_int4 read 0x80", b, 8'h80);
    $display("0x80 interrupt after %0d loops", tries);
    check("RxRDY cleared by vec_int4", kbd_rxrdy, 0);
    check("INT idle after EOI", pic_int, 0);
    io_write(16'h0140, 16'h0016);          // OCW3: read ISR
    io_read(16'h0140, id);
    check("ISR clear after EOI 0xC8", id[8:1], 8'h00);
    check("no FIFO overflow", overflow, 0);

    finish();
  end

  initial begin
    #1s;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
