# APB card bench: translator x PROM table, handshake, 8086 test program.
#   make        build the test image (needs GNU as, the z8086 microcode) and run
#   make clean
# UCODE=<file> uses a local microcode copy (else make_apb_rom.sh fetches it).

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/apb.mk

OBJ    := obj_dir
VFLAGS := --binary --timing -O3 -j 2 --top-module tb_apb \
          --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
          $(ROOT)/lint/vendor.vlt
RUNFL  := +verilator+rand+reset+2 +verilator+seed+5 $(RUNARGS)

.PHONY: all run clean
all: run

$(OBJ)/apb_test.bin: apb_test.S
	@mkdir -p $(OBJ)
	as --32 -o $(OBJ)/apb_test.o $<
	objcopy -O binary $(OBJ)/apb_test.o $@

$(OBJ)/apb_test.rom: $(OBJ)/apb_test.bin $(ROOT)/scripts/make_apb_rom.sh
	$(ROOT)/scripts/make_apb_rom.sh $@ $<

$(OBJ)/Vtb_apb: $(APB_SRCS) $(ROOT)/rtl/bus/m20_prom.sv tb_apb.sv
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --Mdir $(OBJ) $^ > $(OBJ)/build.log 2>&1 || (tail -40 $(OBJ)/build.log; false)

run: $(OBJ)/Vtb_apb $(OBJ)/apb_test.rom
	cd $(ROOT) && stdbuf -oL tb/apb/$(OBJ)/Vtb_apb $(RUNFL) +img=tb/apb/$(OBJ)/apb_test.rom | tee tb/apb/$(OBJ)/run.log
	@grep -q '^PASS' $(OBJ)/run.log

clean:
	rm -rf $(OBJ)
