# Theory of operation

How each block of the M20 core works and why it is shaped that way, for
whoever maintains it. Each document covers the ports and parameters,
clocking and reset, the internal blocks, the main transactions, timing and
fit, what is inferred, and how it is tested.

| block | document | RTL |
|---|---|---|
| MiSTer shell: hps_io, OSD, clocks, reset, loaders, disk streaming, SDRAM, audio, LEDs | [SYSTEM.md](SYSTEM.md) | `M20.sv`, `rtl/m20_core.sv`, `rtl/host/`, `rtl/sdram/`, `rtl/common/` |
| Mainboard: Z8001 wiring, clocks, mapping PROM, DRAM, I/O decode, ROMs | [MAINBOARD.md](MAINBOARD.md) | `rtl/bus/` |
| Video: MC6845, planes, pixel path | [VIDEO.md](VIDEO.md) | `rtl/video/` |
| Floppy: FD1797 on the streamed image | [FLOPPY.md](FLOPPY.md) | `rtl/fdc/` |
| Hard disk card (WD1000 registers) | [HARDDISK.md](HARDDISK.md) | `rtl/hdc/` |
| 8259, 8253, 8255, 8251s, keyboard unit, buzzer, RS-232 | [PERIPHERALS.md](PERIPHERALS.md) | `rtl/periph/` |
| Expansion cards: twin RS-232, IEEE-488, 8259 cascade | [EXPANSION.md](EXPANSION.md) | `rtl/exp/` |
| APB 1086 8086 card | [APB.md](APB.md) | `rtl/apb/` |

## Conventions common to every block

- **One clock.** Every flop runs on `clk` (48 MHz, `clk_sys`). Chip clocks
  are one-clock enables: `ce16` (16 MHz), `cpu_clk_rise`/`cpu_clk_fall`
  (4 MHz Z8001 CLK edges), `ce_pit`, `ce_usart`, `ce_fdc`, `ce_pix`,
  `ce_crtc`, `ce8` (APB). The SDRAM controller alone has a second clock,
  `clk_ram` (96 MHz), edge-aligned to `clk`.
- **Reset.** `rst_n` is active low with asynchronous assertion and
  synchronous release (`c900_rst_sync`). The SDRAM resets on PLL lock
  only, so memory survives a machine reset as DRAM does.
- **Bus model.** The mainboard oversamples the Z8001 strobes with `clk`
  and presents one I/O bus to every device: `io_addr` (latched at /AS),
  `io_wdata`, `io_rd`/`io_wr` (levels while /DS is Low), `io_rd_end`/
  `io_wr_end` (one-clock pulses at the /DS rise) and per-device `cs_*`
  levels. Devices return `*_rdata` while selected; the mainboard samples
  it at the /DS rise. Writes are captured while the strobe is Low and
  committed at its end, so a device never acts twice on one strobe.
  Byte devices sit on D7-D0; D15-D8 read 0xFF. The 8259s sit on D8-D1.
- **Memory.** DRAM is a request level (`mem_rd`/`mem_wr` held with
  address, byte enables and data until `mem_ack`); the SDRAM controller
  returns `mem_rvalid` with the ack of a read.
- **Disk images** are streamed, never held in memory: controllers see
  512-byte blocks on a drive-side copy of the hps_io `sd_*` protocol and
  `disk_stream` keeps one cylinder per drive in BRAM.
- **Vendored RTL** (`rtl/vendor/`) is never edited; a changed copy lives
  in the block directory with a header naming the change.

Block map and interface tables: [../ARCHITECTURE.md](../ARCHITECTURE.md).
APB 1086 PAL reconstruction and evidence: [../APB.md](../APB.md).
