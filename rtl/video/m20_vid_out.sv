// M20 pixel path: the CRT data-out
// latch and 74LS166 shifters (U124/U145, one per plane), the 74LS670
// palette (U88), the 74LS244 8-colour bypass (U89) and the 74S163 pixel
// register (U61, cleared by blanking).
//
// Per character (16 ce_pix), with `load` = the ce_pix that starts it:
//   load:      shifters <= plane words; char latch <= {de, hs, vs, hb, vb}.
//              Pixel register takes the previous character's last pixel.
//   load+k:    pixel register <= colour(shifter MSBs) gated by the latched
//              DE; sync register <= char latch; shifters << 1.
// So pixel k (k = 0 leftmost = word bit 15) of a character leaves the
// pixel register on the (k+1)-th ce_pix after its load, together with that
// character's syncs and blanks.  Outputs change only on ce_pix.
//
// Modes from the configuration code {BW, 32/128, COL4^8}:
//   BW = 1:           plane 0, 1 = white.
//   BW = 0, D5 = 1:   4 colours: entry = 2*plane0 + plane1, entry bit 0 = R,
//                     1 = G, 2 = B, 3 = bright.
//   BW = 0, D5 = 0:   8 colours: plane0 = G, plane1 = B, plane2 = R,
//                     plane3 = bright.
// Intensity: a lit channel is 0xFF; an unlit channel is 0x00, or 0x55 with
// bright (bright only lightens the PCOS colours).
`default_nettype none

module m20_vid_out (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ce_pix,
    input  logic        load,       // ce_pix that starts a character
    input  logic [15:0] p0,
    input  logic [15:0] p1,
    input  logic [15:0] p2,
    input  logic [15:0] p3,
    input  logic        de,
    input  logic        hs,
    input  logic        vs,
    input  logic        hb,
    input  logic        vb,
    input  logic        mode_bw,    // config code D7
    input  logic        mode_c4,    // config code D5
    input  logic        pal_we,
    input  logic  [1:0] pal_idx,
    input  logic  [3:0] pal_data,
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,
    output logic        hsync,
    output logic        vsync,
    output logic        hblank,
    output logic        vblank
);

    localparam logic [7:0] LVL_ON  = 8'hFF;
    localparam logic [7:0] LVL_BRT = 8'h55;
    localparam logic [7:0] LVL_OFF = 8'h00;

    // 74LS670 register file, no reset.
    logic [3:0] pal_q [0:3];
    always_ff @(posedge clk) begin
        if (pal_we) pal_q[pal_idx] <= pal_data;
    end

    // The four plane shift registers.
    logic [15:0] sh0_q, sh1_q, sh2_q, sh3_q;
    always_ff @(posedge clk) begin
        if (load) begin
            sh0_q <= p0;
            sh1_q <= p1;
            sh2_q <= p2;
            sh3_q <= p3;
        end else if (ce_pix) begin
            sh0_q <= {sh0_q[14:0], 1'b0};
            sh1_q <= {sh1_q[14:0], 1'b0};
            sh2_q <= {sh2_q[14:0], 1'b0};
            sh3_q <= {sh3_q[14:0], 1'b0};
        end
    end

    // Character latch: syncs and DE of the character in the shifters.
    logic de_q, hs_q, vs_q, hb_q, vb_q;
    always_ff @(posedge clk) begin
        if (!rst_n)    de_q <= 1'b0;
        else if (load) de_q <= de;
    end
    always_ff @(posedge clk) begin
        if (load) {hs_q, vs_q, hb_q, vb_q} <= {hs, vs, hb, vb};
    end

    logic [3:0] entry;
    logic       c_r, c_g, c_b, c_i;

    always_comb begin
        entry = pal_q[{sh0_q[15], sh1_q[15]}];
        c_r = 1'b0; c_g = 1'b0; c_b = 1'b0; c_i = 1'b0;
        if (mode_bw) begin
            c_r = sh0_q[15]; c_g = sh0_q[15]; c_b = sh0_q[15];
        end else if (mode_c4) begin
            c_r = entry[0]; c_g = entry[1]; c_b = entry[2]; c_i = entry[3];
        end else begin
            c_g = sh0_q[15]; c_b = sh1_q[15]; c_r = sh2_q[15]; c_i = sh3_q[15];
        end
    end

    function automatic logic [7:0] lvl(input logic on, input logic brt);
        lvl = on ? LVL_ON : (brt ? LVL_BRT : LVL_OFF);
    endfunction

    // The 74S163 pixel register and the matching sync/blank register.
    always_ff @(posedge clk) begin
        if (ce_pix) begin
            r <= de_q ? lvl(c_r, c_i) : LVL_OFF;
            g <= de_q ? lvl(c_g, c_i) : LVL_OFF;
            b <= de_q ? lvl(c_b, c_i) : LVL_OFF;
            {hsync, vsync, hblank, vblank} <= {hs_q, vs_q, hb_q, vb_q};
        end
    end

endmodule

`default_nettype wire
