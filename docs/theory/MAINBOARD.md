# Mainboard -- theory of operation

RTL: `rtl/bus/m20_mainboard.sv` (top), `m20_clkgen.sv` (U12/U29/U28),
`m20_prom.sv` + `m20_prom.hex` (U44), `m20_boot_rom.sv` (U54/U65 and the
extension sockets), `m20_dram.sv` (DRAM client and video snoop),
`m20_iodec.sv` (U39/U21/U26/U8). The Z8001 is the vendored k8000 core
(`rtl/vendor/k8000/k800x_cpu/`, `z8000_cpu`); its internals are described
in the k8000 repository (`docs/theory/Z8000_CPU.md`,
`docs/K800X_CPU_TESTS.md`) and are not repeated here.

## 1. The board

The M20 mainboard is a Z8001 at 4 MHz with its address and segment latches,
a 1K x 8 mapping PROM that turns `{segment, A15, A14, status}` into a
physical device and 16 KB block, up to four 128 KB DRAM devices, the boot
EPROM pair and three extension socket pairs, two 74LS138 I/O decoders, the
port 0x21 configuration latch, the NVI flip-flop, the VI acknowledge
gating for the 8259 and a wait-state generator that stretches T3 while the
CRT controller fetches from DRAM. The RTL keeps the board's structure and
names the TTL it stands for.

### Ports

| group | ports | notes |
|---|---|---|
| clock, reset | `clk`, `rst_n` | 48 MHz; machine reset |
| enables out | `ce16`, `ce_pit`, `ce_usart`, `ce_fdc` | from `m20_clkgen`, for the peripherals |
| jumpers | `cfg_code[2:0]`, `cfg_za`, `cfg_spare1` | `{BW^COL, 32^128, COL4^8}` = port 0x21 D7..D5 = PROM A8, A7, A9; ZA = D3, SPARE1 = D4 |
| ROM loader | `rom_wr`, `rom_addr[15:0]`, `rom_data[7:0]`, `rom_ext`, `rom_start` | |
| memory | `mem_addr[23:1]`, `mem_rd`, `mem_wr`, `mem_be`, `mem_wdata`, `mem_rdata`, `mem_rvalid`, `mem_ack`, `mem_ready`, `mem_refresh_ok` | SDRAM client port |
| video snoop | `vram_we`, `vram_plane`, `vram_addr[13:1]`, `vram_be`, `vram_wdata` | |
| I/O bus | `io_addr`, `io_wdata`, `io_rd`, `io_wr`, `io_rd_end`, `io_wr_end`, `cs_*`, `*_rdata`, `cs_exp`, `exp_rdata`, `cs_exp16`, `exp_rdata16` | [README](README.md) bus model |
| interrupts | `pic_int` in, `pic_inta_n` out, `pit_out2` in, `nvi` out | |
| CRT | `crt_fetch` in | one-clock pulse per displayed character |
| port 0x21 | `fdc_ds[1:0]`, `fdc_motor`, `fdc_dden_n`, `fdc_tg43` | the write latch outputs |
| bus master | `ext_busreq_n`, `ext_nmi_n` in; `ext_busack_n`, `ext_clk_rise`, `ext_rdata` out; `ext_as_n`, `ext_ds_n`, `ext_ad`, `ext_ad_drive`, `ext_sn`, `ext_st`, `ext_r_w`, `ext_b_w` in | the APB card ([APB.md](APB.md)) |

Parameters: `STRETCH` (T3 stretch steps of 62.5 ns, 4), `CRT_WIN` (clocks
after `crt_fetch` in which a DRAM strobe is stretched, 12), `PROM_FILE`.

## 2. Clocking and reset

`m20_clkgen` derives every enable from `clk`:

```
 clk 48 MHz --/3--> ce16 (U12, 16 MHz)
                     +--/13--> ce_pit   1.230769 MHz   8253 CLK
                     +--/8---> ce_usart 2 MHz          8251A CLK
                     +--/16--> ce_fdc   1 MHz          FD1797 CLK
                     +--> U29 (74LS163) q[1:0], counts while !hold
                            q 01->10: cpu_clk_rise    q 11->00: cpu_clk_fall
                            SCLOCK = Q1, 4 MHz when free running
```

`cpu_clk_rise` and `cpu_clk_fall` are the Z8001's `clk_rise`/`clk_fall`
enables: one clock wide, twelve clocks apart when the CPU clock is not
stretched. `hold` (CEP/CET through U28) freezes `u29_q` at the next
`ce16`, so the CPU clock stretches in 62.5 ns steps while the peripheral
enables keep running from the oscillator, as on the board.

The CPU's `reset_n` is `cpu_rst_n = rst_cnt_q[3]`: eight CPU clock rises
after `rst_n` releases, since the Z8001 needs CLK running while /RESET is
Low. Every latch on the board resets with `rst_n`: `boot_q` set, `segt_n_q`
High, `nvi_q` clear, `lat_q` zero, strobes "High" (`as_q`, `ds_q` = 1).

## 3. Blocks

```
                          m20_mainboard
  ext_* -----------+
                   v  cpu_busack_n Low: card drives
  z8000_cpu u58 --[bus master mux]--> cpu_ad_out cpu_as_n cpu_ds_n cpu_st cpu_sn cpu_r_w cpu_b_w
       ^                                   |
       | ad_q (read capture)               v /AS Low: transparent
       |                        [a_q sn_q st_q rw_q bw_q]  cyc_q  tst_q (rises since T1)
       |                                   |
       |      +------------+---------------+-----------------+----------------+
       |      v            v               v                 v                v
       |  [m20_prom u44] [boot_q U18B]  [m20_iodec]     [SEGT U6B]      [wd_q write data]
       |   prom_q          |             cs_* io_rd ...   segt_n_q
       |      |            |               |
       |      v            v               v
       |  rom_sel / dram_sel         io_word <-- *_rdata, pic_rdata, exp_rdata*
       |      |         |
       |      v         v
       |  [m20_boot_rom] [m20_dram] --> mem_* (SDRAM), vram_* (video snoop)
       |   rom_q          rd_hit/rd_have/wr_busy
       |      |            |
       +------+------------+--- ad_d mux (ROM, DRAM, I/O, VI ack, else FFFF) --> ad_q
                           |
  crt_fetch --> crt_win_q --+--> str_q (T3 stretch) --+
  mem_ready, wait_rd, wr_busy -------------------------+--> u29_hold --> m20_clkgen
  pit_out2 --> nvi_q (U92A)         pic_int --> vi_n      u5a_q/u5b_q --> pic_inta_n
```

| block | state | notes |
|---|---|---|
| bus master mux | none | `cpu_*` are the Z8001's pins while `cpu_busack_n` is High, the `ext_*` pins while Low; `ext_rdata = ad_q`, `ext_clk_rise = cpu_clk_rise` |
| strobe edges | `as_q`, `ds_q` | `as_fall`, `as_rise`, `ds_fall`, `ds_rise` combinational |
| /AS latches (U45/U46 address, U43 segment, status) | `a_q`, `sn_q`, `st_q`, `rw_q`, `bw_q` | copy the pins every clock while `cpu_as_n` is Low, hold after |
| cycle | `cyc_q`, `tst_q` | `cyc_q` from /AS Low to the clock after /DS rises; `tst_q` counts CPU clock rises since T1, saturating at 3 |
| status decode (U8, PROM enables) | none | `mem_c = cyc_q & st_q[3]`; `prom_en = st_q[3] & ~st_q[1]`; `io_c = cyc_q & (st_q == 0010)` |
| mapping PROM U44 | `prom_q` (registered read) | section 4 |
| boot overlay U18B | `boot_q` | set by reset, cleared at the first /DS rise with `a_q[3]` = 1 |
| SEGT U6B | `segt_n_q` | at the /AS rise: Low for status 1000-1101 with `sn_q[6:4] != 0` |
| boot ROMs | `m20_boot_rom` | section 6 |
| DRAM | `m20_dram` | section 5 |
| T3 stretch (U18A/U11/U28) | `crt_win_q`, `str_q` | section 7 |
| U29 hold | none | `u29_hold` from `mem_ready`, `str_hold`, `wait_rd`, `wr_busy` |
| port 0x21 (U16 write, U15 read) | `lat_q[4:0]` | section 8 |
| I/O bus | `wd_q`, `m20_iodec` | section 8 |
| NVI U92A | `out2_q`, `nvi_q` | set at the OUT2 rise, cleared while `cpu_st` = NVI acknowledge |
| VI acknowledge (U3/U4/U5/U20) | `u5a_q`, `u5b_q` | section 9 |
| read capture | `ad_q` | registered mux; the CPU's `ad_in` |

Why this shape:

- **The CPU is a pin model.** k8000's `z8000_cpu` sees the board through
  its real pins (`ad_in`, `ad_out`/`ad_drive`, `as_n`, `ds_n`, `st`, `sn`,
  `r_w`, `b_w`, `busack_n`) stepped by `clk_rise`/`clk_fall`. The
  mainboard therefore oversamples strobes at 48 MHz and rebuilds the
  TTL latches, rather than giving the CPU a synchronous memory port. That
  is what lets a second master (the APB) drive the same latches.
- **Latch, then decode.** Everything downstream (PROM, decoders, SEGT,
  DRAM request) works from the /AS latches, not the live pins, as the
  74LS373s do; the PROM read is registered, one clock after `a_q`, and
  is stable before /DS falls, a CPU clock later.
- **Reads are captured, not muxed into the CPU.** `ad_d` picks the source
  by the latched cycle type and `ad_q` presents it to `ad_in` one clock
  later; the CPU samples at its T3 rise, so the extra clock is free.
  While a DRAM read is in flight `ad_q` holds its old value and the CPU
  clock is held instead.

## 4. Mapping PROM and segment translation

`m20_prom` is U44 (N82S181, 1K x 8), initialised from `m20_prom.hex`
(1024 bytes transcribed from the documented mapping tables). Address
pins as on the board:

```
 A9 A8 A7 A6  A5  A4 A3 A2  A1  A0
 |  |  |  |   |   |  |  |   |   |
 |  |  |  SN3 ST2 SN2 SN1 SN0 A15 A14     addr = {j_col48, j_bw, j_32_128, sn[3], st2, sn[2:0], a15, a14}
 |  |  32^128
 |  BW^COL
 COL4^8
```

Output byte: O7 `*ROM`, O6 `*SRAM`, O5 `*DRAM`, O4-O2 TSN2-TSN0, O1 TA15,
O0 TA14. The enables are applied by the caller: `prom_en = ST3 & ~ST1`
(CE3 = ST3, `*CE2` = ST1), so statuses 1010, 1011, 1110 and 1111 map
nothing and read 0xFFFF. ST2 distinguishes instruction space (1100, 1101)
from data space, which is how PCOS gives segment 0 code and data different
physical blocks.

| select | condition |
|---|---|
| `rom_sel` | `mem_c & (boot_q | (prom_en & ~prom_q[7]))` |
| `dram_sel` | `mem_c & ~boot_q & prom_en & prom_q[7] & ~prom_q[5]` |
| SRAM0 (`prom_q[6]`) | not fitted on the board; `prom_q[6]` is unused and such a cycle reads 0xFFFF |

A DRAM word address is `{TSN2, TSN1}` (device 0-3) `{TSN0, TA15, TA14}`
(16 KB block) `A13-A1`: 512 KB in `mem_addr[18:1]`, the maximum the PROM
tables can reach. A ROM cycle uses `prom_q[2:0]` as the socket select
(0 boot, 4-6 extension, section 6).

The boot overlay: while `boot_q` is set every memory cycle, whatever the
PROM says, selects the boot EPROMs at block 0 (U18B forces U36 to O0 and
inhibits TA14/TA15/TSN0). The flip-flop is clocked by the end of each data
strobe with K = A3, so the first cycle with A3 = 1 clears it: the reset
vector fetches at <0>0000-<0>0006 keep it set, and the ROM's first access
with A3 set (a `clrb <4>FFFF` in ROM 1.0, per `tb_bus`) removes the
overlay.

SEGT: the Z8001's /SEGT input is `segt_n_q`, sampled from the latches at
the /AS rise. A memory cycle (status 1000-1101) in a segment with SN6-SN4
set (segment 16 and up) traps; segments 0-15 are all the PROM decodes.

## 5. DRAM

`m20_dram` turns a CPU DRAM cycle into one SDRAM request and snoops writes
to the video planes.

| signal | meaning |
|---|---|
| `start_rd` / `start_wr` | `ds_fall & dram_sel & rw_q` / `& ~rw_q`: the CAS point |
| `rd_q` / `wr_q` | the request level, held until `mem_ack`; taken only while idle |
| `addr_q`, `be_q`, `wdata_q` | the request payload; `be = 11` for a word, `01`/`10` for the odd/even byte, reads always `11` |
| `rd_have` | the current cycle's read word has arrived (cleared at the next /AS) |
| `rd_hit` | `mem_rdata` holds it this clock (`rd_q & mem_rvalid`) |
| `wr_busy` | a write is outstanding |
| `vram_we` | one-clock pulse in the clock after a write request to block 0 of any device, with `vram_plane = dev`, `vram_addr`, `vram_be`, `vram_wdata` |

`mem_refresh_ok = ~mem_rd & ~mem_wr`. A byte write's data is already on
both halves of AD (the Z8001 duplicates it), so `wdata` is passed through
unchanged and the byte enables do the work.

### Bus cycle timing

CPU clock rises e0, e1, ... and falls f0, f1, ... ; at least twelve
`clk` between rises.

| cycle | e0 | f0 | e1 | f1 | e2 | f2 |
|---|---|---|---|---|---|---|
| memory read | /AS Low | /AS High | /DS Low: `start_rd` | | data taken (`ad_q` must hold the word) | /DS High |
| memory write | /AS Low | /AS High | data on AD (`wd_q`) | /DS Low: `start_wr` | | /DS High |

The read must be in by e2. `wait_rd = dram_sel & rw_q & ~cpu_ds_n & (tst_q
== 1) & ~rd_have` holds U29 at `u29_q == 01` (the state before the rise)
until the word has been captured, so e2 is delayed by exactly the SDRAM
latency beyond the T2 half-cycle; with the controller idle (ack at S + 4)
this is shorter than the twelve clocks to e2 and no stretch happens. A
write is posted: the cycle ends at f2 and the next cycle's T1 rise (any
rise after `cyc_q` has dropped) waits while `wr_busy`, so back-to-back
writes never overrun the one-request port. `~mem_ready` holds U29
outright, which keeps the CPU clock stopped until the SDRAM is up.

## 6. Boot ROM and extension sockets

`m20_boot_rom` holds the four EPROM pairs in two 32 KB byte RAMs (`rom_h`
= U54/U55/U56/U57, D15-D8; `rom_l` = U65/U66/U67/U68, D7-D0): 16 KB per
socket, read address `{sock, addr[13] & big_q[sock], addr[12:1]}`.

| socket | `blk` (PROM TSN0/TA15/TA14) | board address | loaded by |
|---|---|---|---|
| 0 | 0 | ROM0 block 0000 | `boot.rom` / Load Firmware (`ld_ext = 0`) |
| 1 | 4 | <7>4000 | extension image bytes 0000-3FFF |
| 2 | 5 | <7>8000 | 4000-7FFF |
| 3 | 6 | <7>C000 | 8000-BFFF |

Other `blk` values and sockets with no image read 0xFFFF (`empty_q`).
Per socket, `big_q` records that the image wrote address bit 13: an 8 KB
image (2732s) ignores A13 and appears twice in its block, as the socket
wiring makes it. `fitted_q[3:1]` marks extension sockets that received
data; `ld_start` with `ld_ext` clears them, so a new download forgets the
old image's size. Both survive machine resets (no `rst_n`); their power-up
value is "nothing fitted". Loader bytes alternate H, L (`ld_addr[0]`).

## 7. T3 stretch

The CRT controller fetches one DRAM word per character (every 1.333 us in
the active area). On the board U18A/U11/U28 hold SCLOCK High in T3 while
the CRT has the DRAM; here video gives `crt_fetch` and the mainboard
models the conflict window:

- `crt_win_q` is loaded with `CRT_WIN` at each `crt_fetch` and counts
  down.
- A DRAM cycle whose /DS falls inside the window (`ds_fall & dram_sel &
  crt_win_q != 0`) loads `str_q = STRETCH`, unless the boot overlay is
  set (U18A J = /BOOT.FF: no stretch while booting).
- `str_hold = str_q != 0 & tst_q == 2 & u29_q == 10`: with SCLOCK High in
  T3 (after e2), U29 is frozen and `str_q` counts down once per `ce16`,
  so T3 is longer by `STRETCH` x 62.5 ns.

The memory itself is not shared: video reads its own plane BRAM. The
stretch exists only so that software timing (PCOS's loops and the ROM's
self-tests) sees the board's wait states.

## 8. I/O

`io_c` is a standard I/O cycle (status 0010). `m20_iodec` decodes
`a_q[15:5]`: A15-A11 must be 0 (U26), A8 picks U39 (0) or U21 (1), A7-A5
the output; A10, A9 and A0 are not decoded, so ports mirror at +0x200,
+0x400, +0x600 and the byte lane follows from the device's data pins.

| select | U39 / U21 output | port |
|---|---|---|
| `cs_fdc` | U39 O0 | 0x00 |
| `cs_latch` | U39 O1 | 0x20 |
| `cs_crtc` | U39 O3 | 0x60 |
| `cs_ppi` | U39 O4 | 0x80 |
| `cs_kbd` | U39 O5 | 0xA0 |
| `cs_ser` | U39 O6 | 0xC0 |
| `cs_pit` | U21 O1 | 0x120 |
| `cs_pic` | U21 O2 | 0x140 |
| `cs_pal` | U21 O4 | 0x180 |

The open outputs (U39 O2, O7; U21 O0, O3, O5-O7) are where the expansion
cards decode themselves ([EXPANSION.md](EXPANSION.md)). `io_rd`/`io_wr`
are `io_c & r_w & ~ds_n`; `io_rd_end`/`io_wr_end` the same with
`ds_rise`. The read word is the selected device's byte on D7-D0 with
D15-D8 = 0xFF, `pic_rdata` or `exp_rdata16` whole, else 0xFFFF; `cs_exp`
and `cs_exp16` are the cards' own decodes with their data.

Write data: `wd_q` copies `cpu_ad_out` every clock in which the cycle is
past /AS, the CPU drives AD and the cycle is a write (`cyc_q & cpu_as_n &
cpu_ad_drive & ~rw_q`), so `io_wdata` holds the data from T2 through the
`io_wr_end` clock.

Port 0x21: U16 (74LS374) latches `{D7, D3-D0}` at `io_wr_end & cs_latch`
into `lat_q`: `fdc_ds = lat_q[1:0]`, `fdc_motor = lat_q[2]`, `fdc_dden_n =
lat_q[3]`, `fdc_tg43 = lat_q[4]`. U15 reads `{cfg_code, cfg_spare1,
cfg_za, lat_q[2:0]}`: ROM 1.x takes D3 as the self-test switch, ROM 2.x
D4:D3 as the floppy type.

## 9. Interrupts

- **VI.** `pic_int` (8259 INT, High = request) is `vi_n` inverted.
- **NVI.** U92A: `nvi_q` sets at a rising edge of `pit_out2` (the 20 Hz
  tick) and clears while the live status is the NVI acknowledge (0110,
  U8 O6). The acknowledge cycle reads 0xFFFF (nothing drives AD).
- **VI acknowledge** (status 0111). `pic_inta_n = ~(cpu_st == 0111 &
  (~u5b_q | ~cpu_ds_n))`. U5A/U5B shift `cpu_as_n` on SCLOCK falls, so
  `u5b_q` goes Low two falls after /AS fell and High two falls after it
  rose: the first /INTA pulse, about one CPU clock long, early in the
  acknowledge; the second lasts while /DS is Low. The 8259 latches its
  request on the first and drives the vector on the second; the read
  capture takes `pic_rdata` for a VI-acknowledge cycle, which is
  `{7'h7F, vector, 1'b0}` on AD8-AD1 with AD0 pulled Low by U4
  ([PERIPHERALS.md](PERIPHERALS.md)). The cascade mux in `m20_core`
  substitutes a slave's word when CAS names one.

## 10. Timing and resources

Everything is one 48 MHz domain. The longest combinational paths are the
read mux `ad_d` (ROM, DRAM, the I/O read mux across nine devices and two
card ports, the PIC word) and the PROM-to-select decode; both have a full
clock. The PROM is one M10K, the boot ROM 64 KB of M10K (two 32 KB byte
arrays), the plane snoop adds no memory here. No fit figures are recorded.

## 11. Inferred and assumed

The header of `m20_mainboard.sv` lists the assumptions; in summary:

| item | status |
|---|---|
| CRT DRAM window `CRT_WIN` = 12 clocks after `crt_fetch`, `STRETCH` = 4 steps | this implementation's values, not derived from a schematic delay |
| Port 0x21 latch, boot and SEGT flip-flops reset values | inferred from the ROM's expectations |
| U18B J input Low (overlay clears, never re-sets) | inferred |
| SRAM0 reads 0xFFFF; NVI acknowledge reads 0xFFFF | nothing drives AD; pull-ups assumed |
| /WAIT, /STOP, MEMDIS inactive | not modelled |
| The CPU leaves reset 8 CPU clocks after `rst_n` | the Z8001 needs CLK during /RESET; the count is this implementation's |
| PROM code 4 (undocumented) reads as code 5 | the `.hex` fills it so; `tb_prom` checks it |
| Posted writes (`wr_busy` only holds the next T1) | the board's DRAM controller timing is not modelled; the SDRAM is faster than a T-state |

## 12. Verification

| bench | checks |
|---|---|
| `tb/bus/tb_prom.sv` | `m20_prom` against the documented mapping table: hand-transcribed rows on the named pins, every entry of `prom_vec.txt`, code 4 = code 5 |
| `tb/bus/tb_rom.sv` | `m20_boot_rom`: 8 KB (A13 ignored) and 16 KB boot images, extension images filling sockets in order, empty sockets and unused `blk` values read 0xFFFF, a new download forgets the old size |
| `tb/bus/tb_bus.sv` (`make tb-bus`) | `m20_mainboard` with the real CPU running boot ROM 1.0 against `sdram_lat` (behavioural SDRAM latency, `+lat`) and `m20_stubs`: a reference model built from the CPU pins alone checks the boot overlay, every memory cycle's target from the PROM tables (DRAM cycles issue exactly one request with the right physical address), read data (shadow DRAM, ROM word or 0xFFFF), SEGT after each /AS, port 0x21; ordered milestones reset vector, overlay clear, memory size, SEGT trap, `check_devices`, device probes to the VI test |
| `tb/core/tb_core.sv` | the whole machine to the PCOS prompt ([SYSTEM.md](SYSTEM.md)) |
