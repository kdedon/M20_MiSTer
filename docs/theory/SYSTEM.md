# System -- theory of operation

RTL: `M20.sv` (the MiSTer `emu` shell), `rtl/m20_core.sv` (the machine),
`rtl/host/disk_stream.sv` (image streaming), `rtl/sdram/c900_sdram.sv`
(DRAM port), `rtl/common/c900_rom.sv`, `c900_rst_sync.sv`, `c900_sync2.sv`,
`rtl/pll.v`.

## 1. The shell

`M20.sv` is the framework's `emu` module: it owns `hps_io`, the PLL, the
SDRAM controller, the UART pins, `disk_stream`, `video_mixer`, audio and the
LEDs, and instantiates one `m20_core`. `m20_core` wires the mainboard,
video, peripherals, cards and controllers together and carries no logic of
its own beyond that wiring, the OSD key gate and a few constant inputs.

```
 HPS_BUS --> hps_io --+-- status[127:0] ----> OSD latches (cfg_*)
                      +-- ioctl_* ---------> rom_wr / apb_ld_we
                      +-- img_* / sd_* ----> disk_stream --> fd_* hd_* (drive side)
                      +-- ps2_key ---------> m20_core
 CLK_50M --> pll --> clk_sys 48 MHz, clk_ram 96 MHz
                      c900_sdram <--mem_*--> m20_core <--> video_mixer --> VGA_*
                      UART_RXD/TXD/RTS/DTR <-> m20_core (ser_*)
                      AUDIO_L/R <-- beep        LED_DISK, LED_USER
```

### OSD status bits (`CONF_STR`)

| bits | option | use |
|---|---|---|
| 0 | Reset | `reset_req` |
| 3:1 | Configuration | memory and video cards, latched into `cfg_code` |
| 6:4 | Jumpers ZA/SPARE1 | `cfg_spare1`, `cfg_za` (port 0x21 D4:D3) |
| 7 | IEEE-488 card | `cfg_ieee` |
| 8 | Twin RS-232 card | `cfg_twin` |
| 10:9 | Serial port | `ser_sel`: UART on the mainboard, twin A or twin B |
| 11 | APB 8086 card | `cfg_apb` |
| 13:12 | Keyboard | `kbd_layout` national code: US 4, UK 3, Italian 0, German 1 |
| 122:121 | Aspect ratio | `VIDEO_ARX/ARY` |

`S0`-`S3` are the floppy and hard disk mounts (`VDNUM = 4`); `F1`
(index 1) loads a boot ROM, `F2` (index 2) the extension sockets, `F3`
(index 3) the APB image. `v,6` names the settings file `M20_v6.CFG`.

The card and jumper options are read at reset, as the board reads its
jumpers: `cfg_code`, `cfg_za`, `cfg_spare1`, `cfg_ieee`, `cfg_twin` and
`cfg_apb` are loaded from `status` only while `rst_n` is Low. The OSD
order is mapped to the hardware configuration code `{BW^COL, 32^128,
COL4^8}` by a `case`; the default (and undefined codes) is 6, B/W with
128K cards. `ser_sel` and `kbd_layout` follow `status` live.

## 2. Clocks

`pll` (`rtl/pll.v`, Altera PLL `pll_0002`) makes `clk_sys` = 48 MHz and
`clk_ram` = 96 MHz from `CLK_50M`, both 0 ps phase. `clk_sys` is also
`CLK_VIDEO`; `CE_PIXEL` comes from `video_mixer`, fed by the core's
`ce_pix` (12 MHz, every fourth clock).

Everything in the core is a clock enable from `clk_sys` (table in
[MAINBOARD.md](MAINBOARD.md) section 2). `clk_ram` reaches only
`c900_sdram` and the vendored controller.

## 3. Reset

```
 RESET --(c900_sync2, INIT 1)--> reset_in --+
 status[0] (held by Main until the mounts are in) --> hps_rst --+
 status[0], buttons[1], ioctl_download, ~sdram_ready ----------+--> reset_req (registered)
                                                                      |
 pll_locked ---------------------------> c900_rst_sync -----------> rst_n
```

- `hps_rst` starts High and drops once `status[0]` has been seen High and
  then Low: Main holds the reset bit from the core load until the options,
  `boot.rom` and the start-up mounts are in, so the machine never runs
  before them. That is power-on, not a reset press.
- `ioctl_download` of any index resets the machine, so a ROM load restarts
  it with the new image. `~sdram_ready` keeps it in reset until the SDRAM
  controller has initialised.
- `c900_rst_sync` asserts asynchronously (`arst | ~pll_locked`) and
  releases two clocks after both are clear.
- SDRAM: `u_sdram_rst` and `u_sdram_ram_rst` take `arst = 0`, so the
  controller follows PLL lock only and the DRAM contents survive a machine
  reset.
- Inside the core the Z8001 leaves reset eight CPU clocks after `rst_n`
  ([MAINBOARD.md](MAINBOARD.md)); `disk_stream` keeps its cached cylinders
  across `core_rst_n` and replays each slot's mount to the controllers.

## 4. Firmware loading

`ioctl_index[7:0]` identifies the file; `[5:0]` is the `F` slot number in
`CONF_STR`, `[7:6]` the file-type position. The shell decodes:

| file | index | enable | target |
|---|---|---|---|
| `boot.rom` at core start | `[7:0] == 0` | `rom_wr`, `rom_ext = 0` | boot EPROMs U54/U65, 16 KB max (`ioctl_addr[15:14] == 0`) |
| Load Firmware | `[5:0] == 1` | same | same |
| Load extension ROM | `[5:0] == 2` | `rom_wr`, `rom_ext = 1` | sockets U55-U57/U66-U68, 48 KB (`ioctl_addr[26:16] == 0`) |
| `boot1.rom` at start | `[7:0] == 0x40` | `apb_ld_we` | APB ROM and microcode, 32 KB window (`ioctl_addr[26:15] == 0`) |
| Load APB ROM | `[5:0] == 3` | same | same |

`rom_start` is a one-clock pulse at the rise of `ioctl_download` for a
ROM index: the boot ROM forgets the previous image's size so that an 8 KB
image loaded after a 16 KB one appears twice in its socket
([MAINBOARD.md](MAINBOARD.md) section 6). Index 0x40 is excluded from
`rom_index` by the `[7:0]` compare, so `boot1.rom` never lands in the
boot socket.

## 5. Memory

`c900_sdram` is the DRAM port in front of the vendored single-port
controller (`rtl/vendor/sdram/sdram.sv`, NeoGeo). The client contract,
used by `m20_dram`:

- `rd` or `wr` is a level held with `addr`, `be` and `wdata` until `ack`
  (one clock); `rd`/`wr` in the ack clock are ignored; `wr` wins.
- `rvalid` is High in the ack clock of a read, `rdata` valid that clock.
- Nothing is accepted before `ready`.
- `refresh_ok` tells the port when a refresh may start; the mainboard
  gives it whenever no request is outstanding.

Read timing from the clock S in which the request is first seen: ACTIVE
at S + 0.5 (the controller samples on `clk_ram`), READ at S + 1.5, word
in the controller at S + 3, `ack` and `rdata` at S + 4. A refresh (one
per `REFRESH_CYCLES` = 336 clocks, 7.0 us, both chips) holds the port for
four clocks and starts only in a `refresh_ok` or ack clock. Z8001
addresses are words: `mem_addr[23:1]`, `mem_be[1]` = D15-D8.

## 6. Disk image streaming (`disk_stream`)

### Ports and parameters

| port | side | meaning |
|---|---|---|
| `img_mounted[3:0]`, `img_readonly`, `img_size` | hps_io | mount events |
| `h_lba`, `h_blk_cnt`, `h_rd`, `h_wr`, `h_ack`, `h_buff_*` | hps_io | the `sd_*` block protocol, one job at a time, fanned to all four slots in `M20.sv` |
| `d_mounted[3:0]`, `d_readonly`, `d_size` | drive | one-clock mount pulse per slot with the size |
| `d_lba`, `d_scr`, `d_rd`, `d_wr`, `d_ack`, `d_buff_*` | drive | the same protocol, 512-byte blocks, served from BRAM |
| `resident`, `busy`, `wb_busy`, `fmt_full`, `ld_min/max` | status | LED and diagnostics |
| `bpc[1:0]` | | hard disk blocks per cylinder; `M20.sv` gives 99 (6 heads x 33 sectors x 256 B / 512) |

Parameters: `UMAX` (hard disk unit size in blocks, 99 here), `NFMT` (format
entries per hard disk, 8), `QUIET` (clocks without a drive write before a
flush, 4,800,000 = 100 ms).

### BRAM layout

One byte-wide true dual-port RAM of `TOT` blocks:

```
 block   0 ..  15   floppy 0 unit   (one M20 cylinder: 2 sides x 8 blocks)
        16 ..  31   floppy 1 unit
        32 .. 130   hard disk 0 unit (UMAX = 99 blocks, one cylinder)
       131 .. 229   hard disk 1 unit
       230, 231     probe block per hard disk (bpc unknown: one block at a time)
       232 .. 247   NFMT format entries per hard disk (scratch tracks)
```

Port A belongs to the drive engine, port B to the HPS engine.

### Mounts

`img_mounted` rises are taken on a two-flop history (`mnt_ev`); each
records `mnt_q`, `ro_q`, `size_q`, `nblk_q` (blocks, rounded up, saturated
at 2^20) and pulses `d_mounted[s]` with `d_size`/`d_readonly`. A mount
invalidates the slot's unit and dirty bits and aborts a running HPS job
for that slot (`h_ab`). After a machine reset (`core_rst_n` rise) `rpl_q`
replays one slot's mount per clock in slot order, so controllers reset
with the machine learn their media again; the cached unit stays valid.

### Drive engine (port A)

Requests are served round robin from `d_rr`. `cand[s]` is a request that
can be served now: no medium (completes at once, no data), a floppy
scratch block (`d_scr`: reads zero, writes dropped), an LBA beyond 2^20
(`far`: zeros), a hit in the resident unit (`hit`: `dl - u_base <
u_len`), or the probe block in `pt_mode`. `need[s]` is a miss that waits
for the HPS engine.

| state | action |
|---|---|
| `D_IDLE` | pick a slot, raise `d_ack[slot]`, compute the BRAM block |
| `D_READ` | 512 bytes, one per clock: `d_buff_addr`, `d_buff_dout`, `d_buff_wr` (two-stage: address, then data) |
| `D_WRITE` | one byte per two clocks from `d_buff_din[slot]`; at byte 511 marks the block dirty (`dw_mark`) if it is inside the image and the slot is writable |
| `D_FIND`, `D_CMP`, `D_UPD`, `D_UPD2` | hard disk scratch tracks (below) |
| `D_END` | drop `d_ack` |

The controllers see a block as `d_ack` High with 512 `d_buff_wr` pulses
(read) or 512 `d_buff_addr` steps (write), as hps_io would give it.

Hard disk scratch blocks hold recorded track formats: `m20_hdc` does not
use them (its `d_scr` is 0 in `M20.sv`), but the engine supports them.
A format job stores the written block in a free format entry with the ID
bytes XOR the track's own `{cyl, head}` (`fnorm`), then compares it with
the other entries in use (`D_CMP`, two bytes per two clocks) and, on a
match, frees the new entry and points the track's index (`fidx`, 16K
entries of `{held, entry}`) at the old one, keeping a use count `rc`.
Identically formatted tracks thus share one entry; `fmt_full` records a
format that found no free entry.

### HPS engine (port B)

Serves `need` first, else a flush when `quiet` has reached `QUIET` and a
slot has dirty blocks.

```
 H_IDLE --need--> (dirty? H_WSCAN ... ) --> H_CLAIM --> H_DIV --> H_LREQ <-> H_LXFER --> H_ZERO --> H_DONE
        --flush-> H_WSCAN --> H_WRUN --> H_WREQ <-> H_WXFER --> H_WSCAN ...
        --probe-> H_PREQ <-> H_PXFER
```

- `H_CLAIM`/`H_DIV`: the unit holding the missed LBA. Floppy: `h_base =
  lba & ~15`, 16 blocks. Hard disk: `h_base` steps by `bpc` from the old
  base (or 0), one step per clock, until it covers the LBA; `h_len = bpc`.
- `H_LREQ`/`H_LXFER`: reads of up to 32 blocks (`h_blk_cnt = n - 1`) until
  `h_nin_c`, the part of the unit inside the file; `H_ZERO` fills the rest
  with zeros, one byte per clock. `H_DONE` validates the unit and records
  the load time in `ld_min/ld_max` (clk / 1024).
- Write-back: `H_WSCAN` finds the first dirty block, `H_WRUN` collects a
  run of consecutive dirty blocks (at most 32), clearing each dirty bit as
  it joins (a drive write meanwhile sets it again), `H_WREQ`/`H_WXFER`
  write the run with one `h_wr`. A flush before a miss load returns to
  `H_IDLE`, where the pending `need` is picked up again, now with a clean
  unit.
- `H_PREQ`/`H_PXFER` (`pt_mode`: `bpc` 0 or above `UMAX`): one block
  straight into the probe block, used once (`pt_val` cleared at the
  drive's `D_END`).

`busy` is High during a load or probe, `wb_busy` while any dirty block or
a write-back job exists; `M20.sv` ORs both into `LED_DISK` so that an
image is not ejected with writes queued.

Why this shape: the hps_io buffer bus is one 8-bit port shared by all
slots and far slower than a controller's byte rate, while the FD1797 and
WD1000 models want a sector in a few hundred clocks. Caching one cylinder
makes every sector of a track a hit after the first miss (a PCOS boot
walks tracks sequentially), the dirty map turns many sector writes into
few multi-block `sd_wr` jobs, and the quiet timer bounds how long a write
stays only in BRAM.

## 7. Serial, keyboard, audio, video, LEDs

- **UART.** `UART_RXD` is synchronised (`c900_sync2`, idle High) and goes
  to the port picked by `ser_sel`; `UART_TXD`, `UART_RTS`, `UART_DTR` come
  from `m20_rs232`. `UART_CTS` and `UART_DSR` are not read: every 8251
  sees CTS and DSR asserted ([PERIPHERALS.md](PERIPHERALS.md)).
- **Keyboard.** `ps2_key` is copied into `key_q` in `m20_core` only while
  `osd_active` (`OSD_STATUS`) is Low, so keys typed in the OSD do not
  reach the machine.
- **Audio.** `beep` (the keyboard unit's 3100 Hz tone) becomes a signed
  16-bit square wave of amplitude 0x1800 on both channels (`AUDIO_S = 1`,
  `AUDIO_MIX = 0`).
- **Video.** `video_mixer` with `LINE_LENGTH = 660`, no HQ2x, no gamma;
  the scandoubler follows `forced_scandoubler` (the 18.75 kHz lines need
  it on VGA). Aspect: 4:3 or the framework's `[ARC1]`/`[ARC2]`.
- **LEDs.** `LED_DISK = led_fdd | img_loading | img_wb_busy` where
  `led_fdd = |fdc_ds` (a floppy selected). `LED_USER = ~pll_locked |
  apb_run` (the 8086 owns the bus).

Unused framework ports are tied off at the top of `M20.sv` (DDRAM, SD
SPI, ADC, VGA scaler flags, `BUTTONS`, `USER_OUT`).

## 8. Timing and fit

The core has one 48 MHz domain plus the 96 MHz SDRAM clock; `M20.sdc` is
`derive_pll_clocks` and `derive_clock_uncertainty` only. The bus,
peripherals, video and controllers run at 48 MHz with registered BRAM
reads throughout. No fit or Fmax numbers are recorded in the repository.

## 9. Inferred and assumed

| item | status |
|---|---|
| Reset on every `ioctl_download` (APB image included) | this implementation's choice; `ARCHITECTURE.md` lists only `rom_loading` |
| `hps_rst` power-on sequence (`status[0]` seen High then Low) | relies on Main holding the reset bit through the start-up mounts |
| 100 ms quiet flush, 32-block runs | chosen for the hps_io block rate; not a hardware property |
| Hard disk `bpc = 99` and `UMAX = 99` | the card's fixed 6 x 33 x 256 B geometry ([HARDDISK.md](HARDDISK.md)) |
| Keyboard national codes (US 4, UK 3, Italian 0, German 1) | Service Manual keyboard jumper table and the PCOS SL list |
| Audio amplitude 0x1800 | arbitrary |

## 10. Verification

| bench | checks |
|---|---|
| `tb/core/tb_core.sv` (`make tb-core`) | the whole `m20_core` with `sdram_lat`, `disk_stream` fed by an image-backed block server (`fb_io.cpp`), `boot.rom` through the ioctl path, a scripted PS/2 injector; ordered boot ROM milestones to the PCOS prompt, frames to PPM, optional hard disk, extension ROM, cards and APB (`+apb`) |
| `tb/sdram/tb_sdram.sv` | `c900_sdram` with the vendored controller against timing-checking SDRAM models: every read acked exactly `READ_LAT` clocks after it is first seen, refresh placement |
| `tb/fdc`, `tb/hdc` | `disk_stream` under the controllers against a behavioural hps_io server, file contents compared after write-back ([FLOPPY.md](FLOPPY.md), [HARDDISK.md](HARDDISK.md)) |

`M20.sv` itself has no bench; it is exercised on hardware. On a MiSTer
(build da5fb70): ROM 1.0 and 2.0f boot PCOS 1.x to 4.1a; MS-DOS 2.0 boots
on the APB; the hard disk formats (`vformat`) and installs (`hdisk`);
floppy writes persist in the image; RS-232 works both ways in OLITERM at
4800 8N2; the German layout types correctly with `SL 1`.
