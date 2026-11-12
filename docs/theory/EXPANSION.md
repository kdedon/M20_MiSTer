# Expansion cards -- theory of operation

RTL: `rtl/exp/m20_twin.sv` (G0221 twin RS-232 card), `m20_ieee.sv` (G0220
IEEE-488 card), `m20_gpib.sv` (its 8291A/8292 registers), `m20_xpic.sv`
(slave 8259 on a card), `m20_cascade.sv` (the vector mux on the
mainboard bus).

## 1. The cards

Both cards sit on the bus decoder's open outputs, decode their own
ports, and carry a slave 8259A whose INT is one of the master's cascade
inputs: the twin card's `*SYSINT` on IR7, the IEEE-488 card's `*COMVI1`
on IR1. The OSD fits them (`cfg_twin`, `cfg_ieee`, latched at reset);
with a card out its ports read 0xFFFF and its interrupt line is Low.

Both decode with `strobe = io_rd | io_wr | io_rd_end | io_wr_end` so
their `cs`/`cs16` cover the strobe and its end clock, as the mainboard's
read mux needs.

## 2. Twin RS-232 (`m20_twin`)

```
 A15-A12 = 0, A11 = 1 (0x800 block); A7-A5 picks:
   0x801/0x803  8251 A   cs_usart[0]  C/D = A1
   0x821/0x823  8251 B   cs_usart[1]
   0x840/0x842  8259     cs16         D1-D8, A0 = A1
   0x861-0x867  8253     cs_pit       A1-A0 = A2-A1
   0x881        modem status (read)   cs_modem: 0x5F
```

A0, A3, A4, A8-A10 are not decoded. The card's 8253 (`m20_pit`) takes
`ce_pit` as every CLK (the card's own 16 MHz oscillator through a
74LS163, taken as the same /13), GATEs High; OUT0 clocks 8251 A, OUT1
8251 B, OUT2 is not jumpered. The slave 8259 inputs are IR0 RxRDY A, IR1
TxRDY A, IR2 RxRDY B, IR3 TxRDY B; IR4-IR7 grounded. Modem status reads
`{0, 1, 0, 1, BUSY B, SDET B, BUSY A, SDET A}` = 0x5F: receivers idle.
`sysint = en & irq`.

The channels' `rxd`, `txd`, `cts_n`, `dsr_n`, `rts_n`, `dtr_n` go to
`m20_rs232`, which routes the one MiSTer UART to the port chosen in the
OSD and holds CTS/DSR asserted ([PERIPHERALS.md](PERIPHERALS.md)).

## 3. IEEE-488 (`m20_ieee`, `m20_gpib`)

```
 A15-A11 = 0, A8 = 1 (the mainboard's open U21 outputs); A7-A5 picks:
   0x101/0x103         8292 controller   cs_ctl   A0 = A1
   0x161-0x16F (odd)   8291A talker/listener  cs_tl   RS2-RS0 = A3-A1
   0x1A0/0x1A2         8259              cs16     D1-D8
```

`m20_gpib` is the two chips at register level on an empty bus: no device
ever answers, so nothing moves; the registers hold, read back and
interrupt as the header of `m20_gpib.sv` tabulates (ISR1 ERR sets on each
data-out write since no listener holds NRFD/NDAC; address status follows
the address mode; auxiliary command 0x02 resets; the 8292 TCI clears
while a command is written and sets at its end; SYC = 1). Writes commit
at `io_wr_end`. Slave 8259 inputs: IR1 8292 TCI, IR2 SPI, IR3 8291A INT,
IR4 8292 input buffer empty (`~ibf`), IR5 OBF. `comvi1 = en & irq`.

The card exists so that software probing for it (PCOS device checks,
the ROM) finds a quiet, correctly registered card; it carries no bus.

## 4. Slave 8259 (`m20_xpic`)

The same KF8259 wrapper as `m20_pic` with `slave_program_n = 0` and
`cascade_in = cas` from the master. Its D0-D7 sit on D1-D8 like the
master's, so the card decodes a word port with A0 = CPU A1. During an
acknowledge the slave compares `cas` with its ICW3 number and, when it
matches, drives `{ICW2[7:3], IR}` while the second /INTA is Low; `rdata`
is `{7'h7F, data, 1}` or `{7'h7F, vector, 0}`, held for the clock after
the strobe, as the master's.

## 5. Cascade (`m20_cascade`)

The master puts the slave number on CAS0-2 during the acknowledge and
drives no vector. `cas_q` latches `cas` while `pic_inta_n` is Low, so
the choice holds through the end clock like the data words. The
mainboard's `pic_rdata` is then:

| condition | word |
|---|---|
| `cs_pic` (a read of the master's own ports) | `master_rdata` |
| `cas_q == 1 & ieee_en` | `ieee_rdata` (the IEEE-488 slave) |
| `cas_q == 7 & twin_en` | `twin_rdata` (the twin slave) |
| else | `master_rdata` |

The mainboard's read capture takes `pic_rdata` in a VI-acknowledge cycle
([MAINBOARD.md](MAINBOARD.md) section 9), so a slave's vector reaches the
Z8001 exactly as the master's would. IR2 (`*COMVI2`) has no card and is
tied Low.

## 6. Timing and resources

Byte-rate logic; one KF8259 per card and two 8251s plus a KF8253 on the
twin card.

## 7. Inferred and assumed

| item | status |
|---|---|
| Twin card 8253 CLK taken as the mainboard's `ce_pit` | the card's oscillator and 74LS163 divide are assumed to give the same 1.23 MHz |
| Modem status bits D4/D6 = 1, D5/D7 = 0 | the RTL's constant; not checked with software |
| IEEE-488 register behaviour on an empty bus | derived from the 8291A/8292 data sheets for the no-handshake case |
| Slave ICW3 numbers 1 and 7 | what the ROM programs; `m20_cascade` hard-codes them |

## 8. Verification

| bench | checks |
|---|---|
| `tb/exp/tb_twin.sv` | `m20_twin` with the mainboard 8259 as master: decode (ports, mirrors, nothing elsewhere or with the card out), modem status, the 8253 baud timer, a byte from channel A to B over a crossed cable at 9615 baud, channel B's RxRDY vectoring through the slave on IR7 |
| `tb/exp/tb_ieee.sv` | `m20_ieee` with the master: decode (ports, A9/A10 mirrors, nothing elsewhere or with the card out), the 8291A and 8292 registers on an empty bus, the slave vectoring through IR1 |
| `tb/core/tb_core.sv` `+twin`, `+ieee` | the ROM's and PCOS's device checks with the cards fitted |

`make tb-exp` runs both.
