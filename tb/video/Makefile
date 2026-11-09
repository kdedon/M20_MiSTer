# m20_video bench: CRTC timing, plane fetch, palette, R15 readback.
#   make            build and run (PPMs in out/)
#   make clean

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/video.mk

OBJ    := obj_dir
SRCS   := $(VIDEO_SRCS) tb_video.sv
VFLAGS := --binary --timing --timescale 1ps/1ps -O3 -j 2 --top-module tb_video \
          --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
          $(ROOT)/lint/vendor.vlt

.PHONY: all run clean

all: run

$(OBJ)/Vtb_video: $(SRCS)
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --Mdir $(OBJ) $(SRCS) > $(OBJ)/build.log 2>&1 || (cat $(OBJ)/build.log; false)

run: $(OBJ)/Vtb_video
	@mkdir -p out
	./$(OBJ)/Vtb_video +verilator+rand+reset+2 +verilator+seed+11

clean:
	rm -rf $(OBJ) out
