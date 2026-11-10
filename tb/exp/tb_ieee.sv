// m20_ieee with the mainboard 8259 as master: decode (ports, A9/A10
// mirrors, nothing elsewhere or with the card out), the 8291A and 8292
// registers on an empty bus, and the slave 8259 vectoring through IR1.
`timescale 1ns/1ps
`default_nettype none
module tb_ieee;
  `include "tb_io.svh"

  logic        en = 1'b1;
  logic        cs8, cs16, comvi1, pic_int;
  logic [7:0]  rdata8;
  logic [15:0] slave_word, master_word, pic_word;
  logic [2:0]  cas;

  m20_ieee dut (
    .clk, .rst_n, .en, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .cs(cs8), .rdata(rdata8), .cs16, .pic_rdata(slave_word), .pic_inta_n, .cas, .comvi1
  );

  m20_pic u_master (
    .clk, .rst_n, .cs_pic, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pic_rdata(master_word), .pic_inta_n, .pic_int,
    .ir_fdc(1'b0), .ir_comvi1(comvi1), .ir_comvi2(1'b0), .ir_ser_rxrdy(1'b0),
    .ir_kbd_rxrdy(1'b0), .ir_kbd_txrdy(1'b0), .ir_ppi(1'b0), .ir_sysint(1'b0), .cas
  );

  m20_cascade u_casc (
    .clk, .rst_n, .pic_inta_n, .cas, .cs_pic, .master_rdata(master_word),
    .ieee_en(en), .ieee_rdata(slave_word), .twin_en(1'b0), .twin_rdata(16'h0000),
    .pic_rdata(pic_word)
  );

  // Mainboard read mux.
  assign rd_mux = cs16 ? slave_word : cs8 ? {8'hFF, rdata8} : pic_word;

  localparam logic [15:0] CTL0 = 16'h0101, CTL1 = 16'h0103;
  localparam logic [15:0] SPIC0 = 16'h01A0, SPIC1 = 16'h01A2;
  function automatic logic [15:0] tl(input int r);
    return 16'h0161 + 16'(2 * r);
  endfunction

  logic [7:0]  b;
  logic [15:0] w, id, lw;

  // Select clocks seen.
  int n8 = 0, n16 = 0;
  always @(posedge clk) begin
    if (cs8)  n8++;
    if (cs16) n16++;
  end

  // Clocks of a master port access where the word is the master's.
  int n_mstr = 0;
  always @(posedge clk) if (cs_pic && io_rd && pic_word == master_word) n_mstr++;

  task automatic probe(input logic [15:0] a, input bit exp8, input bit exp16, input string what);
    int s8, s16;
    s8 = n8; s16 = n16;
    io_read(a, w);
    check({what, " byte select"}, n8 != s8, exp8);
    check({what, " 8259 select"}, n16 != s16, exp16);
  endtask

  initial begin
    reset_dut();

    // ---- decode ----
    probe(16'h0101, 1, 0, "0x101");
    probe(16'h0103, 1, 0, "0x103");
    probe(16'h0161, 1, 0, "0x161");
    probe(16'h016F, 1, 0, "0x16F");
    probe(16'h01A0, 0, 1, "0x1A0");
    probe(16'h01A2, 0, 1, "0x1A2");
    probe(16'h0301, 1, 0, "0x301 (A9 mirror)");
    probe(16'h05A0, 0, 1, "0x5A0 (A10 mirror)");
    probe(16'h0121, 0, 0, "0x121 (8253)");
    probe(16'h0140, 0, 0, "0x140 (8259)");
    probe(16'h0181, 0, 0, "0x181 (palette)");
    probe(16'h01C1, 0, 0, "0x1C1 (hard disk)");
    probe(16'h0001, 0, 0, "0x001 (FDC)");
    probe(16'h0901, 0, 0, "0x901 (A11)");
    probe(16'h8101, 0, 0, "0x8101 (A15)");
    en = 1'b0;
    probe(16'h0101, 0, 0, "0x101 card out");
    probe(16'h01A0, 0, 0, "0x1A0 card out");
    en = 1'b1;

    // ---- 8291A ----
    io_read8(tl(1), b); check("ISR1 idle", b, 8'h00);
    io_read8(tl(2), b); check("ISR2 idle", b, 8'h00);
    io_read8(tl(4), b); check("address status idle", b, 8'h00);
    io_write(tl(6), 16'h0015);                     // ADR0 = 0x15
    io_write(tl(6), 16'h00E3);                     // ADR1: DT1 DL1, 3
    io_read8(tl(6), b); check("address 0", b, 8'h15);
    io_read8(tl(7), b); check("address 1", b, 8'h63);
    io_write(tl(4), 16'h0080);                     // ton
    io_read8(tl(4), b); check("address status ton", b, 8'h08);
    io_write(tl(4), 16'h0040);                     // lon
    io_read8(tl(4), b); check("address status lon", b, 8'h10);
    io_write(tl(3), 16'h0041);
    io_read8(tl(3), b); check("serial poll status", b, 8'h41);
    io_write(tl(0), 16'h0055);                     // data out, no listener
    io_read8(tl(1), b); check("ISR1 ERR", b, 8'h04);
    io_read8(tl(1), b); check("ISR1 cleared by read", b, 8'h00);
    check("INT masked", dut.tl_int, 0);
    io_write(tl(1), 16'h0004);                     // IMR1 ERR
    io_write(tl(0), 16'h0055);
    check("INT on ERR", dut.tl_int, 1);
    io_read8(tl(2), b); check("ISR2 INT", b, 8'h80);
    io_read8(tl(6), b); check("address 0 INT", b, 8'h95);
    io_read8(tl(1), b); check("ISR1 ERR again", b, 8'h04);
    check("INT cleared", dut.tl_int, 0);
    io_write(tl(5), 16'h0002);                     // chip reset
    io_read8(tl(6), b); check("chip reset clears address 0", b, 8'h00);
    io_read8(tl(3), b); check("chip reset clears serial poll", b, 8'h00);

    // ---- 8292 ----
    io_read8(CTL1, b); check("8292 status idle", b, 8'h20);
    io_read8(CTL0, b); check("8292 data", b, 8'h00);
    io_write(CTL1, 16'h00F5);
    io_read8(CTL1, b); check("8292 TCI after a command", b, 8'h60);
    io_read8(CTL1, b); check("8292 TCI held", b, 8'h60);

    // ---- cascade: master as the ROM sets it, slave id 1, vector base 0x40 ----
    io_write(16'h0140, 16'h0022);
    io_write(16'h0142, 16'h0000);
    io_write(16'h0142, 16'h010C);
    io_write(16'h0142, 16'h0022);
    io_write(16'h0142, 16'h01FA);                  // master: IR1 only
    io_write(SPIC0, 16'h0022);                     // ICW1 cascade, ICW4
    io_write(SPIC1, 16'h0080);                     // ICW2 0x40
    io_write(SPIC1, 16'h0002);                     // ICW3 id 1
    io_write(SPIC1, 16'h0002);                     // ICW4 8086
    io_write(SPIC1, 16'h01FA);                     // slave: IR1 only
    io_read(SPIC1, w); check("slave IMR readback", w, 16'hFFFB);

    // A new command: TCI falls, rises at the end -> IR1 -> COMVI1 -> master IR1.
    io_write(CTL1, 16'h00F5);
    clocks(4);
    check("slave INT on TCI", comvi1, 1);
    check("master INT", pic_int, 1);
    inta_cycle(id, lw);
    check("identifier from the slave", id, {7'h7F, 8'h41, 1'b0});
    check("identifier while /INTA low", lw, {7'h7F, 8'h41, 1'b0});
    check("slave INT drops", comvi1, 0);
    n_mstr = 0;
    io_read(16'h0140, w);
    check("master port read after a slave acknowledge sees the master", n_mstr > 20, 1);
    io_write(SPIC0, 16'h0016);                     // OCW3: read ISR
    io_read(SPIC0, w); check("slave ISR", w[8:1], 8'h02);
    io_write(SPIC0, 16'h00C2);                     // specific EOI IR1
    io_write(16'h0140, 16'h00C2);
    io_read(SPIC0, w); check("slave ISR after EOI", w[8:1], 8'h00);

    // Card out: no request reaches the master.
    en = 1'b0;
    io_write(CTL1, 16'h00F5);
    clocks(4);
    check("no COMVI1 with the card out", comvi1, 0);

    finish();
  end
endmodule
`default_nettype wire
