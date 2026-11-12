# Video -- theory of operation

RTL: `rtl/video/m20_video.sv` (CRTC, planes, fetch), `m20_vplane.sv` (one
plane BRAM), `m20_vid_out.sv` (shifters, palette, pixel register). The
MC6845 is the vendored C900 netlist (`rtl/vendor/c900/mc6845/`).

## 1. The hardware

The M20 displays a 512 x 256 bitmap. An MC6845 (U78) runs with a 750 kHz
character clock and a 16-dot character: each character fetch reads one
16-bit word per plane from the first 16 KB of a DRAM device, and 74LS166
shifters push the bits out at 12 MHz. The B/W board has one plane; the
colour boards have two (4 colours through a 74LS670 palette, U88) or four
(8 colours plus intensity, straight through U89). The CRTC's DE, HSYNC and
VSYNC go through a character-wide latch to meet the shifted pixels.

### Ports

| port | meaning |
|---|---|
| `io_addr`, `io_wdata`, `io_rd`, `io_wr`, `io_wr_end`, `cs_crtc`, `cs_pal`, `crtc_rdata` | CRTC at 0x61 (address) / 0x63 (data); palette entry k at 0x181 + 2k |
| `vram_we`, `vram_plane`, `vram_addr[13:1]`, `vram_be`, `vram_wdata` | the mainboard's DRAM write snoop |
| `cfg_code[2:0]` | `{BW, 32/128, COL4^8}`; bit 1 unused here |
| `ce_pix`, `vga_r/g/b[7:0]`, `hsync`, `vsync`, `hblank`, `vblank` | to `video_mixer` |
| `crt_fetch` | one clock per displayed character, to the T3 stretch |

No parameters.

## 2. Clocking and reset

```
 clk 48 MHz --div4_q--> ce_pix  12 MHz (U109 dot clock), dot_q counts 0..15
                        ce_crtc = ce_pix & dot 15   750 kHz MC6845 CLK
                        load    = ce_pix & dot 0    shifter load
```

The dividers free-run without reset; the CRTC takes `nRESET = rst_n`.
The CRTC steps on `CLKEN = ce_crtc`; its register port uses `CLKEN_CPU =
wr_crtc` so a write is applied in exactly one clock.

## 3. Blocks

```
 I/O bus --> [write capture] arm_crtc_q arm_pal_q wdata_q wreg_q
                 | wr_crtc (io_wr_end)         | pal_we
                 v                             v
            [mc6845 u_crtc] MA RA DE HS VS   [pal_q 74LS670] (in m20_vid_out)
                 |                                   |
                 v fetch_addr = {MA[8:5], RA[3:0], MA[4:0]}
 vram_* ---> [m20_vplane x4] plane_q[0..3] -----------+
                 |                                    v
            step_q, c_de --> crt_fetch        [m20_vid_out]
                                              sh0..sh3 (74LS166) --> colour --> pixel register (74S163)
                                              de_q hs_q vs_q hb_q vb_q (character latch) --> sync register
```

| block | state | notes |
|---|---|---|
| write capture | `arm_crtc_q`, `arm_pal_q`, `wdata_q`, `wreg_q` | a write seen while `io_wr & cs_*` is committed at `io_wr_end` |
| CRTC | the netlist | `ENABLE = wr_crtc | (cs_crtc & io_rd)`, `RS = A1`; `DO_VALID` gates reads |
| planes | 4 x `m20_vplane`, 8K x 16 each | write port = snoop, read port = fetch, registered read |
| fetch | `step_q[1:0]`, `crt_fetch` | `ce_crtc` delayed two clocks, when MA/RA and DE are valid |
| pixel path | `m20_vid_out` | section 4 |

Why this shape:

- **Planes are copies, not the DRAM.** PCOS and the ROM write the bitmap
  through ordinary memory cycles; the mainboard mirrors every write to
  block 0 of any device into the plane BRAM in the same cycle. Video then
  never touches the SDRAM, has no arbitration and no latency, and the
  CPU's T3 stretch can be a pure timing model.
- **One address for all planes.** On the board every plane sits at the
  same offset in its own device, so one `fetch_addr` reads all four
  BRAMs; a configuration with fewer planes leaves the others unwritten.
- **Delays are matched in characters, not pixels.** The CRTC's syncs and
  DE are latched at `load` with the plane words, then move with the
  pixels through the output register. Frame geometry is therefore the
  CRTC's and the bench checks it as such.

## 4. Operation

### Fetch

`fetch_addr = {c_ma[8:5], c_ra[3:0], c_ma[4:0]}`: word = MA[4:0] +
32 x RA[3:0] + 512 x MA[9:5] as the board wires the DRAM address, except
that MA9 (word bit 13) is dropped because the plane holds 8K words: rows
16-31 alias rows 0-15. The CRTC is programmed with 32 characters per line
and 16 scan lines per character row, 16 rows: 512 x 256.

Pipeline, C = the clock in which the CRTC steps (`ce_crtc`):

| clock | event |
|---|---|
| C | CRTC counters advance |
| C+1 | MA/RA valid; `fetch_addr` on the plane BRAMs |
| C+2 | `plane_q` valid; DE, HSYNC, VSYNC valid |
| C+3 | `crt_fetch` pulse (if DE) |
| C+4 | `load` (dot 0): shifters take `plane_q`, character latch takes DE and syncs |
| C+8+4k | pixel k (k = 0 is bit 15, leftmost) and that character's syncs at the outputs |

Syncs, blanks and pixels share the two-dot delay after the CRTC step.

### Pixel path (`m20_vid_out`)

At `load` the four shifters take the plane words; at every other `ce_pix`
they shift left. The colour of the current dot comes from the MSBs:

| mode (`cfg_code`) | rule |
|---|---|
| BW = 1 | plane 0 bit: white |
| BW = 0, COL4^8 = 1 (4 colours) | `entry = pal_q[{p0, p1}]`; entry bit 0 = R, 1 = G, 2 = B, 3 = bright |
| BW = 0, COL4^8 = 0 (8 colours) | plane 0 = G, plane 1 = B, plane 2 = R, plane 3 = bright (U89 bypass) |

A lit channel is 0xFF; an unlit one is 0x00, or 0x55 with bright (bright
lightens the dark channels of the PCOS colours). The pixel register
(74S163, cleared by blanking) stores the colour gated by the latched DE,
and the sync register stores the latched HS, VS, HB, VB in the same
clock; outputs change only on `ce_pix`.

`hblank`/`vblank` are the CRTC's horizontal and vertical display flags
inverted (`~c_hdisp`, `~c_vdisp`), DE is their AND. HSYNC and VSYNC are
the CRTC's, active High as the J5 75451 drivers give them; VSYNC is the
MC6845's fixed 16 lines.

### Register port

A CRTC write: `io_wr & cs_crtc` sets `arm_crtc_q` and captures the byte
and `{A2, A1}`; `io_wr_end` makes `wr_crtc`, one clock, with `RS =
wreg_q[0]`. A read presents `RS = io_addr[1]` while `cs_crtc & io_rd`;
`crtc_rdata = c_do_valid ? c_do : 0xFF`: R14-R17 read back, the other
registers and the address register float (the netlist's `DO_VALID`).
Palette writes (`cs_pal`) land in `pal_q[wreg_q]` with `wdata_q[3:0]`; the
74LS670 has no reset.

Frame timing with the boot ROM's tables, checked by the bench: B/W 640
dots x 275 lines (HSync 5 characters wide, at dot 544), colour 656 x 284
(HSync 6 characters); 18.75 kHz lines in B/W; 8192 fetches per frame.

## 5. Timing and resources

Four 8K x 16 planes = 64 KB of M10K (16 per plane), written one word per
snoop and read one word per character. The pixel path is a 12 MHz enable
on 48 MHz: three idle clocks per dot. Nothing here is near the clock
limit.

## 6. Inferred and assumed

| item | status |
|---|---|
| MA9 dropped, rows 16-31 alias | follows from the 16 KB plane; not checked on hardware |
| bright level 0x55, lit 0xFF | monitor levels are a choice |
| HSYNC/VSYNC polarity active High at the core output | from the 75451 drivers; `video_mixer` takes either |
| unreadable CRTC registers read 0xFF | the netlist's `DO_VALID`; the bench expects it |
| palette and 4-colour entry bit order | from the board's 74LS670/U89 wiring, checked against the ROM's 0,0,1,1 palette reading red |

## 7. Verification

| bench | checks |
|---|---|
| `tb/video/tb_video.sv` (`make tb-video`) | programs the CRTC with the boot ROM's B/W and colour tables through the I/O port, fills the planes through the snoop, and checks line and frame periods, sync widths and positions, the active area (256 lines x 512 pixels); every pixel of a frame against a reference model in B/W, scrolled B/W, 4-colour and 8-colour; palette entries 0-15, the ROM's palette, the 8-colour bypass; R15/R14 readback and floating registers; the `crt_fetch` count (32 x 256); outputs changing only after `ce_pix`. Writes one PPM per mode |
| `tb/core/tb_core.sv` | frames of the whole machine to PPM |
