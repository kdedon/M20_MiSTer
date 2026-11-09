// z8000_refresh -- DRAM refresh prescaler and row step.
//
// REFRESH register: bit 15 RE, bits 14:9 RATE (0 means 64), bits 8:1 ROW;
// bit 0 is always 0.
// While enabled the prescaler is clocked at CLK/4 whatever the bus is
// doing; reaching zero reloads it from RATE and leaves a refresh pending.
// Up to two are owed at once; a third is lost. Writing REFRESH with RE set
// also reloads it.
// The sequencer issues a refresh at its next allowed boundary, one per
// boundary. One that comes due while the bus is granted or held by a wait
// state is skipped: then the refreshes owed at that point go out back to
// back from the first boundary after (`now`), whatever cycle it follows.
// One coming due after them waits for an allowed boundary.
// Each refresh cycle puts ROW on AD and steps it by two (bit 0 cleared).
//
// `pending` includes an underflow on this edge or the next: a refresh's T1
// may be the clock the prescaler underflows in. A refresh taken against the
// next edge's underflow swallows it. `take` marks the edge the sequencer commits to
// a refresh, which on a T3 edge is one clock before its T1; `cyc_row` is
// the row that cycle drives.

module z8000_refresh (
  input  logic       clk,
  input  logic       clk_en,   // CLK rising edge seen this clock
  input  logic       reset_n,
  input  logic       enable,      // RE
  input  logic [5:0] rate,
  input  logic [8:0] row,
  input  logic       load,        // REFRESH written with RE set
  input  logic [5:0] load_rate,
  input  logic       take,
  input  logic       keep,        // the refresh taken leaves the pending
  input  logic       lost,        // the clock ending at this edge had no bus
  output logic       pending,
  output logic       now,         // a skipped refresh is owed
  output logic [8:0] row_next,    // ROW after this refresh
  output logic [8:0] cyc_row
);

  logic [1:0]  div4_q, div4_d;     // CLK/4 sub-divider
  logic [15:0] count_q, count_d;   // prescaler
  logic [1:0]  owed_q, owed_d;     // refreshes owed, 0 to 2
  logic [8:0]  row_q;
  logic        underflow, soon, skip_q;
  logic [1:0]  now_q, now_set;     // owed refreshes to issue at once
  logic        lost_q, mark;

  logic [15:0] count_dec, reload;
  logic [5:0]  rate_sel;
  assign count_dec = count_q - 16'd1;
  assign rate_sel  = load ? load_rate : rate;
  assign reload    = (rate_sel == 6'd0) ? 16'd64 : {10'd0, rate_sel};

  always_comb begin
    div4_d    = div4_q;
    count_d   = count_q;
    underflow = 1'b0;
    if (enable) begin
      div4_d = div4_q + 2'd1;
      if (div4_q == 2'd3) begin
        count_d = count_dec;
        if (count_dec == 16'd0) begin
          count_d   = reload;
          underflow = 1'b1;
        end
      end
    end
    // The write lands after this edge's step; the CLK/4 phase carries on.
    if (load) count_d = reload;
  end

  // A write on this edge is not seen; the CPU checks that none coincides
  // with a take.
  assign soon      = enable && div4_q == 2'd2 && count_q == 16'd1;
  assign pending   = owed_q != 2'd0 || (underflow && !skip_q) || soon;
  logic used;
  logic [2:0] owed_in;
  assign used      = take && !keep;
  // A take against the next edge's underflow counts it now and skips it then.
  assign owed_in   = {1'b0, owed_q} + {2'd0, underflow && !skip_q} + {2'd0, used && soon};
  assign owed_d    = (owed_in > 3'd2 ? 2'd2 : owed_in[1:0]) - {1'b0, used && owed_in != 3'd0};
  assign row_next  = (row + 9'd2) & 9'h1FE;
  assign cyc_row   = take ? row : row_q;
  // An underflow here is due as of the previous edge, so the clock before
  // that one decides whether it was skipped. It marks every refresh then
  // owed, and counts from this edge.
  assign mark      = underflow && !skip_q && lost_q;
  assign now       = now_q != 2'd0 || mark;
  assign now_set   = mark ? (owed_in > 3'd2 ? 2'd2 : owed_in[1:0]) : now_q;

  // /RESET leaves the prescaler alone; it powers up at zero.
  always_ff @(posedge clk) if (clk_en) begin
    div4_q  <= div4_d;
    count_q <= count_d;
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      owed_q    <= 2'd0;
      skip_q    <= 1'b0;
      now_q     <= 2'd0;
      lost_q    <= 1'b0;
      row_q     <= 9'd0;
    end else if (clk_en) begin
      owed_q    <= owed_d;
      skip_q    <= used && soon;
      now_q     <= now_set - {1'b0, used && now_set != 2'd0};
      lost_q    <= lost;
      row_q     <= cyc_row;
    end
  end

endmodule
