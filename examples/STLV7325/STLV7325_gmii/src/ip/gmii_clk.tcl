create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name gmii_clk
set_property -dict [list CONFIG.CLK_OUT1_PORT {gmii_clk} \
                         CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
                         CONFIG.RESET_TYPE {ACTIVE_LOW} \
                         CONFIG.RESET_PORT {resetn} \
                    ] [get_ips gmii_clk]
