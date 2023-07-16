set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_property -dict {PACKAGE_PIN C24 IOSTANDARD LVCMOS33} [get_ports sys_rstn]
set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS25} [get_ports sys_clk]
#create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports sys_clk]

############################################################################

set_property -dict {PACKAGE_PIN D11 IOSTANDARD LVCMOS25} [get_ports a_reset]

set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS25} [get_ports {a_rxd[0]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS25} [get_ports {a_rxd[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS25} [get_ports {a_rxd[2]}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS25} [get_ports {a_rxd[3]}]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS25} [get_ports {a_rxd[4]}]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS25} [get_ports {a_rxd[5]}]
set_property -dict {PACKAGE_PIN B14 IOSTANDARD LVCMOS25} [get_ports {a_rxd[6]}]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS25} [get_ports {a_rxd[7]}]

set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS25} [get_ports a_rxdv]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS25} [get_ports a_rxer]
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS25} [get_ports a_rxc]
create_clock -period 8.000 -name a_rxc -waveform {0.000 4.000} [get_ports a_rxc]

set_property -dict {PACKAGE_PIN G12 IOSTANDARD LVCMOS25} [get_ports {a_txd[0]}]
set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS25} [get_ports {a_txd[1]}]
set_property -dict {PACKAGE_PIN G11 IOSTANDARD LVCMOS25} [get_ports {a_txd[2]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS25} [get_ports {a_txd[3]}]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS25} [get_ports {a_txd[4]}]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS25} [get_ports {a_txd[5]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS25} [get_ports {a_txd[6]}]
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS25} [get_ports {a_txd[7]}]

set_property -dict {PACKAGE_PIN F12 IOSTANDARD LVCMOS25} [get_ports a_txen]
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS25} [get_ports a_txer]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS25} [get_ports a_gtxc]

set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS25} [get_ports a_mdc]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS25} [get_ports a_mdio]

############################################################################

set_property -dict {PACKAGE_PIN J8 IOSTANDARD LVCMOS25} [get_ports b_reset]

set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS25} [get_ports {b_rxd[0]}]
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS25} [get_ports {b_rxd[1]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS25} [get_ports {b_rxd[2]}]
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS25} [get_ports {b_rxd[3]}]
set_property -dict {PACKAGE_PIN B10 IOSTANDARD LVCMOS25} [get_ports {b_rxd[4]}]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS25} [get_ports {b_rxd[5]}]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS25} [get_ports {b_rxd[6]}]
set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS25} [get_ports {b_rxd[7]}]

set_property -dict {PACKAGE_PIN A12 IOSTANDARD LVCMOS25} [get_ports b_rxdv]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS25} [get_ports b_rxer]
set_property -dict {PACKAGE_PIN E10 IOSTANDARD LVCMOS25} [get_ports b_rxc]
create_clock -period 8.000 -name b_rxc -waveform {0.000 4.000} [get_ports b_rxc]

set_property -dict {PACKAGE_PIN H11 IOSTANDARD LVCMOS25} [get_ports {b_txd[0]}]
set_property -dict {PACKAGE_PIN J11 IOSTANDARD LVCMOS25} [get_ports {b_txd[1]}]
set_property -dict {PACKAGE_PIN H9 IOSTANDARD LVCMOS25} [get_ports {b_txd[2]}]
set_property -dict {PACKAGE_PIN J10 IOSTANDARD LVCMOS25} [get_ports {b_txd[3]}]
set_property -dict {PACKAGE_PIN H12 IOSTANDARD LVCMOS25} [get_ports {b_txd[4]}]
set_property -dict {PACKAGE_PIN F10 IOSTANDARD LVCMOS25} [get_ports {b_txd[5]}]
set_property -dict {PACKAGE_PIN G10 IOSTANDARD LVCMOS25} [get_ports {b_txd[6]}]
set_property -dict {PACKAGE_PIN F9 IOSTANDARD LVCMOS25} [get_ports {b_txd[7]}]

set_property -dict {PACKAGE_PIN F8 IOSTANDARD LVCMOS25} [get_ports b_txen]
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS25} [get_ports b_gtxc]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS25} [get_ports b_txer]

set_property -dict {PACKAGE_PIN H8 IOSTANDARD LVCMOS25} [get_ports b_mdc]
set_property -dict {PACKAGE_PIN G9 IOSTANDARD LVCMOS25} [get_ports b_mdio]

############################################################################

#set_clock_groups -logically_exclusive -group [get_clocks a_rxc] -group [get_clocks -of_objects [get_pins gmii_clk_i/inst/mmcm_adv_inst/CLKOUT0]]
#set_clock_groups -logically_exclusive -group [get_clocks b_rxc] -group [get_clocks -of_objects [get_pins gmii_clk_i/inst/mmcm_adv_inst/CLKOUT0]]
