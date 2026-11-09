// DRAM0-3 behind the platform RAM controller, plus the video plane snoop.
// Physical word address = {device[1:0], block[2:0], A13-A1} (512 KB in
// mem_addr[18:1]), device = {TSN2, TSN1}, block = {TSN0, TA15, TA14}.
// A read is requested when /DS falls in a DRAM read cycle, a write when /DS
// falls in a DRAM write cycle (the CAS point, write data on AD since T2).
// Each request is a level held with its address, byte enables and data
// until mem_ack.  Byte enables: be[1] = D15-D8 (even
// byte); a byte write's data is already on both halves.
//
// rd_have: the read word of the current cycle has been captured (cleared
// at the next /AS).  rd_hit: mem_rdata holds it this clock.  wr_busy: a
// write is outstanding.
// The snoop pulses vram_we in the first clock of each write request to
// block 0 of any device (plane n = device n).
`default_nettype none
module m20_dram (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        new_cyc,     // /AS fell
  input  logic        start_rd,
  input  logic        start_wr,
  input  logic [1:0]  dev,
  input  logic [2:0]  blk,
  input  logic [13:1] a,
  input  logic [1:0]  be,
  input  logic [15:0] wdata,
  output logic        rd_have,
  output logic        rd_hit,
  output logic        wr_busy,
  // platform RAM port
  output logic [23:1] mem_addr,
  output logic        mem_rd,
  output logic        mem_wr,
  output logic [1:0]  mem_be,
  output logic [15:0] mem_wdata,
  input  logic        mem_rvalid,
  input  logic        mem_ack,
  // video plane snoop
  output logic        vram_we,
  output logic [1:0]  vram_plane,
  output logic [13:1] vram_addr,
  output logic [1:0]  vram_be,
  output logic [15:0] vram_wdata
);
  // Request level, address, enables, data held to ack.
  logic        rd_q, wr_q;
  logic [18:1] addr_q;
  logic [1:0]  be_q;
  logic [15:0] wdata_q;
  logic        idle;
  assign idle = !rd_q && !wr_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_q <= 1'b0;
      wr_q <= 1'b0;
    end else if (mem_ack) begin
      rd_q <= 1'b0;
      wr_q <= 1'b0;
    end else if (idle) begin
      rd_q <= start_rd;
      wr_q <= start_wr;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      addr_q  <= 18'h0;
      be_q    <= 2'b00;
      wdata_q <= 16'h0000;
    end else if (idle && (start_rd || start_wr)) begin
      addr_q  <= {dev, blk, a};
      be_q    <= start_wr ? be : 2'b11;
      wdata_q <= wdata;
    end
  end

  // The cycle's read word is in.
  always_ff @(posedge clk) begin
    if (!rst_n)                      rd_have <= 1'b0;
    else if (new_cyc)                rd_have <= 1'b0;
    else if (rd_q && mem_rvalid)     rd_have <= 1'b1;
  end
  assign rd_hit  = rd_q && mem_rvalid;
  assign wr_busy = wr_q;

  assign mem_addr  = {5'b00000, addr_q};
  assign mem_rd    = rd_q;
  assign mem_wr    = wr_q;
  assign mem_be    = be_q;
  assign mem_wdata = wdata_q;

  // One-clock snoop pulse with the request's word.
  always_ff @(posedge clk) begin
    if (!rst_n) vram_we <= 1'b0;
    else        vram_we <= idle && start_wr && blk == 3'd0;
  end
  always_ff @(posedge clk) begin
    if (idle && start_wr) begin
      vram_plane <= dev;
      vram_addr  <= a;
      vram_be    <= be;
      vram_wdata <= wdata;
    end
  end
endmodule
`default_nettype wire
