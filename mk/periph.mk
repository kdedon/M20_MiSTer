# Peripheral block: PIC, PIT, PPI, two 8251s, keyboard HLE.
#   PERIPH_SRCS    vendored KF cores + our RTL, in compile order
#   PERIPH_VFLAGS  include path for the KF headers + lint waivers
#   tb-periph      every peripheral bench
#   lint-periph    verilator -Wall on each module
#   needs: ROOT

PERIPH_GOAL := $(.DEFAULT_GOAL)

PERIPH_KF8259 := $(addprefix $(ROOT)/rtl/vendor/KF8259/, \
  KF8259_Bus_Control_Logic.sv KF8259_In_Service.sv \
  KF8259_Interrupt_Request.sv KF8259_Priority_Resolver.sv KF8259.sv)
PERIPH_KF8253 := $(addprefix $(ROOT)/rtl/vendor/KF8253/, \
  KF8253_Control_Logic.sv KF8253_Counter.sv KF8253.sv)
PERIPH_KF8255 := $(addprefix $(ROOT)/rtl/vendor/KF8255/, \
  KF8255_Control_Logic.sv KF8255_Group.sv KF8255_Port.sv KF8255_Port_C.sv KF8255.sv)

PERIPH_SRCS := $(PERIPH_KF8259) $(ROOT)/rtl/periph/KF8259_Control_Logic.sv $(PERIPH_KF8253) $(PERIPH_KF8255) \
  $(addprefix $(ROOT)/rtl/periph/, m20_pic.sv m20_pit.sv m20_ppi.sv i8251.sv m20_rs232.sv m20_kbd.sv)
PERIPH_HDRS := $(wildcard $(ROOT)/rtl/periph/inc/*.svh)
PERIPH_VFLAGS := -I$(ROOT)/rtl/periph/inc $(ROOT)/lint/vendor.vlt $(ROOT)/rtl/periph/periph.vlt

PERIPH_TOPS := m20_pic m20_pit m20_ppi i8251 m20_rs232 m20_kbd

.PHONY: tb-periph lint-periph

tb-periph:
	$(MAKE) -C $(ROOT)/tb/periph

lint-periph:
	@for t in $(PERIPH_TOPS); do \
	  verilator --lint-only -Wall $(PERIPH_VFLAGS) $(PERIPH_SRCS) --top-module $$t || exit 1; \
	  echo "lint $$t clean"; \
	done

.DEFAULT_GOAL := $(PERIPH_GOAL)
