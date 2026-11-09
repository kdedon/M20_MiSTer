// Behavioural model of the c900_sdram client port: ready after INIT clocks;
// a request (rd or wr level) is taken when idle, acked BASE clocks later
// plus a refresh delay of 0-4 clocks when a refresh falls due (every
// REFRESH clocks, started only while refresh_ok or with the request).
// rvalid with ack for reads; rdata held until the next read.  The port
// contract (request and payload held until ack) is checked.
// Memory: 256K words (512 KB), initialised with a pattern of the address.
`default_nettype none
module sdram_lat #(
  parameter int INIT    = 200,
  parameter int BASE    = 4,
  parameter int REFRESH = 336
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [23:1] addr,
  input  logic        rd,
  input  logic        wr,
  input  logic [1:0]  be,
  input  logic [15:0] wdata,
  input  logic        refresh_ok,
  output logic [15:0] rdata,
  output logic        rvalid,
  output logic        ack,
  output logic        ready,
  output int          n_rd,
  output int          n_wr
);
  logic [15:0] mem [0:262143];

  function automatic logic [15:0] pattern(input logic [18:1] a);
    return 16'(a[16:1] * 16'h9E37) ^ {13'h0, a[18:16]};
  endfunction

  int base = BASE;
  initial begin
    void'($value$plusargs("lat=%d", base));
    for (int i = 0; i < 262144; i++) mem[i] = pattern(18'(i));
  end

  int  init_cnt, busy, ref_cnt;
  logic pend, pend_we, ref_due;
  logic [23:1] p_addr;
  logic [1:0]  p_be;
  logic [15:0] p_wdata;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      init_cnt <= 0; ready <= 1'b0; pend <= 1'b0; ack <= 1'b0; rvalid <= 1'b0;
      ref_cnt <= 0; ref_due <= 1'b0; n_rd <= 0; n_wr <= 0;
    end else begin
      ack    <= 1'b0;
      rvalid <= 1'b0;
      if (init_cnt < INIT) init_cnt <= init_cnt + 1; else ready <= 1'b1;
      ref_cnt <= (ref_cnt == REFRESH - 1) ? 0 : ref_cnt + 1;
      if (ref_cnt == REFRESH - 1) ref_due <= 1'b1;
      if (ready && !pend && !ack && (rd || wr)) begin
        pend    <= 1'b1;
        pend_we <= wr;
        p_addr  <= addr;
        p_be    <= be;
        p_wdata <= wdata;
        busy    <= base - 1 + (ref_due ? 1 + int'($urandom_range(3)) : 0);
        ref_due <= 1'b0;
      end else if (pend) begin
        if (busy == 0) begin
          pend <= 1'b0;
          ack  <= 1'b1;
          if (p_addr[23:19] != 5'd0) $fatal(1, "sdram_lat: address %06h above 512 KB", {p_addr, 1'b0});
          if (pend_we) begin
            if (p_be[1]) mem[p_addr[18:1]][15:8] <= p_wdata[15:8];
            if (p_be[0]) mem[p_addr[18:1]][7:0]  <= p_wdata[7:0];
            n_wr <= n_wr + 1;
          end else begin
            rdata  <= mem[p_addr[18:1]];
            rvalid <= 1'b1;
            n_rd   <= n_rd + 1;
          end
        end else busy <= busy - 1;
      end else if (ref_due && refresh_ok && !(rd || wr)) begin
        ref_due <= 1'b0;
      end
      // Port contract: the request and its payload hold until ack.
      if (pend && !ack && busy != 0) begin
        if (!(rd || wr)) $fatal(1, "sdram_lat: request dropped before ack");
        if (addr != p_addr || wr != pend_we || (wr && (be != p_be || wdata != p_wdata)))
          $fatal(1, "sdram_lat: payload changed before ack");
      end
    end
  end
endmodule
`default_nettype wire
