// Behavioural stand-ins for the M20 peripherals, enough to answer the boot
// ROM 1.0 probes:
//   8253      modes 2/3, latch, LSB/MSB access
//   FD1797    track/sector/data registers, status 0x00 (ready, not busy);
//             Restore sets TRK0 (0x04); a Read Sector answers Record Not
//             Found (0x10).  INTRQ pulses after each command.
//   MC6845    address register + 18 registers, all readable
//   8255      port A/C output latches read back, port B reads 0xFF
//   8251 x2   mode/command sequence; status TxRDY|TxEMPTY (0x05) plus RxRDY
//   keyboard  replies 0x0F to 0x03 and 0x80 to 0x80, KBD_DLY clocks later
//   8259      ICW1-4, IMR, specific/non-specific EOI, edge IRQ, two-pulse
//             INTA (8086 mode), D1-D8 shift with bit 0 floating High
`default_nettype none
module m20_stubs #(
  parameter int KBD_DLY = 20000
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        ce_pit,
  input  logic [15:0] io_addr,
  input  logic [15:0] io_wdata,
  input  logic        io_rd,
  input  logic        io_wr,
  input  logic        io_rd_end,
  input  logic        io_wr_end,
  input  logic        cs_fdc,
  input  logic        cs_crtc,
  input  logic        cs_ppi,
  input  logic        cs_kbd,
  input  logic        cs_ser,
  input  logic        cs_pit,
  input  logic        cs_pic,
  output logic [7:0]  fdc_rdata,
  output logic [7:0]  crtc_rdata,
  output logic [7:0]  ppi_rdata,
  output logic [7:0]  kbd_rdata,
  output logic [7:0]  ser_rdata,
  output logic [7:0]  pit_rdata,
  output logic [15:0] pic_rdata,
  output logic        pic_int,
  input  logic        pic_inta_n,
  output logic        pit_out2,
  output int          n_kbd_tx,
  output int          n_inta
);
  logic [7:0] wb;
  logic       a1, wr_fdc, wr_crtc, wr_ppi, wr_kbd, wr_ser, wr_pic, rd_kbd, rd_ser;
  assign wb      = io_wdata[7:0];
  assign a1      = io_addr[1];
  assign wr_fdc  = io_wr_end && cs_fdc;
  assign wr_crtc = io_wr_end && cs_crtc;
  assign wr_ppi  = io_wr_end && cs_ppi;
  assign wr_kbd  = io_wr_end && cs_kbd;
  assign wr_ser  = io_wr_end && cs_ser;
  assign wr_pic  = io_wr_end && cs_pic;
  assign rd_kbd  = io_rd_end && cs_kbd;
  assign rd_ser  = io_rd_end && cs_ser;

  // ---- FD1797 ----
  logic [7:0] fd_st, fd_trk, fd_sec, fd_dat;
  logic       fd_intrq;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fd_st <= 8'h00; fd_trk <= 8'h00; fd_sec <= 8'h01; fd_dat <= 8'h00; fd_intrq <= 1'b0;
    end else begin
      fd_intrq <= 1'b0;
      if (wr_fdc) unique case (io_addr[2:1])
        2'd0: begin
          fd_intrq <= 1'b1;
          if (wb[7:4] == 4'h0)       begin fd_st <= 8'h04; fd_trk <= 8'h00; end
          else if (wb[7:4] == 4'hD)  fd_st <= (fd_trk == 8'h00) ? 8'h04 : 8'h00;
          else if (wb[7] == 1'b0)    begin fd_st <= 8'h00; if (wb[7:4] == 4'h1) fd_trk <= fd_dat; end
          else                       fd_st <= 8'h10;
        end
        2'd1: fd_trk <= wb;
        2'd2: fd_sec <= wb;
        default: fd_dat <= wb;
      endcase
    end
  end
  always_comb unique case (io_addr[2:1])
    2'd0: fdc_rdata = fd_st;
    2'd1: fdc_rdata = fd_trk;
    2'd2: fdc_rdata = fd_sec;
    default: fdc_rdata = fd_dat;
  endcase

  // ---- MC6845 ----
  logic [4:0] crtc_ar;
  logic [7:0] crtc_r [0:17];
  always_ff @(posedge clk) begin
    if (!rst_n) crtc_ar <= 5'd0;
    else if (wr_crtc && !a1) crtc_ar <= wb[4:0];
    else if (wr_crtc && crtc_ar < 5'd18) crtc_r[crtc_ar] <= wb;
  end
  assign crtc_rdata = (a1 && crtc_ar < 5'd18) ? crtc_r[crtc_ar] : 8'h00;

  // ---- 8255 ----
  logic [7:0] ppa, ppc, ppctl;
  always_ff @(posedge clk) begin
    if (!rst_n) begin ppa <= 8'h00; ppc <= 8'h00; ppctl <= 8'h9B; end
    else if (wr_ppi) unique case (io_addr[2:1])
      2'd0: ppa <= wb;
      2'd2: ppc <= wb;
      2'd3: if (wb[7]) ppctl <= wb; else ppc[wb[3:1]] <= wb[0];
      default: ;
    endcase
  end
  always_comb unique case (io_addr[2:1])
    2'd0: ppi_rdata = ppa;
    2'd1: ppi_rdata = 8'hFF;
    2'd2: ppi_rdata = ppc;
    default: ppi_rdata = 8'hFF;
  endcase

  // ---- 8251 (keyboard) + keyboard ----
  logic       k_mode, k_rx;
  logic [7:0] k_rxd;
  int         k_dly;
  logic [7:0] k_reply;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      k_mode <= 1'b1; k_rx <= 1'b0; k_rxd <= 8'h00; k_dly <= 0; k_reply <= 8'h00; n_kbd_tx <= 0;
    end else begin
      if (wr_kbd && a1) begin
        if (k_mode)        k_mode <= 1'b0;           // mode instruction
        else if (wb[6])    k_mode <= 1'b1;           // internal reset
      end
      if (wr_kbd && !a1) begin
        n_kbd_tx <= n_kbd_tx + 1;
        if (wb == 8'h03)      begin k_reply <= 8'h0F; k_dly <= KBD_DLY; end
        else if (wb == 8'h80) begin k_reply <= 8'h80; k_dly <= KBD_DLY; end
      end
      if (k_dly == 1) begin k_rx <= 1'b1; k_rxd <= k_reply; end
      if (k_dly != 0) k_dly <= k_dly - 1;
      if (rd_kbd && !a1) k_rx <= 1'b0;
    end
  end
  assign kbd_rdata = a1 ? {5'b10000, 1'b1, k_rx, 1'b1} : k_rxd;

  // ---- 8251 (RS-232) ----
  assign ser_rdata = io_addr[1] ? 8'h85 : 8'h00;
  logic unused_ser;
  assign unused_ser = &{1'b0, wr_ser, rd_ser, io_rd};

  // ---- 8253: modes 2 and 3 (others run as mode 2), latch command,
  // LSB/MSB/word access, one count per ce_pit, gates High ----
  logic [15:0] p_cnt [0:2], p_rld [0:2], p_lat [0:2];
  logic [1:0]  p_rl  [0:2];
  logic        p_m3  [0:2], p_out [0:2], p_run [0:2], p_latd [0:2], p_wff [0:2], p_rff [0:2];
  logic [1:0]  pa;
  assign pa = io_addr[2:1];
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int c = 0; c < 3; c++) begin
        p_cnt[c] <= 16'h0; p_rld[c] <= 16'h0; p_rl[c] <= 2'd3; p_m3[c] <= 1'b0; p_out[c] <= 1'b1;
        p_run[c] <= 1'b0; p_latd[c] <= 1'b0; p_wff[c] <= 1'b0; p_rff[c] <= 1'b0; p_lat[c] <= 16'h0;
      end
    end else begin
      for (int c = 0; c < 3; c++) if (ce_pit && p_run[c]) begin
        if (p_m3[c]) begin
          if (p_cnt[c] <= 16'd2 && p_cnt[c] != 16'd0) begin p_cnt[c] <= p_rld[c]; p_out[c] <= !p_out[c]; end
          else p_cnt[c] <= p_cnt[c] - 16'd2;
        end else begin
          if (p_cnt[c] == 16'd2) p_out[c] <= 1'b0;
          if (p_cnt[c] == 16'd1) begin p_cnt[c] <= p_rld[c]; p_out[c] <= 1'b1; end
          else p_cnt[c] <= p_cnt[c] - 16'd1;
        end
      end
      if (io_wr_end && cs_pit) begin
        if (pa == 2'd3) begin
          if (wb[7:6] != 2'd3) begin
            if (wb[5:4] == 2'd0) begin p_lat[wb[7:6]] <= p_cnt[wb[7:6]]; p_latd[wb[7:6]] <= 1'b1; end
            else begin
              p_rl[wb[7:6]] <= wb[5:4]; p_m3[wb[7:6]] <= wb[2:1] == 2'd3; p_run[wb[7:6]] <= 1'b0;
              p_out[wb[7:6]] <= 1'b1; p_wff[wb[7:6]] <= 1'b0; p_rff[wb[7:6]] <= 1'b0;
            end
          end
        end else begin
          logic [15:0] v;
          v = p_rld[pa];
          if (p_rl[pa] == 2'd1 || (p_rl[pa] == 2'd3 && !p_wff[pa])) v[7:0] = wb; else v[15:8] = wb;
          if (p_rl[pa] == 2'd1) v[15:8] = 8'h00;
          if (p_rl[pa] == 2'd2) v[7:0]  = 8'h00;
          p_rld[pa] <= v;
          if (p_rl[pa] == 2'd3) p_wff[pa] <= !p_wff[pa];
          if (p_rl[pa] != 2'd3 || p_wff[pa]) begin p_cnt[pa] <= v & (p_m3[pa] ? 16'hFFFE : 16'hFFFF); p_run[pa] <= 1'b1; end
        end
      end
      if (io_rd_end && cs_pit && pa != 2'd3) begin
        if (p_rl[pa] == 2'd3) p_rff[pa] <= !p_rff[pa];
        if (p_rl[pa] != 2'd3 || p_rff[pa]) p_latd[pa] <= 1'b0;
      end
    end
  end
  logic [15:0] p_rv;
  assign p_rv = p_latd[pa] ? p_lat[pa] : p_cnt[pa];
  assign pit_rdata = (pa == 2'd3) ? 8'hFF :
                     (p_rl[pa] == 2'd2 || (p_rl[pa] == 2'd3 && p_rff[pa])) ? p_rv[15:8] : p_rv[7:0];
  assign pit_out2  = p_out[2];

  // ---- 8259 ----
  logic [7:0] imr, irr, isr, icw2, pic_d;
  logic [2:0] step, cur;
  logic       sngl, ic4, second, inta_q;
  logic [7:0] ir, ir_q;
  assign ir    = {3'b000, k_rx, 3'b000, fd_intrq};
  assign pic_d = io_wdata[8:1];

  function automatic logic [2:0] hi_pri(input logic [7:0] v);  // IR6 highest, IR5 lowest
    for (int k = 0; k < 8; k++) if (v[(6 + 8 - k) % 8]) return 3'((6 + 8 - k) % 8);
    return 3'd0;
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      imr <= 8'hFF; irr <= 8'h00; isr <= 8'h00; icw2 <= 8'h00; step <= 3'd0;
      sngl <= 1'b0; ic4 <= 1'b0; second <= 1'b0; inta_q <= 1'b1; ir_q <= 8'h00; cur <= 3'd0;
      n_inta <= 0;
    end else begin
      ir_q   <= ir;
      inta_q <= pic_inta_n;
      irr    <= irr | (ir & ~ir_q);
      if (wr_pic) begin
        if (!a1 && pic_d[4]) begin
          step <= 3'd2; sngl <= pic_d[1]; ic4 <= pic_d[0]; imr <= 8'h00; isr <= 8'h00; irr <= 8'h00;
        end else if (a1 && step == 3'd2) begin
          icw2 <= pic_d; step <= !sngl ? 3'd3 : (ic4 ? 3'd4 : 3'd0);
        end else if (a1 && step == 3'd3) begin
          step <= ic4 ? 3'd4 : 3'd0;
        end else if (a1 && step == 3'd4) begin
          step <= 3'd0;
        end else if (a1) begin
          imr <= pic_d;
        end else if (!pic_d[3] && pic_d[5]) begin
          if (pic_d[6]) isr[pic_d[2:0]] <= 1'b0;
          else          isr[hi_pri(isr)] <= 1'b0;
        end
      end
      if (inta_q && !pic_inta_n) begin
        if (!second) begin
          cur    <= hi_pri(irr & ~imr);
          irr[hi_pri(irr & ~imr)] <= 1'b0;
          isr[hi_pri(irr & ~imr)] <= 1'b1;
          second <= 1'b1;
          n_inta <= n_inta + 1;
        end
      end
      if (!inta_q && pic_inta_n && second && cur_out) second <= 1'b0;
    end
  end
  // The vector is driven through the second pulse.
  logic cur_out;
  always_ff @(posedge clk) begin
    if (!rst_n)                                    cur_out <= 1'b0;
    else if (inta_q && !pic_inta_n && second)      cur_out <= 1'b1;
    else if (!inta_q && pic_inta_n && cur_out)     cur_out <= 1'b0;
  end
  assign pic_int   = |(irr & ~imr) && isr == 8'h00;
  assign pic_rdata = (cur_out && !pic_inta_n) ? {7'h7F, icw2[7:3], cur, 1'b0}
                                              : {7'h7F, a1 ? imr : irr, 1'b1};
  logic unused_ok;
  assign unused_ok = &{1'b0, ppctl, io_wr};
endmodule
`default_nettype wire
