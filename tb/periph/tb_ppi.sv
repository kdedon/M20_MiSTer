// m20_ppi: mode 0xA6 and the boot ROM's bit set/reset words, the EC0
// port A readback (255..1), a port B status the ROM reads as "printer not
// ready", PC3 (INTR A) on IR6, and the PC5 strobe set/reset.
`timescale 1ns/1ps
`default_nettype none
module tb_ppi;
  `include "tb_io.svh"

  logic [7:0] ppi_rdata, ppi_pa, ppi_pc;
  logic       ppi_ir6;

  m20_ppi dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .cs_ppi    (cs_ppi),
    .io_rd     (io_rd),
    .io_wr     (io_wr),
    .io_rd_end (io_rd_end),
    .io_wr_end (io_wr_end),
    .io_addr   (io_addr),
    .io_wdata  (io_wdata),
    .ppi_rdata (ppi_rdata),
    .ppi_pa    (ppi_pa),
    .ppi_pc    (ppi_pc),
    .ppi_ir6   (ppi_ir6)
  );

  assign rd_mux = {8'hFF, ppi_rdata};

  logic [7:0] b;

  initial begin
    reset_dut();

    // Mode, then bit set/reset 0x0D, 0x04, 0x08, 0x0B.
    io_write(16'h0087, 16'h00A6);
    check("IR6 low before INTE A", ppi_ir6, 0);
    io_write(16'h0087, 16'h000D);          // PC6 set: INTE A
    check("INTR A (PC3) with INTE A, /OBF and /ACK high", ppi_ir6, 1);
    io_write(16'h0087, 16'h0004);          // PC2 reset: INTE B
    io_write(16'h0087, 16'h0008);          // PC4 reset
    io_write(16'h0087, 16'h000B);          // PC5 set: strobe idle
    check("PC5 set", ppi_pc[5], 1);

    // EC0: port A write/readback 255..1.
    for (int n = 255; n >= 1; n--) begin
      io_write(16'h0081, 16'(n));
      io_read8(16'h0081, b);
      check("PA readback", b, n);
      check("PA latch output", ppi_pa, n);
    end
    check("INTR A cleared by the PA write (no /ACK)", ppi_ir6, 0);
    check("/OBF A low after PA write", ppi_pc[7], 0);

    // The error path prints only if PB1 = 0 and PB5 = 1.
    io_read8(16'h0083, b);
    check("PB status idle", b, 8'hFF);
    check("printer not ready (ROM test)", (b[1] == 1'b0 && b[5] == 1'b1), 0);
    check("PB6 RING IND inactive", b[6], 1);
    check("PB7 SIGDET inactive", b[7], 1);

    // Strobe pulse as the ROM sends a character: 0x0A then 0x0B.
    io_write(16'h0087, 16'h000A);
    check("PC5 reset (strobe)", ppi_pc[5], 0);
    io_write(16'h0087, 16'h000B);
    check("PC5 set (strobe end)", ppi_pc[5], 1);

    // Port C readback: PC3 output (INTR A = 0), PC5 = 1, PC2 input low.
    io_read8(16'h0085, b);
    check("PC3 read", b[3], 0);
    check("PC5 read", b[5], 1);
    check("PC2 read (/STB B input)", b[2], 0);

    finish();
  end

  initial begin
    #50ms;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
