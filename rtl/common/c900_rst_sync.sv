// Reset release synchroniser: asynchronous assert, release two clock edges
// after both the reset request is gone and the PLL is locked.
`default_nettype none
module c900_rst_sync (
  input  logic clk,
  input  logic arst,        // active high, asynchronous
  input  logic pll_locked,
  output logic rst_n
);
  wire async_n = ~arst & pll_locked;
  (* preserve *) logic [1:0] sync_q;
  always_ff @(posedge clk or negedge async_n) begin
    if (!async_n) sync_q <= 2'b00;
    else          sync_q <= {sync_q[0], 1'b1};
  end
  assign rst_n = sync_q[1];
endmodule
`default_nettype wire
