create_ip -name ila -vendor xilinx.com -library ip -module_name ila_axis8
set_property -dict [list CONFIG.C_DATA_DEPTH {4096} \
                         CONFIG.C_MONITOR_TYPE {AXI} \
                         CONFIG.C_ADV_TRIGGER {true} \
                         CONFIG.C_SLOT_0_AXI_PROTOCOL {AXI4S} \
                         CONFIG.C_SLOT_0_AXIS_TDATA_WIDTH {8} \
                         CONFIG.C_SLOT_0_AXIS_TID_WIDTH {0} \
                         CONFIG.C_SLOT_0_AXIS_TDEST_WIDTH {0} \
                         CONFIG.C_ENABLE_ILA_AXI_MON {true} \
                    ] [get_ips ila_axis8]
