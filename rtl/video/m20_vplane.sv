// One M20 bitmap plane: 8K x 16 words, the first 16 KB of
// one DRAM device.  Write port = the CPU write snoop;
// read port = the CRT fetch.  Simple-dual-port, one clock, registered read,
// old-data read-during-write (16 M10K).
`default_nettype none

module m20_vplane (
    input  logic        clk,
    input  logic        we,
    input  logic [12:0] waddr,
    input  logic  [1:0] be,         // be[1] = D15-D8 (even byte, left pixels)
    input  logic [15:0] wdata,
    input  logic [12:0] raddr,
    output logic [15:0] q
);

    (* ramstyle = "M10K" *) logic [15:0] mem [0:8191];

    always_ff @(posedge clk) begin
        if (we && be[1]) mem[waddr][15:8] <= wdata[15:8];
        if (we && be[0]) mem[waddr][7:0]  <= wdata[7:0];
        q <= mem[raddr];
    end

endmodule

`default_nettype wire
