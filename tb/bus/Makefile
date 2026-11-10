# m20_mainboard benches.
#   make            PROM table, ROM sockets, then boot ROM 1.0 for config codes 5 and 0
#   make prom       PROM table only
#   make rom        ROM sockets only
#   make boot CFG=n boot ROM run for one config code
#   make clean
# boot.rom is generated here.

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/bus.mk

OBJ    := obj_dir
VFLAGS := --binary --timing --timescale 1ps/1ps -O3 -j 4 \
          --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
          $(ROOT)/lint/vendor.vlt
RUNFL  := +verilator+rand+reset+2 +verilator+seed+5
CFG    ?= 5

.PHONY: all run prom rom boot clean

all: run
run: prom rom
	$(MAKE) boot CFG=5
	$(MAKE) boot CFG=0

boot.rom: $(ROOT)/scripts/make_boot_rom.sh
	$(ROOT)/scripts/make_boot_rom.sh 1.0 $@

$(OBJ)/prom/Vtb_prom: $(ROOT)/rtl/bus/m20_prom.sv tb_prom.sv
	@mkdir -p $(OBJ)/prom
	$(VERILATOR) $(VFLAGS) --top-module tb_prom --Mdir $(OBJ)/prom $^ > $(OBJ)/prom/build.log 2>&1 || (cat $(OBJ)/prom/build.log; false)

$(OBJ)/bus/Vtb_bus: $(BUS_SRCS) sdram_lat.sv m20_stubs.sv tb_bus.sv
	@mkdir -p $(OBJ)/bus
	$(VERILATOR) $(VFLAGS) --top-module tb_bus --Mdir $(OBJ)/bus $(BUS_SRCS) \
	  sdram_lat.sv m20_stubs.sv tb_bus.sv \
	  > $(OBJ)/bus/build.log 2>&1 || (cat $(OBJ)/bus/build.log; false)

$(OBJ)/rom/Vtb_rom: $(ROOT)/rtl/bus/m20_boot_rom.sv tb_rom.sv
	@mkdir -p $(OBJ)/rom
	$(VERILATOR) $(VFLAGS) --top-module tb_rom --Mdir $(OBJ)/rom $^ > $(OBJ)/rom/build.log 2>&1 || (cat $(OBJ)/rom/build.log; false)

rom: $(OBJ)/rom/Vtb_rom
	./$(OBJ)/rom/Vtb_rom $(RUNFL)

prom: $(OBJ)/prom/Vtb_prom
	./$(OBJ)/prom/Vtb_prom $(RUNFL)

boot: $(OBJ)/bus/Vtb_bus boot.rom
	./$(OBJ)/bus/Vtb_bus $(RUNFL) +cfg=$(CFG)

clean:
	rm -rf $(OBJ) boot.rom
