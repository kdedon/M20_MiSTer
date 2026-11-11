# APB 1086 card: status

## Works (simulation)

- 8086 core: z8086 (nand2mario, Apache-2.0 per its README, ~1.2k ALMs, original Intel microcode). Vendored pristine in `rtl/vendor/z8086/`; patched copy `rtl/apb/z8086.sv` (clock enable, loadable microcode, 3 bug fixes below). Microcode is not committed: `scripts/make_apb_rom.sh` fetches it (SHA1 checked) into boot1.rom.
- Card `rtl/apb/m20_apb.sv` + translator `m20_apb_xlat.sv`; mainboard `ext_*` master port (mux while /BUSACK Low), next to main's `cs_exp`/`cs_exp16`; OSD `O[11]`, `v,6`; boot1.rom (index 0x40) / F3 load (F2 is main's extension ROM; index 0x40 is excluded from the boot ROM load).
- Merged with main 0c8cbea (hard disk, k8000 39738d4, keyboard layouts, expansion cards, hdboot, OSD defaults). Card decode checked: memory goes to SN 0/2/3/8-F only, never SN 7 (extension ROM) and never a PROM ROM entry in any config; its only I/O decode is A13-A3 all ones (7FF8-7FFF), clear of the hard disk and card ports.
- `make lint` clean; `tb/bus`, `tb/fdc`, `tb/periph`, `tb/hdc`, `tb/exp`, `tb/apb` PASS after the last merge.
- No-card boot: `make ROM=2.0f ZA=0 CFG=6 KEYS= IMG_SRC=~/m20_mame_tmp/p20f.img RUNARGS="+keysfile=<main's layout keys> +layout=4"` PASS; last and before-keys frames byte-identical to main's `out_m_20f`, same 201 disk reads. (pcos102 is PCOS 1.x; reference pcos20f.img has a zeroed descriptor sector.)
- APB boot (`make APB=1 APBKEYS=y ROM=2.0f ZA=0 CFG=5 IMG_SRC=.../msdos2_0.img RUNARGS="+keysfile=<~~dir~`^> +kgap=14400000 +maxclk=2800000000 +kquiet=240000000"`, ~2 h): PASS. Prompt -> y -> POST -> MS-DOS 2.0 -> `A>`; `dir` lists 35 files, 25600 bytes free; Tab+Esc -> /NMI, run 0, Z8001 cold start, ROM asks "Select Alternate CPU" again. Core bench keys: `` ` `` waits for quiet disks, `^` is COMMAND+RESET only with +apb, `+kgap` slows typing (300 ms works).

## Broken / unverified

- Quartus not run (user asked to be asked first): no ALM/RAM/timing numbers. Expect +~1.5k ALMs, +~17 M10K (ROM 14, microcode 2, FDC track buffer doubled to 8 KB).
- Not tested: hardware, colour/expansion configs with DOS, CP/M-86, writes to PC disks from DOS, VI from the 8259 cascade (twin RS-232 slave), the APB with the hard disk card mounted.

## Next steps

1. MiSTer hardware run (MS-DOS boot, dir, return).
2. Ask user, then `scripts/build.sh`; check M10K inference of z8086 ucode RAM and rom_lo/hi.
3. CFG=6 (496 KB) DOS run; DOS file writes.

## Traps

- z8086 bugs fixed (header of `rtl/apb/z8086.sv`): (1) FC popped the opcode byte when taking a hardware interrupt -> IRET one byte too far; (2) INTR latched at an early RNI inside the interrupt sequence -> handler interrupted at its first instruction; (3) REP prefix SC coinciding with previous RNI was dropped -> REP ran once (broke SYSINIT relocation). All only show with real bus latency/interrupts; the core's SingleStepTests don't cover them. Standalone harnesses in the session scratchpad `zt/` were the fast way to bisect.
- z8086 `inta` is not reset: the card ignores strobes until the first ce after reset (`live_q`).
- The APB ROM has deliberate multi-second delay loops (e.g. 2.3 s after "Floppy Drive A") — not hangs.
- tb_core debug: `+apbring` / `+apbdump=<clk>` / `+apbwa/+apbwd` / `+apbnone +apbtop` dump the last 4096 8086 requests; `+fdclog`. Logging slows the sim ~20%.
- 360K disks need drive type 2 (OSD "2.x 320K drives", ZA=0); the boot sector picks geometry from port 0x21 D4:D3.
- Use exact PIDs (cwd check) when killing sims: other agents run Vtb_core too; `pkill -f` matched the calling shell.
- Machine is shared: `nice -n 15`, `-j 2`, one long sim at a time; whole-machine APB runs take 1.5-2 h.
