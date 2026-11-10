// 8259 cascade on the mainboard data bus: in a VI acknowledge the slave
// named on CAS0-2 drives the identifier word instead of the master.
// CAS is latched while /INTA is low, so the choice holds after the
// strobe, like the words themselves.  Reads of the master's own ports
// always see the master.
`default_nettype none
module m20_cascade (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        pic_inta_n,
  input  logic [2:0]  cas,
  input  logic        cs_pic,
  input  logic [15:0] master_rdata,
  input  logic        ieee_en,        // slave on IR1
  input  logic [15:0] ieee_rdata,
  input  logic        twin_en,        // slave on IR7
  input  logic [15:0] twin_rdata,
  output logic [15:0] pic_rdata
);
  logic [2:0] cas_q;
  always_ff @(posedge clk) begin
    if (!rst_n)           cas_q <= 3'd0;
    else if (!pic_inta_n) cas_q <= cas;
  end

  always_comb begin
    pic_rdata = master_rdata;
    if (!cs_pic) begin
      if (cas_q == 3'd1 && ieee_en) pic_rdata = ieee_rdata;
      if (cas_q == 3'd7 && twin_en) pic_rdata = twin_rdata;
    end
  end
endmodule
`default_nettype wire
