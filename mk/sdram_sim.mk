# Simulation copy of the vendored SDRAM controller, patched for Verilator:
# the procedurally assigned inout becomes an output register and an enable
# register (as Quartus builds it), and the two initialised variables move
# out of the always block (Verilator would re-run their initialisers on
# every clock).  Build artifact.
#   needs: ROOT

SDRAM_GOAL := $(.DEFAULT_GOAL)

SDRAM_SIM  := $(ROOT)/obj_dir/sdram/sdram.sv
SDRAM_SIM_SRCS := $(SDRAM_SIM) $(ROOT)/rtl/sdram/c900_sdram.sv $(ROOT)/tb/common/altddio_out.sv

$(SDRAM_SIM): $(ROOT)/rtl/vendor/sdram/sdram.sv $(ROOT)/tb/common/sdram_sim.patch
	mkdir -p $(dir $@)
	patch -s -o $@.tmp $< $(ROOT)/tb/common/sdram_sim.patch
	mv $@.tmp $@

.DEFAULT_GOAL := $(SDRAM_GOAL)
