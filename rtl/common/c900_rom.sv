// ROM image in block RAM: written once by the loader, read synchronously.
`default_nettype none
module c900_rom #(
  parameter int AW = 14
) (
  input  logic          clk,
  input  logic [AW-1:0] addr,
  output logic [7:0]    q,
  input  logic          ld_we,
  input  logic [AW-1:0] ld_addr,
  input  logic [7:0]    ld_data
);
  (* ramstyle = "M10K" *) logic [7:0] mem [0:(1<<AW)-1];
  always_ff @(posedge clk) begin
    if (ld_we) mem[ld_addr] <= ld_data;
    q <= mem[addr];
  end
endmodule
`default_nettype wire
