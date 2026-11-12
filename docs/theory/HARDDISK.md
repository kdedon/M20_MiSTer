# Hard disk card -- theory of operation

RTL: `rtl/hdc/m20_hdc.sv` (one module). Images come through
`disk_stream` slots 2 and 3 ([SYSTEM.md](SYSTEM.md) section 6).

## 1. The card

The M20 hard disk card presents a WD1000-compatible task file at ports
0x1C1-0x1CF (controller A0-A2 on bus A1-A3, D7-D0) and drives up to two
disks of 6 heads x 33 sectors x 256 bytes per cylinder. ROM 2.x boots
from it when the card answers; PCOS's `vformat` and `hdisk` format and
install it. The model is register level: a sector buffer, the task file
and the command set the ROM and PCOS use (Restore, Seek, Read Sector,
Write Sector, Format Track). Seeks are instant; there is no ECC.

### Ports

| port | meaning |
|---|---|
| `io_addr`, `io_wdata`, `io_rd`, `io_wr`, `io_rd_end`, `io_wr_end` | the I/O bus; the card decodes itself |
| `sel`, `rdata` | this access is the card's; its byte (`cs_exp`/`exp_rdata` in `m20_core`) |
| `intrq` | INTRQ; not connected on the mainboard (section 6) |
| `d_mounted[1:0]`, `d_readonly`, `d_size`, `d_lba`, `d_rd`, `d_wr`, `d_ack`, `d_buff_*` | `disk_stream` drive side |

No parameters; the geometry is the localparams `HEADS` = 6, `SPT` = 33,
`SPC` = 198 sectors per cylinder.

### Registers (`rs = io_addr[3:1]`)

| n | read | write |
|---|---|---|
| 0 | data (`b_q`) | data |
| 1 | error `err_q` | write precompensation (stored, unused) |
| 2 | sector count `scnt_q` | sector count |
| 3 | sector `sec_q` | sector |
| 4 | cylinder low | cylinder low |
| 5 | cylinder high (2 bits) | cylinder high |
| 6 | SDH `sdh_q` | SDH: [6:5] size (0 = 256 B), [4:3] drive, [2:0] head |
| 7 | status | command |

While `bsy_q` every register reads as status. Status bits: BSY 0x80, RDY
0x40 (`sdh_q[4] == 0 & mnt_q[drv]`), SC 0x10 (seek complete, always set
after a seek), DRQ 0x08, ERR 0x01. Errors: ID not found 0x10, aborted
command 0x04.

## 2. Clocking and reset

All on `clk`. `rst_n` clears the task file (`sdh_q` = 0x20: 256-byte
sectors, head 0, drive 0) and `mnt_q`; `disk_stream` replays the mounts
after a machine reset, so `mnt_q` comes back within a few clocks. `ro_q`
and `nsec_q` (sectors in the image, `d_size / 256`) are not reset.

## 3. Blocks

```
 I/O bus --> sel = mnt_q != 0 & io_addr[15:4] == 0x01C
             wd_q (write data while /DS Low) --> host_wr (io_wr_end) / host_rd (io_rd_end)
                     |
                     v
 [task file] err precomp scnt sec cyl_lo cyl_hi sdh cmd; bsy drq sc err_st intrq
   trk0 = (cyl * 198 + head * 33), lba = trk0 + sec, id_ok / trk_ok
                     |
                     v
 [command engine e_st] E_IDLE E_DATA E_RD E_RDX E_WR E_WRX E_NEXT
   half_q ptr_q blk_q blk_end_q keep_q zero_q
                     |
                     v
 [sector buffer sbuf 512 B] <--> d_lba d_rd d_wr d_buff_* (one image block = two sectors)
```

Why this shape:

- **One block, two sectors.** The image block is 512 bytes and a sector
  256, so `half_q = lba[0]` picks the half. A read fetches the block and
  the host reads its half through `ptr_q`; a write collects 256 host
  bytes into the half, then reads the block from the image, overwriting
  only the other half (`keep_q`), and writes the whole block back.
- **Format is a zero fill.** Format Track takes the host's 256 format
  bytes as the WD1000 does (and ignores them), then walks the track's
  blocks `trk0/2 .. (trk0 + 32)/2`, zeroing the halves inside the track
  (`zero_q`) and keeping the neighbours' halves (`keep_q`), since a
  33-sector track starts or ends mid-block.
- **Self-decoding.** The card lives on an open decoder output and is
  present only while an image is mounted (`mnt_q != 0`), so a machine
  without a hard disk image sees 0xFFFF at 0x1C0 and ROM 2.x boots from
  floppy.

## 4. Operation

### Command write (`rs` = 7, not busy)

Clears INTRQ, error and DRQ; with the drive not ready sets aborted
command and INTRQ. Otherwise it latches `jdrv_q`, `half_q`, `trk0_q`,
`blk_q = lba / 2` and dispatches on `wd_q[7:4]`:

| op | code | action |
|---|---|---|
| Restore, Seek | 1, 7 | SC set, INTRQ |
| Read Sector | 2 | `id_ok` else ID-not-found; BSY, `keep_q = 11`, `E_RD` |
| Write Sector, Format | 3, 5 | DRQ, `E_DATA`: wait for 256 host bytes |
| other | | aborted command |

`trk_ok`: size code 0, head below 6, track start inside the image.
`id_ok`: `trk_ok`, sector below 33, LBA inside the image.

### Read

`E_RD` raises `d_rd[jdrv_q]` with `d_lba = blk_q`; `E_RDX` copies the 512
bytes into `sbuf` while `d_ack` and `d_buff_wr` (both halves, `keep_q =
11`); at the end BSY clears, DRQ and INTRQ set. The host reads register
0: each read advances `ptr_q` within `{half_q, ptr_q}`; the 256th clears
DRQ. A read of the cylinder-low register or status clears INTRQ; a
cylinder-low read while idle also clears DRQ.

### Write

`E_DATA`: each data write with DRQ stores `wd_q` at `{half_q, ptr_q}` and
advances; at the 256th byte BSY sets and the checks run (`id_ok` for a
write, `trk_ok` for a format; read-only drive = aborted). Then `E_RD`
fetches the block with `keep_q` = the other half only, so the host's
half survives, `E_WR`/`E_WRX` write the block back, `E_NEXT` ends with
INTRQ (or, for a format, steps `blk_q` to `blk_end_q` with fresh
`keep_q`/`zero_q` from `in_trk`, and finally zeroes the sector count).

### Multi-sector

`scnt_q` is stored but every command transfers one sector; the ROM and
PCOS issue one command per sector.

## 5. Timing and resources

A sector read is one block job (`disk_stream` hit: 512 clocks plus handshake)
plus 256 host reads; a write or format is two block jobs per block. The
buffer is one 512-byte M10K. Nothing waits on a spindle: there is no
rotational model.

## 6. Inferred and assumed

| item | status |
|---|---|
| Geometry 6 x 33 x 256, sectors from 0, cylinders from the image size | from the PCOS tools and ROM 2.x; the original drive's parameters are not documented in the repository |
| Instant seeks, SC always set | no timing in the software depends on it |
| Format zero-fills, ignores the format bytes | the WD1000 writes the ID fields from them; the image has no IDs |
| Drives 2 and 3 (SDH bit 4) never ready | two slots only |
| INTRQ unconnected | `hdc_intrq` is in `m20_core`'s unused list; ROM 2.x and PCOS poll status. Whether the card drives an 8259 input on the real board is not established |
| Status while busy returned for every register | WD1000 behaviour |

## 7. Verification

| bench | checks |
|---|---|
| `tb/hdc/tb_hdc.sv` (`make tb-hdc`) | `m20_iodec` + `m20_hdc` + `disk_stream` against a behavioural hps_io server: slot 2 a 180-cylinder patterned image, slot 3 small and read-only; a reference copy follows every write and format. Card absent while nothing is mounted (0xFFFF); status after mount; both halves of a block read; write then read back with the other half untouched; format of an odd and an even track start with neighbouring sectors kept; ID not found (sector 33, head 6, cylinder 180, size code 1, format head 6); not ready; reads while busy return status; write to the read-only drive aborted; INTRQ; eject; the whole image compared after write-back |
| `tb/core/tb_core.sv` `+hd=<file>` | ROM 2.x boot from the card |
