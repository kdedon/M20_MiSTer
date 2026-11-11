# M20_MiSTer architecture

An Olivetti L1 M20 (Z8001) on MiSTer.

## 1. Clocks and resets

| Name | Frequency | Use |
|---|---|---|
| `clk` (clk_sys) | 48 MHz | Every core flop; also CLK_VIDEO |
| `clk_ram` | 96 MHz, edge-aligned | SDRAM controller only |

All other timing is clock enables from `clk`:

| Enable | Rate | Divider | Models |
|---|---|---|---|
| `ce16` | 16 MHz | ÷3 | U12 crystal; wait-state granularity (62.5 ns) |
| `cpu_clk_rise` | 4 MHz | U29 74LS163 Q1 on `ce16`, frozen while stretched | Z8001 CLK |
| `ce_pit` | 1.230769 MHz | ÷39 (16 MHz ÷ 13) | 8253 CLK, all channels |
| `ce_usart` | 2 MHz | ÷24 | 8251A CLK |
| `ce_fdc` | 1 MHz | ÷48 | FD1797 CLK |
| `ce_pix` | 12 MHz | ÷4 | U109 dot clock |
| `ce_crtc` | 750 kHz | `ce_pix` ÷16 | MC6845 CLK |

Resets are active-low `rst_n` with synchronous release.
- **Machine:** `RESET | status[0] | buttons[1] | rom_loading`.
- **SDRAM:** PLL lock only, so memory survives a machine reset as DRAM does.

## 2. Blocks

```
M20.sv          hps_io, CONF_STR, pll, SDRAM, disk_stream, video_mixer, UART
└── m20_core.sv
    ├── bus/m20_mainboard.sv   CPU, clocks, status decode, PROM, SEGT, boot overlay,
    │                          ROM, DRAM client, VRAM snoop, I/O decode, port 0x21,
    │                          NVI flip-flop, VI-ack/INTA, T3 stretch
    ├── video/m20_video.sv     MC6845, plane BRAM, shifter, 74LS670 palette, sync
    ├── periph/m20_pic.sv      8259 (vector on D1–D8, two-pulse INTA)
    ├── periph/m20_pit.sv      8253
    ├── periph/m20_ppi.sv      8255, Centronics stub
    ├── periph/i8251.sv ×2     async USART
    ├── periph/m20_kbd.sv      keyboard: PS/2 in, 1200 8N2 serial
    ├── fdc/m20_fdc.sv         FD1797 on the sd_* block interface
    ├── hdc/m20_hdc.sv         hard disk card (WD1000 registers), ports 0x1C0-0x1CF
    ├── exp/m20_ieee.sv        IEEE-488 card, slave 8259 on IR1
    ├── exp/m20_twin.sv        twin RS-232 card, slave 8259 on IR7
    ├── exp/m20_cascade.sv     slave 8259 vector during VI acknowledge
    └── apb/m20_apb.sv         APB 1086 8086 card, bus master on the ext_* port
```

| Directory | Lint top | Bench |
|---|---|---|
| `rtl/bus/` | `m20_mainboard` | `tb/bus/` |
| `rtl/video/` | `m20_video` | `tb/video/` |
| `rtl/periph/` | each module | `tb/periph/` |
| `rtl/fdc/`, `rtl/host/` | `m20_fdc` | `tb/fdc/` |
| `rtl/hdc/` | `m20_hdc` | `tb/hdc/` |
| `rtl/exp/` | `m20_ieee`, `m20_twin`, `m20_cascade` | `tb/exp/` |
| `rtl/apb/` | `m20_apb` | `tb/apb/` |
| `rtl/m20_core.sv`, `M20.sv` | `m20_core` | `tb/core/` |

Each block has a `<dir>.qip` (included from `files.qip`) and `mk/<dir>.mk` (`<DIR>_SRCS`, `tb-<dir>` target).

`rtl/vendor/` is never edited; changed copies live in the block directory with a header naming the change (`rtl/cpu/` holds the patched Z8000 files, see `rtl/vendor/MANIFEST.txt`).

## 3. Interfaces (all on `clk`)

### 3.1 I/O bus

Standard I/O (status 0010). A11–A15 = 0; A9–A10 are ignored, so ports mirror; A8 and A7–A5 select the device.

| Signal | Width | Meaning |
|---|---|---|
| `io_addr` | 16 | Byte address latched at /AS (odd = D0–D7) |
| `io_wdata` | 16 | Data phase AD bus |
| `io_rd` / `io_wr` | 1 | High while /DS is low |
| `io_rd_end` / `io_wr_end` | 1 | Pulse at /DS rise: read side effects, write commit |
| `cs_fdc` `cs_latch` `cs_crtc` `cs_ppi` `cs_kbd` `cs_ser` `cs_pit` `cs_pic` `cs_pal` | 1 each | Valid from /AS to end of /DS |

Devices return `*_rdata` while `cs && io_rd`; the mainboard samples at /DS rise. Byte devices drive D7–D0 and D15–D8 read 0xFF. The PIC returns 16 bits (§3.4).

Expansion cards decode their own ports: `cs_exp`/`exp_rdata` (byte port, hard disk and cards) and `cs_exp16`/`exp_rdata16` (slave 8259 word).

### 3.2 Memory

The mainboard translates through the PROM and reads 0xFFFF where nothing is mapped. 512 KB is the maximum: the 128K-card PROM tables wrap past it.

| Signal | Width | Meaning |
|---|---|---|
| `mem_addr` | [23:1] | Word address; DRAM = {device[1:0], block[2:0], A13:A1} |
| `mem_rd` / `mem_wr` | 1 | Held until `mem_ack` |
| `mem_be` | 2 | be[1] = D15–D8 (even byte) |
| `mem_wdata` / `mem_rdata` | 16 | |
| `mem_rvalid` / `mem_ack` / `mem_ready` | 1 | SDRAM controller handshake |

The CPU waits at T3 until read data arrives. An SDRAM round trip (100–200 ns) is shorter than a T-state (250 ns), so this rarely stretches.

Boot ROM: up to 16 KB BRAM loaded as `boot.rom` (ioctl index 0) or with Load Firmware (index 1); `scripts/make_boot_rom.sh` builds it from ROM dumps. Extension sockets: up to 48 KB (ioctl index 2), 0xFFFF where empty.

### 3.3 Video plane snoop

Plane *n* is DRAM device *n*, block 0. CPU writes there are mirrored into the video plane BRAM in the same cycle as the SDRAM write, so video never reads SDRAM.

| Signal | Width | Meaning |
|---|---|---|
| `vram_we` | 1 | Pulse |
| `vram_plane` | 2 | Device number |
| `vram_addr` | [13:1] | Word in the 16 KB block |
| `vram_be` | 2 | Byte enables |
| `vram_wdata` | 16 | |

### 3.4 Interrupts

- **VI:** 8259 INT → /VI.
- **NVI:** 8253 OUT2 rising edge sets U92A; NVI acknowledge (status 0110) clears it.
- **VI acknowledge (status 0111):** `pic_inta_n` pulses for one CPU clock about two edges after /AS, then again with /DS. The second INTA returns `{7'h7F, vec[7:0], 1'b0}`: vector on AD1–AD8, AD0 = 0. Normal PIC reads put data on bits 8:1 with bit 0 = 1.

| 8259 input | Source |
|---|---|
| IR0 | FDC INTRQ |
| IR1 | IEEE-488 card (slave) |
| IR2 | 0 |
| IR7 | twin RS-232 card (slave) |
| IR3 | RS-232 RxRDY |
| IR4 | keyboard RxRDY |
| IR5 | keyboard TxRDY (JP4 6-3) |
| IR6 | 8255 PC3 |

### 3.5 T3 stretch

Video pulses `crt_fetch` at each character fetch (every 1.333 µs in the active area). A CPU DRAM cycle whose data strobe lands in that window freezes `cpu_clk_rise` for `STRETCH` (default 4) 62.5 ns steps. No stretch while the boot overlay is active.

### 3.6 Port 0x21

- **Write:** `fdc_ds[1:0]` (D0–D1), `fdc_motor` (D2), `fdc_dden_n` (D3), `fdc_tg43` (D7).
- **Read:** `{cfg_bw, cfg_32_128, cfg_col48, cfg_spare1, cfg_za, latch[2:0]}`, config bits from the OSD. ROM 1.x reads D3 as the self-test switch; ROM 2.x reads D4:D3 as the floppy type (0 = ask, 1 = 160K, 2 = 320K, 3 = 640K).
- **Config code** {D7, D6, D5} ∈ {5, 7, 3, 2, 6, 1, 0}; it also drives PROM A8 (BW), A7 (32/128) and A9 (COL4/8).

### 3.7 Floppy

Two drives on the `disk_stream` drive side (slots 0 and 1, 512 B blocks); images are streamed, never held in memory.

- **Image:** raw `.img`, 35 cylinders × 2 sides × 16 × 256 B = 286,720 B. Every sector takes a 256 B slot; the 128 B FM sectors of track 0 side 0 fill the first half of theirs. LBA = (cyl·2 + side)·8 + (sector−1)/2, offset ((sector−1) & 1)·256.
- **Sizes:** 655,360 B = 80 cylinders (640K); 143,360 B = single-sided (160K).
- **Density:** T0S0 is FM, other tracks MFM; a /DDEN mismatch gives Record Not Found, which ROM 2.x relies on.

### 3.8 Keyboard

Serial only: `kbd_txd` (M20 → keyboard), `kbd_rxd` (keyboard → M20), 1200 baud 8N2.

| Command | Reply |
|---|---|
| 0x03 | 0x0F (Italian layout, OK; layout nibble configurable) |
| 0x0A | beep, none |
| 0x80 | 0x80 |

PS/2 makes become M20 make codes; SHIFT adds 0x30, CTRL 0x60, COMMAND 0x90.

## 4. Conventions

- `` `default_nettype none ``, `always_ff`/`<=`, `always_comb`/`=`, sized literals, typed enums, registered BRAM reads, no fabric clocks.
- `verilator --lint-only -Wall` clean; vendored RTL waived in `lint/vendor.vlt`.
- Benches: Verilator, `--x-initial unique`, scoreboard, `PASS` last; expected values come from the hardware tables, not the RTL.
- Quartus 17.0.2 sizes `N'(... int'(x) ...)` as 1 bit; avoid it.
