# M20_MiSTer: lint and testbenches.  Keep the *_SRCS fragments in step with
# the Quartus .qip source lists.
#
#   make lint      Verilator -Wall over m20_core (vendored RTL waived) and
#                  each block's own lint target
#   make tb        every block bench (the bus bench runs the boot ROM: minutes)
#   make tb-core   the whole machine: boot ROM to the disk boot
#   make build     full Quartus compile

ROOT := $(CURDIR)
VERILATOR ?= verilator

include mk/bus.mk
include mk/video.mk
include mk/periph.mk
include mk/fdc.mk
include mk/hdc.mk
include mk/exp.mk

CORE_SRCS := $(BUS_SRCS) $(VIDEO_SRCS) $(PERIPH_SRCS) $(FDC_SRCS) $(HDC_SRCS) $(EXP_SRCS) $(ROOT)/rtl/m20_core.sv
CORE_VFLAGS := $(PERIPH_VFLAGS)

.PHONY: lint lint-core tb tb-core build clean

lint: lint-core lint-bus lint-video lint-periph lint-fdc lint-hdc lint-exp
	@# Quartus 17 sizes N'(... int'(x) ...) as one bit: the index silently loses bits.
	@if grep -rnE "[0-9]'\([^;]*int'\(" rtl --include='*.sv' --exclude-dir=vendor M20.sv; then echo "lint: size cast of an int' cast"; exit 1; fi
	@echo "lint: clean"

lint-core:
	$(VERILATOR) --lint-only -Wall --top-module m20_core $(CORE_VFLAGS) $(CORE_SRCS)

tb: tb-bus tb-video tb-periph tb-fdc tb-hdc tb-exp

tb-core:
	$(MAKE) -C tb/core

build:
	scripts/build.sh

clean:
	rm -rf obj_dir tb/*/obj_dir
