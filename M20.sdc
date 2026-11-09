derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# clk_sys (48 MHz) and clk_ram (96 MHz) come from one PLL with aligned
# rising edges; c900_sdram times the crossing between them.  CLK_VIDEO is
# clk_sys.  There are no other core clock domains.
