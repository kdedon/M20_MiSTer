// z8000_int_unit -- the external interrupt requests of one CPU.
//
// /NMI is edge-triggered: a falling edge seen at a clock edge is held
// until a sample takes it. /VI, /NVI and SEGT are levels. The requests are
// sampled at the end of each instruction (`smp_end`) and between the
// elements of a repeat form (`smp_elem`): the NMI edge moves into the
// request and stays there until its entry starts; the levels are copied.
// An entry may start at the boundary after a sample: NMI, then the segment
// trap, then VI if FCW VIE is set, then NVI if NVIE is.
//
// HALT samples in each of its internal cycles (`smp_halt`); an enabled
// request (or the NMI edge) seen at two samples in a row ends it, and
// that sample is also the instruction's.
//
// The pins are sampled raw, in the CPU's clock domain; an asynchronous
// board-level source needs a two-flop synchronizer at the top.

module z8000_int_unit
  import z8000_zbus_pkg::*;
(
  input  logic       clk,
  input  logic       clk_en,   // CLK rising edge seen this clock
  input  logic       reset_n,
  input  logic       nmi_n,
  input  logic       nvi_n,
  input  logic       vi_n,
  input  logic       segt_n,       // High on a part without the pin
  input  logic       vie,          // FCW bit 12
  input  logic       nvie,         // FCW bit 11

  input  logic       smp_end,      // the instruction's sample
  input  logic       smp_elem,     // a sample between repeat elements
  input  logic       smp_halt,     // a HALT internal cycle's sample
  input  logic       halt_on,      // HALT runs
  input  logic       take,         // the entry for `st` starts on this edge
  input  logic       clr,          // the sample is used up on this edge

  output logic       irq,          // an entry starts at this boundary
  output logic       irq_now,      // an enabled request as of the sample on this edge
  output logic [3:0] st,           // its acknowledge status
  output logic       halt_exit     // HALT's last internal cycle runs
);

  logic nmi_q, nmi_pend_q, nmi_req_q, segt_req_q, vi_req_q, nvi_req_q, smp_q;
  logic [1:0] hcnt_q;
  logic pend, hit, smp;

  assign pend = nmi_pend_q || (nmi_q && !nmi_n);
  assign hit = pend || !segt_n || (!vi_n && vie) || (!nvi_n && nvie);
  assign smp = smp_end || smp_elem || (smp_halt && halt_on && hit && hcnt_q == 2'd1);
  assign irq_now = nmi_req_q || hit;

  assign irq = smp_q && (nmi_req_q || segt_req_q || (vi_req_q && vie) || (nvi_req_q && nvie));
  assign st  = nmi_req_q ? ST_NMI_ACK : segt_req_q ? ST_SEGMENT_TRAP :
               (vi_req_q && vie) ? ST_VI_ACK : ST_NVI_ACK;
  assign halt_exit = hcnt_q == 2'd2;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      nmi_q      <= 1'b1;
      nmi_pend_q <= 1'b0;
      nmi_req_q  <= 1'b0;
      segt_req_q <= 1'b0;
      vi_req_q   <= 1'b0;
      nvi_req_q  <= 1'b0;
      smp_q      <= 1'b0;
      hcnt_q     <= 2'd0;
    end else if (clk_en) begin
      nmi_q <= nmi_n;
      if (smp) begin
        nmi_pend_q <= 1'b0;
        if (pend) nmi_req_q <= 1'b1;
        segt_req_q <= !segt_n;
        vi_req_q  <= !vi_n;
        nvi_req_q <= !nvi_n;
      end else if (pend) begin
        nmi_pend_q <= 1'b1;
      end
      if (take && st == ST_NMI_ACK) nmi_req_q <= 1'b0;
      if (smp)      smp_q <= 1'b1;
      else if (clr) smp_q <= 1'b0;
      if (!halt_on)      hcnt_q <= 2'd0;
      else if (smp_halt) hcnt_q <= hit ? hcnt_q + 2'd1 : 2'd0;
    end
  end

endmodule
