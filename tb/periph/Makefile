# Peripheral benches: one per module plus the 8251 <-> keyboard loopback.
#   make            build and run all
#   make tb_pic     build and run one
#   make lint       verilator -Wall on each module
#   make clean

VERILATOR ?= verilator
ROOT      := ../..
include $(ROOT)/mk/periph.mk

BENCHES := tb_pic tb_pit tb_ppi tb_i8251 tb_kbd tb_kbd_loop
OBJ     := obj_dir
VFLAGS  := --binary --timing --timescale 1ns/1ps -j 2 \
           --x-initial unique --x-assign unique -Wno-fatal -Wno-lint -Wno-style \
           $(PERIPH_VFLAGS) -I.

.PHONY: all lint clean $(BENCHES)

all: $(BENCHES)

$(BENCHES): %: $(OBJ)/%/V%
	./$(OBJ)/$@/V$@ +verilator+rand+reset+2 +verilator+seed+7

$(OBJ)/%/V%: %.sv tb_io.svh $(PERIPH_SRCS) $(PERIPH_HDRS)
	@mkdir -p $(dir $@)
	$(VERILATOR) $(VFLAGS) --top-module $* --Mdir $(dir $@) $(PERIPH_SRCS) $< > $(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; false)

lint: lint-periph

clean:
	rm -rf $(OBJ)
