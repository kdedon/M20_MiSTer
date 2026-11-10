# Olivetti M20 for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

The Olivetti L1 M20 (1982): a Zilog Z8001 personal computer running PCOS.

## Features

- Z8001 CPU at 4 MHz with the mapping PROM, segment traps and CRT wait states.
- Up to 512 KB RAM in every PCOS memory configuration.
- 512×256 bitmap video: black and white, 4 or 8 colours.
- Two floppy drives (FD1797), streamed from SD.
- M20 keyboard from PS/2, with buzzer.
- RS-232 port on the MiSTer UART.
- 8259 PIC, 8253 PIT, 8255 PPI.
- Optional expansion cards: twin RS-232 (two 8251, 8253, slave 8259) and IEEE-488 (8291A/8292 registers only, nothing on the bus).
- Boot ROM of 8 KB (2732) or 16 KB (2764), and the three extension ROM sockets.

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

### Disk images

Raw `.img`, every sector 256 bytes (track 0 side 0 holds 128-byte FM sectors in the first half):

| Size | Format |
|---|---|
| 286,720 | 320K, 35 cylinders, double sided |
| 143,360 | 160K, single sided |
| 655,360 | 640K, 80 cylinders |

## OSD

| Option | Meaning |
|---|---|
| Floppy 0 / 1 | Mount an image |
| Configuration | Memory and video cards: B/W, 4 or 8 colours, 32K or 128K cards |
| Jumpers ZA/SPARE1 | ROM 1.x: run or skip self-tests. ROM 2.x: drive type (160K, 320K, 640K, or ask) |
| Aspect ratio | Original, full screen, custom |
| IEEE-488 card, Twin RS-232 card | Fit the card |
| Serial port | RS-232 port on the MiSTer UART: mainboard, twin card A or B. The others see an idle line. |
| Load Firmware | Load a boot ROM |
| Load extension ROM | Load the extension sockets |
| Reset | |

Change the configuration, jumpers or cards, then reset.

## Keyboard

Italian layout. Keys map by position, except , ; . which follow their legends.

| PC key | M20 key |
|---|---|
| Esc | RESET |
| Tab | COMMAND |
| \\ or F1 | S1 |
| Backspace or F2 | S2 |
| Left Alt or ISO <> | < > |
| Keypad | Keypad |

## Status

Boots ROM 1.0 and 2.0f to the PCOS prompt in simulation, with 512 KB and a correct memory count. Not yet tested on hardware; disk writes are untested.

## Credits

- Z8001 CPU: k8000.
- 8259, 8253, 8255: KF8259/KF8253/KF8255 by Kitune-san (MIT).
- FD1797: derived from sorgelig's wd1793 (GPL).
- MC6845 and SDRAM controller: from C900_MiSTer and NeoGeo_MiSTer.
- Hardware documentation, ROMs and disk archive: z80ne.com/m20.
