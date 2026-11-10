# Expansion card benches, each with the mainboard 8259 as cascade master.
#   make            build and run all
#   make tb_ieee    build and run one
#   make clean

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/periph.mk
include $(ROOT)/mk/exp.mk

BENCHES := tb_ieee tb_twin
OBJ     := obj_dir
VFLAGS  := --binary --timing --timescale 1ns/1ps -j 2 \
           --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
           $(PERIPH_VFLAGS) -I. -I../periph

.PHONY: all clean $(BENCHES)

all: $(BENCHES)

$(BENCHES): %: $(OBJ)/%/V%
	./$(OBJ)/$@/V$@ +verilator+rand+reset+2 +verilator+seed+7

$(OBJ)/%/V%: %.sv ../periph/tb_io.svh $(PERIPH_SRCS) $(PERIPH_HDRS) $(EXP_SRCS)
	@mkdir -p $(dir $@)
	$(VERILATOR) $(VFLAGS) --top-module $* --Mdir $(dir $@) $(PERIPH_SRCS) $(EXP_SRCS) $< > $(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; false)

clean:
	rm -rf $(OBJ)
