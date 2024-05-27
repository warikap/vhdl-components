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
-- use ieee.numeric_std.all;

entity axis_gmii is
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
end entity axis_gmii;

architecture rtl of axis_gmii is

    component axis_gmii_rx is
        port (
            clk : in    std_logic;
            rst : in    std_logic;

            gmii_rxd   : in    std_logic_vector(7 downto 0);
            gmii_rx_dv : in    std_logic;
            gmii_rx_er : in    std_logic;

            m_axis_tdata  : out   std_logic_vector(7 downto 0);
            m_axis_tvalid : out   std_logic;
            m_axis_tlast  : out   std_logic;
            m_axis_tuser  : out   std_logic;

            start_packet    : out   std_logic;
            error_bad_frame : out   std_logic;
            error_bad_fcs   : out   std_logic
        );
    end component;

    component axis_gmii_tx is
        port (
            clk : in    std_logic;
            rst : in    std_logic;

            s_axis_tdata  : in    std_logic_vector(7 downto 0);
            s_axis_tvalid : in    std_logic;
            s_axis_tready : out   std_logic;
            s_axis_tlast  : in    std_logic;

            gmii_txd   : out   std_logic_vector(7 downto 0);
            gmii_tx_en : out   std_logic;
            gmii_tx_er : out   std_logic
        );
    end component;

begin

    axis_gmii_rx_i : component axis_gmii_rx
        port map (
            clk => rx_clk,
            rst => rx_rst,

            gmii_rxd   => gmii_rxd,
            gmii_rx_dv => gmii_rx_dv,
            gmii_rx_er => gmii_rx_er,

            m_axis_tdata  => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tlast  => m_axis_tlast,
            m_axis_tuser  => m_axis_tuser,

            start_packet    => rx_start_packet,
            error_bad_frame => rx_error_bad_frame,
            error_bad_fcs   => rx_error_bad_fcs
        );

    axis_gmii_tx_i : component axis_gmii_tx
        port map (
            clk => tx_clk,
            rst => tx_rst,

            s_axis_tdata  => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,

            gmii_txd   => gmii_txd,
            gmii_tx_en => gmii_tx_en,
            gmii_tx_er => gmii_tx_er
        );

end architecture rtl;
