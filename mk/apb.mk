# APB 1086 card block.
#   needs: ROOT
#   APB_SRCS   m20_apb, its translator and the 8086 core
#   tb-apb     card bench
#   lint-apb   verilator -Wall on m20_apb (the 8086 core waived)

APB_GOAL := $(.DEFAULT_GOAL)

APB_SRCS := $(ROOT)/rtl/apb/z8086_alu.sv $(ROOT)/rtl/apb/z8086.sv \
  $(ROOT)/rtl/apb/m20_apb_xlat.sv $(ROOT)/rtl/apb/m20_apb.sv

.PHONY: tb-apb lint-apb
tb-apb:
	$(MAKE) -C $(ROOT)/tb/apb

lint-apb:
	verilator --lint-only -Wall --top-module m20_apb $(ROOT)/lint/vendor.vlt $(ROOT)/lint/apb.vlt $(APB_SRCS)

.DEFAULT_GOAL := $(APB_GOAL)
