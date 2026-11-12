# APB 1086 card -- theory of operation

RTL: `rtl/apb/m20_apb.sv` (card), `m20_apb_xlat.sv` (PL40 address
translator), `z8086.sv` + `z8086_alu.sv` (changed copy of nand2mario's
z8086, pristine in `rtl/vendor/z8086/`). The PAL reconstruction, the
evidence for every table below and the open points are in
[../APB.md](../APB.md); this document covers how the RTL realises it.

## 1. The card

The APB 1086 (G0246) puts an 8086 at 8 MHz on the M20 bus. It has its own
16 KB ROM at FC000; everything else it touches is an M20 bus cycle: memory
as program-reference cycles (status 1100) through the mapping PROM with
the segment and A15/A14 from PL40, I/O as standard I/O (0010). The Z8001
starts it with an I/O write to 0x3FFC (run latch set, /BUSREQ), after a
probe write to 0x3FFA that pulls /NMI; the 8086 returns control with its
own `OUT 7FFA` (the same bus port), which pulls /NMI, clears the latch and
puts the 8086 back in reset.

### Ports

| group | ports |
|---|---|
| control | `clk`, `rst_n`, `fitted` (OSD), `run` (LED) |
| image loader | `ld_we`, `ld_addr[14:0]`, `ld_data`: bytes 0000-3FFF the ROM as the 8086 sees it at FC000, 4000-47FF the microcode (512 words of 4 bytes, little endian) |
| bus master | `busreq_n`, `nmi_n` out; `busack_n`, `clk_rise` (M20 CPU clock rise), `rdata` (the mainboard's read capture) in; `as_n`, `ds_n`, `ad`, `ad_drive`, `sn`, `st`, `r_w`, `b_w` out |
| handshake snoop | `io_addr`, `io_act` (/DS Low in an I/O cycle, any master), `io_end` |
| interrupts | `vi` (8259 INT), `nvi` (the mainboard flip-flop) |

No parameters; `CE_LAST` = 5 (8 MHz enable), `LOCAL_LAT` = 1.

## 2. Clocking and reset

`ce8` is one clock in six (`div_q`): the 8086 and its request logic step
on it. Bus cycles step on `clk_rise`, the mainboard's 4 MHz CPU clock,
so the mainboard's DRAM waits and CRT stretches apply to the 8086's
cycles exactly as to the Z8001's.

```
 rst_n, fitted --> run_q (the run latch) --> busreq_n
 run_q & ~busack_n --> own --> own_q (registered) = 8086 reset_n and the reset of every bus-side flop
```

The 8086 is in reset unless the latch is set and the Z8001 has granted
the bus; a machine reset or the card unfitted clears the latch. `live_q`
ignores the CPU's strobes until its first `ce8` out of reset, because
z8086's `inta` is not cleared by its reset.

## 3. Blocks

```
 io_addr/io_act/io_end --> [handshake] hs_hit (A13-A3 = 1), hs_set (A2:A1 = 10), hs_clr (01)
                               run_q --> busreq_n ; nmi_n = ~(fitted & io_act & hs_clr)
 ld_* --> [image] rom_lo/rom_hi 8K x 8 each, uc_lo_q + uc_we --> z8086 microcode RAM
 vi, nvi --> intr                 |
                                  v
                        [z8086 u_cpu] addr din dout rd wr io word inta ready
                                  | start (ce8 & live_q & strobe & ~rq_q)
                                  v
 [m20_apb_xlat] a[19:14] --> sn a15 a14 bus rom
                                  |
                        [request] rq_q rq_wr rq_io rq_word rq_inta rq_bus rq_a rq_d rq_za rq_sn
                                  lat_q (local cycles), inta2_q, nvi_sel_q, rdy_q, din_q
                                  |
                        [Z-bus sequencer] z_act z_e e_dsf e_smp e_end --> as_n ds_n ad ad_drive sn st r_w b_w
                                  z_data <- rdata at e_smp, z_done
```

| block | notes |
|---|---|
| handshake (74LS133) | any I/O cycle, either master, with A13-A3 all ones: `hs_clr` (0x3FFA) pulls /NMI while /DS is Low and clears `run_q` at `io_end`; `hs_set` (0x3FFC) sets it |
| image | ROM in two byte M10Ks indexed by `rq_a[13:1]`; microcode words assembled from bytes 0, 1 (held in `uc_lo_q`) and 2 (`uc_we`, 21 bits `{ld_data[4:0], uc_lo_q}`) |
| CPU | z8086 with `ce`, `reset_n = own_q`, `intr = fitted & (vi | nvi)`, `nmi = 0` |
| translator | section 4 |
| request | one outstanding CPU cycle; local (ROM, empty page) or bus (`rq_bus`) |
| sequencer (PL42) | section 5 |

Why this shape:

- **The card is a second Z-bus master, not a memory port.** It drives the
  mainboard's `ext_*` pins and the mainboard treats them as the CPU's
  while `cpu_busack_n` is Low: the same /AS latches, PROM, DRAM client,
  I/O decode and read capture serve both. The 8086 therefore sees exactly
  the Z8001's memory map through the PROM, byte lanes included.
- **Two time bases.** The 8086 runs at its own 8 MHz; a bus cycle is
  built on the M20 CPU clock, as PL42 is clocked by it. `rq_q`/`rdy_q`
  bridge them: a request is taken at a `ce8`, the cycle runs on
  `clk_rise`, and `ready` is held until the CPU's next `ce8`.
- **ROM and empty pages take four CPU clocks.** `LOCAL_LAT` = 1 makes a
  local access last about an 8086 bus cycle, so the POST's timing loops
  run at the right speed.

## 4. Address translation (`m20_apb_xlat`)

8086 A19-A14 to the segment and A15/A14 of a program-reference cycle:

| 8086 page | `n` = A19-16 | `sn` | A15, A14 | note |
|---|---|---|---|---|
| 00000 | 0 | 0 | q | |
| 10000 | 1 | 2 | q | |
| 20000 | 2 | 8 + A15 | 1, A14 | |
| 30000-6FFFF | 3-6 | n + 8 | q | |
| 70000 | 7 | F | q | 7C000-7FFFF none |
| 80000-DFFFF | 8-D | | | none |
| E0000 | E | 3 | q | video planes |
| F0000 | F, q = 0 / 1 | 0 / 3 | 0, 0 | |
| F8000 | F, q = 2 | | | none |
| FC000 | F, q = 3 | | | local ROM |

`q` = A15-A14. `bus` = 0 for "none": the request completes locally,
reads 0xFFFF, writes dropped. I/O cycles go out with A15 = A14 = 0 and
SN = 0. What reaches DRAM then depends on the configuration code
through the PROM ([MAINBOARD.md](MAINBOARD.md) section 4); the
reconstruction's section 2.2 tabulates the result per configuration.

Byte lanes: D0-D15 pass straight through, so an 8086 byte at an even
address is the Z-bus byte at the odd address: `rq_za[0] = ~word &
~A0`. A byte write puts the byte on both halves (`rq_d`); a byte read
takes `loc_data[15:8]` for an odd 8086 address, `[7:0]` for even.

## 5. The bus cycle (PL42 sequencer)

A request with `rq_bus` starts at the next `clk_rise` with the sequencer
idle (T1): /AS Low, `ad` = the address (0 for INTA), `sn`, `st`, `r_w`,
`b_w` driven. Edge counter `z_e` then steps once per `clk_rise`:

| cycle | `st` | /AS High | /DS Low (`e_dsf`) | data taken (`e_smp`) | /DS High (`e_end`) |
|---|---|---|---|---|---|
| memory read | 1100 | 1 | 1 | 2 | 3 |
| memory write | 1100 | 1 (data on AD) | 2 | | 3 |
| I/O read / write | 0010 | 1 | 2 | 3 | 4 |
| INTA | 0110 or 0111 | 1 | 5 | 7 | 8 |

Edges count CPU clock rises after T1. At `e_end` /DS rises, `ad_drive`
drops, `st` returns to 0000, `z_done` pulses and the request completes
(`rdy_q`). The next T1 is the clock rise after. `rdata` is the
mainboard's `ad_q`, valid at the rise it is sampled on; since the
mainboard holds the CPU clock while a DRAM read is in flight, sampling
at edge 2 is always after the data.

Memory cycles never reach segment 7 (the extension ROM) or a PROM ROM
entry, and the card's only I/O decode is the 74LS133 window, clear of
the hard disk and card ports.

### Interrupts

`intr = vi | nvi`. The first INTA stays on the card: `inta2_q` toggles,
`nvi_sel_q` latches `nvi` (NVI has priority), no bus cycle, four CPU
clocks. The second runs an acknowledge cycle: status 0110 (NVI) reads
0xFFFF, since nothing drives the bus and the mainboard's NVI flip-flop
clears on the status; status 0111 (VI) gives the 8259 its two /INTA
pulses and the vector word with AD0 = 0, so the 8086 reads 2n. The APB
ROM installs its 20 Hz tick handler at vector 0xFF and the keyboard
handler at INT 8 (IR4 x 2).

### Handover

| step | mechanism |
|---|---|
| probe | Z8001 `OUT 3FFA`: `hs_clr`, /NMI while /DS Low; the Z8001's NMI handler prints "Select Alternate CPU (y/n)?" |
| start | Z8001 `OUT 3FFC`: `run_q` set at `io_end`, `busreq_n` Low; the Z8001 grants, `own` rises, `own_q` releases the 8086 reset; it fetches FFFF0 from the local ROM |
| return | 8086 `OUT 7FFA` (bus 0x3FFA through the card's own I/O cycle): /NMI while /DS Low, `run_q` cleared at the cycle's end, /BUSREQ High; the mainboard's mux returns to the Z8001, which takes the NMI and cold-starts |
| reset | machine reset or the card unfitted clears `run_q` |

The Z8001's `JR $` park and the NMI handler's R12 codes are software
([../APB.md](../APB.md) section 3.1).

## 6. The 8086 core

z8086 runs the original Intel microcode from a RAM loaded through the
image (the microcode file is fetched by `scripts/make_apb_rom.sh`, not
committed). The changed copy adds the clock enable on every register,
the loadable microcode RAM, renames the ALU module, and fixes three
behaviours seen only with real bus latency and interrupts: an interrupt
taken at FC left the return address one byte too far (the opcode byte
was popped); INTR was latched inside the interrupt sequence so a second
interrupt hit the handler's first instruction; a REP prefix decoded at
the previous instruction's last micro-instruction was dropped. Each is
named in the file header.

## 7. Timing and resources

A ROM access is four CPU clocks (one `LOCAL_LAT` tick of `ce8` plus the
handshake); a DRAM read is a three-edge Z-bus cycle plus any mainboard
wait, about 1 us; so the 8086 runs well below 8 MHz bus throughput, as
the real card did behind the M20 bus. Memory: ROM 16 KB (two 8K x 8
M10K arrays), microcode 512 x 21 bits in z8086. No fit numbers are
recorded.

## 8. Inferred and assumed

The PAL equations are reconstructed, so most of this card is inference;
the confidence per item is in [../APB.md](../APB.md). RTL-level choices:

| item | status |
|---|---|
| Edge numbers of the bus cycles (1/2/3, 2/-/3, 2/3/4, 5/7/8) | chosen to fit the Z8001's own timing and PL42's register count; not from a dump |
| `LOCAL_LAT` = 1 (ROM and empty cycles four CPU clocks) | tuned so the ROM's delay loops run at the documented speed |
| 74LS133 window: any I/O cycle, either master, read or write, A13-A3 all ones | the schematic shows A13-A3; A14/A15 and R/W gating are not established |
| NVI priority at the first INTA; vector 0xFF for NVI | schematic D05/F08 and the ROM's handler at vector 0xFF |
| No 8086 NMI, HOLD unused | pins tied on the board |
| Translator rows marked "none" | reconstruction section 2.2 |

## 9. Verification

| bench | checks |
|---|---|
| `tb/apb/tb_apb.sv` (`make tb-apb`) | `m20_apb` against a Z-bus model of the mainboard whose CPU clock rises at random 12-19 clock spacing and whose /BUSACK follows /BUSREQ after two rises: (1) translator + PROM: the 16 KB blocks every 8086 page reaches in each of the seven configurations, against the published table; (2) handshake: OUT 3FFA probe (NMI, no run), OUT 3FFC (run, /BUSREQ, 8086 out of reset), the 8086's OUT 7FFA (NMI, release, reset), twice; no response unfitted; (3) the 8086 test program `apb_test.S`: byte lanes, page translation, I/O window, NVI and VI acknowledge cycles with their vectors, odd-stack pushes, the return address of an interrupt inside a counting loop, a VI during the NVI entry waiting for IRET, REP MOVSW at an odd address |
| `tb/core/tb_core.sv` `+apb=<file>` | the whole machine: ROM 2.0f prompt, `y`, POST, MS-DOS 2.0 to `A>`, `dir`, Tab+Esc back to the Z8001 cold start |

On hardware (MiSTer, build da5fb70) MS-DOS 2.0 boots on the card from a
360K PC image.
