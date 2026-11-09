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

## Installation

- Copy `M20_*.rbf` to `_Computer/`.
- Put the boot ROM in `games/M20/boot.rom` (loaded at start), or load one with **Load Firmware**.
- Put disk images in `games/M20/`.

### Boot ROM

`boot.rom` is 8192 bytes: the two 2732 EPROMs interleaved, high byte first (H = U54, L = U65).

```
scripts/make_boot_rom.sh 2.0f games/M20/boot.rom   # versions 1.0, 1.0bc, 2.0d, 2.0f
```

ROMs are not included.

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
| Load Firmware | Load a boot ROM |
| Reset | |

Change the configuration or jumpers, then reset.

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
