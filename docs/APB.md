# APB 1086 (G0246): PAL reconstruction and implementation spec

Best-guess behavioural spec for the Olivetti APB 1086 8086 co-processor board, written so that an RTL author can implement it without the PAL dumps.

Confidence levels:
- **H** (high): two or more independent sources agree.
- **M** (medium): one direct source plus a consistency argument.
- **L** (low): inferred from function only.

## 0. Sources and evidence keys

| Key | What | Location |
|---|---|---|
| S1 | APB schematic sheet 01 (8086, 8284, ROMs, latches, transceivers, parts list 1) | HW2 page 7-35 = `reference/hardware/manuals/hw2.pdf` PDF p. 74 |
| S2 | APB schematic sheet 02 (both PALs, status logic, activation latch, parts list 2) | HW2 7-36 = PDF p. 75 |
| S3 | APB component layout and BOM | HW2 7-37 = PDF p. 76 |
| B | Block diagram Fig. 2-55 and the text "8086 Activation Circuits" / "Address Decoder" | HW1 2-86…2-90 = `hw1.pdf` PDF pp. 104–108 (Fig. 2-55 is p. 106) |
| F | APB ROM `apb-1086-2.0.bin` (= U11 even / U12 odd interleaved), mapped at FC000–FFFFF; reset `JMP F000:C858`. Addresses below are 8086 offsets in segment F000 | `reference/hardware/firmware/firmware86/` |
| Z | Z8001 ROM 2.0f (`m20-20f_interleaved.bin`, byte offsets) | `reference/hardware/firmware/Firmware_2_0f/` |
| D | MS-DOS 2.0 disk: `CONIO.BIN` (console driver), `IO.SYS`, and two memory dumps `E0.BIN`/`F0.BIN` (64 KB each, dated 1980-01-01 00:07/00:08, i.e. RTC unset, probably a real machine) | `reference/software/os/msdos2_0.img` |
| M | MAME `m20_8086.cpp` (whole file), `m20.cpp` lines 242–243 (NVI forward), 691 (handshake map), 721–722 (VI forward), 763 (halt at reset) | `reference/emulators/mame/` |
| P | M20 mapping PROM table (RAMTAB, Appendix A) and status decode | `docs/hardware_spec.md` §1, §3.2, §6 |

## 1. Board inventory and the two PALs

### 1.1 What the schematic shows (S1, S2, S3 parts lists)

| Ref | Part | Role |
|---|---|---|
| C532 (A06, S1) | 8086-2 (8 MHz) | MN/MX tied high (minimum mode). HOLD is pulled low (unused). RESET pin 21 = `RESE0`. NMI pin 17 = `NMION`. INTR pin 18 = `INTR0` |
| MCD9 (A08, S1) | 8284 | 24 MHz crystal, so CLK = 8 MHz. RDY2 (pin 6) = `PRDY0`. /AEN2 is grounded. /AEN1 net `AEN10` has a pull-up. RDY1 is unconnected (Z). /RES = RC power-on. READY drives the 8086 |
| PMSF ×2 | 2764 | APB ROM (U11 even byte, U12 odd byte) |
| DKL6 / DKLM | 74LS373 / 74LS533 | Address latches (`LA0`–`LA19`) |
| LBEH | 74LS245 | Data transceivers. The bus D0–D15 are wired straight to 8086 AD0–AD15 (see §2.4) |
| LDE9 (B01, S2) | 74LS244 | Bus drivers: `*MREQ`, ST2, ST0, `*AS` out; `CPU/*CRT`, `LATCH`, `*SWAIT`, `*NVI` in. Enabled by `RESE0` = 0 |
| NEDL | 74LS133 (13-input NAND) | **Address decoder** for the handshake ports (§3) |
| **PL40** (C10, S2) | **PAL16L8**, label "P U17 V2.3" | **Address translator** (§1.2) |
| **PL42** (A03, S2) | **PAL16R6**, label "P.U18 V2.1" | **State sequencer** (§1.3) |
| N08/P08 (S2) | 74LS10 ×2, cross-coupled | **Run latch** = `*BUSRQ` (§3) |
| D05, F08 (S2) | 74LS74 | INTA sequencing and the NVI-vs-VI choice (§3) |
| G11, G12 (S2) | 2-pin jumpers | Pull PL40 inputs `RP109`/`RP110` to ground (configuration, §1.2) |

The status generator is **discrete TTL, not a PAL** (S2 gates C07, D02, D08, E03, E07). This answers HW1's "Status Generation Logic" block.

### 1.2 PL40: PAL16L8 address translator. Pinout legible on S2 [H]

| Pin | Signal | Dir | Meaning |
|---|---|---|---|
| 1 | `RESE0` | in | 1 = APB inactive / 8086 in reset; presumably tri-states the outputs |
| 2 | `LA14` | in | 8086 A14 (latched) |
| 3 | `MIOON` | in | 8086 M/IO inverted (memory vs I/O) |
| 4 | `LA15` | in | 8086 A15 |
| 5–8 | `LA16N`…`LA19N` | in | 8086 A16–A19, inverted |
| 9 | `RP109` | in | Jumper G12; pull-up = 1 |
| 11 | `RP110` | in | Jumper G11; pull-up = 1 |
| 19 | `A1500` | out | M20 bus A15 |
| 12 | `A1400` | out | M20 bus A14 |
| 18–15 | `SN000`…`SN300` | out | M20 bus SN0–SN3 |
| 13 | `ROM00` | out | Local 2764 select. It also blocks the M20 data buffers (gates A06/A07: `DENON` = OR(NAND(`ROM00`, `OUTD4`), `DEN00`)) |
| 14 | `PAL06` | out | Goes to PL42 pin 8. This is the block diagram's `*VRAM`. Most likely "valid M20 memory cycle" (start a bus cycle) [L]. Possibly "video RAM" [L] |

**Function [M].** The translator maps 8086 A19–A14 (64 × 16 KB pages) to the M20 bus {SN3..0, A15, A14}. The M20's own mapping PROM (U44, P §3.2) then turns that into a physical DRAM block.

The APB cannot bypass that PROM: the bus carries pre-PROM SN/A14/A15, and the TA lines never reach the slot. So the 8086 sees memory through PCOS segment numbers. The table is derived in §2.2.

For I/O cycles (`MIOON`), the PAL must drive bus A14 = A15 = 0, or the motherboard decoder (NOR A11–A15, P §1) would not respond to 8086 port 0x40A0 etc. [M].

The two jumpers probably select a top-of-memory cut-off or a colour/B-W variant (§2.3 conflict C3) [L].

### 1.3 PL42: PAL16R6 state sequencer. Pinout legible on S2 [H]

| Pin | Signal | Dir | Meaning (best guess) |
|---|---|---|---|
| 1 | `CLKON` | clk | 8284 CLK inverted (8 MHz) |
| 2 | `MIO00` | in | 8086 M/IO |
| 3 | `INTA0` | in | 8086 /INTA |
| 4 | `CPUCT` | in | Bus `CPU_OR_CRT` (pin 86): DRAM slot owner [M] |
| 5 | `SWAIN` | in | Bus `*SWAIT` (pin 54): DRAM/CRT collision stretch [M] |
| 6 | `LATEN` | in | Bus `LATCH` (pin 85, `/VT_LATCH`): read data latched [L] |
| 7 | `DTR00` | in | 8086 DT/R |
| 8 | `PAL06` | in | From PL40 (`*VRAM`) |
| 9 | `ALE00` | in | 8086 ALE: start of a cycle |
| 11 | `RESE0` | /OE | Outputs tri-stated while the APB is inactive [M] |
| 19 | `ASOON` | out (comb.) | Bus `*AS` |
| 18 | `DS000` | out (reg.) | Bus `*DS` |
| 17 | `ST300` | out (reg.) | Bus ST3 (1 = memory) |
| 16 | `OUTD4` | out (reg.) | "Bus data phase", enables M20 data transceivers (gate A06) [M] |
| 15–13 | `TW000`/`TW100`/`TW200` | out (reg.) | 3-bit state counter (T1/T2/T3/Tw…) [M] |
| 12 | `MEMGR` | out (comb.) | Unclear. Possibly `*MREQ` gating or the READY request into the `AEN10`/`PRDY` net [L] |

**Function [M].**
- On ALE, if the cycle is for the M20 bus (not ROM, not the first INTA), the sequencer emits a Z8000-style cycle: `*AS` pulse, ST3, then `*DS`.
- It holds the 8086 not-ready until the M20 completes. That means waiting while `*SWAIT` / `CPU_OR_CRT` say the CRT owns DRAM, and for read data (`LATCH`).
- It then releases `*DS`.

The exact READY path is **not legible**. `PRDY0` (8284 RDY2) = NAND(`VIINT`, `OUT60`) and `AEN10` has a pull-up, so some sequencer output must also pull a ready term [L].

### 1.4 Status generation (TTL, S2) [M]

| Bus line | Equation read from S2 | Resulting codes |
|---|---|---|
| ST3 | PL42 `ST300` | 1 for memory |
| ST2 | `ST2ON` = OR(`VIINT`, M/IO) (E07) | 1 for memory **and** interrupt acknowledge, 0 for I/O |
| ST1 | Not traced; must be ≈ NOT M/IO | 0 memory, 1 I/O and INTA |
| ST0 | `ST0ON` = AND(`VIINT`, `OUT50`) (C07, open collector, pull-up B09) | 0 memory/I/O; 1 = VI ack; 0 = NVI ack (NVI latched by D05) |
| `*MREQ` | NAND(`WERD0`, M/IO) (E03) | Memory cycles |

Resulting Z-bus status per 8086 cycle:

| 8086 cycle | Z8000 status |
|---|---|
| Memory (code or data) | **1100**: program reference, i.e. **I-space** in the M20 PROM |
| I/O | 0010: standard I/O |
| Second INTA, VI | 0111: VI ack, so the M20 generates its two 8259 /INTA pulses |
| Second INTA, NVI | 0110: NVI ack, which clears the M20 NVI flip-flop |

ST2 = 1 for every memory cycle independently confirms the I-space translation in §2.2.

## 2. 8086-side map

### 2.1 Memory map (reconciled)

| 8086 range | Contents | MAME (M) | Firmware / DOS evidence | Conf. |
|---|---|---|---|---|
| 00000 – top of RAM | M20 DRAM, contiguous in 16 KB pages, video plane(s) skipped | `ram+0x4000` linear to `ram_size-0x4001` | F `CBA6–CC93`: sizes RAM by writing 0x55AA at seg 0x0400, 0x0800, … until a page fails (starts at 16 KB; size = 16·n+16 KB, stored at `0:0460`). Then an address-in-data pattern test (aliasing ⇒ "FAIL", non-fatal). Boot sector loaded to `0000:8000` (F `D220`) | H (contiguous), M (exact mapping §2.2) |
| top … DFFFF | Nothing: reads 0xFF/0xFFFF, writes ignored | unmapped | Required so the sizing loop stops | M |
| E0000–E3FFF | Video plane 0 (DRAM0 0000 = PCOS <3>0000) | VRAM | D `CONIO.BIN` 0x1491/0x1500: `VRAM_SEG = E000`. D `E0.BIN` E0000–E3FFF = screen bitmap | H |
| E4000–EFFFF | Colour planes 1–3 (= <3>4000/8000/C000), absent on B/W | **missing** | D `CONIO.BIN` 0x1118 (`add di,4000h` per plane), 0x1C41 (clears `E000:4000` onward). `E0.BIN` (B/W machine): all 0xFF | M |
| F0000–F3FFF | **Alias of 00000–03FFF** (IVT, BIOS data) | `highram` = `ram+0x4000` | F uses CS-relative data everywhere (`cs:0460`, `cs:04D8`, …) and puts SS = CS = F000. `F0.BIN` 0x0000 = IVT (`CACB:F000` entries) | H |
| F4000–F7FFF | Video plane 0 (same as E0000) | VRAM | F `D8DC` sets `cs:04D8` = 0x4000 (screen base). `D790` uses ES = F000. Scroll at `D9A4` | H |
| F8000–FBFFF | Nothing (0xFF) | unmapped | `F0.BIN` 0x8000–0xBFFF all 0xFF | M |
| FC000–FFFFF | APB ROM 16 KB (local, no bus cycle) | ROM | `F0.BIN` 0xC000+ = ROM image; reset vector at FFFF0 | H |

### 2.2 Translation 8086 → M20 bus (PL40 contents, best guess) [M]

Memory cycles always use **status 1100 (I-space)** (§1.4). Let n = 8086 A19–A16 and q = A15–A14.

| 8086 range | n | Bus SN3–0 | Bus A15,A14 | PROM I-space result (all configs, P App. A) |
|---|---|---|---|---|
| 00000–0FFFF | 0 | 0 | q | DRAM0 4000–13FFF (blocks 1–4) |
| 10000–1FFFF | 1 | 2 | q | DRAM0 14000–1FFFF, then first expansion block (or none) |
| 20000–2FFFF | 2 | 8 + (A15) | 1, A14 | <8>8000, <8>C000, <9>8000, <9>C000 |
| 30000–7BFFF | 3–7 | n + 8 (B–F) | q | Expansion, linear |
| 7C000–7FFFF | 7, q=3 | **none** (guess) | – | PROM would give an alias of block 24 (see C3) |
| 80000–DFFFF | 8–D | none | – | – |
| E0000–EFFFF | E | 3 | q | Planes 0–3 (B/W: plane 0 only, rest none) |
| F0000–F3FFF | F, q=0 | 0 | 0,0 | Block 1 = alias of 8086 page 0 |
| F4000–F7FFF | F, q=1 | 3 | 0,0 | Block 0 = VRAM plane 0 |
| F8000–FBFFF | F, q=2 | none | – | – |
| FC000–FFFFF | F, q=3 | – (`ROM00` = 0) | – | Local ROM |

**Why this table.** Tested by script against all seven RAMTAB configurations in `hardware_spec.md` Appendix A (I-space column):

| Config | Blocks seen by 8086 pages 0, 1, 2, … | Pages until first hole/alias |
|---|---|---|
| No expansion (128 KB) | 1–7, then none | 7 = 112 KB (all non-video DRAM) |
| B/W 32K cards | 1–8, 9, 16, 17, 24, 25, then none | 13 = 208 KB (all non-video DRAM) |
| B/W 128K cards | 1–31, then 24 (alias) | 31 = 496 KB (all non-video DRAM) |
| 4-col 32K | 1–7, 9, 16, 17, 24, 25 (skips plane block 8) | 12 |
| 8-col 32K | 1–7, 9, 17, 24, 25 (skips planes 8, 16) | 11 |
| 4-col 128K | 1–7, 9–31, then 24, 25 | 30 |
| 8-col 128K | 1–7, 9–15, 17–31, then 24–26 | 29 |

- Every configuration yields **contiguous, non-aliased RAM that skips exactly the colour planes**. That is what the 8086 memory test requires.
- No D-space or identity mapping does this. D<0>4000 = expansion RAM, and "No expansion" D<1>C000 aliases block 4.
- The <8>/<9> choice for n = 2 is interchangeable with <A>/<9>: identical PROM contents.

### 2.3 Conflicts and open points

| # | Item | MAME | This spec | Resolution needed |
|---|---|---|---|---|
| C1 | 8086 RAM layout | Linear over MAME's RAM buffer + 0x4000, config-independent | Through the M20 PROM. Equals MAME for B/W 128K-card machines; skips colour planes otherwise; 32K cards differ | Implement via the core's PROM function with ST2 = 1 |
| C2 | Colour planes at E4000–EFFFF | Not mapped | Mapped to <3>4000… | CONIO.BIN uses them |
| C3 | Top-of-memory cut-off | `ram_size − 0x4000` | Page 0x1F guessed "none". In the 4/8-colour 128K configs, PROM aliases begin at pages 30/29, which the ROM test would flag. Possibly what jumpers G11/G12 select | PL40 dump or jumper silkscreen |
| C4 | HW1 "7FFA/7FFC" vs Z8001 "3FFA/3FFC" | Both mapped literally | Same bus address. The 8086's port 0x7FFA reaches the bus as 0x3FFA because PL40 forces bus A14/A15 = 0 on I/O. The 74LS133 decodes A3–A13 = 1 plus A1/A2; A14 is not decoded. HW1 quotes the 8086 view | 74LS133 pin trace (help wanted) |
| C5 | 8086 I/O window | 0x4000–0x4FFF only | Probably 0x4000–0x7FFF → bus 0x0000–0x3FFF. Ports with A14 = 0 are unknown. Firmware/DOS only use 0x4000–0x41CE, 0x4802–0x4866 and 0x7FFA | Low impact |
| C6 | 8086 stop | HALT line; restart pulses reset | Run latch cleared ⇒ 8086 **held in RESET** while it does not own the bus (`RESE0` = 8086 RESET pin) | Same software-visible behaviour |
| C7 | NVI to 8086 | Raw PIT level; Z8001 latch not cleared by the 8086 ack | 8086 INTA runs a Z NVI-ack cycle (0110), which clears the M20 NVI flip-flop | Implement the hardware way |
| C8 | 8086 NMI pin | Not connected | `NMION` (inverse of the bus `*NMI` driver) goes to 8086 pin 17. Irrelevant, because the 8086 is reset as soon as its OUT 0x7FFA cycle ends | Tie 8086 NMI low |
| C9 | `MAME emulation_status`: "0x00000 – (RAM−0x4001)" | – | Off by one only; harmless | – |

### 2.4 Byte lanes [H]

- D0–D15 pass straight through (S1 transceivers).
- Evidence 1: the 8259 on D1–D8 returns vector 2n to the 8086. F programs ICW2 = 0 and installs the keyboard (IR4) handler at vector **8** (`ds:0020`, F `C877`). MAME `int_cb` returns `acknowledge()<<1`.
- Evidence 2: CONIO.BIN flips byte addresses with `xor bx,1` (0x0A19) when drawing glyphs into the big-endian bitmap.
- Consequences for the RTL:
  - Word values are identical for both CPUs.
  - An **8086 byte at an even address is the Z8001 byte at the odd address** (D0–D7) and vice versa.
  - The bus A0/B-W must be generated accordingly: for an 8086 byte access, Z A0 = NOT 8086 A0.
  - Z-side 8-bit peripherals at odd ports appear at 8086 even ports (0x4000+port−1).

### 2.5 8086 I/O map actually used (F, D)

| 8086 port | Bus port | Device |
|---|---|---|
| 0x4000–0x4006 | 0x01–0x07 | FD1797 |
| 0x4020 | 0x21 | Config/drive latch. F `C99F`: bits 4..3 = drive type, 0 ⇒ ask the user |
| 0x4060/62 | 0x61/63 | 6845 |
| 0x4080–86 | 0x81–87 | 8255 |
| 0x40A0/A2 | 0xA1/A3 | Keyboard 8251 |
| 0x40C0/C2 | 0xC1/C3 | TTY 8251 |
| 0x4120–26 | 0x121–127 | 8253 (F `CA88`: ch0 mode 3, ch1 mode 3, ch2 count 0xF062 = 20 Hz) |
| 0x4140/42 (word) | 0x140/142 | 8259 (values ×2) |
| 0x4180–86 | 0x181–187 | Unknown option. F `C983` writes 0, 0, 1, 1 once; open bus is fine |
| 0x41C0–CE | 0x1C1–1CF | WD1000 HDC |
| 0x4802–4866 | 0x802–866 | Twin RS-232 board (8251 ×2, 8259, 8253) |
| **0x7FFA** | **0x3FFA** | CLRRUN (F `D4B4`) |

## 3. Handshake and interrupts

### 3.1 Run/stop sequence

| Step | Hardware (S2, B) | Software evidence |
|---|---|---|
| 1. Presence probe | Z8001 `LD R12,#DEAD; OUT 3FFA,R13`, then a DJNZ timeout. An APB decodes 0x3FFA → `*CLRRUN` → bus `*NMI` low (74LS09 `NM100`) | Z 0x9EC–0x9F5. NMI vector in PSA at Z 0x128 → handler 0x78E |
| 2. Prompt | NMI handler: R12 = DEAD ⇒ prints "Select Alternate CPU (y/n)?" | Z 0x798–0x7BC, string at Z 0x1359 |
| 3. SETRUN | `DI; LD R12,#C01D; OUT 3FFC,R13; JR $`. Decoder → `*SETRUN` → run latch (N08/P08 NAND-SR) sets → `*BUSRQ` low | Z 0x7BE–0x7C9 |
| 4. Grant | Z8001 floats the bus, `*BUSACK`. `RESE0` = NAND(`/RESET`, BUSACK, BUSWE) goes 0: 8086 leaves reset, 244/PAL outputs enabled | S2 L11 |
| 5. 8086 runs | Fetches FFFF0 from local ROM, POST, boots DOS. Z8001 stays parked in `JR $` | F `C858` |
| 6. Return | User presses keyboard code 0x90 → 8086 `OUT 7FFA,AX; HLT` → bus I/O 0x3FFA → `*CLRRUN`: latch clears (`*BUSRQ` high) and bus `*NMI` pulses | F `D4AC–D4B8` (INT 8 = IR4 handler) |
| 7. Release | When the 8086 write cycle ends (`BUSWE` term), `RESE0` = 1: 8086 in RESET, APB drivers off. Z8001 resumes and takes the NMI | S2 M10/L11 |
| 8. Reboot | NMI handler: R12 = C01D ⇒ `JP <4>0150` (Z8001 cold start) | Z 0x78E–0x797 |
| M20 `*RESET` | Clears the run latch and holds the 8086 in reset | S2 N08 |

Other NMI cases: R12 neither DEAD nor C01D → `nmi_halt` path (Z 0x7CA).

### 3.2 Interrupts to the 8086 [M]

| Item | Behaviour | Evidence |
|---|---|---|
| INTR | `INTR0` = NAND(`*VI`, `*NVI`) = VI OR NVI, from the bus | S2 D01; M `nvi_w`/`vi_w` |
| VI gating | Bus `*VI` reaches the 8086 only while the APB runs (the Z8001 is parked with DI) | M `int_w` |
| First INTA | Handled on the board. D05 samples `*NVI` at the first INTA, gated by F08, so **NVI has priority**. No bus cycle | S2 D04/D05/F08; M `int_cb` checks NVI first |
| Second INTA, NVI pending | Bus cycle with status **0110**. Nobody drives D; pull-ups on AD (KR93 networks, S1) give **vector 0xFF**. The M20 NVI flip-flop clears | F `C8F9` installs the tick handler at vector 0xFF (`ds:03FC` = D3B8); the handler does no I/O ack (F `D3B8–D482`); M returns 0xFF |
| Second INTA, VI | Bus cycle with status **0111**. M20 logic gives the 8259 its two /INTA pulses and forces D0 = 0, so the 8086 reads **2n** | P §6; M `acknowledge()<<1` |
| EOI | Software, specific EOI to 8086 port 0x4140 (value 0xC8 = IR4) | F `D4A5`, `D570` |
| 8086 NMI | Not used (see C8) | – |

## 4. Help wanted (README text)

> **Help wanted: Olivetti APB 1086 (8086 board, G0246) PAL contents.** We are reconstructing the board for an FPGA core and have a working best-guess spec (`docs/APB.md`). Any of the following would settle the open points:
>
> 1. **JEDEC/fuse dumps** of the two PALs:
>    - **PL40**: MMI/TI **PAL16L8**, board position **C10**, Olivetti program "U17 V2.3". This is the address translator.
>    - **PL42**: **PAL16R6**, position **A03**, program "U18 V2.1". This is the bus state sequencer.
>
>    Secured parts can still be read functionally. The 16L8 needs an exhaustive 10-input sweep. The 16R6 needs a state-exploring reader such as the hkzlab DuPAL (support for 16R6 unverified).
>
>    Salvatore Paxia reproduced this board and programmed these PALs (z80ne.com, Davide Bucci's 2024 APB page), so his JED files or equations would answer everything.
> 2. **Photos** of an original APB 1086 (both sides). We need chip markings and the silkscreen next to jumpers G11/G12.
> 3. **Continuity checks** on a real board:
>    - which address lines go into the 74LS133 (NEDL) and the A1/A2 gating for 0x3FFA/0x3FFC;
>    - what drives bus ST1, R/W, B/W, N/S and A0;
>    - what drives 8284 pin 3 (/AEN1, net `AEN10`) and PL42 pin 12 (`MEMGR`).
> 4. **Jumper G11/G12 settings** used with 128 KB, 32K-card, 128K-card and colour machines.
> 5. A **memory dump** from MS-DOS `DEBUG` on a colour or 512 KB M20 with the APB (`D 7000:C000`, `D E000:4000`), plus the "Memory Test" result line at power-on.

## 5. Implementation effort in the MiSTer core

### 5.1 Work items

| Item | Notes | Estimate |
|---|---|---|
| 8086 CPU core | See 5.2; needs min-mode style bus or a simple req/ack wrapper | 3–5 d integration |
| Bus-master bridge | When run = 1: park the Z8001 (hold its clock enable or a BUSREQ input). Route 8086 memory cycles through the **existing M20 PROM mapping** with {SN, A15, A14} from the §2.2 table and I-space; I/O to the I/O decoder with A14 = A15 = 0; byte-lane rule §2.4; open-bus 0xFFFF for "none" | 3–4 d |
| Translator, ROM, aliases | §2.2 as a 64-entry LUT; 16 KB ROM from the APB image (BRAM 8 × M10K or SDRAM) | 1 d |
| Handshake | Run latch (set on bus I/O 0x3FFC/D, clear on 0x3FFA/B or reset); NMI pulse on 0x3FFA; 8086 reset = !(run & granted) with completion of the in-flight cycle | 1 d |
| INTA path | NVI-priority latch at first INTA; second INTA → reuse the core's VI-ack / NVI-ack logic (two 8259 /INTA pulses, D0 = 0); undriven ⇒ 0xFF | 1–2 d |
| Floppy format | MS-DOS disks are PC 360K (40 × 2 × 9 × 512 MFM). The disk-stream layer must synthesize 9-sector 512-byte tracks and allow 40 cylinders | 2–3 d |
| OSD | "APB fitted" option (no NMI on the 0x3FFA probe when absent) | <0.5 d |
| Verification | APB POST screen ("M20 Power on Test Results"), DOS 2.0 boot, CONIO colour, return-to-PCOS (key 0x90) | 1–2 wk |

**Total: about 3–5 weeks.** `core_readiness.md` says 2–3 wk; the extra time is the 360K floppy format and colour/RAM-config verification.

Resource impact: an 8086 core plus glue is about 3–8 k ALMs. That fits next to the Z8001 (about 4.7 k) in the 5CSEBA6.

### 5.2 FPGA 8086 core options

Everything in this table except the summary line is **unverified**: check the repository and licence before use.

| Core | ISA | Licence | Notes |
|---|---|---|---|
| MCL86 (MicroCore Labs, Ted Fried) | 8088/8086, microsequenced, cycle-accurate | Unverified (believed permissive) | Used in early PCXT_MiSTer work (unverified). The 8088 bus variant may need a 16-bit wrapper |
| PCXT_MiSTer CPU (spark2k06 / kitune-san) | 8088 | Unverified (believed GPL-3) | 8-bit bus; would need adapting to the 16-bit 8086 bus |
| Next186 (Nicolae Dumitrache) | 80186 | Unverified | Compact, not cycle-accurate |
| s80x86 (Jamie Iles) | 80186 | Unverified (believed GPL-3) | Clean SystemVerilog, microcoded |
| Zet | 8086 | Unverified (believed GPL-3) | Older, Wishbone bus |
| v30mz (WonderSwan_MiSTer, R. Peip) | NEC V30MZ (80186-like) | Unverified | Fast, VHDL |
| ao486 (A. Osman) | 486 SX | Unverified (believed BSD-style) | Far too large for this job |

**Summary.** Cycle accuracy is not needed: the Z8001 is parked and the firmware times with NVI and FDC status. A 186-class core is acceptable unless software depends on 8086-only quirks (PUSH SP, shift counts > 31, POP CS); MS-DOS 2.0 and the APB ROM do not appear to. Pick the core whose licence matches the project (MiSTer cores are typically GPL-2/3).

**Chosen: z8086** (nand2mario, github.com/nand2mario/z8086 @ 596d9a6, Apache-2.0 per its README). A real 8086: 16-bit `rd/wr/io/word/ready` bus (odd words split by the core), two INTA cycles per interrupt, ~1.2 k ALMs, runs the original Intel microcode. Not cycle-exact. The microcode (512 × 21 bits) is not committed: `scripts/make_apb_rom.sh` appends it to the APB ROM image. MCL86 (MIT, PCXT_MiSTer) was the fallback: field-proven, but its BIUs are 8088 (byte-split I/O words would break the 8259 on D1–D8).

## 6. What the core implements

`rtl/apb/m20_apb.sv`; the mainboard takes it as a bus master through its `ext_*` port while /BUSACK is Low.

| Item | Core behaviour |
|---|---|
| 8086 clock | 8 MHz clock enable on the 48 MHz clock |
| ROM | 16 KB at FC000, 4 CPU clocks per access (an 8086 bus cycle), no bus cycle |
| Empty pages (§2.2 "none") | No bus cycle; reads 0xFFFF, 4 CPU clocks |
| Bus cycles | Z8001 timing on the mainboard CPU clock (so DRAM waits and the CRT stretch apply). /DS falls / data taken / /DS rises at CPU clock 1/2/3 (memory read), 2/–/3 (write), 2/3/4 (I/O), 5/7/8 (acknowledge). Next T1 one clock after /DS rises |
| Byte writes | Byte on both halves of AD, Z A0 = NOT 8086 A0 |
| I/O | All 8086 ports, A15/A14 dropped |
| 74LS133 | Any I/O cycle (either master, read or write) with A13–A3 = 1: A2:A1 = 01 pulls /NMI while /DS is Low and clears the run latch at its end; 10 sets it |
| Reset | 8086 in reset unless run latch and /BUSACK; also on machine reset and with the OSD option off (no /NMI, no /BUSREQ) |
| INTA | First INTA on the card (latches NVI); second runs status 0110 (NVI, reads 0xFFFF) or 0111 (VI) |
| CPU patch | z8086 popped the next opcode byte at the FC that takes a hardware interrupt, so IRET returned one byte too far (the APB ROM's 20 Hz tick handler then corrupted the POST). The patched copy leaves the byte in the queue. It also latched INTR at an early RNI inside the interrupt sequence (IF still set), so a VI arriving during the NVI entry interrupted the handler's first instruction ("Unexpected Interrupt"); INTR is no longer latched while INT/INTO/the interrupt sequence runs. A REP prefix whose decode met the previous instruction's last micro-instruction was dropped (seen as a one-word SYSINIT relocation); the set now wins |
| Floppy | The FDC serves 163,840 / 184,320 / 327,680 / 368,640-byte images as PC 8/9 × 512, 40 cylinders, all MFM, 1:1 interleave |

### 6.1 Seen in simulation (ROM 2.0f, APB ROM 2.0, MS-DOS 2.0, 128K B/W)

- The probe NMI, prompt and SETRUN/BUSACK hand-over work as in §3.1; the 8086 passes all power-on tests and boots MS-DOS to `A>`. Key 0x90 (COMMAND+RESET) runs OUT 7FFA: /NMI, run latch clear, 8086 reset, Z8001 cold start (§3.1 steps 6-8).
- SYSINIT sizes memory itself (paragraph NOT/compare scan from 32 KB) and stops at 1C000: 112 KB, as §2.2 predicts for this configuration.
- Floppy: the APB ROM and IO.SYS read 512-byte sectors with 0x88/0x8A (L = 1, size from the ID), one sector per command, side by U. The boot sector takes the geometry from port 0x21 D4:D3: 1 = 180K (FC), 2 = 360K (FD), 3 = 720K (7D, 80 tracks). A 360K disk needs drive type 2 (OSD "2.x 320K drives"). Port 0x21 D7 = TG43 from cylinder 43.
