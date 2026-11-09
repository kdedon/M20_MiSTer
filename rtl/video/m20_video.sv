// M20 video: MC6845 CRTC U78,
// bitmap planes, CRT fetch, shifters, 74LS670 palette U88 and sync out.
//
// Clocks: everything on clk = 48 MHz.  ce_pix = clk/4 = 12 MHz (U109 dot
// clock); the CRTC character clock is ce_pix/16 = 750 kHz.
//
// CPU port: CRTC at 0x61 (RS = A1 = 0, address) and 0x63 (RS = 1,
// data); palette entry k at 0x181 + 2k, data D0-D3.  A write is captured
// while cs && io_wr and committed on io_wr_end.  R14-R17 read back from the
// CRTC itself; other CRTC reads float (0xFF).
//
// Pipeline, C = the clk on which the CRTC steps (ce_pix with dot 15):
//   C       CRTC counters advance
//   C+1     MA/RA valid; plane word address presented to the BRAM
//   C+2     plane words valid; DE/HSYNC/VSYNC and display flags valid
//   C+3     crt_fetch pulse (displayed characters only)
//   C+4     ce_pix, dot 0: shifters load, character latch takes DE/syncs
//   C+8+4k  pixel k of the character (k = 0 = bit 15, leftmost) and its
//           syncs/blanks at the outputs, k = 0..15
// Syncs, blanks and pixels share the same delay (two dots after the CRTC
// step), so the frame geometry is the CRTC's.
//
// Monitor signals: HSYNC and VSYNC are the CRTC's (active high, as the J5
// 75451 drivers); VSYNC is the MC6845's fixed 16 lines.  HBlank/VBlank are
// the CRTC's horizontal/vertical display flags; DE = both displayed.
`default_nettype none

module m20_video (
    input  logic        clk,
    input  logic        rst_n,
    // I/O bus
    input  logic [15:0] io_addr,
    input  logic [15:0] io_wdata,
    input  logic        io_rd,
    input  logic        io_wr,
    input  logic        io_wr_end,
    input  logic        cs_crtc,
    input  logic        cs_pal,
    output logic  [7:0] crtc_rdata,
    // VRAM snoop
    input  logic        vram_we,
    input  logic  [1:0] vram_plane,
    input  logic [13:1] vram_addr,
    input  logic  [1:0] vram_be,
    input  logic [15:0] vram_wdata,
    // Port 0x21 configuration code {D7, D6, D5}
    input  logic  [2:0] cfg_code,
    // Video out
    output logic        ce_pix,
    output logic  [7:0] vga_r,
    output logic  [7:0] vga_g,
    output logic  [7:0] vga_b,
    output logic        hsync,
    output logic        vsync,
    output logic        hblank,
    output logic        vblank,
    // CRT DRAM fetch
    output logic        crt_fetch
);

    // ---------------------------------------------------------------- clocks
    // Dot clock divider (U109) and dot counter, free running.
    logic [1:0] div4_q;
    logic [3:0] dot_q;
    always_ff @(posedge clk) div4_q <= div4_q + 2'd1;
    always_ff @(posedge clk) if (ce_pix) dot_q <= dot_q + 4'd1;

    logic ce_crtc, load;
    assign ce_pix  = (div4_q == 2'd3);
    assign ce_crtc = ce_pix & (dot_q == 4'd15);
    assign load    = ce_pix & (dot_q == 4'd0);

    // --------------------------------------------------------- write capture
    // A write held from io_wr to its io_wr_end commit.
    logic       arm_crtc_q, arm_pal_q;
    logic [7:0] wdata_q;
    logic [1:0] wreg_q;         // {A2, A1}
    always_ff @(posedge clk) begin
        if (!rst_n)                  {arm_crtc_q, arm_pal_q} <= 2'b00;
        else if (io_wr_end)          {arm_crtc_q, arm_pal_q} <= 2'b00;
        else if (io_wr && cs_crtc)   {arm_crtc_q, arm_pal_q} <= 2'b10;
        else if (io_wr && cs_pal)    {arm_crtc_q, arm_pal_q} <= 2'b01;
    end
    always_ff @(posedge clk) begin
        if (io_wr && (cs_crtc || cs_pal)) begin
            wdata_q <= io_wdata[7:0];
            wreg_q  <= io_addr[2:1];
        end
    end

    logic wr_crtc, pal_we;
    assign wr_crtc = io_wr_end & arm_crtc_q;
    assign pal_we  = io_wr_end & arm_pal_q;

    // ------------------------------------------------------------------ CRTC
    logic        c_en, c_rnw, c_rs;
    logic  [7:0] c_do;
    logic        c_do_valid;
    logic        c_hs, c_vs, c_de, c_cursor, c_hdisp, c_vdisp;
    logic [13:0] c_ma;
    logic  [4:0] c_ra;
    logic  [3:0] c_test;
    logic  [7:0] c_r1;

    assign c_en  = wr_crtc | (cs_crtc & io_rd);
    assign c_rnw = ~wr_crtc;
    assign c_rs  = wr_crtc ? wreg_q[0] : io_addr[1];

    mc6845 u_crtc (
        .CLOCK       (clk),
        .CLKEN       (ce_crtc),
        .CLKEN_CPU   (wr_crtc),
        .nRESET      (rst_n),
        .ENABLE      (c_en),
        .R_nW        (c_rnw),
        .RS          (c_rs),
        .DI          (wdata_q),
        .DO          (c_do),
        .DO_VALID    (c_do_valid),
        .VSYNC       (c_vs),
        .HSYNC       (c_hs),
        .DE          (c_de),
        .CURSOR      (c_cursor),
        .LPSTB       (1'b0),
        .VGA         (1'b0),
        .MA          (c_ma),
        .RA          (c_ra),
        .test        (c_test),
        .R1_ACTIVE   (c_r1),
        .H_DISPLAY_O (c_hdisp),
        .V_DISPLAY_O (c_vdisp)
    );

    assign crtc_rdata = c_do_valid ? c_do : 8'hFF;

    // ----------------------------------------------------------------- fetch
    // word = MA[4:0] + 32*RA[3:0] + 512*MA[9:5], a concatenation.  The plane holds 8K words, so
    // MA9 (word address bit 13) is dropped: rows 16-31 alias rows 0-15.
    logic [12:0] fetch_addr;
    assign fetch_addr = {c_ma[8:5], c_ra[3:0], c_ma[4:0]};

    logic [15:0] plane_q [0:3];
    genvar n;
    generate
    for (n = 0; n < 4; n = n + 1) begin : g_plane
        localparam logic [1:0] PN = n;
        m20_vplane u_plane (
            .clk   (clk),
            .we    (vram_we && (vram_plane == PN)),
            .waddr (vram_addr),
            .be    (vram_be),
            .wdata (vram_wdata),
            .raddr (fetch_addr),
            .q     (plane_q[n])
        );
    end
    endgenerate

    // CRTC step delayed to C+2, where DE is valid.
    logic [1:0] step_q;
    always_ff @(posedge clk) step_q <= {step_q[0], ce_crtc};

    // Registered crt_fetch pulse.
    always_ff @(posedge clk) begin
        if (!rst_n) crt_fetch <= 1'b0;
        else        crt_fetch <= step_q[1] & c_de;
    end

    // ---------------------------------------------------------- pixel path
    m20_vid_out u_out (
        .clk      (clk),
        .rst_n    (rst_n),
        .ce_pix   (ce_pix),
        .load     (load),
        .p0       (plane_q[0]),
        .p1       (plane_q[1]),
        .p2       (plane_q[2]),
        .p3       (plane_q[3]),
        .de       (c_de),
        .hs       (c_hs),
        .vs       (c_vs),
        .hb       (~c_hdisp),
        .vb       (~c_vdisp),
        .mode_bw  (cfg_code[2]),
        .mode_c4  (cfg_code[0]),
        .pal_we   (pal_we),
        .pal_idx  (wreg_q),
        .pal_data (wdata_q[3:0]),
        .r        (vga_r),
        .g        (vga_g),
        .b        (vga_b),
        .hsync    (hsync),
        .vsync    (vsync),
        .hblank   (hblank),
        .vblank   (vblank)
    );

    logic unused_ok;
    assign unused_ok = &{1'b0, io_addr[15:3], io_addr[0], io_wdata[15:8],
                         cfg_code[1], c_cursor, c_ma[13:9], c_ra[4], c_test, c_r1};

endmodule

`default_nettype wire
