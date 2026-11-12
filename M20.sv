//============================================================================
//  Olivetti L1 M20 for MiSTer: the emu shell around m20_core.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL      = 0;
assign VGA_F1      = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_POWER = 0;
assign BUTTONS   = 0;
assign USER_OUT  = 7'h7F;

//////////////////////////////////////////////////////////////////
// Status bit map
//   0       reset
//   3:1     configuration (jumpers BW^COL, 32^128, COL4^8)
//   6:4     jumpers ZA/SPARE1 (port 0x21 D3/D4): self-test switch, ROM 2.x floppy type
//   7       IEEE-488 card
//   8       twin RS-232 card
//   10:9    serial port on the UART: mainboard, twin A, twin B
//   11      APB 1086 8086 card
//   13:12   keyboard layout
//   122:121 aspect ratio
//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"M20;UART9600:4800:2400:1200:300;",
	"-;",
	"S0,IMG,Floppy 0;",
	"S1,IMG,Floppy 1;",
	"S2,IMG,Hard disk 0;",
	"S3,IMG,Hard disk 1;",
	"-;",
	"O[3:1],Configuration,B/W 128K cards,B/W 32K cards,B/W no cards,4 colours 32K,4 colours 128K,8 colours 32K,8 colours 128K;",
	"O[6:4],Jumpers ZA/SPARE1,2.x 320K drives,2.x 640K drives,2.x 160K drives,2.x ask drive type,1.x full tests,1.x skip tests;",
	"O[13:12],Keyboard,US,UK,Italian,German;",
	"-;",
	"O[7],IEEE-488 card,Off,On;",
	"O[8],Twin RS-232 card,Off,On;",
	"O[10:9],Serial port,Mainboard,Twin card A,Twin card B;",
	"O[11],APB 8086 card,Off,On;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"F1,ROMBIN,Load Firmware;",
	"F2,ROMBIN,Load extension ROM;",
	"F3,ROM,Load APB ROM;",
	"R[0],Reset;",
	"v,6;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[4];
wire  [5:0] sd_blk_cnt[4];
wire  [3:0] sd_rd;
wire  [3:0] sd_wr;
wire  [3:0] sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[4];
wire        sd_buff_wr;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(4)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_in(128'd0),
	.status_set(1'b0),
	.status_menumask(16'd0),

	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(1'b0),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba('{sd_lba[0], sd_lba[1], sd_lba[2], sd_lba[3]}),
	.sd_blk_cnt('{sd_blk_cnt[0], sd_blk_cnt[1], sd_blk_cnt[2], sd_blk_cnt[3]}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din[0], sd_buff_din[1], sd_buff_din[2], sd_buff_din[3]}),
	.sd_buff_wr(sd_buff_wr)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, clk_ram;
wire pll_locked;

// clk_sys: the one machine clock, 48 MHz (CLK_VIDEO too).  clk_ram: 96 MHz
// for the SDRAM controller, rising edges with clk_sys.
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_ram),
	.locked(pll_locked)
);

///////////////////////   RESET   ////////////////////////////////

wire reset_in;
c900_sync2 #(.INIT(1'b1)) u_reset_sync (.clk(clk_sys), .d(RESET), .q(reset_in));

// Main holds status[0] from the core load until the options, boot.rom and
// the mounts are in: that is power-on, not a reset press.
reg hps_rst = 1'b1, hps_seen = 1'b0;
always @(posedge clk_sys) begin
	if (status[0]) hps_seen <= 1'b1;
	if (hps_seen && !status[0]) hps_rst <= 1'b0;
end

wire sdram_ready;
reg  reset_req = 1'b1;
always @(posedge clk_sys)
	reset_req <= reset_in | hps_rst | status[0] | buttons[1] | ioctl_download | ~sdram_ready;

wire rst_n;
c900_rst_sync u_rst (.clk(clk_sys), .arst(reset_req), .pll_locked(pll_locked), .rst_n(rst_n));

// Jumpers are read at reset, as on the board.  OSD order -> configuration
// code {BW^COL, 32^128, COL4^8} (port 0x21 D7..D5).
reg [2:0] cfg_code = 3'd6;
reg       cfg_za     = 1'b0;
reg       cfg_spare1 = 1'b1;
reg       cfg_ieee, cfg_twin, cfg_apb;
always @(posedge clk_sys) begin
	if (!rst_n) begin
		cfg_ieee <= status[7];
		cfg_twin <= status[8];
		cfg_apb  <= status[11];
		case (status[3:1])
			3'd0: cfg_code <= 3'd6;   // 128K cards, B/W
			3'd1: cfg_code <= 3'd7;   // 32K cards, B/W
			3'd2: cfg_code <= 3'd5;   // no cards, B/W
			3'd3: cfg_code <= 3'd3;   // 32K cards, 4 colours
			3'd4: cfg_code <= 3'd1;   // 128K cards, 4 colours
			3'd5: cfg_code <= 3'd2;   // 32K cards, 8 colours
			3'd6: cfg_code <= 3'd0;   // 128K cards, 8 colours
			default: cfg_code <= 3'd6;
		endcase
		// {SPARE1, ZA} = port 0x21 D4:D3.  ROM 1.x reads ZA as the self-test
		// switch; ROM 2.x reads D4:D3 as the floppy type (0 = ask).
		case (status[6:4])
			3'd0: {cfg_spare1, cfg_za} <= 2'b10;   // 2.x type 2, 320K
			3'd1: {cfg_spare1, cfg_za} <= 2'b11;   // 2.x type 3, 640K
			3'd2: {cfg_spare1, cfg_za} <= 2'b01;   // 2.x type 1, 160K
			3'd3: {cfg_spare1, cfg_za} <= 2'b00;   // 2.x ask at boot
			3'd4: {cfg_spare1, cfg_za} <= 2'b11;   // 1.x full tests
			3'd5: {cfg_spare1, cfg_za} <= 2'b10;   // 1.x skip tests
			default: {cfg_spare1, cfg_za} <= 2'b10;
		endcase
	end
end

///////////////////////   FIRMWARE   /////////////////////////////

// boot.rom (index 0) or Load Firmware (index 1): up to 16 KB.  Extension
// ROM (index 2): up to 48 KB.
wire rom_ext   = ioctl_index[5:0] == 6'd2;
wire rom_index = ioctl_index[7:0] == 8'd0 || ioctl_index[5:0] == 6'd1 || rom_ext;
wire rom_wr    = ioctl_download && ioctl_wr && rom_index &&
                 (ioctl_addr[26:16] == 11'd0) && (rom_ext || ioctl_addr[15:14] == 2'd0);

reg  dl_q = 1'b0;
always @(posedge clk_sys) dl_q <= ioctl_download;
wire rom_start = ioctl_download && !dl_q && rom_index;

// boot1.rom (index 0x40) or Load APB ROM (index 3): 18 KB APB image.
wire apb_ld_we = ioctl_download && ioctl_wr && (ioctl_index[7:0] == 8'h40 || ioctl_index[5:0] == 6'd3) &&
                 (ioctl_addr[26:15] == 12'd0);

///////////////////////   MEMORY   ///////////////////////////////

wire [23:1] mem_addr;
wire        mem_rd, mem_wr, mem_rvalid, mem_ack, mem_refresh_ok;
wire  [1:0] mem_be;
wire [15:0] mem_wdata, mem_rdata;

// SDRAM follows PLL lock only: memory survives a machine reset.
wire sdram_rst_n, sdram_ram_rst_n;
c900_rst_sync u_sdram_rst (.clk(clk_sys), .arst(1'b0), .pll_locked(pll_locked), .rst_n(sdram_rst_n));
c900_rst_sync u_sdram_ram_rst (.clk(clk_ram), .arst(1'b0), .pll_locked(pll_locked), .rst_n(sdram_ram_rst_n));

c900_sdram u_sdram (
	.clk(clk_sys), .clk_ram(clk_ram), .rst_n(sdram_rst_n), .rst_ram_n(sdram_ram_rst_n),
	.refresh_ok(mem_refresh_ok), .ready(sdram_ready),
	.addr(mem_addr), .rd(mem_rd), .wr(mem_wr), .be(mem_be), .wdata(mem_wdata),
	.rdata(mem_rdata), .rvalid(mem_rvalid), .ack(mem_ack),
	.sdram_clk(SDRAM_CLK), .sdram_cke(SDRAM_CKE), .sdram_a(SDRAM_A), .sdram_ba(SDRAM_BA),
	.sdram_dq(SDRAM_DQ), .sdram_dqml(SDRAM_DQML), .sdram_dqmh(SDRAM_DQMH),
	.sdram_ncs(SDRAM_nCS), .sdram_nras(SDRAM_nRAS), .sdram_ncas(SDRAM_nCAS), .sdram_nwe(SDRAM_nWE)
);

///////////////////////   SERIAL   ///////////////////////////////

// The HPS UART goes to the RS-232 port picked in the OSD.  UART_CTS and
// UART_DSR are not used: the core holds CTS and DSR asserted.
wire uart_rxd_s;
c900_sync2 #(.INIT(1'b1)) u_rxd_sync (.clk(clk_sys), .d(UART_RXD), .q(uart_rxd_s));

reg  [1:0] ser_sel = 2'd0;
always @(posedge clk_sys) ser_sel <= status[10:9];

wire ser_txd, ser_rts_n, ser_dtr_n;
assign UART_TXD = ser_txd;
assign UART_RTS = ser_rts_n;
assign UART_DTR = ser_dtr_n;

///////////////////////   DISK IMAGES   //////////////////////////

// Disk images are streamed from the SD card on demand, one cylinder per
// drive in BRAM, written back in the background (disk_stream).  Slots 0
// and 1 are floppies, 2 and 3 hard disks (99 blocks per cylinder).
wire [3:0][31:0] st_h_lba;
wire [3:0][5:0]  st_h_blk_cnt;
wire  [7:0]      st_h_din;
genvar gs;
generate
	for (gs = 0; gs < 4; gs = gs + 1) begin : g_sd
		assign sd_lba[gs]      = st_h_lba[gs];
		assign sd_blk_cnt[gs]  = st_h_blk_cnt[gs];
		assign sd_buff_din[gs] = st_h_din;
	end
endgenerate

wire  [3:0]      core_img_mounted;
wire             core_img_readonly;
wire [63:0]      core_img_size;
wire [1:0][31:0] core_fd_lba;
wire  [1:0]      core_fd_rd, core_fd_wr;
wire  [3:0]      core_sd_ack;
wire  [8:0]      core_sd_buff_addr;
wire  [7:0]      core_sd_buff_dout;
wire [1:0][7:0]  core_fd_buff_din;
wire [1:0][31:0] core_hd_lba;
wire  [1:0]      core_hd_rd, core_hd_wr;
wire [1:0][7:0]  core_hd_buff_din;
wire             core_sd_buff_wr;
wire  [3:0]      ds_resident;
wire             img_loading, img_wb_busy, fmt_full;
wire [1:0][15:0] ld_min, ld_max;

disk_stream #(.UMAX(99)) u_disk_stream (
	.clk(clk_sys), .rst_n(sdram_rst_n), .core_rst_n(rst_n), .bpc({12'd99, 12'd99}),
	.img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
	.h_lba(st_h_lba), .h_blk_cnt(st_h_blk_cnt), .h_rd(sd_rd), .h_wr(sd_wr), .h_ack(sd_ack),
	.h_buff_addr(sd_buff_addr), .h_buff_dout(sd_buff_dout), .h_buff_din(st_h_din),
	.h_buff_wr(sd_buff_wr),
	.d_mounted(core_img_mounted), .d_readonly(core_img_readonly), .d_size(core_img_size),
	.d_lba({core_hd_lba, core_fd_lba}), .d_scr(4'd0),
	.d_rd({core_hd_rd, core_fd_rd}), .d_wr({core_hd_wr, core_fd_wr}), .d_ack(core_sd_ack),
	.d_buff_addr(core_sd_buff_addr), .d_buff_dout(core_sd_buff_dout),
	.d_buff_din({core_hd_buff_din, core_fd_buff_din}),
	.d_buff_wr(core_sd_buff_wr),
	.resident(ds_resident), .busy(img_loading), .wb_busy(img_wb_busy), .fmt_full(fmt_full),
	.ld_min(ld_min), .ld_max(ld_max)
);

///////////////////////   CORE   /////////////////////////////////

// Keyboard national code (P14-P17 jumpers): US 4, UK 3, Italian 0, German 1.
wire [3:0] kbd_layout = (status[13:12] == 2'd0) ? 4'd4 :
                        (status[13:12] == 2'd1) ? 4'd3 :
                        (status[13:12] == 2'd2) ? 4'd0 : 4'd1;

wire       ce_pix, hsync, vsync, hblank, vblank;
wire [7:0] vid_r, vid_g, vid_b;
wire       beep, led_fdd, apb_run;

m20_core u_core (
	.clk(clk_sys), .rst_n(rst_n),
	.cfg_code(cfg_code), .cfg_za(cfg_za), .cfg_spare1(cfg_spare1),
	.cfg_ieee(cfg_ieee), .cfg_twin(cfg_twin), .ser_sel(ser_sel),
	.rom_wr(rom_wr), .rom_addr(ioctl_addr[15:0]), .rom_data(ioctl_dout),
	.rom_ext(rom_ext), .rom_start(rom_start),
	.apb_fitted(cfg_apb), .apb_ld_we(apb_ld_we), .apb_ld_addr(ioctl_addr[14:0]), .apb_ld_data(ioctl_dout),
	.apb_run(apb_run),
	.mem_addr(mem_addr), .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_be(mem_be),
	.mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_rvalid(mem_rvalid), .mem_ack(mem_ack),
	.mem_ready(sdram_ready), .mem_refresh_ok(mem_refresh_ok),
	.fd_mounted(core_img_mounted[1:0]), .fd_readonly(core_img_readonly), .fd_size(core_img_size),
	.fd_lba(core_fd_lba), .fd_rd(core_fd_rd), .fd_wr(core_fd_wr), .fd_ack(core_sd_ack[1:0]),
	.fd_buff_addr(core_sd_buff_addr), .fd_buff_dout(core_sd_buff_dout), .fd_buff_din(core_fd_buff_din),
	.fd_buff_wr(core_sd_buff_wr),
	.hd_mounted(core_img_mounted[3:2]), .hd_lba(core_hd_lba), .hd_rd(core_hd_rd), .hd_wr(core_hd_wr),
	.hd_ack(core_sd_ack[3:2]), .hd_buff_din(core_hd_buff_din),
	.ps2_key(ps2_key), .osd_active(OSD_STATUS), .kbd_layout(kbd_layout),
	.ser_rxd(uart_rxd_s), .ser_txd(ser_txd),
	.ser_rts_n(ser_rts_n), .ser_dtr_n(ser_dtr_n),
	.ce_pix(ce_pix), .vid_r(vid_r), .vid_g(vid_g), .vid_b(vid_b),
	.hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
	.beep(beep), .led_fdd(led_fdd)
);

///////////////////////   AUDIO   ////////////////////////////////

// Keyboard buzzer (8048 P27): m20_kbd toggles beep at 3100 Hz during a bell.
reg  [15:0] audio_q = 16'h0000;
always @(posedge clk_sys) audio_q <= beep ? 16'h1800 : 16'h0000;

assign AUDIO_S   = 1;
assign AUDIO_L   = audio_q;
assign AUDIO_R   = audio_q;
assign AUDIO_MIX = 0;

///////////////////////   VIDEO   ////////////////////////////////

// 12 MHz dots (ce_pix) on the 48 MHz CLK_VIDEO: 4 clocks per pixel.
// 18.3-18.75 kHz lines take the scandoubler.
assign CLK_VIDEO = clk_sys;

video_mixer #(.LINE_LENGTH(660), .HALF_DEPTH(0), .GAMMA(0)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix),
	.scandoubler(forced_scandoubler),
	.hq2x(1'b0),
	.gamma_bus(),
	.R(vid_r), .G(vid_g), .B(vid_b),
	.HSync(hsync), .VSync(vsync), .HBlank(hblank), .VBlank(vblank),
	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_VS(VGA_VS), .VGA_HS(VGA_HS), .VGA_DE(VGA_DE)
);

///////////////////////   LEDS   /////////////////////////////////

// The disk LED stays on while written sectors are still queued for the
// image file: eject only once it is off.
assign LED_DISK = {1'b0, led_fdd | img_loading | img_wb_busy};
assign LED_USER = ~pll_locked | apb_run;

endmodule
