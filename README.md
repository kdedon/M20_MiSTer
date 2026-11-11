# Olivetti M20 for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

The Olivetti L1 M20 (1982): a Zilog Z8001 personal computer running PCOS.

## Features

- Z8001 CPU at 4 MHz with the mapping PROM, segment traps and CRT wait states.
- Up to 512 KB RAM in every PCOS memory configuration.
- 512×256 bitmap video: black and white, 4 or 8 colours.
- Two floppy drives (FD1797), streamed from SD.
- Optional hard disk card (WD1000-compatible) with two drives, present while an image is mounted.
- M20 keyboard from PS/2, with buzzer.
- RS-232 port on the MiSTer UART.
- 8259 PIC, 8253 PIT, 8255 PPI.
- Optional expansion cards: twin RS-232 (two 8251, 8253, slave 8259) and IEEE-488 (8291A/8292 registers only, nothing on the bus).
- Boot ROM of 8 KB (2732) or 16 KB (2764), and the three extension ROM sockets.
- Optional APB 1086 8086 card (MS-DOS 2.0, needs boot ROM 2.0d or 2.0f).

## Installation

- Copy `M20_*.rbf` to `_Computer/`.
- Put the boot ROM in `games/M20/boot.rom` (loaded at start), or load one with **Load Firmware**.
- Put disk images in `games/M20/`.

### Boot ROM

`boot.rom` is 8192 bytes (two 2732) or 16384 bytes (two 2764, e.g. BIOS 2.0x): the two EPROMs interleaved, high byte first (H = U54, L = U65).

```
scripts/make_boot_rom.sh 2.0f games/M20/boot.rom   # versions 1.0, 1.0bc, 2.0d, 2.0f
```

ROMs are not included.

### Extension ROM

**Load extension ROM** takes up to 48 KB in the same format, 16 KB per socket pair (U55/U66 at <7>4000, U56/U67 at <7>8000, U57/U68 at <7>C000); an 8 KB image appears twice in its socket. The boot ROM starts it when the `,` key is held at power-on and <7>4008 holds AAAA5555.

### APB 8086 ROM

`boot1.rom` (loaded at start, or with **Load APB ROM**) is 18432 bytes: the 16 KB APB ROM as the 8086 sees it at FC000 (U11 even bytes, U12 odd), then the 8086 microcode. The script fetches the microcode from the z8086 repository:

```
scripts/make_apb_rom.sh games/M20/boot1.rom
```

### Disk images

Raw `.img`, every sector 256 bytes (track 0 side 0 holds 128-byte FM sectors in the first half):

| Size | Format |
|---|---|
| 286,720 | 320K, 35 cylinders, double sided |
| 143,360 | 160K, single sided |
| 655,360 | 640K, 80 cylinders |
| 368,640 | PC 360K (MS-DOS for the APB): 40 cylinders, 9 × 512, all MFM |
| 327,680 / 184,320 / 163,840 | PC 320K / 180K / 160K |

Hard disk images are raw, 6 heads × 33 sectors × 256 bytes per cylinder, sectors in cylinder/head/sector order. A 9 MB drive (180 cylinders) is 9,123,840 bytes; a blank one:

```
truncate -s 9123840 games/M20/hd0.img
```

A drive is empty until its image is mounted, so the boot ROM asks for a disk if it starts first.

- At core start, `games/M20/boot0.vhd` (any floppy image, renamed) is mounted on Floppy 0 before the machine starts; `boot2.vhd` goes to Hard disk 0.
- In an MGL, mount the floppy before loading the firmware: the firmware load resets the machine.

```
<file delay="1" type="s" index="0" path="pcos20f.img"/>
<file delay="1" type="f" index="1" path="rom20f.rom"/>
```

Paths are relative to `games/M20`. With `boot.rom` loaded at start, end the MGL with `<reset delay="1"/>` instead.

A blank disk reads as formatted and empty: ROM 2.x reports `Invalid File Error 00 on Drive 10` and boots from the floppy. Prepare it under PCOS 2.x with `vformat 10:`. PCOS 1.x calls ROM 1.0 routines and does not run with ROM 2.x.

## OSD

| Option | Meaning |
|---|---|
| Floppy 0 / 1 | Mount an image |
| Hard disk 0 / 1 | Mount an image; the card is fitted while one is mounted (ROM 2.x) |
| Configuration | Memory and video cards: B/W, 4 or 8 colours, 32K, 128K or no cards. Default B/W 128K cards (512 KB); PCOS 2.x does not boot with no cards |
| Jumpers ZA/SPARE1 | ROM 2.x: drive type (320K, 640K, 160K, or ask). ROM 1.x: run or skip self-tests. Default 2.x 320K drives; ROM 1.x needs 1.x full tests, since skipping them also skips the keyboard check that tells PCOS 1.x its layout |
| Aspect ratio | Original, full screen, custom |
| IEEE-488 card, Twin RS-232 card | Fit the card |
| Serial port | RS-232 port on the MiSTer UART: mainboard, twin card A or B. The others see an idle line. |
| APB 8086 card | Fit the card. ROM 2.x then asks "Select Alternate CPU (y/n)?" |
| Load Firmware | Load a boot ROM |
| Load extension ROM | Load the extension sockets |
| Load APB ROM | Load the APB image |
| Reset | |

Change the configuration, jumpers or cards, then reset. Options are kept in `config/M20_v5.CFG`; delete it to return to the defaults.

## Keyboard

Italian layout. Keys map by position, except , ; . which follow their legends.

Ctrl+Esc is CTRL+RESET, the PCOS logical reset (boot PCOS again). RESET on its own is an ordinary key, and the boot ROM has no reset key: at its prompts use OSD Reset.

| PC key | M20 key |
|---|---|
| Esc | RESET |
| Tab | COMMAND |
| \\ or F1 | S1 |
| Backspace or F2 | S2 |
| Left Alt or ISO <> | < > |
| Keypad | Keypad |

Under MS-DOS, Tab+Esc (COMMAND+RESET) returns to the Z8001 and restarts it.

## Status

Boots ROM 1.0 and 2.0f to the PCOS prompt in simulation, with 512 KB and a correct memory count. Not yet tested on hardware; disk writes are untested.
With the APB card, ROM 2.0f hands over to the 8086, which passes its power-on tests and boots MS-DOS 2.0 to the `A>` prompt in simulation (128K B/W); Tab+Esc returns to the Z8001.

## Help wanted: APB 1086 PALs

The APB 1086 (G0246) 8086 board is being built from a best-guess reconstruction (`docs/APB.md`); its two PALs were never published. Any of these would settle the open points:

1. **JEDEC/fuse dumps** of the PALs:
   - PL40, PAL16L8 at C10, program "U17 V2.3" (address translator);
   - PL42, PAL16R6 at A03, program "U18 V2.1" (bus sequencer).

   Secured parts can still be read functionally (exhaustive sweep for the 16L8, a state-exploring reader for the 16R6). Salvatore Paxia reproduced this board and programmed these PALs; his JED files or equations would answer everything.
2. **Photos** of an original board, both sides, showing chip markings and the silkscreen at jumpers G11/G12.
3. **Continuity checks:** the inputs of the 74LS133 port decoder and the A1/A2 gating for 0x3FFA/0x3FFC; what drives bus ST1, R/W, B/W, N/S and A0; what drives 8284 pin 3 (/AEN1) and PL42 pin 12.
4. **G11/G12 jumper settings** used with 128 KB, 32K-card, 128K-card and colour machines.
5. **A memory dump** from MS-DOS `DEBUG` on a colour or 512 KB M20 with the APB (`D 7000:C000`, `D E000:4000`), plus the power-on "Memory Test" line.

Please open an issue.

## Credits

- Z8001 CPU: k8000.
- 8086 CPU: z8086 by nand2mario (Apache 2.0), running the original Intel microcode.
- 8259, 8253, 8255: KF8259/KF8253/KF8255 by Kitune-san (MIT).
- FD1797: derived from sorgelig's wd1793 (GPL).
- MC6845 and SDRAM controller: from C900_MiSTer and NeoGeo_MiSTer.
- Hardware documentation, ROMs and disk archive: z80ne.com/m20.
