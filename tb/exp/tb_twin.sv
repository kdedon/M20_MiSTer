// m20_twin with the mainboard 8259 as master: decode (ports, mirrors,
// nothing elsewhere or with the card out), modem status, the 8253 baud
// timer, a byte from channel A to channel B over a crossed cable at
// 9615 baud, and channel B's RxRDY vectoring through the slave on IR7.
`timescale 1ns/1ps
`default_nettype none
module tb_twin;
  `include "tb_io.svh"

  logic        en = 1'b1;
  logic        cs8, cs16, sysint, pic_int;
  logic [7:0]  rdata8;
  logic [15:0] slave_word, master_word, pic_word;
  logic [2:0]  cas;
  logic [1:0]  txd, rts_n, dtr_n;

  m20_twin dut (
    .clk, .rst_n, .en, .ce_pit, .ce_usart,
    .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .cs(cs8), .rdata(rdata8), .cs16, .pic_rdata(slave_word), .pic_inta_n, .cas, .sysint,
    .rxd({txd[0], txd[1]}), .txd, .cts_n(2'b00), .dsr_n(2'b00), .rts_n, .dtr_n
  );

  m20_pic u_master (
    .clk, .rst_n, .cs_pic, .io_rd, .io_wr, .io_rd_end, .io_wr_end, .io_addr, .io_wdata,
    .pic_rdata(master_word), .pic_inta_n, .pic_int,
    .ir_fdc(1'b0), .ir_comvi1(1'b0), .ir_comvi2(1'b0), .ir_ser_rxrdy(1'b0),
    .ir_kbd_rxrdy(1'b0), .ir_ser_txrdy(1'b0), .ir_ppi(1'b0), .ir_sysint(sysint), .cas
  );

  m20_cascade u_casc (
    .clk, .rst_n, .pic_inta_n, .cas, .cs_pic, .master_rdata(master_word),
    .ieee_en(1'b0), .ieee_rdata(16'h0000), .twin_en(en), .twin_rdata(slave_word),
    .pic_rdata(pic_word)
  );

  // Mainboard read mux.
  assign rd_mux = cs16 ? slave_word : cs8 ? {8'hFF, rdata8} : pic_word;

  localparam logic [15:0] DATA = 16'h0801, CTLA = 16'h0803, DATB = 16'h0821, CTLB = 16'h0823;
  localparam logic [15:0] SPIC0 = 16'h0840, SPIC1 = 16'h0842;

  logic [7:0]  b;
  logic [15:0] w, id, lw;

  int n8 = 0, n16 = 0;
  always @(posedge clk) begin
    if (cs8)  n8++;
    if (cs16) n16++;
  end

  task automatic probe(input logic [15:0] a, input bit exp8, input bit exp16, input string what);
    int s8, s16;
    s8 = n8; s16 = n16;
    io_read(a, w);
    check({what, " byte select"}, n8 != s8, exp8);
    check({what, " 8259 select"}, n16 != s16, exp16);
  endtask

  task automatic usart_init(input logic [15:0] ctl);
    io_write(ctl, 16'h0000); io_write(ctl, 16'h0000); io_write(ctl, 16'h0000);
    io_write(ctl, 16'h0040);
    io_write(ctl, 16'h00CE);                       // x16, 8 bits, 2 stops
    io_write(ctl, 16'h0027);                       // TxEN, DTR, RxE, RTS
  endtask

  initial begin
    reset_dut();

    // ---- decode ----
    probe(16'h0801, 1, 0, "0x801");
    probe(16'h0803, 1, 0, "0x803");
    probe(16'h0821, 1, 0, "0x821");
    probe(16'h0823, 1, 0, "0x823");
    probe(16'h0840, 0, 1, "0x840");
    probe(16'h0841, 0, 1, "0x841");
    probe(16'h0843, 0, 1, "0x843");
    probe(16'h0861, 1, 0, "0x861");
    probe(16'h0867, 1, 0, "0x867");
    probe(16'h0881, 1, 0, "0x881");
    probe(16'h0901, 1, 0, "0x901 (A8 mirror)");
    probe(16'h0E41, 0, 1, "0xE41 (A9/A10 mirror)");
    probe(16'h08A1, 0, 0, "0x8A1");
    probe(16'h08E1, 0, 0, "0x8E1");
    probe(16'h1801, 0, 0, "0x1801 (A12)");
    probe(16'h0001, 0, 0, "0x001 (FDC)");
    probe(16'h00C1, 0, 0, "0x0C1 (RS-232)");
    probe(16'h0141, 0, 0, "0x141 (8259)");
    en = 1'b0;
    probe(16'h0801, 0, 0, "0x801 card out");
    probe(16'h0840, 0, 0, "0x840 card out");
    en = 1'b1;

    io_read8(16'h0881, b); check("modem status idle", b, 8'h5F);

    // ---- 8253: counters 0 and 1 mode 3, count 8 ----
    io_write(16'h0867, 16'h0036);
    io_write(16'h0861, 16'h0008);
    io_write(16'h0861, 16'h0000);
    io_write(16'h0867, 16'h0076);
    io_write(16'h0863, 16'h0008);
    io_write(16'h0863, 16'h0000);
    io_write(16'h0867, 16'h00B4);                  // counter 2 mode 2, count 0x1234
    io_write(16'h0865, 16'h0034);
    io_write(16'h0865, 16'h0012);
    clocks(400);
    io_write(16'h0867, 16'h0080);                  // latch counter 2
    io_read8(16'h0865, b);
    begin
      logic [7:0] hi;
      io_read8(16'h0865, hi);
      check_range("counter 2 counts down", {hi, b}, 16'h1000, 16'h1233);
    end

    // ---- interrupts: master as the ROM sets it plus IR7, slave id 7 ----
    io_write(16'h0140, 16'h0022);
    io_write(16'h0142, 16'h0000);
    io_write(16'h0142, 16'h010C);
    io_write(16'h0142, 16'h0022);
    io_write(16'h0142, 16'h00FE);                  // master: IR7 only
    io_write(SPIC0, 16'h0022);
    io_write(SPIC1, 16'h00A0);                     // ICW2 0x50
    io_write(SPIC1, 16'h000E);                     // ICW3 id 7
    io_write(SPIC1, 16'h0002);                     // ICW4 8086
    io_write(SPIC1, 16'h01F6);                     // slave: IR2 (RxRDY B) only
    io_read(SPIC1, w); check("slave IMR readback", w, 16'hFFF7);

    // ---- channel A -> channel B ----
    usart_init(CTLA);
    usart_init(CTLB);
    io_read8(DATB, b);
    io_read8(CTLA, b); check("A status after set-up", b & 8'h07, 8'h05);
    check("no request yet", pic_int, 0);
    io_write(DATA, 16'h005A);
    begin
      int t;
      t = 0;
      while (!sysint && t < 200000) begin @(posedge clk); t++; end
      check_range("clocks to RxRDY (9.5 bits at 9615 baud x16)", t, 45000, 50000);
    end
    io_read8(CTLB, b); check("B RxRDY", b[1], 1'b1);
    clocks(4);
    check("master INT", pic_int, 1);
    inta_cycle(id, lw);
    check("identifier from the slave", id, {7'h7F, 8'h52, 1'b0});
    check("identifier while /INTA low", lw, {7'h7F, 8'h52, 1'b0});
    io_read8(DATB, b); check("B received byte", b, 8'h5A);
    io_read8(CTLB, b); check("B RxRDY cleared", b[1], 1'b0);
    io_write(SPIC0, 16'h00C4);                     // specific EOI IR2
    io_write(16'h0140, 16'h00CE);                  // specific EOI IR7
    io_write(SPIC0, 16'h0016);
    io_read(SPIC0, w); check("slave ISR after EOI", w[8:1], 8'h00);
    check("SYSINT idle", sysint, 0);

    // Card out: requests stay off the master.
    en = 1'b0;
    clocks(4);
    check("no SYSINT with the card out", sysint, 0);

    finish();
  end
endmodule
`default_nettype wire
