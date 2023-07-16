create_bd_design "system"

set atxFifoName a_tx_fifo
set atxfifo [create_bd_cell -type ip -vlnv xilinx.com:ip:fifo_generator $atxFifoName]
set_property -dict [list CONFIG.INTERFACE_TYPE {AXI_STREAM} \
                         CONFIG.Reset_Type {Asynchronous_Reset} \
                         CONFIG.Full_Flags_Reset_Value {1} \
                         CONFIG.Clock_Type_AXI {Independent_Clock} \
                         CONFIG.TUSER_WIDTH {1} \
                         CONFIG.Enable_TLAST {true} \
                         CONFIG.Input_Depth_axis {4096} \
                         CONFIG.Enable_Safety_Circuit {true} \
                         CONFIG.FIFO_Application_Type_axis {Packet_FIFO} \
                    ] $atxfifo

set btxFifoName b_tx_fifo
set btxfifo [create_bd_cell -type ip -vlnv xilinx.com:ip:fifo_generator $btxFifoName]
set_property -dict [list CONFIG.INTERFACE_TYPE {AXI_STREAM} \
                         CONFIG.Reset_Type {Asynchronous_Reset} \
                         CONFIG.Full_Flags_Reset_Value {1} \
                         CONFIG.Clock_Type_AXI {Independent_Clock} \
                         CONFIG.TUSER_WIDTH {1} \
                         CONFIG.Enable_TLAST {true} \
                         CONFIG.Input_Depth_axis {4096} \
                         CONFIG.Enable_Safety_Circuit {true} \
                         CONFIG.FIFO_Application_Type_axis {Packet_FIFO} \
                    ] $btxfifo

set systemIlaName system_ila
set systemila [create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila $systemIlaName]
set_property -dict [list CONFIG.C_DATA_DEPTH {16384} \
                         CONFIG.C_NUM_MONITOR_SLOTS {2} \
                         CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
                         CONFIG.C_SLOT_0_AXIS_TDATA_WIDTH {8} \
                         CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
                         CONFIG.C_SLOT_1_AXIS_TDATA_WIDTH {8} \
                    ] [get_bd_cells $systemila]

# a_rx_clk input and connections
create_bd_port -dir I -type clk -freq_hz 125000000 a_rx_clk
connect_bd_net [get_bd_ports a_rx_clk] [get_bd_pins $atxfifo/s_aclk]

# b_rx_clk input and connections
create_bd_port -dir I -type clk -freq_hz 125000000 b_rx_clk
connect_bd_net [get_bd_ports b_rx_clk] [get_bd_pins $btxfifo/s_aclk]

# gtc_clk input and connections
create_bd_port -dir I -type clk -freq_hz 125000000 gtx_clk
connect_bd_net [get_bd_ports gtx_clk] [get_bd_pins $atxfifo/m_aclk]
connect_bd_net [get_bd_ports gtx_clk] [get_bd_pins $btxfifo/m_aclk]

# a axis input
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 A_S_AXIS
connect_bd_intf_net [get_bd_intf_ports A_S_AXIS] [get_bd_intf_pins $atxfifo/S_AXIS]

# b axis output
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 B_M_AXIS
connect_bd_intf_net [get_bd_intf_ports B_M_AXIS] [get_bd_intf_pins $atxfifo/M_AXIS]

# b axis input
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 B_S_AXIS
connect_bd_intf_net [get_bd_intf_ports B_S_AXIS] [get_bd_intf_pins $btxfifo/S_AXIS]

# a axis output
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 A_M_AXIS
connect_bd_intf_net [get_bd_intf_ports A_M_AXIS] [get_bd_intf_pins $btxfifo/M_AXIS]

# axis resetn and connections
create_bd_port -dir I -type rst aresetn
connect_bd_net [get_bd_ports aresetn] [get_bd_pins $atxfifo/s_aresetn]
connect_bd_net [get_bd_ports aresetn] [get_bd_pins $btxfifo/s_aresetn]

# System Ila connections
connect_bd_net [get_bd_ports gtx_clk] [get_bd_pins $systemila/clk]
connect_bd_net [get_bd_ports aresetn] [get_bd_pins $systemila/resetn]
connect_bd_intf_net [get_bd_intf_pins $systemila/SLOT_0_AXIS] [get_bd_intf_pins $atxfifo/M_AXIS]
connect_bd_intf_net [get_bd_intf_pins $systemila/SLOT_1_AXIS] [get_bd_intf_pins $btxfifo/M_AXIS]

save_bd_design
