# c900_sdram and the vendored SDRAM controller against two timing-checking
# SDRAM models (the 128 MB dual-chip module).
#
#   make            build and run
#   make clean

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/sdram_sim.mk

OBJ       := obj_dir
SRCS      := $(SDRAM_SIM_SRCS) $(ROOT)/tb/common/sdram_model.sv tb_sdram.sv
VFLAGS    := --binary --timing --timescale 1ns/1ps -j 2 --top-module tb_sdram \
             --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
             $(ROOT)/lint/vendor.vlt

.PHONY: all run clean

all: run

$(OBJ)/Vtb_sdram: $(SRCS)
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --Mdir $(OBJ) $(SRCS) > $(OBJ)/build.log 2>&1 || (cat $(OBJ)/build.log; false)

run: $(OBJ)/Vtb_sdram
	./$(OBJ)/Vtb_sdram +verilator+rand+reset+2 +verilator+seed+7

clean:
	rm -rf $(OBJ)
