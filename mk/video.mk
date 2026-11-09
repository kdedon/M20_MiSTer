# Video block sources and bench.
#   needs: ROOT
#   VIDEO_SRCS   m20_video and its submodules, with the MC6845 netlist
#   tb-video     video bench (writes PPM frames)
#   lint-video   verilator -Wall on m20_video

VIDEO_GOAL := $(.DEFAULT_GOAL)

VIDEO_SRCS := $(ROOT)/rtl/vendor/c900/mc6845/mc6845_synth.v \
  $(ROOT)/rtl/video/m20_vplane.sv $(ROOT)/rtl/video/m20_vid_out.sv \
  $(ROOT)/rtl/video/m20_video.sv

.PHONY: tb-video lint-video
tb-video:
	$(MAKE) -C $(ROOT)/tb/video

lint-video:
	verilator --lint-only -Wall --top-module m20_video $(ROOT)/lint/vendor.vlt $(VIDEO_SRCS)

.DEFAULT_GOAL := $(VIDEO_GOAL)
