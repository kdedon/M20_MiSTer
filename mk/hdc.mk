# Hard disk block: WD1000-compatible card on disk_stream slots 2 and 3.
#   HDC_SRCS   RTL of the block (lint top m20_hdc)
#   tb-hdc     hard disk bench
#   lint-hdc   verilator -Wall on the block's RTL
#   needs: ROOT

HDC_GOAL := $(.DEFAULT_GOAL)

HDC_SRCS := $(ROOT)/rtl/hdc/m20_hdc.sv

.PHONY: tb-hdc lint-hdc
tb-hdc:
	$(MAKE) -C $(ROOT)/tb/hdc

lint-hdc:
	verilator --lint-only -Wall --top-module m20_hdc $(HDC_SRCS)

.DEFAULT_GOAL := $(HDC_GOAL)
