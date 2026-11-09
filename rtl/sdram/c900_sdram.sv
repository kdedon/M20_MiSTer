// DRAM port on the MiSTer SDRAM: request and refresh scheduling for the
// single-port controller (sdram) on clk_ram = 2 x clk, rising edges aligned.
//
// Read timing, 48 MHz clocks from the clock S at which the request is first
// seen (rd High in the clock before edge S):
//   S        request registered here (address, data, byte enables)
//   S + 0.5  controller ACTIVE (it samples at every clk_ram edge)
//   S + 1.5  READ, CL 2
//   S + 3    controller ready, word in its DQ register
//   S + 3.5  word held here (rhold_q)
//   S + 4    ack, word on rdata for the whole ack clock
// Fixed while the controller is idle on arrival.  A refresh holds it for
// 4 clocks and starts only in a refresh_ok or ack clock, so a request seen
// 4+ clocks later is on time (earlier: up to 3 clocks late).  With
// refresh_ok in one of any 8 idle clocks, a refresh starts within 13
// clocks of falling due.
//
// rd or wr is a level held with addr, be, wdata until ack (one-clock
// pulse); rd/wr in the ack clock are ignored; wr wins.  rvalid is High in
// the ack clock of a read.  Nothing is accepted before ready.
`default_nettype none
module c900_sdram #(
  parameter int unsigned REFRESH_CYCLES = 336,  // 7.0 us at 48 MHz
  parameter int unsigned INIT_CYCLES    = 12116 // clk_ram clocks: controller power-up is 12100
) (
  input  logic        clk,
  input  logic        clk_ram,
  input  logic        rst_n,       // clk domain
  input  logic        rst_ram_n,   // clk_ram domain
  input  logic        refresh_ok,
  output logic        ready,
  input  logic [23:1] addr,
  input  logic        rd,
  input  logic        wr,
  input  logic [1:0]  be,          // be[1] = D15:D8
  input  logic [15:0] wdata,
  output logic [15:0] rdata,
  output logic        rvalid,
  output logic        ack,
  output logic        sdram_clk,
  output logic        sdram_cke,
  output logic [12:0] sdram_a,
  output logic [1:0]  sdram_ba,
  inout  wire  [15:0] sdram_dq,
  output logic        sdram_dqml,
  output logic        sdram_dqmh,
  output logic        sdram_ncs,
  output logic        sdram_nras,
  output logic        sdram_ncas,
  output logic        sdram_nwe
);
  localparam int unsigned RW = $clog2(REFRESH_CYCLES);
  localparam int unsigned IW = $clog2(INIT_CYCLES + 1);

  // ------------------------------------------------------------- clk side
  logic        pend_q, ack_q, we_q, req_t, ref_t, done_s;
  logic [23:1] addr_q;
  logic [1:0]  be_q;
  logic [15:0] wdata_q, rdata_q;
  logic        ready_s;
  logic        ref_due_q;
  logic [RW-1:0] ref_cnt_q;

  // clk_ram side, read here
  logic        done_t;
  logic [15:0] rhold_q;
  logic        init_ok_q;

  logic start, done, ref_go;
  assign start  = (rd || wr) && ready_s && !pend_q && !ack_q;
  assign done   = pend_q && (done_t != done_s);
  assign ref_go = ref_due_q && ready_s && !pend_q && !start && (refresh_ok || ack_q);

  always_ff @(posedge clk) begin
    if (!rst_n) ready_s <= 1'b0;
    else        ready_s <= init_ok_q;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pend_q <= 1'b0;
      ack_q  <= 1'b0;
      req_t  <= 1'b0;
      done_s <= 1'b0;
    end else begin
      ack_q <= done;
      if (start) begin
        pend_q <= 1'b1;
        req_t  <= ~req_t;
      end else if (done) begin
        pend_q <= 1'b0;
        done_s <= done_t;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (start) begin
      we_q    <= wr;
      addr_q  <= addr;
      be_q    <= wr ? be : 2'b11;
      wdata_q <= wdata;
    end
    if (done) rdata_q <= rhold_q;
  end

  // Refresh timer: one refresh (both chips) per REFRESH_CYCLES, the first
  // as soon as the controller is ready.
  always_ff @(posedge clk) begin
    if (!rst_n || !ready_s) begin
      ref_cnt_q  <= RW'(REFRESH_CYCLES - 1);
      ref_due_q  <= 1'b1;
      ref_t      <= 1'b0;
    end else begin
      ref_cnt_q <= (ref_cnt_q == '0) ? RW'(REFRESH_CYCLES - 1) : ref_cnt_q - RW'(1);
      if (ref_go) begin
        ref_due_q <= 1'b0;
        ref_t     <= ~ref_t;
      end else if (ref_cnt_q == '0) ref_due_q <= 1'b1;
    end
  end

  assign ready  = ready_s;
  assign ack    = ack_q;
  assign rvalid = ack_q && !we_q;
  assign rdata  = rdata_q;

  // --------------------------------------------------------- clk_ram side
  logic        req_s, acc_q, c_ready, c_ready_q;
  logic [15:0] c_dout;
  logic [IW-1:0] init_cnt_q;
  logic        pend_r;
  assign pend_r = (req_t != req_s);

  // Accepted when the controller drops ready (its ACTIVE); complete when it
  // raises it again (WRITE issued, or the read word in its DQ register).
  always_ff @(posedge clk_ram) begin
    if (!rst_ram_n) begin
      req_s     <= 1'b0;
      acc_q     <= 1'b0;
      done_t    <= 1'b0;
      c_ready_q <= 1'b0;
    end else begin
      c_ready_q <= c_ready;
      if (pend_r && !acc_q && c_ready_q && !c_ready) acc_q <= 1'b1;
      if (acc_q && c_ready && !c_ready_q) begin
        acc_q  <= 1'b0;
        req_s  <= req_t;
        done_t <= ~done_t;
      end
    end
  end

  always_ff @(posedge clk_ram)
    if (acc_q && c_ready && !c_ready_q) rhold_q <= c_dout;

  always_ff @(posedge clk_ram) begin
    if (!rst_ram_n) begin
      init_cnt_q <= '0;
      init_ok_q  <= 1'b0;
    end else begin
      if (init_cnt_q != IW'(INIT_CYCLES)) init_cnt_q <= init_cnt_q + IW'(1);
      else if (c_ready)                   init_ok_q  <= 1'b1;
    end
  end

  logic c_cprd, c_cpbusy, unused_ok;
  assign unused_ok = &{1'b0, c_cprd, c_cpbusy};

  sdram u_ctrl (
    .init(!rst_ram_n),
    .clk(clk_ram),
    .SDRAM_DQ(sdram_dq),
    .SDRAM_A(sdram_a),
    .SDRAM_DQML(sdram_dqml),
    .SDRAM_DQMH(sdram_dqmh),
    .SDRAM_BA(sdram_ba),
    .SDRAM_nCS(sdram_ncs),
    .SDRAM_nWE(sdram_nwe),
    .SDRAM_nRAS(sdram_nras),
    .SDRAM_nCAS(sdram_ncas),
    .SDRAM_CKE(sdram_cke),
    .SDRAM_CLK(sdram_clk),
    .SDRAM_EN(1'b1),
    .sel(1'b1),
    .addr({3'b000, addr_q}),
    .dout(c_dout),
    .din(wdata_q),
    .wr(pend_r && !acc_q && we_q),
    .bs(be_q),
    .rd(pend_r && !acc_q && !we_q),
    .ready(c_ready),
    .refresh(ref_t),
    .cpsel(1'b0),
    .cpaddr(26'h0),
    .cpdin(16'h0000),
    .cprd(c_cprd),
    .cpreq(1'b0),
    .cpbusy(c_cpbusy)
  );
endmodule
`default_nettype wire
