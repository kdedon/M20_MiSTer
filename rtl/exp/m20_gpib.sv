// IEEE-488 chips of the G0220 card at register level, on an empty bus:
// i8291A talker/listener and i8292 controller.  No device ever answers, so
// nothing on the bus moves; the registers hold, read back and interrupt as
// below, and software probing the card finds it idle.
//
// i8291A (cs_tl), RS2-RS0 = A3-A1:
//   read   0 data in (0x00)   1 ISR1 (cleared by the read)   2 ISR2
//          3 serial poll status   4 address status   5 command pass-through (0x00)
//          6 address 0   7 address 1
//   write  0 data out   1 IMR1   2 IMR2   3 serial poll mode   4 address mode
//          5 auxiliary mode   6 address 0/1   7 EOS
//   ISR1: D2 ERR sets on each data-out write (no listener holds NRFD/NDAC).
//   ISR2: D7 INT; the change bits stay 0.  Address status: D3 TA = ton,
//   D4 LA = lon (address mode D7, D6).  Address 0 read: D7 INT.
//   Auxiliary command 0x02 (chip reset) clears every register.
//   INT = |(ISR1 & IMR1), active high.
//
// i8292 (cs_ctl), A0 = A1:
//   write A0 = 1  command: TCI clears while it is written and sets at its end
//   write A0 = 0  data, ignored
//   read  A0 = 1  interrupt status {SPI, TCI, SYC, 5'b0} (OBF, IBF stay 0)
//   read  A0 = 0  data out, 0x00
//   SYC = 1 (system controller jumper).  Pins: TCI, SPI (0), OBF (0),
//   IBF (0).
//
// Writes commit at io_wr_end.
`default_nettype none
module m20_gpib (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cs_tl,          // 8291A
  input  logic        cs_ctl,         // 8292
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  output logic [7:0]  rdata,
  output logic        tl_int,
  output logic        ctl_tci,
  output logic        ctl_spi,
  output logic        ctl_obf,
  output logic        ctl_ibf
);

  // Write held from the strobe to its commit.
  logic       wr_tl_q, wr_ctl_q;
  logic [2:0] wr_a_q;
  logic [7:0] wr_d_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_tl_q  <= 1'b0;
      wr_ctl_q <= 1'b0;
    end else if (io_wr_end) begin
      wr_tl_q  <= 1'b0;
      wr_ctl_q <= 1'b0;
    end else if (io_wr) begin
      if (cs_tl)  wr_tl_q  <= 1'b1;
      if (cs_ctl) wr_ctl_q <= 1'b1;
    end
  end
  always_ff @(posedge clk) begin
    if ((cs_tl || cs_ctl) && io_wr) begin
      wr_a_q <= io_addr[3:1];
      wr_d_q <= io_wdata[7:0];
    end
  end

  wire tl_wr  = io_wr_end && wr_tl_q;
  wire ctl_wr = io_wr_end && wr_ctl_q;

  // ---- 8291A ----
  // Registers as written (chip reset clears them).
  logic [7:0] imr1_q, imr2_q, spm_q, eos_q;
  logic [1:0] ton_lon_q;              // address mode D7, D6
  logic [6:0] adr0_q, adr1_q;
  logic       err_q;                  // ISR1 D2
  logic       chip_rst;
  assign chip_rst = tl_wr && wr_a_q == 3'd5 && wr_d_q == 8'h02;

  always_ff @(posedge clk) begin
    if (!rst_n || chip_rst) begin
      imr1_q <= 8'h00;
      imr2_q <= 8'h00;
      spm_q  <= 8'h00;
      ton_lon_q <= 2'b00;
      eos_q  <= 8'h00;
      adr0_q <= 7'h00;
      adr1_q <= 7'h00;
    end else if (tl_wr) begin
      unique case (wr_a_q)
        3'd1: imr1_q <= wr_d_q;
        3'd2: imr2_q <= wr_d_q;
        3'd3: spm_q  <= wr_d_q;
        3'd4: ton_lon_q <= wr_d_q[7:6];
        3'd6: if (wr_d_q[7]) adr1_q <= wr_d_q[6:0];
              else           adr0_q <= wr_d_q[6:0];
        3'd7: eos_q  <= wr_d_q;
        default: ;
      endcase
    end
  end

  // ISR1 read: the CPU sees it at the strobe, it clears at the strobe end.
  logic rd_isr1_q;
  always_ff @(posedge clk) begin
    if (!rst_n) rd_isr1_q <= 1'b0;
    else        rd_isr1_q <= cs_tl && io_rd && io_addr[3:1] == 3'd1;
  end
  always_ff @(posedge clk) begin
    if (!rst_n || chip_rst)                err_q <= 1'b0;
    else if (tl_wr && wr_a_q == 3'd0)      err_q <= 1'b1;
    else if (rd_isr1_q && io_rd_end)       err_q <= 1'b0;
  end

  logic [7:0] isr1;
  assign isr1   = {5'b00000, err_q, 2'b00};
  assign tl_int = |(isr1 & imr1_q);

  logic [7:0] tl_rd;
  always_comb begin
    tl_rd = 8'h00;
    unique case (io_addr[3:1])
      3'd0: tl_rd = 8'h00;
      3'd1: tl_rd = isr1;
      3'd2: tl_rd = {tl_int, 7'h00};
      3'd3: tl_rd = spm_q;
      3'd4: tl_rd = {3'b000, ton_lon_q[0], ton_lon_q[1], 3'b000};
      3'd5: tl_rd = 8'h00;
      3'd6: tl_rd = {tl_int, adr0_q};
      3'd7: tl_rd = {1'b0, adr1_q};
      default: ;
    endcase
  end

  // ---- 8292 ----
  // Task complete.
  logic tci_q;
  always_ff @(posedge clk) begin
    if (!rst_n)                                   tci_q <= 1'b0;
    else if (ctl_wr && wr_a_q[0])                 tci_q <= 1'b1;
    else if (cs_ctl && io_wr && io_addr[1])       tci_q <= 1'b0;
  end

  assign ctl_tci = tci_q;
  assign ctl_spi = 1'b0;
  assign ctl_obf = 1'b0;
  assign ctl_ibf = 1'b0;

  logic [7:0] ctl_rd;
  assign ctl_rd = io_addr[1] ? {ctl_spi, tci_q, 1'b1, 3'b000, ctl_ibf, ctl_obf} : 8'h00;

  // Last value driven, still valid in the clock the strobe ends (ISR1 has
  // cleared by then).
  logic [7:0] live, hold_q;
  assign live = cs_ctl ? ctl_rd : tl_rd;
  always_ff @(posedge clk) begin
    if (!rst_n)                       hold_q <= 8'hFF;
    else if ((cs_tl || cs_ctl) && io_rd) hold_q <= live;
  end
  assign rdata = io_rd ? live : hold_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, io_addr[15:4], io_addr[0], io_wdata[15:8], imr2_q, eos_q};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
`default_nettype wire
