library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library STD;
use std.env.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use uvvm_util.axistream_bfm_pkg.all;

-- Test case entity
entity uart_tb is
end entity;

-- Test case architecture
architecture func of uart_tb is

    -- Clock and reset signals
    signal clk           : std_logic  := '0';
    signal arstn         : std_logic  := '1';
    --  AXIS master interface
    signal maxis_if : t_axistream_if(tdata(7 downto 0), tkeep(0 downto 0), tuser(0 downto 0), tstrb(0 downto 0), tid(0 downto 0), tdest(0 downto 0)) := init_axistream_if_signals(true, 8, 1, 1, 1);
    signal maxis_if_config : t_axistream_bfm_config := C_AXISTREAM_BFM_CONFIG_DEFAULT;

    signal clock_ena     : boolean   := false;

    constant C_BAUDRATE     : natural := 921600;
    constant C_FCPU         : natural := 100e6;
    constant C_DIVISOR      : natural := C_FCPU/C_BAUDRATE;
    constant C_CLK_PERIOD   : time    := 10 ns;

begin
    -----------------------------------------------------------------------------
    -- Instantiate DUT
    -----------------------------------------------------------------------------
    dut: entity work.uart
        generic map (
            DIVISOR => C_DIVISOR
        )
        port map (
            aclk    => clk,
            aresetn => arstn,
    
            s_axis_tdata    => maxis_if.tdata,
            s_axis_tvalid   => maxis_if.tvalid,
            s_axis_tready   => maxis_if.tready
        );

    maxis_if_config.clock_period <= C_CLK_PERIOD;
    maxis_if_config.max_wait_cycles <= 11 * C_DIVISOR;

    -----------------------------------------------------------------------------
    -- Clock Generator
    -----------------------------------------------------------------------------
    clock_generator(clk, clock_ena, C_CLK_PERIOD, "UART TB clock");

    ------------------------------------------------
    -- PROCESS: p_main
    ------------------------------------------------
    p_main: process

        procedure maxis_transmit (
            constant data_array : in t_slv_array;
            constant msg        : in string) is
        begin
            axistream_transmit(data_array, msg, clk, maxis_if, C_SCOPE, shared_msg_id_panel, maxis_if_config);
        end;

    begin
        -- Print the configuration to the log
        report_global_ctrl(VOID);
        report_msg_id_panel(VOID);

        enable_log_msg(ALL_MESSAGES);
        --disable_log_msg(ALL_MESSAGES);
        --enable_log_msg(ID_LOG_HDR);

        log(ID_LOG_HDR, "Start Simulation of TB for UART", C_SCOPE);
        ------------------------------------------------------------

        clock_ena <= true; -- to start clock generator

        gen_pulse(arstn, '0', 2.5 * C_CLK_PERIOD, "Pulsed reset-signal - active for 2.5T");

        wait for 10 * C_CLK_PERIOD;

        log(ID_LOG_HDR, "Configuration done, start sending data", C_SCOPE);
        ------------------------------------------------------------
        maxis_transmit((x"A5", x"07", x"44", x"5a"), "Transmit bytes by UART");

        log(ID_LOG_HDR, "Check sending data at UART output", C_SCOPE);
        ------------------------------------------------------------

        --==================================================================================================
        -- Ending the simulation
        --------------------------------------------------------------------------------------
        wait for 10000 ns;             -- to allow some time for completion
        report_alert_counters(FINAL); -- Report final counters and print conclusion for simulation (Success/Fail)
        log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

        -- Finish the simulation
        std.env.stop;
        wait;  -- to stop completely

    end process p_main;

end func;
