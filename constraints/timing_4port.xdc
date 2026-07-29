# =====================================================================
# timing_4port.xdc — VU13P 4-port 100G QSFP28 Loopback Test Timing Constraints
# Target: XCVU13P-2FHGB2104I
#
# Port mapping:
#   Index 0 -> QSFP28_0 (Quad 230, GT X1Y40~X1Y43, RefClk P11/P10)
#   Index 1 -> QSFP28_1 (Quad 233, GT X1Y52~X1Y55, RefClk B11/B10)
#   Index 2 -> QSFP28_2 (Quad 129, GT X0Y36~X0Y39, RefClk AA36/AA37)
#   Index 3 -> QSFP28_3 (Quad 131, GT X0Y44~X0Y47, RefClk N36/N37)
# =====================================================================

# =====================================================================
# System Clock (90 MHz, non-dedicated pin)
# =====================================================================
set_property PACKAGE_PIN AL27 [get_ports sys_clk_90m]
set_property IOSTANDARD LVCMOS12 [get_ports sys_clk_90m]
create_clock -period 11.111 -name sys_clk_90m [get_ports sys_clk_90m]

# Non-dedicated clock pin — must relax dedicated route constraint
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets u_clk_rst/u_ibuf_clk/O]

# =====================================================================
# GT Reference Clocks (322.265625 MHz)
# Explicit create_clock is needed so that Vivado can propagate generated
# clocks (txoutclk, rxoutclk) to all 4 CMAC instances.
# The CMAC IP may also create clocks on these ports — that is fine,
# the later definition simply overrides with the same frequency.
# =====================================================================

# QSFP28_0 Reference Clock (GTYE4_COMMON_X1Y10)
set_property PACKAGE_PIN P11 [get_ports QSFPDD0_REFCLK_P]
set_property PACKAGE_PIN P10 [get_ports QSFPDD0_REFCLK_N]
create_clock -period 3.103 -name refclk_qsfp0 [get_ports QSFPDD0_REFCLK_P]

# QSFP28_1 Reference Clock (GTYE4_COMMON_X1Y13)
set_property PACKAGE_PIN B11 [get_ports QSFPDD1_REFCLK_P]
set_property PACKAGE_PIN B10 [get_ports QSFPDD1_REFCLK_N]
create_clock -period 3.103 -name refclk_qsfp1 [get_ports QSFPDD1_REFCLK_P]

# QSFP28_2 Reference Clock (GTYE4_COMMON_X0Y9)
set_property PACKAGE_PIN AA36 [get_ports QSFPDD2_REFCLK_P]
set_property PACKAGE_PIN AA37 [get_ports QSFPDD2_REFCLK_N]
create_clock -period 3.103 -name refclk_qsfp2 [get_ports QSFPDD2_REFCLK_P]

# QSFP28_3 Reference Clock (GTYE4_COMMON_X0Y11)
set_property PACKAGE_PIN N36 [get_ports QSFPDD3_REFCLK_P]
set_property PACKAGE_PIN N37 [get_ports QSFPDD3_REFCLK_N]
create_clock -period 3.103 -name refclk_qsfp3 [get_ports QSFPDD3_REFCLK_P]

# =====================================================================
# Asynchronous Clock Groups
#
# sys_clk_90m is asynchronous to all GT-derived clocks.
# Each QSFP refclk and its generated clocks (txoutclk, rxoutclk) form
# an independent group. Using set_clock_groups is more robust than
# individual set_false_path because it automatically covers all
# generated clocks (via -include_generated_clocks) and all CDC paths.
# =====================================================================
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_90m] \
    -group [get_clocks -quiet -include_generated_clocks refclk_qsfp0] \
    -group [get_clocks -quiet -include_generated_clocks refclk_qsfp1] \
    -group [get_clocks -quiet -include_generated_clocks refclk_qsfp2] \
    -group [get_clocks -quiet -include_generated_clocks refclk_qsfp3]

# =====================================================================
# Aggregator SLR Floorplan (A1) — DISABLED
#
# Previous attempt with whole-SLR1 pblock caused router to fail with
# 58107 node overlaps (congestion explosion). Tier 1 cells alone
# (16 BRAM + adders + 5 layers of 512-bit FFs + state machine) were
# enough to overload SLR1 routing resources even with IS_SOFT=TRUE
# (soft pblock affects placement, not routing congestion).
#
# Re-enable only after RTL-side fixes (Plan A double-register +
# rd_idx local replica) are evaluated alone, and only with a much
# smaller scope or a non-whole-SLR area.
# =====================================================================

# create_pblock pblock_aggregator
# resize_pblock pblock_aggregator -add SLR1
# set_property IS_SOFT TRUE [get_pblocks pblock_aggregator]
# set_property EXCLUDE_PLACEMENT FALSE [get_pblocks pblock_aggregator]
# add_cells_to_pblock pblock_aggregator [get_cells -quiet {
#     u_nf_datapath/u_allreduce_wrapper/u_allreduce/u_aggregator/parallel_aggregate_bram[*].*
#     u_nf_datapath/u_allreduce_wrapper/u_allreduce/u_aggregator/allreduce_aggregate_buffer_controller
# }]

# =====================================================================
# Port-0 CMAC adapter SLR3 pblock — DISABLED
#
# Experiment showed that even a soft whole-SLR3 pblock causes cascading
# placement pressure on Port-1/2/3 adapters and the 250 MHz allreduce
# domain, worsening overall TNS. Keeping disabled until a narrower
# clock-region constraint or per-URAM LOC is validated.
# =====================================================================
# create_pblock pblock_adapter0
# resize_pblock pblock_adapter0 -add SLR3
# set_property IS_SOFT TRUE [get_pblocks pblock_adapter0]
# add_cells_to_pblock pblock_adapter0 [get_cells -quiet {
#     gen_adapter[0].u_tx_adapter
#     gen_adapter[0].u_rx_adapter
# }]

# =====================================================================
# Port-0 CMAC TX FIFO URAM precise LOC to SLR3
#
# Problem: Port-0 u_tx_fifo's 9 URAM cells were placed by Vivado at
# URAM288_X0Y172-Y183 (SLR2 top) while CMACE4_X0Y9 sits in SLR3 bottom.
# The CMACE4.TX_RDYOUT -> LUT -> URAM.EN_A path crosses the SLR2-SLR3
# boundary with 2+ ns routing, producing WNS = -0.587 ns on
# txoutclk_out[0] (2758 failing endpoints contributing -440 ns TNS).
#
# VU13P URAM column X0 SLR ranges:
#   SLR0: Y0-Y47, SLR1: Y48-Y95, SLR2: Y96-Y191, SLR3: Y192-Y239
#
# Y192-Y200 confirmed empty before locking. 9 cells map directly.
# =====================================================================
set_property LOC URAM288_X0Y192 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_0]
set_property LOC URAM288_X0Y193 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_1]
set_property LOC URAM288_X0Y194 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_2]
set_property LOC URAM288_X0Y195 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_3]
set_property LOC URAM288_X0Y196 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_4]
set_property LOC URAM288_X0Y197 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_5]
set_property LOC URAM288_X0Y198 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_6]
set_property LOC URAM288_X0Y199 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_7]
set_property LOC URAM288_X0Y200 [get_cells gen_adapter[0].u_tx_adapter/u_tx_fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_sdpram.xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_8]

# =====================================================================
# Bitstream Configuration
# =====================================================================
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
