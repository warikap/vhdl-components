create_ip -name fifo_generator -vendor xilinx.com -library ip -module_name fifo_4k
set_property -dict [list CONFIG.INTERFACE_TYPE {AXI_STREAM} \
                         CONFIG.Reset_Type {Asynchronous_Reset} \
                         CONFIG.Full_Flags_Reset_Value {1} \
                         CONFIG.Clock_Type_AXI {Independent_Clock} \
                         CONFIG.TUSER_WIDTH {1} \
                         CONFIG.Enable_TLAST {true} \
                         CONFIG.Input_Depth_axis {4096} \
                         CONFIG.Enable_Safety_Circuit {true} \
                         CONFIG.FIFO_Application_Type_axis {Packet_FIFO} \
                    ] [get_ips fifo_4k]
