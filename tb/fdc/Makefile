# m20_fdc + disk_stream against a behavioural hps_io block server backed
# by a copy of a PCOS image with a valid track 0 (generated in obj_dir).
#
#   make                build and run
#   make IMG_SRC=...    another 286,720-byte image with track 0
#   make clean

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/fdc.mk

IMG_SRC   ?= $(HOME)/git/olivetti_m20/reference/software/os/pcos102.img
OBJ       := obj_dir
IMG       := $(OBJ)/m20_test.img
SRCS      := $(FDC_SRCS) $(HOST_SRCS) tb_fdc.sv img_io.cpp
VFLAGS    := --binary --timing --timescale 1ns/1ps -j 4 --top-module tb_fdc \
             --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style -O2 \
             $(ROOT)/lint/vendor.vlt

.PHONY: all run clean

all: run

$(OBJ)/Vtb_fdc: $(SRCS)
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --Mdir $(OBJ) $(SRCS) > $(OBJ)/build.log 2>&1 || (cat $(OBJ)/build.log; false)

# a fresh copy each run: the bench writes into it
run: $(OBJ)/Vtb_fdc
	cp $(IMG_SRC) $(IMG)
	chmod u+w $(IMG)
	./$(OBJ)/Vtb_fdc +verilator+rand+reset+2 +verilator+seed+7

clean:
	rm -rf $(OBJ)
