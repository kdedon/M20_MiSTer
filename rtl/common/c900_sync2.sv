// Two-flop synchroniser for one asynchronous level.
`default_nettype none
module c900_sync2 #(
  parameter logic INIT = 1'b0
) (
  input  logic clk,
  input  logic d,
  output logic q
);
  (* preserve *) (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)
  logic [1:0] sync_q = {2{INIT}};
  always_ff @(posedge clk) sync_q <= {sync_q[0], d};
  assign q = sync_q[1];
endmodule
`default_nettype wire
