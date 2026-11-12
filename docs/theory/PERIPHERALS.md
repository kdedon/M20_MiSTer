# Peripherals -- theory of operation

RTL: `rtl/periph/m20_pic.sv` (8259, U33), `m20_pit.sv` (8253, U152),
`m20_ppi.sv` (8255, U62), `i8251.sv` (USART, U22 keyboard and U131
RS-232), `m20_rs232.sv` (U131 and the UART routing), `m20_kbd.sv` (the
keyboard unit). The Intel chips wrap the vendored KF8259/KF8253/KF8255
(`rtl/vendor/KF82*`); `rtl/periph/KF8259_Control_Logic.sv` is a changed
copy of one KF8259 file.

## 1. Common wrapper shape

Each KF wrapper converts the bus model to the chip's pins:

```
 cs & io_rd  --> rd_act --> read_enable_n, chip_select_n
 cs & io_wr  --> wr_act --> write_enable_n
 io_addr[2:1] or [1] --> address          io_wdata[7:0] (8259: [8:1]) --> data_bus_in
 data_bus_out --> hold_q (registered while rd_act) --> *_rdata = rd_act ? live : hold_q
```

The KF cores act on their strobes as levels, so the wrapper presents
`rd_act`/`wr_act` for the whole /DS Low time; `hold_q` keeps the last
byte driven so that the mainboard, which samples at the /DS rise (the
clock after the strobe), still sees it. `io_rd_end`/`io_wr_end` are
unused by the wrappers. The 8251 and keyboard unit are own RTL and use
the capture-then-commit convention instead.

Clocking: all on `clk`; the 8253 counts on `ce_pit` (1.230769 MHz), the
8251s step on `ce_usart` (2 MHz). Reset is `rst_n` (KF `reset` =
`~rst_n`).

## 2. 8259 PIC (`m20_pic`)

Ports 0x140 (A0 = 0) and 0x142 (A0 = 1): the chip's D0-D7 sit on AD1-AD8,
so I/O is word-wide, `address = io_addr[1]`, data `io_wdata[8:1]`.

| IR | source | signal |
|---|---|---|
| 0 | FDC INTRQ | `ir_fdc` |
| 1 | `*COMVI1`, IEEE-488 card slave INT | `ir_comvi1` |
| 2 | `*COMVI2` | `ir_comvi2` (0) |
| 3 | RS-232 RxRDY | `ir_ser_rxrdy` |
| 4 | keyboard 8251 RxRDY | `ir_kbd_rxrdy` |
| 5 | RS-232 TxRDY (JP4) | `ir_ser_txrdy` |
| 6 | 8255 PC3 (INTR A) | `ir_ppi` |
| 7 | `*SYSINT`, twin RS-232 card slave INT | `ir_sysint` |

`pic_rdata` is `{7'h7F, data, 1}` for a read (AD9-AD15 and AD0 float
High) and `{7'h7F, vector, 0}` while `pic_inta_n` is Low (U4 pulls AD0
Low during /INTA), held in `hold_q` for the clock after. KF8259 in 8086
mode latches the ISR on the first /INTA fall and drives `{ICW2[7:3], IR}`
during the second; with ICW2 = 0 the identifier low byte the Z8001 reads
is 2n. The ROM programs cascade mode with slaves on IR1, IR2, IR7: for
those `cas` carries the slave number and the master drives no vector
([EXPANSION.md](EXPANSION.md)).

The changed KF8259 file: INT drops when the acknowledge is not in
progress and no request remains (an edge request withdrawn before INTA,
or masked), where the original kept INT High and later answered with the
default IR7. The ROM polls away the keyboard's IR4 with VI disabled; a
later `ei vi` must not take vector 7.

## 3. 8253 PIT (`m20_pit`)

Ports 0x121/0x123/0x125 counters 0-2, 0x127 control. All CLK inputs are
`ce_pit`; KF8253 counts on the falling edge, so one pulse is one count.
GATEs are tied High.

| counter | ROM setting | output |
|---|---|---|
| 0 | count 8, mode 3 | `pit_out0`: 9615 Hz x16 clock for the RS-232 8251 (9600 baud) |
| 1 | count 0x40, mode 3 | `pit_out1`: 1202 Hz x16 clock for the keyboard 8251 (1200 baud) |
| 2 | count 0xF062, mode 2 | `pit_out2`: 20 Hz, the NVI tick |

The vendored copy (from PCXT_MiSTer) carries an LSB/MSB preset fix over
upstream KF8253, which the wrapper header names. The twin card reuses
`m20_pit` for its baud timer.

## 4. 8255 PPI (`m20_ppi`)

Ports 0x81 PA, 0x83 PB, 0x85 PC, 0x87 control. The ROM sets mode 0xA6:
PA strobed output (Centronics data), PB strobed input (printer and modem
status), PC3 = INTR A to IR6 (`ppi_ir6 = ppi_pc[3] & ~pc_io[3]`). No
printer exists, so the inputs are constants: PB = 0xFF (printer lines
pulled up, PB1 "not ready" makes the ROM skip its Centronics error, PB6
RING and PB7 SIGDET inactive), PC in = 0xFB (/STB B Low so PB reads the
lines directly; /STB A and /ACK A inactive). `ppi_pa` and `ppi_pc` are
outputs nobody uses.

## 5. 8251A USART (`i8251`)

Asynchronous modes only; sync mode is accepted but idle. Keyboard U22 at
0xA1/0xA3, RS-232 U131 at 0xC1/0xC3, C/D = A1.

```
 I/O bus --> [capture] wr_pend_q wr_cd_q wr_data_q (commit at io_wr_end); rd_pend_q (RxRDY clear at io_rd_end)
             [control FSM] CtlMode -> (CtlSync1 -> CtlSync2) -> CtlCmd; command IR returns to CtlMode
 txc/rxc levels sampled on ce_usart --> edge detect
 [transmitter] TxIdle TxStart TxData TxPar TxStop, on TxC falls, x1/x16/x64
 [receiver]    RxIdle RxStart RxData RxPar RxStop, on RxC rises; start bit found after half a bit
 status = {~dsr_n, brk, fe, oe, pe, txempty, rxrdy, ~tx_full}
```

Mode byte: `[1:0]` baud factor (01 x1, 10 x16, 11 x64), `[3:2]` length
5-8, `[4]` PEN, `[5]` EP, `[7:6]` stop bits (01 1, 10 1.5, 11 2).
Command: TxEN, DTR, RxE, SBRK, ER, RTS, IR, EH. The ROM's reset sequence
0, 0, 0, 0x40 lands in the mode state from either starting point because
command bit 6 returns to it; status after reset and command 0x37 is 0x05
| DSR. BRKDET sets after two all-zero characters with framing errors and
clears when RxD is High at a sample. The TxRDY pin is `~tx_full & txen &
~cts_n`; the status bit is `~tx_full` alone, as on the chip.

## 6. RS-232 (`m20_rs232`)

U131's TxC and RxC are `pit_out0` (jumpers R/S internal). Its TxRDY pin
goes to IR5, its RxRDY to IR3. PCOS's OLITERM driver runs 4800 8N2 with
an interrupt-driven transmitter: TxEN raises TxRDY, IR5 fires, the
handler writes the next byte and sends a specific EOI; with nothing left
it drops TxEN.

Routing: `ser_sel` picks which port owns the MiSTer UART (0 mainboard,
1 twin A, 2 twin B). The chosen port's RxD is `ser_rxd`; the others see
an idle High. `ser_txd`, `ser_rts_n`, `ser_dtr_n` come from the chosen
port, or idle High when a twin channel is chosen with the card out. Every
port sees `cts_n = dsr_n = 0`: the HPS UART's RTS/DTR are not a handshake
M20 software can rely on, and an inactive CTS would hold the 8251's
transmitter.

## 7. Keyboard unit (`m20_kbd`)

A model of the keyboard's 8048, talking to U22 only through `kbd_txd`
(M20 to keyboard) and `kbd_rxd` (keyboard to M20) at 1200 baud, 8 data,
2 stop bits, no parity. Parameters `CLK_HZ`, `BAUD`, `BEEP_HZ` (3100),
`BEEP_MS` (50).

```
 kbd_txd --> [receiver rx_q] RIdle RStart RData RStop RGap --> cmd_v, rx_sh_q
                     |
                     v
 0x03 --> reply {kbd_layout, 0xF}     0x80 --> reply 0x80     0x0A --> bell_q (50 ms), tone_q 3100 Hz --> beep
                     | rep_v_q, rep_q
 ps2_key --> [events] tog_q press key --> mod_q {LShift, RShift, RCtrl, LCtrl, Command}
                     |                          |
                     v                          v mod_off: COMMAND 0x90, CTRL 0x60, SHIFT 0x30, mixes 0
             [layout map] code, map_hit, en_key --> [FIFO 8] --> [transmitter] tx_sh_q --> kbd_rxd
```

- **Commands.** 0x03 replies with the national code in the high nibble
  and self-test OK (0xF) in the low; 0x80 replies 0x80 (the ROM's VI
  test); 0x0A sounds the bell and replies nothing; others are ignored.
  Replies go before queued keys. Half duplex: a byte to the M20 starts
  only while the receiver is idle (`rx_q == RIdle`, which includes the
  second stop bit and a gap).
- **Keys.** Each press of a mapped key queues one make code, no break
  codes. Modifiers are not sent; they offset the code mod 256. Make codes
  are M20 key numbers: `row * 8 + column` for rows 0-5, `0xC0 + (row - 6)
  * 8 + column` for rows 6-8. The header of `m20_kbd.sv` tabulates every
  PS/2 scan code.
- **Layouts** (`kbd_layout`, the national code jumpers P14-P17): 0
  Italian maps letters, digits and `, ; .` by legend on the QZERTY
  layout, the rest by position; 3 UK and 4 US map PC legends onto the
  PCOS ASCII table, choosing the M20 key and shift state that give the
  PC legend (US Shift+2 sends key 28, "@"); 1 German maps a QWERTZ
  keyboard by position with the M20's `^`/`'` placement. The code the
  keyboard reports is what PCOS 1.x uses to pick its table; PCOS 2.x and
  later follow `SL`.
- **Bell.** `beep` toggles at `BEEP_HZ` for `BEEP_MS`; the shell turns it
  into audio.
- **FIFO.** Eight entries; the line drains a byte per 9.2 ms, so the FIFO
  only absorbs bursts while a reply holds the line. A press into a full
  FIFO is dropped and sets `kbd_overflow` (unused in the core).

The keyboard 8251 (U22) takes `pit_out1` as TxC/RxC, CTS and DSR
asserted; its RxRDY is IR4.

## 8. Timing and resources

All byte-rate logic; the 8251 bit timing is counted in `ce_usart` ticks,
the keyboard's in clocks (`BIT_CLK` = 40,000). The three KF cores are
the bulk of the logic; the keyboard map is one case statement per
layout.

## 9. Inferred and assumed

| item | status |
|---|---|
| 8259 INT drop on withdrawn request (the changed KF file) | the ROM's keyboard poll needs it; the data sheet gives IR7 for a request withdrawn during the acknowledge; the original KF core also kept INT High, which the ROM's `ei vi` would then take |
| 8255 constant inputs (printer not ready, RING/SIGDET inactive, /STB B Low) | chosen so the ROM's device checks pass without a printer |
| CTS and DSR asserted everywhere | the MiSTer UART's modem lines are not forwarded |
| Keyboard half-duplex rule and reply priority | the 8048 firmware is not available; inferred from the ROM's polling loops |
| Modifier offsets +0x90/+0x60/+0x30, mixes +0 | from the keyboard code table; mixes are not documented |
| National codes 0/1/3/4 | Service Manual jumper table and the PCOS SL list |
| Bell 3100 Hz, 50 ms | approximate |

`m20_core`'s port comment lists `kbd_layout` as "0 Italian, 3 UK, 4 US";
the German code 1 is also accepted by `m20_kbd`.

## 10. Verification

| bench | checks |
|---|---|
| `tb/periph/tb_pic.sv` | the boot ROM's 8259 set-up, IMR readback, the two-pulse acknowledge (vector n on AD1-AD8, AD0 = 0), specific EOI, priority with IR5 lowest, edge triggering |
| `tb/periph/tb_pit.sv` | the ROM's counter set-up, the latch test at instruction timing, one count per `ce_pit`, OUT0/OUT1/OUT2 periods |
| `tb/periph/tb_ppi.sv` | mode 0xA6, bit set/reset, port A readback, port B "printer not ready", PC3 on IR6, PC5 strobe |
| `tb/periph/tb_i8251.sv` | the 8251A data sheet and the ROM's set-up: frames on TxD (stop bit lengths), loopback x1/x16/x64, 5-bit characters, parity, framing, overrun, break detect, CTS gating, SBRK |
| `tb/periph/tb_rs232.sv` | U131 with the 8253 as in the core: the ROM's 9600 8N1 set-up, bytes out on `ser_txd` and in from `ser_rxd`; then OLITERM's 4800 8N2 interrupt-driven transmitter through IR5 with specific EOI |
| `tb/periph/tb_kbd.sv` | `m20_kbd`: frames, the three commands, make codes with modifier offsets, replies before keys, no transmission while a host byte arrives, FIFO overflow, the US/UK legend maps and the German positional map |
| `tb/periph/tb_kbd_loop.sv` | the keyboard path end to end: 8253 channel 1 clocking U22, 0x03 reply polled as the ROM does, the bell, 0x80 by interrupt through IR4 and the acknowledge identifier 0xFE08 |

All run with `make tb-periph`; expected values come from the data sheets
and the ROM, not from the RTL.
