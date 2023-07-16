-- Copyright (c) 2023 Marcin Zaremba
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity stlv7325_gmii is
    port (
        sys_clk  : in    std_logic;
        sys_rstn : in    std_logic;

        a_reset : out   std_logic;
        a_rxc   : in    std_logic;
        a_rxdv  : in    std_logic;
        a_rxer  : in    std_logic;
        a_rxd   : in    std_logic_vector(7 downto 0);
        a_gtxc  : out   std_logic;
        a_txen  : out   std_logic;
        a_txer  : out   std_logic;
        a_txd   : out   std_logic_vector(7 downto 0);
        a_mdc   : out   std_logic;
        a_mdio  : inout std_logic;

        b_reset : out   std_logic;
        b_rxc   : in    std_logic;
        b_rxdv  : in    std_logic;
        b_rxer  : in    std_logic;
        b_rxd   : in    std_logic_vector(7 downto 0);
        b_gtxc  : out   std_logic;
        b_txen  : out   std_logic;
        b_txer  : out   std_logic;
        b_txd   : out   std_logic_vector(7 downto 0);
        b_mdc   : out   std_logic;
        b_mdio  : inout std_logic
    );
end entity stlv7325_gmii;

architecture rtl of stlv7325_gmii is

    component gmii_clk is
        port (
            gmii_clk : out   std_logic;
            resetn   : in    std_logic;
            locked   : out   std_logic;
            clk_in1  : in    std_logic
        );
    end component;

    component axis_gmii is
        port (
            rx_clk : in    std_logic;
            rx_rst : in    std_logic;

            tx_clk : in    std_logic;
            tx_rst : in    std_logic;

            m_axis_tdata  : out   std_logic_vector(7 downto 0);
            m_axis_tvalid : out   std_logic;
            m_axis_tlast  : out   std_logic;
            m_axis_tuser  : out   std_logic;

            s_axis_tdata  : in    std_logic_vector(7 downto 0);
            s_axis_tvalid : in    std_logic;
            s_axis_tready : out   std_logic;
            s_axis_tlast  : in    std_logic;

            gmii_rxd   : in    std_logic_vector(7 downto 0);
            gmii_rx_dv : in    std_logic;
            gmii_rx_er : in    std_logic;

            gmii_txd   : out   std_logic_vector(7 downto 0);
            gmii_tx_en : out   std_logic;
            gmii_tx_er : out   std_logic;

            rx_start_packet    : out   std_logic;
            rx_error_bad_frame : out   std_logic;
            rx_error_bad_fcs   : out   std_logic
        );
    end component;

    component system is
        port (
            a_rx_clk : in    std_logic;
            b_rx_clk : in    std_logic;
            gtx_clk  : in    std_logic;
            aresetn  : in    std_logic;

            a_s_axis_tdata  : in    std_logic_vector( 7 downto 0);
            a_s_axis_tlast  : in    std_logic;
            a_s_axis_tready : out   std_logic;
            a_s_axis_tuser  : in    std_logic_vector( 0 to 0);
            a_s_axis_tvalid : in    std_logic;

            b_m_axis_tdata  : out   std_logic_vector( 7 downto 0);
            b_m_axis_tlast  : out   std_logic;
            b_m_axis_tready : in    std_logic;
            b_m_axis_tuser  : out   std_logic_vector( 0 to 0);
            b_m_axis_tvalid : out   std_logic;

            b_s_axis_tdata  : in    std_logic_vector( 7 downto 0);
            b_s_axis_tlast  : in    std_logic;
            b_s_axis_tready : out   std_logic;
            b_s_axis_tuser  : in    std_logic_vector( 0 to 0);
            b_s_axis_tvalid : in    std_logic;

            a_m_axis_tdata  : out   std_logic_vector( 7 downto 0);
            a_m_axis_tlast  : out   std_logic;
            a_m_axis_tready : in    std_logic;
            a_m_axis_tuser  : out   std_logic_vector( 0 to 0);
            a_m_axis_tvalid : out   std_logic
        );
    end component system;

    signal gmii_rstn : std_logic;
    signal gtx_clk   : std_logic;

    signal arx_tdata  : std_logic_vector(7 downto 0);
    signal arx_tlast  : std_logic;
    signal arx_tready : std_logic;
    signal arx_tuser  : std_logic;
    signal arx_tvalid : std_logic;

    signal btx_tdata  : std_logic_vector(7 downto 0);
    signal btx_tlast  : std_logic;
    signal btx_tready : std_logic;
    signal btx_tuser  : std_logic;
    signal btx_tvalid : std_logic;

    signal brx_tdata  : std_logic_vector(7 downto 0);
    signal brx_tvalid : std_logic;
    signal brx_tready : std_logic;
    signal brx_tlast  : std_logic;
    signal brx_tuser  : std_logic;

    signal atx_tdata  : std_logic_vector(7 downto 0);
    signal atx_tlast  : std_logic;
    signal atx_tready : std_logic;
    signal atx_tuser  : std_logic;
    signal atx_tvalid : std_logic;

begin

    gmii_clk_i : component gmii_clk
        port map (
            gmii_clk => gtx_clk,
            resetn   => sys_rstn,
            locked   => gmii_rstn,
            clk_in1  => sys_clk
        );

    axis_gmii_a_b : component axis_gmii
        port map (
            rx_clk => a_rxc,
            rx_rst => not sys_rstn,

            tx_clk => gtx_clk,
            tx_rst => not sys_rstn,

            m_axis_tdata  => arx_tdata,
            m_axis_tvalid => arx_tvalid,
            m_axis_tlast  => arx_tlast,
            m_axis_tuser  => arx_tuser,

            s_axis_tdata  => btx_tdata,
            s_axis_tvalid => btx_tvalid,
            s_axis_tready => btx_tready,
            s_axis_tlast  => btx_tlast,

            gmii_rxd   => a_rxd,
            gmii_rx_dv => a_rxdv,
            gmii_rx_er => a_rxer,

            gmii_txd   => b_txd,
            gmii_tx_en => b_txen,
            gmii_tx_er => b_txer,

            rx_start_packet    => open,
            rx_error_bad_frame => open,
            rx_error_bad_fcs   => open
        );

    axis_gmii_b_a : component axis_gmii
        port map (
            rx_clk => b_rxc,
            rx_rst => not sys_rstn,

            tx_clk => gtx_clk,
            tx_rst => not sys_rstn,

            m_axis_tdata  => brx_tdata,
            m_axis_tvalid => brx_tvalid,
            m_axis_tlast  => brx_tlast,
            m_axis_tuser  => brx_tuser,

            s_axis_tdata  => atx_tdata,
            s_axis_tvalid => atx_tvalid,
            s_axis_tready => atx_tready,
            s_axis_tlast  => atx_tlast,

            gmii_rxd   => b_rxd,
            gmii_rx_dv => b_rxdv,
            gmii_rx_er => b_rxer,

            gmii_txd   => a_txd,
            gmii_tx_en => a_txen,
            gmii_tx_er => a_txer,

            rx_start_packet    => open,
            rx_error_bad_frame => open,
            rx_error_bad_fcs   => open
        );

    system_i : component system
        port map (
            a_rx_clk => a_rxc,
            b_rx_clk => b_rxc,
            gtx_clk  => gtx_clk,
            aresetn  => gmii_rstn,

            a_s_axis_tdata    => arx_tdata,
            a_s_axis_tlast    => arx_tlast,
            a_s_axis_tready   => arx_tready,
            a_s_axis_tuser(0) => arx_tuser,
            a_s_axis_tvalid   => arx_tvalid,

            b_m_axis_tdata    => btx_tdata,
            b_m_axis_tlast    => btx_tlast,
            b_m_axis_tready   => btx_tready,
            b_m_axis_tuser(0) => btx_tuser,
            b_m_axis_tvalid   => btx_tvalid,

            b_s_axis_tdata    => brx_tdata,
            b_s_axis_tlast    => brx_tlast,
            b_s_axis_tready   => brx_tready,
            b_s_axis_tuser(0) => brx_tuser,
            b_s_axis_tvalid   => brx_tvalid,

            a_m_axis_tdata    => atx_tdata,
            a_m_axis_tlast    => atx_tlast,
            a_m_axis_tready   => atx_tready,
            a_m_axis_tuser(0) => atx_tuser,
            a_m_axis_tvalid   => atx_tvalid
        );

    a_reset <= gmii_rstn;
    a_gtxc  <= gtx_clk;

    b_reset <= gmii_rstn;
    b_gtxc  <= gtx_clk;

    a_mdc  <= '1';
    a_mdio <= '1';

    b_mdc  <= '1';
    b_mdio <= '1';

end architecture rtl;
