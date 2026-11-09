// Simulation model of the Intel DDIO output used to forward SDRAM clocks:
// datain_h while outclock is High, datain_l while it is Low.
`default_nettype none
/* verilator lint_off UNUSEDPARAM */
module altddio_out #(
  parameter extend_oe_disable      = "OFF",
  parameter intended_device_family = "Cyclone V",
  parameter invert_output          = "OFF",
  parameter lpm_hint               = "UNUSED",
  parameter lpm_type               = "altddio_out",
  parameter oe_reg                 = "UNREGISTERED",
  parameter power_up_high          = "OFF",
  parameter int width              = 1
) (
  input  wire [width-1:0] datain_h,
  input  wire [width-1:0] datain_l,
  input  wire             outclock,
  output wire [width-1:0] dataout,
  input  wire             aclr,
  input  wire             aset,
  input  wire             oe,
  input  wire             outclocken,
  input  wire             sclr,
  input  wire             sset
);
  assign dataout = outclock ? datain_h : datain_l;
  wire unused_ok = &{1'b0, aclr, aset, oe, outclocken, sclr, sset};
endmodule
/* verilator lint_on UNUSEDPARAM */
`default_nettype wire
