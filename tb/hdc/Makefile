# m20_iodec + m20_hdc + disk_stream against a behavioural hps_io block
# server with synthetic images.
#
#   make                build and run
#   make clean

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/fdc.mk
include $(ROOT)/mk/hdc.mk

OBJ       := obj_dir
SRCS      := $(ROOT)/rtl/bus/m20_iodec.sv $(HDC_SRCS) $(HOST_SRCS) tb_hdc.sv
VFLAGS    := --binary --timing --timescale 1ns/1ps -j 4 --top-module tb_hdc \
             --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style -O2 \
             $(ROOT)/lint/vendor.vlt

.PHONY: all run clean

all: run

$(OBJ)/Vtb_hdc: $(SRCS)
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --Mdir $(OBJ) $(SRCS) > $(OBJ)/build.log 2>&1 || (cat $(OBJ)/build.log; false)

run: $(OBJ)/Vtb_hdc
	./$(OBJ)/Vtb_hdc +verilator+rand+reset+2 +verilator+seed+7

clean:
	rm -rf $(OBJ)
