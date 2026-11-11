// Olivetti APB 1086 (G0246): 8086 co-processor card on the M20 bus.
//
// The 8086 (8 MHz, clock enable ce8) runs from its own 16 KB ROM at FC000.
// Every other memory cycle goes out as a Z-bus program-reference cycle
// (status 1100) through the M20 mapping PROM, with SN3-SN0, A15, A14 from
// the translator (PL40); I/O cycles go out as standard I/O (0010) with
// A15 = A14 = 0.  Cycles follow the Z8001 bus timing on the mainboard's CPU
// clock rises (PL42), so the mainboard's waits and stretches apply.
//
//   cycle      /DS falls  data taken  /DS rises   (CPU clock rises after T1)
//   mem read   1          2           3
//   mem write  2          -           3
//   I/O        2          3           4
//   INTA       5          7           8
//
// D0-D15 pass straight through: an 8086 byte at an even address is the
// Z-bus byte at the odd address (Z A0 = NOT 8086 A0); byte writes drive the
// byte on both halves.  Unmapped memory reads 0xFFFF, writes are dropped.
//
// Handshake (74LS133 on bus A13-A3 = 1): any I/O cycle at 0x3FF8 + 2
// (0x3FFA, the 8086's 0x7FFA) pulls /NMI while /DS is Low and clears the run
// latch at its end; 0x3FFC sets it.  The run latch is /BUSREQ.  The 8086
// is held in reset unless the latch is set and /BUSACK is Low.
//
// Interrupts: INTR = VI OR NVI.  The first INTA stays on the card and
// latches NVI (priority); the second runs an NVI (0110) or VI (0111)
// acknowledge.  Nothing drives the bus in an NVI acknowledge: vector 0xFF.
//
// Image (ld_*): bytes 0000-3FFF the ROM as the 8086 sees it at FC000;
// 4000-47FF the CPU microcode, 512 words of 4 bytes, little endian.
`default_nettype none
module m20_apb (
  input  logic        clk,           // 48 MHz
  input  logic        rst_n,
  input  logic        fitted,

  input  logic        ld_we,
  input  logic [14:0] ld_addr,
  input  logic [7:0]  ld_data,

  // bus master port
  output logic        busreq_n,
  output logic        nmi_n,
  input  logic        busack_n,
  input  logic        clk_rise,      // M20 CPU clock rise
  output logic        as_n,
  output logic        ds_n,
  output logic [15:0] ad,
  output logic        ad_drive,
  output logic [6:0]  sn,
  output logic [3:0]  st,
  output logic        r_w,
  output logic        b_w,
  input  logic [15:0] rdata,         // read capture, valid at the clock rise

  // I/O cycle in progress (any master)
  input  logic [15:0] io_addr,
  input  logic        io_act,        // /DS Low
  input  logic        io_end,        // the cycle's /DS rise

  input  logic        vi,
  input  logic        nvi,

  output logic        run
);
  localparam logic [3:0] ST_MEM = 4'b1100, ST_IO = 4'b0010,
                         ST_NVIACK = 4'b0110, ST_VIACK = 4'b0111, ST_IDLE = 4'b0000;
  localparam logic [2:0] CE_LAST = 3'd5;
  localparam logic [1:0] LOCAL_LAT = 2'd1;    // ROM and empty cycles take 4 CPU clocks

  // ---- 8 MHz clock enable -------------------------------------------------------
  logic [2:0] div_q;
  logic       ce8;
  always_ff @(posedge clk) begin
    if (!rst_n || div_q == CE_LAST) div_q <= 3'd0;
    else                            div_q <= div_q + 3'd1;
  end
  assign ce8 = div_q == CE_LAST;

  // ---- handshake ------------------------------------------------------------------
  logic hs_hit, hs_set, hs_clr, run_q, own, own_q;
  assign hs_hit = io_addr[13:3] == 11'h7FF;
  assign hs_set = hs_hit && io_addr[2:1] == 2'b10;
  assign hs_clr = hs_hit && io_addr[2:1] == 2'b01;
  always_ff @(posedge clk) begin
    if (!rst_n || !fitted)    run_q <= 1'b0;
    else if (io_end && hs_clr) run_q <= 1'b0;
    else if (io_end && hs_set) run_q <= 1'b1;
  end
  assign busreq_n = !run_q;
  assign nmi_n    = !(fitted && io_act && hs_clr);
  assign own      = run_q && !busack_n;
  assign run      = run_q;
  // 8086 RESET, and everything on the card's bus side.
  always_ff @(posedge clk) own_q <= rst_n && own;

  // ---- image: ROM and microcode ------------------------------------------------------
  (* ramstyle = "M10K" *) logic [7:0] rom_lo [0:8191];
  (* ramstyle = "M10K" *) logic [7:0] rom_hi [0:8191];
  logic [12:0] rom_a;
  logic [15:0] rom_q;
  always_ff @(posedge clk) begin
    if (ld_we && !ld_addr[14] && !ld_addr[0]) rom_lo[ld_addr[13:1]] <= ld_data;
    rom_q[7:0] <= rom_lo[rom_a];
  end
  always_ff @(posedge clk) begin
    if (ld_we && !ld_addr[14] && ld_addr[0]) rom_hi[ld_addr[13:1]] <= ld_data;
    rom_q[15:8] <= rom_hi[rom_a];
  end

  // Microcode word bytes 0, 1 held until byte 2 writes the word.
  logic [15:0] uc_lo_q;
  logic        uc_we;
  always_ff @(posedge clk) begin
    if (ld_we && ld_addr[14] && ld_addr[1:0] == 2'd0) uc_lo_q[7:0]  <= ld_data;
    if (ld_we && ld_addr[14] && ld_addr[1:0] == 2'd1) uc_lo_q[15:8] <= ld_data;
  end
  assign uc_we = ld_we && ld_addr[14] && ld_addr[1:0] == 2'd2 && ld_addr[13:11] == 3'd0;

  // ---- CPU ------------------------------------------------------------------------
  logic [19:0] c_addr;
  logic [15:0] c_din, c_dout;
  logic        c_rd, c_wr, c_io, c_word, c_inta, c_ready;
  z8086 u_cpu (
    .clk(clk), .ce(ce8), .reset_n(own_q),
    .addr(c_addr), .din(c_din), .dout(c_dout), .wr(c_wr), .rd(c_rd), .io(c_io),
    .word(c_word), .ready(c_ready), .intr(fitted && (vi || nvi)), .nmi(1'b0), .inta(c_inta),
    .uc_we(uc_we), .uc_addr(ld_addr[10:2]), .uc_data({ld_data[4:0], uc_lo_q})
  );

  // ---- request ----------------------------------------------------------------------
  // A request is the CPU's one-ce strobe; ready is held until the CPU's next ce.
  logic        rq_q, rq_wr, rq_io, rq_word, rq_inta, rq_bus;
  logic [19:0] rq_a;
  logic [15:0] rq_d;
  logic        inta2_q, nvi_sel_q;
  logic [1:0]  lat_q;
  logic        rdy_q;
  logic [15:0] din_q;
  logic        x_bus, x_rom, x_a15, x_a14;
  logic [3:0]  x_sn;
  logic        z_done;
  logic [15:0] z_data;

  m20_apb_xlat u_xlat (
    .a(c_addr[19:14]), .sn(x_sn), .a15(x_a15), .a14(x_a14), .bus(x_bus), .rom(x_rom)
  );

  // Bus-cycle address: {A15, A14, A13-A1, Z A0} and segment.
  logic [15:0] rq_za;
  logic [3:0]  rq_sn;
  logic        start;
  // INTA is not cleared by the CPU's reset: ignore strobes until its first clock out of reset.
  logic live_q;
  always_ff @(posedge clk) begin
    if (!own_q)   live_q <= 1'b0;
    else if (ce8) live_q <= 1'b1;
  end
  assign start = ce8 && live_q && (c_rd || c_wr || c_inta) && !rq_q;
  assign rom_a = rq_a[13:1];

  logic [15:0] loc_data;
  assign loc_data = rq_bus ? z_data : (rq_a[19:14] == 6'h3F ? rom_q : 16'hFFFF);

  always_ff @(posedge clk) begin
    if (!own_q) begin
      rq_q <= 1'b0; rq_wr <= 1'b0; rq_io <= 1'b0; rq_word <= 1'b0; rq_inta <= 1'b0;
      rq_bus <= 1'b0; rq_a <= 20'd0; rq_d <= 16'd0; rq_za <= 16'd0; rq_sn <= 4'd0;
      inta2_q <= 1'b0; nvi_sel_q <= 1'b0; lat_q <= 2'd0; rdy_q <= 1'b0; din_q <= 16'hFFFF;
    end else begin
      if (ce8 && rdy_q) rdy_q <= 1'b0;
      if (ce8 && lat_q != 2'd0) lat_q <= lat_q - 2'd1;
      if (start) begin
        rq_q    <= 1'b1;
        rq_wr   <= c_wr;
        rq_io   <= c_io;
        rq_word <= c_word;
        rq_inta <= c_inta;
        rq_a    <= c_addr;
        rq_d    <= c_word ? c_dout : {c_dout[7:0], c_dout[7:0]};
        rq_za   <= {c_io ? 2'b00 : {x_a15, x_a14}, c_addr[13:1], !c_word && !c_addr[0]};
        rq_sn   <= x_sn;
        rq_bus  <= c_inta ? inta2_q : (c_io || x_bus);
        lat_q   <= LOCAL_LAT;
        if (c_inta) begin
          inta2_q <= !inta2_q;
          if (!inta2_q) nvi_sel_q <= nvi;
        end
      end else if (rq_q && (rq_bus ? z_done : (lat_q == 2'd0 && ce8))) begin
        rq_q  <= 1'b0;
        rdy_q <= 1'b1;
        din_q <= (rq_word || rq_inta) ? loc_data :
                 {8'h00, rq_a[0] ? loc_data[15:8] : loc_data[7:0]};
      end
    end
  end
  assign c_ready = rdy_q;
  assign c_din   = din_q;

  // ---- Z-bus sequencer (PL42) -------------------------------------------------------
  // Edge count since T1; the cycle's strobe edges.
  logic       z_act;
  logic [3:0] z_e;
  logic [3:0] e_dsf, e_smp, e_end, e_nx;
  always_comb begin
    if (rq_inta)    begin e_dsf = 4'd5; e_smp = 4'd7; e_end = 4'd8; end
    else if (rq_io) begin e_dsf = 4'd2; e_smp = 4'd3; e_end = 4'd4; end
    else if (rq_wr) begin e_dsf = 4'd2; e_smp = 4'd0; e_end = 4'd3; end
    else            begin e_dsf = 4'd1; e_smp = 4'd2; e_end = 4'd3; end
  end
  assign e_nx = z_e + 4'd1;

  always_ff @(posedge clk) begin
    if (!own_q) begin
      z_act <= 1'b0; z_e <= 4'd0; z_done <= 1'b0; z_data <= 16'hFFFF;
      as_n <= 1'b1; ds_n <= 1'b1; ad <= 16'h0000; ad_drive <= 1'b0;
      sn <= 7'd0; st <= ST_IDLE; r_w <= 1'b1; b_w <= 1'b0;
    end else begin
      z_done <= 1'b0;
      if (clk_rise) begin
        if (!z_act) begin
          if (rq_q && rq_bus && !z_done) begin            // T1
            z_act    <= 1'b1;
            z_e      <= 4'd0;
            as_n     <= 1'b0;
            ad       <= rq_inta ? 16'h0000 : rq_za;
            ad_drive <= 1'b1;
            sn       <= {3'd0, rq_io || rq_inta ? 4'd0 : rq_sn};
            st       <= rq_inta ? (nvi_sel_q ? ST_NVIACK : ST_VIACK) : rq_io ? ST_IO : ST_MEM;
            r_w      <= !rq_wr;
            b_w      <= !(rq_word || rq_inta);
          end
        end else begin
          z_e  <= e_nx;
          if (e_nx == 4'd1) begin
            as_n <= 1'b1;
            if (rq_wr) ad <= rq_d;
            else       ad_drive <= 1'b0;
          end
          if (e_nx == e_dsf) ds_n <= 1'b0;
          if (e_nx == e_smp && !rq_wr) z_data <= rdata;
          if (e_nx == e_end) begin
            ds_n     <= 1'b1;
            ad_drive <= 1'b0;
            st       <= ST_IDLE;
            z_act    <= 1'b0;
            z_done   <= 1'b1;
          end
        end
      end
    end
  end

  logic unused_ok;
  assign unused_ok = &{1'b0, ld_data[7:5], io_addr[15:14], io_addr[0], x_rom};
endmodule
`default_nettype wire
