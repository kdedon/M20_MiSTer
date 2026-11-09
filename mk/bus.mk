# Mainboard block sources and bench.
#   needs: ROOT
#   BUS_SRCS   m20_mainboard and its submodules, with the vendored Z8001 core
#   tb-bus     mainboard bench (PROM table, then the boot ROM)
#   lint-bus   verilator -Wall on m20_mainboard

BUS_GOAL := $(.DEFAULT_GOAL)

K8000_DIR := $(ROOT)/rtl/vendor/k8000/k800x_cpu
K8000_SRCS := $(K8000_DIR)/gen/z8000_zbus_pkg.sv $(K8000_DIR)/gen/z8000_ctrl_pkg.sv \
  $(K8000_DIR)/gen/z8000_mc_pkg.sv $(K8000_DIR)/gen/z8000_decode_rom_gen.sv \
  $(K8000_DIR)/gen/z8000_mc_rom_gen.sv $(K8000_DIR)/z8000_alu.sv $(K8000_DIR)/z8000_cond.sv \
  $(K8000_DIR)/z8000_decode.sv $(K8000_DIR)/z8000_regfile.sv $(K8000_DIR)/z8000_refresh.sv \
  $(K8000_DIR)/z8000_int_unit.sv $(K8000_DIR)/z8000_bus_unit.sv $(K8000_DIR)/z8000_serial.sv \
  $(ROOT)/rtl/cpu/z8000_execute.sv $(ROOT)/rtl/cpu/z8000_sequencer.sv $(ROOT)/rtl/cpu/z8000_cpu.sv

BUS_SRCS := $(K8000_SRCS) \
  $(ROOT)/rtl/bus/m20_clkgen.sv $(ROOT)/rtl/bus/m20_prom.sv $(ROOT)/rtl/bus/m20_boot_rom.sv \
  $(ROOT)/rtl/bus/m20_dram.sv $(ROOT)/rtl/bus/m20_iodec.sv $(ROOT)/rtl/bus/m20_mainboard.sv

.PHONY: tb-bus lint-bus
tb-bus:
	$(MAKE) -C $(ROOT)/tb/bus

lint-bus:
	verilator --lint-only -Wall --top-module m20_mainboard $(ROOT)/lint/vendor.vlt $(BUS_SRCS)

.DEFAULT_GOAL := $(BUS_GOAL)
