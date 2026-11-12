# Floppy -- theory of operation

RTL: `rtl/fdc/m20_fdc.sv` (one module), derived from sorgelig's
`wd1793.sv`. The image cache it talks to is `disk_stream`
([SYSTEM.md](SYSTEM.md) section 6).

## 1. The chip and the drives

The M20 has an FD1797 (U14) at ports 0x01-0x07 with a true data bus, two
5.25" drives selected through the port 0x21 latch, and a medium of 35
cylinders x 2 sides x 16 sectors: cylinder 0 side 0 in FM with 128-byte
sectors (so that any ROM can read the directory), everything else MFM
with 256-byte sectors, 2:1 interleave. ROM 2.x probes the density by
reading with the wrong /DDEN and expecting Record Not Found.

The model is sector level: no bit stream, no CRC on the medium. It keeps
the FD1797's register and status behaviour, its command timing in
microseconds and its index/ID geometry, and serves sector data from a
track buffer filled from the image.

### Ports and parameters

| port | meaning |
|---|---|
| `ce_fdc` | 1 MHz tick |
| `cs_fdc`, `io_addr[2:1]`, `io_wdata[7:0]`, `io_rd`, `io_wr`, `io_rd_end`, `io_wr_end`, `fdc_rdata` | registers 0 command/status, 1 track, 2 sector, 3 data |
| `intrq`, `drq`, `busy` | INTRQ goes to 8259 IR0; DRQ and BUSY are also status bits |
| `fdc_ds[1:0]`, `fdc_motor`, `fdc_dden_n`, `fdc_tg43` | port 0x21: drive select (one-hot), motor, /DDEN (1 = FM), TG43; motor and TG43 are ignored |
| `d_mounted`, `d_readonly`, `d_size`, `d_lba`, `d_rd`, `d_wr`, `d_ack`, `d_buff_*` | `disk_stream` drive side, slots 0 and 1 |

| parameter | value | meaning |
|---|---|---|
| `SLOT_T` | 12500 | ticks per sector slot: 200 ms / 16 (300 rpm) |
| `SLOT_T8`, `SLOT_T9` | 25000, 22222 | PC images, 8 or 9 slots per revolution |
| `ID_T` | 600 | tick in the slot at which the ID passes |
| `IDX_T` | 4000 | index pulse width |
| `MS` | 1000 | ticks per millisecond (step rates, settle) |

## 2. Clocking and reset

All flops on `clk`; `ce_fdc` advances the spindle (`rot_t`, `rot_s`) and
the timer `tmr`. Byte times are counted in ticks: 64 (FM) or 32 (MFM) per
byte, 128/64 for the CRC. `bt` subtracts one when the reload happens in
a tick clock so that a byte time stays exact. `rst_n` clears everything,
including the media table and the head positions (`head`).

## 3. Blocks

```
 I/O bus --> [bus access] acc_q acc_a acc_d done_q --> ev_rd_st ev_rd_dat ev_wr_cmd ev_wr_trk ev_wr_sec ev_wr_dat
                                                                 |
 d_mounted/d_size --> [media] mnt ro ds2 ncyl pc pc9             v
 fdc_ds fdc_dden_n --> [selected drive] sel ready tr00 cyl exists trk_fm den_ok
 ce_fdc --> [spindle] rot_t rot_s --> idx_rise idx_lvl id_ev id_sec
                                                                 |
                              [sequencer st] <--------------------+
                               trk_r sec_r dat_r cmd_q busy_q drq_q intrq_q flags
                               m_* (matched sector)  cnt len  wt_* (write track)
                                 |  blk_go ...              | port B (x_addr, b_we_q)
                                 v                          v
                      [block engine b_st] <----> [track buffer tbuf 8 KB, 16 slots]
                        d_lba d_rd d_wr        port A (d_buff_addr, a_we)
```

| block | state | notes |
|---|---|---|
| bus access | `acc_q`, `acc_w`, `acc_a`, `acc_d`, `done_q` | a strobe is latched once; the `ev_*` pulses fire at its end, so each access has one effect |
| media | `mnt`, `ro`, `ds2`, `ncyl`, `pc`, `pc9` per drive | from `d_mounted` with `d_size`: section 5 |
| spindle | `rot_t`, `rot_s` | slot counter; `idx_lvl` for the first `IDX_T` ticks of slot 0; `id_ev` at tick `ID_T` of every slot; `id_sec` the sector number passing |
| selected drive | none | `sel = ~fdc_ds[0]`, `ready = sel_ok & mnt[sel]`, `cyl = head[sel]`, `exists` (cylinder and side inside the image), `trk_fm`, `den_ok = fdc_dden_n == trk_fm` |
| track buffer | `tbuf[8191]`, M10K, two ports | slot = sector pair (M20) or sector - 1 (PC); port A for image blocks, port B for the transfer |
| block engine | `b_st`, `b_drv`, `b_wr`, `b_lba`, `b_slot` | one `disk_stream` job: `B_REQ` raises `d_rd`/`d_wr` until `d_ack`, `B_XFER` copies while `d_ack` |
| sequencer | `st` (24 states), registers, flags, `m_*`, `cnt`/`len`, `wt_*` | section 4 |

Why this shape:

- **Sector level.** The ROM and PCOS only ever use the controller through
  its registers and interrupts; what matters is that each command returns
  the right bytes and status with plausible timing. Modelling the bit
  stream would cost a format decoder and buy nothing the images carry.
- **Real revolutions.** The spindle, slot timing, ID positions and index
  pulses are kept so that Record Not Found takes the documented five
  index pulses, Force Interrupt on index works, head load and unload
  behave, and PCOS's timeouts are met as on hardware.
- **Track buffer with on-demand blocks.** A sector read fetches only its
  512-byte image block (two M20 sectors); the cache in `disk_stream`
  makes that a BRAM copy of a few hundred clocks, far inside one slot
  time. The 16-slot buffer holds a whole PC track for
  Write Track.

## 4. Operation

### Command register

A write to register 0 (`ev_wr_cmd`) clears INTRQ. Type IV (0xDx) loads
`fi_c` and `intrq_imm`; if busy it aborts the command to `S_IDLE`. Any
other command while not busy loads `cmd_q`, sets BUSY, clears DRQ and
the flags, then:

- Type I (bit 7 = 0): `hld = h`, `step_n = 0`; Restore presets track
  0xFF, data 0; Step In/Out set `dir_in`; go to `S_T1`.
- Type II/III: `sso = cmd[1]` (U bit selects the side, no side compare),
  head loaded, `tmr = 30 ms` settle. Not ready ends at once; Write
  Sector / Write Track on a protected disk set `f_wp` and end; Write
  Track raises DRQ for its first byte; `S_EDLY` (E bit) or `S_PREP`.

### Type I

```
 S_T1 --(one step decision)--> S_STEPW --(step rate 6/12/20/30 ms)--> S_T1 (Restore, Seek) | S_VFY
 S_VFY --(V bit)--> S_SETTLE (30 ms) --> S_SRCH ... ID with cyl == trk_r --> S_END
                                          five index pulses --> f_s4 (seek error), S_END
```

Restore steps out until `tr00` (track 0 = `cyl == 0` of the selected
drive), up to 255 steps; Seek steps `trk_r` toward `dat_r`; Step
commands move once, updating `trk_r` if the T bit is set. Each step
moves `head[sel]` (saturating at 0 and `CYL_MAX` = 83). Verify waits for
an ID on the current track at the current density.

### Read Sector (0x8x/0x9x)

```
 S_PREP: snapshot sel/cyl/side; blk_go = fetch the sector's image block into slot (sec-1)/2
 S_SRCH: wait for id_ev with exists & den_ok and id_sec == sec_r, cyl == trk_r
         (five idx_rise without a match: f_s4 = Record Not Found)
 S_HOLD: wait for the block (blk_pend); cnt = 0, len = phys << ~L
 S_RD:   tmr = dstart (18 FM / 38 MFM byte times to the data field)
 S_RD2:  dat_r <= tbuf byte (or gap filler FF/4E past the sector), DRQ, lost data if the
         previous byte was not read; cnt++; next S_RD with tmr = bt, or S_RDE after len bytes
 S_RDE:  CRC time; len > phys -> f_crc; m bit -> sec_r++, S_PREP; else S_END
```

`len = phys << !cmd_q[3]`: with L = 1 the length is the physical sector's
(the size code), with L = 0 it is doubled, which gives the FD1797 table
(code 0 = 256, 1 = 512, 2 = 1024). A transfer longer than the sector
reads gap filler and ends with CRC error, as the real chip would.
`rlost = drq_q & ~ev_rd_dat`: DRQ still set when the next byte is due.

### Write Sector (0xAx/0xBx)

`S_HOLD` raises DRQ and waits `gap2` (11 FM / 22 MFM byte times); in
`S_WR1` the first byte must have arrived (`wlost` ends with Lost Data),
then `wstart` (7 / 16 byte times of gap and marks); `S_WR` writes a byte
per byte time into the track buffer through port B (`b_we_q`, one clock
after the decision), taking this clock's bus write or `dat_r`, a zero
for a late byte; bytes past `phys` are dropped. `S_WRE` waits the CRC
time, then `blk_go` with `blk_go_wr` writes the block back to the image
(read-modify-write: the block was fetched in `S_PREP`); `S_WRF` waits for
it; multi-sector continues at `S_PREP`.

### Read Address (0xCx)

The next ID at the current density: six bytes `{cyl, side, sector, size
code, CRC}` with a computed CCITT CRC (`crc8`, preset 0xFFFF for FM,
0xCDB4 for MFM after the A1 sync bytes), one per byte time; the sector
register receives the cylinder at the end.

### Write Track (0xFx)

```
 S_WT_LD: fetch all m_nblk blocks of the track (8, or 9 for PC) into the buffer
 S_WT_IX: wait for the index; the first byte must be in dat_r
 S_WT:    one byte per byte time until the next index (DRQ per byte, lost data -> flag):
          FE opens an ID (track, side, sector, size); FB/F8 opens a data field, which ends
          at F7 or after 128 << size bytes; data of sectors 1..16 (1..spt) goes to the slot
 S_WT_FL: write all blocks back
```

Gaps, deleted marks and the format density are not recorded: the image
has no room for them, and the track's density stays what the medium
defines. Read Track (0xEx) returns no data and ends at the second index.

### Status

Type I status `{~ready, wp, hld, f_s4, f_crc, tr00, index, busy}`, type
II/III `{~ready, f_wp, 0, f_s4, f_crc, f_lost, drq, busy}`. A status read
clears INTRQ; a data read clears DRQ. `intrq = intrq_q | intrq_imm`
(0xD8 holds it until the next command). Force Interrupt conditions
`fi_c` (ready change, index) raise INTRQ while armed. The head unloads
after 15 idle index pulses (`hld_n`).

## 5. Image formats

`d_mounted[i]` with `d_size` classifies the medium:

| size (bytes) | format | `ncyl` | `ds2` | `pc` |
|---|---|---|---|---|
| 143,360 or smaller | M20 single sided, 160K | `size / 4096` | 0 | 0 |
| over 143,360 (not a PC size) | M20 double sided | `size / 8192`, at most 84 | 1 | 0 |
| 163,840 / 184,320 | PC single sided, 8 / 9 x 512, 40 cylinders | 40 | 0 | 1 (`pc9` for 9) |
| 327,680 / 368,640 | PC double sided | 40 | 1 | 1 |

M20 image block `lba_of`: `((cyl * sides + side) * 8) + (sector - 1) / 2`;
sector offset in the block `((sector - 1) & 1) * 256`; cylinder 0 side 0
holds the 128-byte FM sectors in the first half of each 256-byte slot.
PC images: `(cyl * sides + side) * spt + sector - 1`, all MFM, 1:1
interleave, `spt` slots per revolution of `SLOT_T8`/`SLOT_T9` ticks; the
APB's MS-DOS reads them with L = 1 and size code 2
([APB.md](APB.md)).

The sector passing the head in slot p is `p odd ? (p+1)/2 : p/2 + 9`
(2:1 interleave) on M20 media, `p + 1` on PC media. An ID is seen only
when the track exists in the image (`exists`: cylinder below `ncyl`, side
1 only if `ds2`) and `/DDEN` matches the track's density, which is what
turns a density mismatch or a 160K disk's side 1 into Record Not Found.

## 6. Timing and resources

| interval | ticks | note |
|---|---|---|
| revolution | 16 x 12,500 = 200,000 | 300 rpm |
| index pulse | 4,000 | |
| ID to data field | 1,152 FM / 1,216 MFM | 18 / 38 byte times |
| byte | 64 FM / 32 MFM | |
| step | 6, 12, 20, 30 ms | r1 r0 |
| settle (E, V) | 30 ms | |
| not found | 5 index pulses | about 1 s |

A sector read from a cache hit: search up to one revolution, the data
field delay, then 256 byte times (8.2 ms MFM). The track buffer is one
8 KB M10K block pair; the sequencer is a 24-state FSM with 16-bit
timers. The module has no fit figures recorded.

## 7. Inferred and assumed

| item | status |
|---|---|
| `ID_T` = 600 ticks into the slot, `IDX_T` = 4000 | positions chosen, not measured |
| head unload after 15 index pulses, head load = 30 ms settle | FD179x data sheet values; HLT is not an input |
| no side compare (C bit ignored) | the M20 wires SSO from the U bit; the ROM never sets C |
| TG43 and motor ignored | no effect on a sector-level model |
| Write Track parses only FE/FB/F8/F7 | enough for the ROM's and PCOS's formatters; gaps are not stored |
| Read Track unsupported | nothing in the software uses it |
| gap filler FF (FM) / 4E (MFM) past a sector | from the format; the real chip would read whatever follows |
| `CYL_MAX` = 83, `ncyl` at most 84 | 80-track drives with a few spare cylinders |

The FDC header says the track buffer is 4 KB with 8 slots; the RTL
declares 8 KB (`tbuf[0:8191]`, 16 slots) for the PC track formats.

## 8. Verification

| bench | checks |
|---|---|
| `tb/fdc/tb_fdc.sv` (`make tb-fdc`) | `m20_fdc` + `disk_stream` against a behavioural hps_io block server (`img_io.cpp`): slot 0 a real PCOS image file, slot 1 a synthetic 640K or 160K image. Phases: status and register tests; the boot ROM's `disk_io` sequence (select via 0x21, /DDEN per block, Restore, Seek + Verify, Read with DRQ/BUSY polling, FM 128 B on T0S0, MFM 256 B after; drive 1 empty = NOT READY); density mismatch = RNF after 4+ revolutions; multi-sector read of a whole track then RNF at sector 17; Read Address; Step commands; seek verify error; INTRQ; Force Interrupt D0/D8; Write Sector single and multi, read back, write-back to the file re-read and compared; Write Track MFM (cylinder 4 side 1) and FM (T0S0), sectors read back, file checked; 640K cylinder 79 side 1; 160K side 1 RNF; write protect; PC 360K: 512-byte MFM on T0S0 and cylinder 39 side 1, 9-sector multi read, Read Address size code 2, sector write, 9 x 512 format |
| `tb/core/tb_core.sv` | PCOS boots and runs from the streamed image; every new LBA logged |
