# Whole-machine bench: m20_core + sdram_lat + disk_stream + hps_io block
# server, boot ROM to PCOS.  Frames in out/ (PPM, last frame also PNG).
#
#   make                 boot ROM 1.0, config code 5, ZA 1, type KEYS at the prompt
#   make ROM=2.0f ZA=0 OBJ=obj_20f OUT=out_20f   another boot ROM
#                        ROM 2.x reads port 0x21 D4:D3 as the drive type; D4 (SPARE1)
#                        is 1 (+spare1=0 via RUNARGS for types 0/1), so ZA=1 selects
#                        80-track drives (double step on a 35-track image)
#   make KEYS=           boot only (ends when the disk has been quiet)
#   make RUNARGS=...     extra plusargs (+maxclk=n +pctrace=n +pcto=n +iolog=n)
#   make IMG_SRC=...     another 286,720-byte PCOS image with track 0
#   make T0_SRC=...      take track 0 (first 4096 B) from this image
#   make clean
# A run takes about 45 min (PCOS prompt at 17 s machine time).
# The image is copied and the boot ROM built into obj_dir (the bench writes the image).
# The binary runs from the repository root, where m20_prom.hex is found.

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/bus.mk
include $(ROOT)/mk/video.mk
include $(ROOT)/mk/periph.mk
include $(ROOT)/mk/fdc.mk

IMG_SRC ?= $(HOME)/git/olivetti_m20/reference/software/os/pcos102.img
ROM     ?= 1.0
KEYS    ?= vl
CFG     ?= 5
ZA      ?= 1
OUT     ?= out
OBJ     ?= obj_dir
HERE    := tb/core

SRCS := $(BUS_SRCS) $(VIDEO_SRCS) $(PERIPH_SRCS) $(FDC_SRCS) $(HOST_SRCS) $(ROOT)/rtl/m20_core.sv \
        ../bus/sdram_lat.sv tb_core.sv
CSRCS := ../fdc/img_io.cpp fb_io.cpp
VFLAGS := --binary --timing --timescale 1ps/1ps -O3 -j 8 --top-module tb_core \
          --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
          $(PERIPH_VFLAGS) -CFLAGS -O2
RUNFL := +verilator+rand+reset+2 +verilator+seed+5
ROM_LABELS := $(if $(filter 1.0 1.0bc,$(ROM)),,+rom20)

.PHONY: all run clean

all: run

$(OBJ)/Vtb_core: $(SRCS) $(CSRCS) $(PERIPH_HDRS)
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --Mdir $(OBJ) $(SRCS) $(CSRCS) > $(OBJ)/build.log 2>&1 || (tail -40 $(OBJ)/build.log; false)

$(OBJ)/boot$(ROM).rom: $(ROOT)/scripts/make_boot_rom.sh
	@mkdir -p $(OBJ)
	$(ROOT)/scripts/make_boot_rom.sh $(ROM) $@

run: $(OBJ)/Vtb_core $(OBJ)/boot$(ROM).rom
	@mkdir -p $(OUT)
	rm -f $(OUT)/*.ppm $(OUT)/*.png
	cp $(IMG_SRC) $(OBJ)/m20_boot$(ROM).img
	chmod u+w $(OBJ)/m20_boot$(ROM).img
	$(if $(T0_SRC),dd if=$(T0_SRC) of=$(OBJ)/m20_boot$(ROM).img bs=4096 count=1 conv=notrunc status=none)
	cd $(ROOT) && stdbuf -oL $(HERE)/$(OBJ)/Vtb_core $(RUNFL) +cfg=$(CFG) +za=$(ZA) $(ROM_LABELS) \
	  +rom=$(HERE)/$(OBJ)/boot$(ROM).rom +img=$(HERE)/$(OBJ)/m20_boot$(ROM).img +out=$(HERE)/$(OUT) \
	  +keys=$(KEYS) $(RUNARGS) | tee $(HERE)/$(OUT)/run.log
	@for f in $(OUT)/*.ppm; do python3 -I ppm2png.py $$f > /dev/null; done
	@grep -q '^PASS' $(OUT)/run.log

clean:
	rm -rf obj_dir obj_* out out_*
