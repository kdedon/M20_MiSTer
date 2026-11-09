// m20_video bench.  Programs the CRTC with the boot ROM's B/W and colour
// tables through the I/O bus, fills the planes through the VRAM snoop and
// checks, against the documented timings and a reference model of the
// bitmap and colour rules:
//   1. line/frame periods, sync widths and positions, active area
//   2. every pixel of a frame in B/W, scrolled B/W, 4-colour, 8-colour
//   3. palette entries 0..15, the ROM's 0,0,1,1 palette, the 8-colour bypass
//   4. R15 (and R14) readback, unreadable registers float
//   5. crt_fetch count, outputs changing only after ce_pix
// Writes one PPM per mode to out/.
`timescale 1ps/1ps
`default_nettype none

module tb_video;

    logic clk = 1'b0;
    always #10417 clk = ~clk;     // 48 MHz

    logic        rst_n;
    logic [15:0] io_addr, io_wdata;
    logic        io_rd, io_wr, io_wr_end, cs_crtc, cs_pal;
    logic  [7:0] crtc_rdata;
    logic        vram_we;
    logic  [1:0] vram_plane;
    logic [13:1] vram_addr;
    logic  [1:0] vram_be;
    logic [15:0] vram_wdata;
    logic  [2:0] cfg_code;
    logic        ce_pix;
    logic  [7:0] vga_r, vga_g, vga_b;
    logic        hsync, vsync, hblank, vblank, crt_fetch;

    m20_video dut (.*);

    // ------------------------------------------------------------ helpers
    int errors = 0;
    task automatic check(input bit ok, input string what);
        if (!ok) begin
            errors++;
            $display("FAIL: %s", what);
            if (errors > 20) $fatal(1, "too many errors");
        end
    endtask

    task automatic io_write(input logic [15:0] a, input logic [7:0] d);
        @(negedge clk);
        io_addr = a;
        cs_crtc = (a[8:5] == 4'h3) && !a[15:11];
        cs_pal  = (a[8:5] == 4'hC) && !a[15:11];
        repeat (2) @(negedge clk);
        io_wdata = {d, d};
        io_wr = 1'b1;
        repeat (6) @(negedge clk);
        io_wr = 1'b0;
        io_wr_end = 1'b1;
        io_wdata = 16'h5A5A;      // data gone at the commit: capture must hold it
        @(negedge clk);
        io_wr_end = 1'b0;
        cs_crtc = 1'b0;
        cs_pal = 1'b0;
        io_addr = 16'hFFFF;
        @(negedge clk);
    endtask

    task automatic io_read(input logic [15:0] a, output logic [7:0] d);
        @(negedge clk);
        io_addr = a;
        cs_crtc = (a[8:5] == 4'h3) && !a[15:11];
        cs_pal  = (a[8:5] == 4'hC) && !a[15:11];
        repeat (2) @(negedge clk);
        io_rd = 1'b1;
        repeat (6) @(negedge clk);
        d = crtc_rdata;           // sampled at the /DS rise
        io_rd = 1'b0;
        cs_crtc = 1'b0;
        cs_pal = 1'b0;
        io_addr = 16'hFFFF;
        @(negedge clk);
    endtask

    task automatic crtc_wr(input logic [4:0] r, input logic [7:0] v);
        io_write(16'h0061, {3'b000, r});
        io_write(16'h0063, v);
    endtask

    // The boot ROM's c6845_ini tables, without R10/R11.
    localparam logic [7:0] BW_TAB  [0:13] = '{8'h27, 8'h20, 8'h22, 8'h05, 8'h10, 8'h03, 8'h10,
                                             8'h10, 8'h00, 8'h0F, 8'h00, 8'h00, 8'h00, 8'h00};
    localparam logic [7:0] COL_TAB [0:13] = '{8'h28, 8'h20, 8'h22, 8'h06, 8'h10, 8'h0C, 8'h10,
                                             8'h10, 8'h00, 8'h0F, 8'h00, 8'h00, 8'h00, 8'h00};

    task automatic crtc_program(input bit colour);
        for (int r = 0; r < 14; r++) crtc_wr(5'(r), colour ? COL_TAB[r] : BW_TAB[r]);
    endtask

    // Reference planes.
    logic [15:0] ref_mem [0:3][0:8191];

    task automatic vwrite(input int p, input int a, input logic [1:0] be, input logic [15:0] d);
        @(negedge clk);
        vram_we = 1'b1;
        vram_plane = 2'(p);
        vram_addr = 13'(a);
        vram_be = be;
        vram_wdata = d;
        if (be[1]) ref_mem[p][a][15:8] = d[15:8];
        if (be[0]) ref_mem[p][a][7:0]  = d[7:0];
        @(negedge clk);
        vram_we = 1'b0;
        vram_wdata = 16'hDEAD;
    endtask

    function automatic logic [15:0] hash(input int p, input int a);
        logic [31:0] x;
        x = 32'(a) * 32'h9E3779B1 + 32'(p) * 32'h85EBCA6B;
        x = x ^ (x >> 15);
        x = x * 32'h2C1B3C6D;
        return x[31:16] ^ x[15:0];
    endfunction

    // Plane 0: frame, diagonal; plane 1: 64-pixel bars; plane 2: 16-line
    // bands; plane 3: one block.
    function automatic logic [15:0] pic(input int p, input int a);
        int y, wx;
        logic [15:0] w;
        y = a / 32;
        wx = a % 32;
        w = 16'h0000;
        case (p)
            0: begin
                if (y == 0 || y == 127) w = 16'hFFFF;
                if (wx == 0) w[15] = 1'b1;
                if (wx == 31) w[0] = 1'b1;
                if ((y * 4) / 16 == wx) w[15 - (y * 4) % 16] = 1'b1;
            end
            1: w = ((wx / 4) % 2 == 1) ? 16'hFFFF : 16'h0000;
            2: w = ((y / 16) % 2 == 1) ? 16'hFFFF : 16'h0000;
            default: w = (wx >= 16 && wx < 24 && y >= 32 && y < 96) ? 16'hFFFF : 16'h0000;
        endcase
        return w;
    endfunction

    // ------------------------------------------------------------ monitor
    // Sampled on negedges: the values the mixer takes at the next posedge
    // when ce_pix is high.
    logic [23:0] fb [0:255][0:511];
    int  pc = 0, cyc = 0;
    int  ax = 0, ay = 0, last_w = 0, frames = 0, act_lines = 0;
    int  hs_rise_pc = 0, hs_rise_cyc = 0, line_px = 0, line_cyc = 0, hs_w = 0;
    int  vs_rise_cyc = 0, frame_cyc = 0, lines_cnt = 0, frame_lines = 0;
    int  vs_lines = 0, vs_w_lines = 0, de_start_pc = 0, hs_from_de = 0;
    int  vs_line_in_frame = 0, vb_fall_line = 0, vs_after_active = 0;
    int  fetch_cnt = 0, frame_fetch = 0;
    int  bad_width = 0, blank_rgb = 0, ungated = 0;
    logic phs = 1'b0, pvs = 1'b0, phb = 1'b1, pvb = 1'b1, pce = 1'b0;
    logic [27:0] pout = '0;

    always @(negedge clk) begin
        cyc++;
        if (crt_fetch) fetch_cnt++;
        if (rst_n && !pce && {vga_r, vga_g, vga_b, hsync, vsync, hblank, vblank} != pout) ungated++;
        pout = {vga_r, vga_g, vga_b, hsync, vsync, hblank, vblank};
        pce = ce_pix;
        if (ce_pix) begin
            pc++;
            if (hsync && !phs) begin
                line_px = pc - hs_rise_pc;
                line_cyc = cyc - hs_rise_cyc;
                hs_rise_pc = pc;
                hs_rise_cyc = cyc;
                hs_from_de = pc - de_start_pc;
                lines_cnt++;
                if (vsync) vs_lines++;
            end
            if (!hsync && phs) hs_w = pc - hs_rise_pc;
            if (vsync && !pvs) begin
                frame_cyc = cyc - vs_rise_cyc;
                vs_rise_cyc = cyc;
                frame_lines = lines_cnt;
                lines_cnt = 0;
                vs_lines = 0;
                frame_fetch = fetch_cnt;
                fetch_cnt = 0;
                vs_after_active = (vblank && !pvb) ? 0 : vs_line_in_frame;
            end
            if (!vsync && pvs) vs_w_lines = vs_lines;
            if (!hblank && phb) de_start_pc = pc;
            if (!vblank && pvb) begin
                ay = 0;
                ax = 0;
                vb_fall_line = lines_cnt;
            end
            if (!hblank && !vblank) begin
                if (ay < 256 && ax < 512) fb[ay][ax] = {vga_r, vga_g, vga_b};
                ax++;
            end else if (rst_n && (vga_r != 0 || vga_g != 0 || vga_b != 0)) blank_rgb++;
            if (hblank && !phb && !vblank) begin
                last_w = ax;
                if (ax != 512) bad_width++;
                ax = 0;
                ay++;
            end
            if (vblank && !pvb) begin
                act_lines = ay;
                vs_line_in_frame = 0;
                frames++;
            end
            if (hsync && !phs && vblank) vs_line_in_frame++;
            phs = hsync; pvs = vsync; phb = hblank; pvb = vblank;
        end
    end

    task automatic next_frame(); // returns just after a complete frame
        int f0;
        f0 = frames;
        wait (frames == f0 + 2);
    endtask

    // ------------------------------------------------------------ model
    typedef enum logic [1:0] {MBW, MC4, MC8} mode_e;

    function automatic logic [7:0] lvl(input logic on, input logic brt);
        return on ? 8'hFF : (brt ? 8'h55 : 8'h00);
    endfunction

    function automatic logic [23:0] expect_px(input mode_e m, input logic [3:0] pal [0:3],
                                              input int x, input int y, input int line0);
        int w, bit_n;
        logic p0, p1, p2, p3;
        logic [3:0] e;
        w = ((y + line0) % 256) * 32 + x / 16;     // line n at byte 0x40*n
        bit_n = 15 - (x % 16);                     // MSB = leftmost
        p0 = ref_mem[0][w][bit_n];
        p1 = ref_mem[1][w][bit_n];
        p2 = ref_mem[2][w][bit_n];
        p3 = ref_mem[3][w][bit_n];
        case (m)
            MBW: return p0 ? 24'hFFFFFF : 24'h000000;
            MC4: begin
                e = pal[{p0, p1}];                  // entry = 2*plane0 + plane1
                return {lvl(e[0], e[3]), lvl(e[1], e[3]), lvl(e[2], e[3])};
            end
            default: return {lvl(p2, p3), lvl(p0, p3), lvl(p1, p3)};
        endcase
    endfunction

    task automatic check_frame(input string name, input mode_e m, input logic [3:0] pal [0:3],
                               input int line0);
        int bad;
        bad = 0;
        for (int y = 0; y < 256; y++)
            for (int x = 0; x < 512; x++)
                if (fb[y][x] !== expect_px(m, pal, x, y, line0)) begin
                    if (bad < 12)
                        $display("  %s (%0d,%0d) got %06x want %06x", name, x, y, fb[y][x],
                                 expect_px(m, pal, x, y, line0));
                    bad++;
                end
        check(bad == 0, $sformatf("%s: %0d pixel mismatches", name, bad));
        check(act_lines == 256, $sformatf("%s: %0d active lines", name, act_lines));
        check(last_w == 512, $sformatf("%s: %0d active pixels/line", name, last_w));
        $display("%s: frame compared, %0d mismatches", name, bad);
    endtask

    task automatic write_ppm(input string fname);
        int fd;
        fd = $fopen(fname, "w");
        $fwrite(fd, "P3\n512 256\n255\n");
        for (int y = 0; y < 256; y++) begin
            for (int x = 0; x < 512; x++)
                $fwrite(fd, "%0d %0d %0d ", fb[y][x][23:16], fb[y][x][15:8], fb[y][x][7:0]);
            $fwrite(fd, "\n");
        end
        $fclose(fd);
    endtask

    task automatic check_timing(input string name, input int dots, input int lines,
                                input int hsw);
        $display("%s: line %0d px / %0d clk (%.3f kHz), frame %0d lines / %0d clk (%.2f Hz)",
                 name, line_px, line_cyc, 48.0e3 / line_cyc, frame_lines, frame_cyc,
                 48.0e6 / frame_cyc);
        $display("%s: active %0d x %0d, HSync %0d px at dot %0d, VSync %0d lines at line %0d, fetches %0d",
                 name, last_w, act_lines, hs_w, hs_from_de, vs_w_lines, 256 + vs_after_active,
                 frame_fetch);
        check(line_px == dots, $sformatf("%s line %0d px", name, line_px));
        check(line_cyc == dots * 4, $sformatf("%s line %0d clk", name, line_cyc));
        check(frame_lines == lines, $sformatf("%s frame %0d lines", name, frame_lines));
        check(frame_cyc == dots * 4 * lines, $sformatf("%s frame %0d clk", name, frame_cyc));
        check(hs_w == hsw * 16, $sformatf("%s HSync width %0d", name, hs_w));
        check(hs_from_de == 544, $sformatf("%s HSync at dot %0d", name, hs_from_de));
        check(vs_w_lines == 16, $sformatf("%s VSync %0d lines", name, vs_w_lines));
        check(vs_after_active == 0, $sformatf("%s VSync not at line 256 (%0d)", name, vs_after_active));
        check(frame_fetch == 32 * 256, $sformatf("%s %0d fetches", name, frame_fetch));
    endtask

    // ------------------------------------------------------------ test
    logic [3:0] pal [0:3];
    logic [7:0] d;

    task automatic pal_set(input logic [3:0] a, b, c, e);
        pal[0] = a; pal[1] = b; pal[2] = c; pal[3] = e;
        for (int k = 0; k < 4; k++) io_write(16'h0181 + 16'(2 * k), {4'hF, pal[k]});
    endtask

    initial begin
        rst_n = 1'b0;
        io_addr = 16'hFFFF; io_wdata = 16'h0; io_rd = 1'b0; io_wr = 1'b0; io_wr_end = 1'b0;
        cs_crtc = 1'b0; cs_pal = 1'b0;
        vram_we = 1'b0; vram_plane = 2'd0; vram_addr = 13'd0; vram_be = 2'b11;
        vram_wdata = 16'h0;
        cfg_code = 3'b101;                         // code 5: B/W
        repeat (37) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(negedge clk);

        // Planes: hashed patterns, plus marker words in plane 0.
        // Lines 0-127 a picture, 128-255 hashed words.
        for (int p = 0; p < 4; p++)
            for (int a = 0; a < 8192; a++) vwrite(p, a, 2'b11, a < 4096 ? pic(p, a) : hash(p, a));
        vwrite(0, 0, 2'b11, 16'h8000);             // (0,0) only
        vwrite(0, 31, 2'b11, 16'h0001);            // (511,0) only
        vwrite(0, 32, 2'b11, 16'hC000);            // line 1 at byte 0x40
        vwrite(0, 64 * 100 / 2, 2'b10, 16'hFF00);  // line 100 left byte only
        vwrite(0, 64 * 100 / 2, 2'b01, 16'h1234);  // right byte only

        // 4. R15 readback, R14, unreadable registers.
        for (int n = 255; n >= 1; n--) begin
            crtc_wr(5'd15, 8'(n));
            io_read(16'h0063, d);
            check(d == 8'(n), $sformatf("R15 read %02x want %02x", d, n));
        end
        crtc_wr(5'd14, 8'h3F);
        io_read(16'h0063, d);
        check(d == 8'h3F, $sformatf("R14 read %02x", d));
        io_write(16'h0061, 8'h0C);
        io_read(16'h0063, d);
        check(d == 8'hFF, $sformatf("R12 read %02x, want floating", d));
        io_read(16'h0061, d);
        check(d == 8'hFF, $sformatf("address register read %02x, want floating", d));
        $display("R15 readback: 255 values checked");

        // 1-2. B/W.
        crtc_program(1'b0);
        pal_set(4'h0, 4'h0, 4'h1, 4'h1);
        next_frame();
        check_timing("B/W", 640, 275, 5);
        check_frame("B/W", MBW, pal, 0);
        check(fb[0][0] == 24'hFFFFFF && fb[0][1] == 24'h000000 && fb[0][511] == 24'hFFFFFF &&
              fb[0][510] == 24'h000000, "leftmost/rightmost pixel of line 0");
        check(fb[1][0] == 24'hFFFFFF && fb[1][1] == 24'hFFFFFF && fb[1][2] == 24'h000000,
              "line 1 at word 32");
        write_ppm("out/bw.ppm");

        // Start address R12/R13 = 0x0020: row 1 first, MA9 wraps.
        crtc_wr(5'd13, 8'h20);
        next_frame();
        check_frame("B/W scrolled", MBW, pal, 16);
        crtc_wr(5'd13, 8'h00);

        // 3. 4-colour (code 3), ROM palette 0,0,1,1: plane 0 red.
        cfg_code = 3'b011;
        crtc_program(1'b1);
        pal_set(4'h0, 4'h0, 4'h1, 4'h1);
        next_frame();
        check_timing("colour", 656, 284, 6);
        check_frame("4-colour ROM palette", MC4, pal, 0);
        check(fb[0][0] == 24'hFF0000, $sformatf("ROM palette (0,0) %06x, want red", fb[0][0]));
        write_ppm("out/col4.ppm");
        for (int s = 0; s < 4; s++) begin
            pal_set(4'(4 * s), 4'(4 * s + 1), 4'(4 * s + 2), 4'(4 * s + 3));
            next_frame();
            check_frame($sformatf("4-colour palette %0d-%0d", 4 * s, 4 * s + 3), MC4, pal, 0);
        end

        // 8-colour (code 0).
        cfg_code = 3'b000;
        next_frame();
        check_frame("8-colour", MC8, pal, 0);
        write_ppm("out/col8.ppm");

        check(ungated == 0, $sformatf("%0d output changes not after ce_pix", ungated));
        check(blank_rgb == 0, $sformatf("%0d non-black blanked pixels", blank_rgb));
        if (errors == 0) $display("PASS");
        else $fatal(1, "%0d errors", errors);
        $finish;
    end

    initial begin
        #400ms;
        $fatal(1, "timeout");
    end

endmodule

`default_nettype wire
