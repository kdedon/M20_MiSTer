# Expansion cards: IEEE-488 and twin RS-232 (both use the peripheral block).
#   needs: ROOT, mk/periph.mk
#   EXP_SRCS   RTL of the block
#   tb-exp     card benches
#   lint-exp   verilator -Wall on each card

EXP_GOAL := $(.DEFAULT_GOAL)

EXP_SRCS := $(addprefix $(ROOT)/rtl/exp/, m20_xpic.sv m20_gpib.sv m20_ieee.sv m20_twin.sv m20_cascade.sv)
EXP_TOPS := m20_ieee m20_twin m20_cascade

.PHONY: tb-exp lint-exp
tb-exp:
	$(MAKE) -C $(ROOT)/tb/exp

lint-exp:
	@for t in $(EXP_TOPS); do \
	  verilator --lint-only -Wall $(PERIPH_VFLAGS) $(PERIPH_SRCS) $(EXP_SRCS) --top-module $$t || exit 1; \
	  echo "lint $$t clean"; \
	done

.DEFAULT_GOAL := $(EXP_GOAL)
