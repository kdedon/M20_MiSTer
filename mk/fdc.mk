# Floppy block: FD1797 controller and the disk_stream image cache.
#   FDC_SRCS   RTL of the block (lint top m20_fdc)
#   HOST_SRCS  disk_stream, instantiated by the shell
#   tb-fdc     floppy bench (needs the PCOS image)
#   lint-fdc   verilator -Wall on the block's RTL
#   needs: ROOT

FDC_GOAL := $(.DEFAULT_GOAL)

FDC_SRCS  := $(ROOT)/rtl/fdc/m20_fdc.sv
HOST_SRCS := $(ROOT)/rtl/host/disk_stream.sv

.PHONY: tb-fdc lint-fdc
tb-fdc:
	$(MAKE) -C $(ROOT)/tb/fdc

lint-fdc:
	verilator --lint-only -Wall --top-module m20_fdc $(FDC_SRCS)
	verilator --lint-only -Wall --top-module disk_stream $(HOST_SRCS)

.DEFAULT_GOAL := $(FDC_GOAL)
