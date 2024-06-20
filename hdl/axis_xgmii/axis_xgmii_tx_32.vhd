-- Copyright (c) 2024 Marcin Zaremba
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

entity axis_xgmii_tx_32 is
    port (
        clk : in    std_logic;
        rst : in    std_logic;

        s_axis_tdata  : in    std_logic_vector(31 downto 0);
        s_axis_tkeep  : in    std_logic_vector(3 downto 0);
        s_axis_tvalid : in    std_logic;
        s_axis_tready : out   std_logic;
        s_axis_tlast  : in    std_logic;
        s_axis_tuser  : in    std_logic_vector(0 downto 0);

        xgmii_txd : out   std_logic_vector(31 downto 0);
        xgmii_txc : out   std_logic_vector(3 downto 0);

        cfg_ifg       : in    std_logic_vector(7 downto 0);
        cfg_tx_enable : in    std_logic;

        start_packet    : out   std_logic;
        error_underflow : out   std_logic
    );
end entity axis_xgmii_tx_32;

architecture rtl of axis_xgmii_tx_32 is

    constant ETH_PRE : std_logic_vector(7 downto 0) := x"55";
    constant ETH_SFD : std_logic_vector(7 downto 0) := x"D5";

    constant XGMII_IDLE  : std_logic_vector(7 downto 0) := x"07";
    constant XGMII_START : std_logic_vector(7 downto 0) := x"FB";
    constant XGMII_TERM  : std_logic_vector(7 downto 0) := x"FD";
    constant XGMII_ERROR : std_logic_vector(7 downto 0) := x"FE";

    type fsm_state_t is (IDLE, PREAMBLE, PAYLOAD, PAD, FCS_1, FCS_2, FCS_3, ERR, IFG);

    signal state_reg  : fsm_state_t;
    signal state_next : fsm_state_t;

    signal reset_crc  : std_logic;
    signal update_crc : std_logic;

    type crc_state_t is array (0 to 3) of std_logic_vector(31 downto 0);

    signal crc_state_reg  : crc_state_t;
    signal crc_state_next : crc_state_t;

    signal s_axis_tdata_masked : std_logic_vector(31 downto 0);

    signal s_tdata_reg,            s_tdata_next : std_logic_vector(31 downto 0);
    signal s_empty_reg,            s_empty_next : natural range 0 to 3;

    signal fcs_output_txd_0 : std_logic_vector(31 downto 0);
    signal fcs_output_txd_1 : std_logic_vector(31 downto 0);
    signal fcs_output_txc_0 : std_logic_vector(3 downto 0);
    signal fcs_output_txc_1 : std_logic_vector(3 downto 0);

    signal ifg_offset : natural range 0 to 255;

    signal extra_cycle : std_logic;

    signal frame_reg,              frame_next           : std_logic;
    signal frame_error_reg,        frame_error_next     : std_logic;
    signal frame_min_count_reg,    frame_min_count_next : natural range 0 to 63;

    signal ifg_count_reg,          ifg_count_next          : natural range 0 to 255;
    signal deficit_idle_count_reg, deficit_idle_count_next : natural range 0 to 3;

    signal s_axis_tready_reg,      s_axis_tready_next : std_logic;

    signal xgmii_txd_reg,          xgmii_txd_next : std_logic_vector(31 downto 0);
    signal xgmii_txc_reg,          xgmii_txc_next : std_logic_vector(3 downto 0);

    signal start_packet_reg,       start_packet_next    : std_logic;
    signal error_underflow_reg,    error_underflow_next : std_logic;

    procedure crc_step_8 (
        signal crcIn  : in std_logic_vector(31 downto 0);
        signal data   : in std_logic_vector(7 downto 0);
        signal crcOut : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- vsg_off
        crcOut(0)  <= crcIn(2) xor crcIn(8) xor data(2);
        crcOut(1)  <= crcIn(0) xor crcIn(3) xor crcIn(9) xor data(0) xor data(3);
        crcOut(2)  <= crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(10) xor data(0) xor data(1) xor data(4);
        crcOut(3)  <= crcIn(1) xor crcIn(2) xor crcIn(5) xor crcIn(11) xor data(1) xor data(2) xor data(5);
        crcOut(4)  <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(12) xor data(0) xor data(2) xor data(3) xor data(6);
        crcOut(5)  <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(7) xor crcIn(13) xor data(1) xor data(3) xor data(4) xor data(7);
        crcOut(6)  <= crcIn(4) xor crcIn(5) xor crcIn(14) xor data(4) xor data(5);
        crcOut(7)  <= crcIn(0) xor crcIn(5) xor crcIn(6) xor crcIn(15) xor data(0) xor data(5) xor data(6);
        crcOut(8)  <= crcIn(1) xor crcIn(6) xor crcIn(7) xor crcIn(16) xor data(1) xor data(6) xor data(7);
        crcOut(9)  <= crcIn(7) xor crcIn(17) xor data(7);
        crcOut(10) <= crcIn(2) xor crcIn(18) xor data(2);
        crcOut(11) <= crcIn(3) xor crcIn(19) xor data(3);
        crcOut(12) <= crcIn(0) xor crcIn(4) xor crcIn(20) xor data(0) xor data(4);
        crcOut(13) <= crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(21) xor data(0) xor data(1) xor data(5);
        crcOut(14) <= crcIn(1) xor crcIn(2) xor crcIn(6) xor crcIn(22) xor data(1) xor data(2) xor data(6);
        crcOut(15) <= crcIn(2) xor crcIn(3) xor crcIn(7) xor crcIn(23) xor data(2) xor data(3) xor data(7);
        crcOut(16) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(24) xor data(0) xor data(2) xor data(3) xor data(4);
        crcOut(17) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(25) xor data(0) xor data(1) xor data(3) xor data(4) xor data(5);
        crcOut(18) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(26) xor data(0) xor data(1) xor data(2) xor data(4) xor data(5) xor data(6);
        crcOut(19) <= crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(27) xor data(1) xor data(2) xor data(3) xor data(5) xor data(6) xor data(7);
        crcOut(20) <= crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(28) xor data(3) xor data(4) xor data(6) xor data(7);
        crcOut(21) <= crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(29) xor data(2) xor data(4) xor data(5) xor data(7);
        crcOut(22) <= crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(30) xor data(2) xor data(3) xor data(5) xor data(6);
        crcOut(23) <= crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(31) xor data(3) xor data(4) xor data(6) xor data(7);
        crcOut(24) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7);
        crcOut(25) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor data(0) xor data(1) xor data(2) xor data(3) xor data(5) xor data(6);
        crcOut(26) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(6) xor data(7);
        crcOut(27) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor data(1) xor data(3) xor data(4) xor data(5) xor data(7);
        crcOut(28) <= crcIn(0) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor data(0) xor data(4) xor data(5) xor data(6);
        crcOut(29) <= crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(5) xor data(6) xor data(7);
        crcOut(30) <= crcIn(0) xor crcIn(1) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(6) xor data(7);
        crcOut(31) <= crcIn(1) xor crcIn(7) xor data(1) xor data(7);
        -- vsg_on
    end procedure;

    procedure crc_step_16 (
        signal crcIn  : in std_logic_vector(31 downto 0);
        signal data   : in std_logic_vector(15 downto 0);
        signal crcOut : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- vsg_off
        crcOut(0) <= crcIn(0) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(10) xor crcIn(16) xor data(0) xor data(4) xor data(6) xor data(7) xor data(10);
        crcOut(1) <= crcIn(1) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(11) xor crcIn(17) xor data(1) xor data(5) xor data(7) xor data(8) xor data(11);
        crcOut(2) <= crcIn(2) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(12) xor crcIn(18) xor data(2) xor data(6) xor data(8) xor data(9) xor data(12);
        crcOut(3) <= crcIn(3) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(13) xor crcIn(19) xor data(3) xor data(7) xor data(9) xor data(10) xor data(13);
        crcOut(4) <= crcIn(4) xor crcIn(8) xor crcIn(10) xor crcIn(11) xor crcIn(14) xor crcIn(20) xor data(4) xor data(8) xor data(10) xor data(11) xor data(14);
        crcOut(5) <= crcIn(5) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(15) xor crcIn(21) xor data(5) xor data(9) xor data(11) xor data(12) xor data(15);
        crcOut(6) <= crcIn(0) xor crcIn(4) xor crcIn(7) xor crcIn(12) xor crcIn(13) xor crcIn(22) xor data(0) xor data(4) xor data(7) xor data(12) xor data(13);
        crcOut(7) <= crcIn(1) xor crcIn(5) xor crcIn(8) xor crcIn(13) xor crcIn(14) xor crcIn(23) xor data(1) xor data(5) xor data(8) xor data(13) xor data(14);
        crcOut(8) <= crcIn(0) xor crcIn(2) xor crcIn(6) xor crcIn(9) xor crcIn(14) xor crcIn(15) xor crcIn(24) xor data(0) xor data(2) xor data(6) xor data(9) xor data(14) xor data(15);
        crcOut(9) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(15) xor crcIn(25) xor data(1) xor data(3) xor data(4) xor data(6) xor data(15);
        crcOut(10) <= crcIn(2) xor crcIn(5) xor crcIn(6) xor crcIn(10) xor crcIn(26) xor data(2) xor data(5) xor data(6) xor data(10);
        crcOut(11) <= crcIn(3) xor crcIn(6) xor crcIn(7) xor crcIn(11) xor crcIn(27) xor data(3) xor data(6) xor data(7) xor data(11);
        crcOut(12) <= crcIn(0) xor crcIn(4) xor crcIn(7) xor crcIn(8) xor crcIn(12) xor crcIn(28) xor data(0) xor data(4) xor data(7) xor data(8) xor data(12);
        crcOut(13) <= crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(8) xor crcIn(9) xor crcIn(13) xor crcIn(29) xor data(0) xor data(1) xor data(5) xor data(8) xor data(9) xor data(13);
        crcOut(14) <= crcIn(1) xor crcIn(2) xor crcIn(6) xor crcIn(9) xor crcIn(10) xor crcIn(14) xor crcIn(30) xor data(1) xor data(2) xor data(6) xor data(9) xor data(10) xor data(14);
        crcOut(15) <= crcIn(2) xor crcIn(3) xor crcIn(7) xor crcIn(10) xor crcIn(11) xor crcIn(15) xor crcIn(31) xor data(2) xor data(3) xor data(7) xor data(10) xor data(11) xor data(15);
        crcOut(16) <= crcIn(0) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor data(0) xor data(3) xor data(6) xor data(7) xor data(8) xor data(10) xor data(11) xor data(12);
        crcOut(17) <= crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor data(0) xor data(1) xor data(4) xor data(7) xor data(8) xor data(9) xor data(11) xor data(12) xor data(13);
        crcOut(18) <= crcIn(1) xor crcIn(2) xor crcIn(5) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor data(1) xor data(2) xor data(5) xor data(8) xor data(9) xor data(10) xor data(12) xor data(13) xor data(14);
        crcOut(19) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor data(0) xor data(2) xor data(3) xor data(6) xor data(9) xor data(10) xor data(11) xor data(13) xor data(14) xor data(15);
        crcOut(20) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(6) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor data(0) xor data(1) xor data(3) xor data(6) xor data(11) xor data(12) xor data(14) xor data(15);
        crcOut(21) <= crcIn(1) xor crcIn(2) xor crcIn(6) xor crcIn(10) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor data(1) xor data(2) xor data(6) xor data(10) xor data(12) xor data(13) xor data(15);
        crcOut(22) <= crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(10) xor crcIn(11) xor crcIn(13) xor crcIn(14) xor data(2) xor data(3) xor data(4) xor data(6) xor data(10) xor data(11) xor data(13) xor data(14);
        crcOut(23) <= crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor data(3) xor data(4) xor data(5) xor data(7) xor data(11) xor data(12) xor data(14) xor data(15);
        crcOut(24) <= crcIn(0) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(10) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor data(0) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(15);
        crcOut(25) <= crcIn(1) xor crcIn(4) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(13) xor crcIn(14) xor data(1) xor data(4) xor data(7) xor data(8) xor data(9) xor data(10) xor data(11) xor data(13) xor data(14);
        crcOut(26) <= crcIn(2) xor crcIn(5) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor data(2) xor data(5) xor data(8) xor data(9) xor data(10) xor data(11) xor data(12) xor data(14) xor data(15);
        crcOut(27) <= crcIn(0) xor crcIn(3) xor crcIn(4) xor crcIn(7) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor data(0) xor data(3) xor data(4) xor data(7) xor data(9) xor data(11) xor data(12) xor data(13) xor data(15);
        crcOut(28) <= crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor data(0) xor data(1) xor data(5) xor data(6) xor data(7) xor data(8) xor data(12) xor data(13) xor data(14);
        crcOut(29) <= crcIn(1) xor crcIn(2) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor data(1) xor data(2) xor data(6) xor data(7) xor data(8) xor data(9) xor data(13) xor data(14) xor data(15);
        crcOut(30) <= crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(14) xor crcIn(15) xor data(2) xor data(3) xor data(4) xor data(6) xor data(8) xor data(9) xor data(14) xor data(15);
        crcOut(31) <= crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(9) xor crcIn(15) xor data(3) xor data(5) xor data(6) xor data(9) xor data(15);
        -- vsg_on
    end procedure;

    procedure crc_step_24 (
        signal crcIn  : in std_logic_vector(31 downto 0);
        signal data   : in std_logic_vector(23 downto 0);
        signal crcOut : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- vsg_off
        crcOut(0) <= crcIn(0) xor crcIn(8) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor crcIn(18) xor crcIn(24) xor data(0) xor data(8) xor data(12) xor data(14) xor data(15) xor data(18);
        crcOut(1) <= crcIn(0) xor crcIn(1) xor crcIn(9) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(19) xor crcIn(25) xor data(0) xor data(1) xor data(9) xor data(13) xor data(15) xor data(16) xor data(19);
        crcOut(2) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(10) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(20) xor crcIn(26) xor data(0) xor data(1) xor data(2) xor data(10) xor data(14) xor data(16) xor data(17) xor data(20);
        crcOut(3) <= crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(11) xor crcIn(15) xor crcIn(17) xor crcIn(18) xor crcIn(21) xor crcIn(27) xor data(1) xor data(2) xor data(3) xor data(11) xor data(15) xor data(17) xor data(18) xor data(21);
        crcOut(4) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(12) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(22) xor crcIn(28) xor data(0) xor data(2) xor data(3) xor data(4) xor data(12) xor data(16) xor data(18) xor data(19) xor data(22);
        crcOut(5) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(13) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(23) xor crcIn(29) xor data(0) xor data(1) xor data(3) xor data(4) xor data(5) xor data(13) xor data(17) xor data(19) xor data(20) xor data(23);
        crcOut(6) <= crcIn(1) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(12) xor crcIn(15) xor crcIn(20) xor crcIn(21) xor crcIn(30) xor data(1) xor data(2) xor data(4) xor data(5) xor data(6) xor data(8) xor data(12) xor data(15) xor data(20) xor data(21);
        crcOut(7) <= crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(13) xor crcIn(16) xor crcIn(21) xor crcIn(22) xor crcIn(31) xor data(2) xor data(3) xor data(5) xor data(6) xor data(7) xor data(9) xor data(13) xor data(16) xor data(21) xor data(22);
        crcOut(8) <= crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(10) xor crcIn(14) xor crcIn(17) xor crcIn(22) xor crcIn(23) xor data(3) xor data(4) xor data(6) xor data(7) xor data(8) xor data(10) xor data(14) xor data(17) xor data(22) xor data(23);
        crcOut(9) <= crcIn(0) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(23) xor data(0) xor data(4) xor data(5) xor data(7) xor data(9) xor data(11) xor data(12) xor data(14) xor data(23);
        crcOut(10) <= crcIn(1) xor crcIn(5) xor crcIn(6) xor crcIn(10) xor crcIn(13) xor crcIn(14) xor crcIn(18) xor data(1) xor data(5) xor data(6) xor data(10) xor data(13) xor data(14) xor data(18);
        crcOut(11) <= crcIn(0) xor crcIn(2) xor crcIn(6) xor crcIn(7) xor crcIn(11) xor crcIn(14) xor crcIn(15) xor crcIn(19) xor data(0) xor data(2) xor data(6) xor data(7) xor data(11) xor data(14) xor data(15) xor data(19);
        crcOut(12) <= crcIn(1) xor crcIn(3) xor crcIn(7) xor crcIn(8) xor crcIn(12) xor crcIn(15) xor crcIn(16) xor crcIn(20) xor data(1) xor data(3) xor data(7) xor data(8) xor data(12) xor data(15) xor data(16) xor data(20);
        crcOut(13) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(8) xor crcIn(9) xor crcIn(13) xor crcIn(16) xor crcIn(17) xor crcIn(21) xor data(0) xor data(2) xor data(4) xor data(8) xor data(9) xor data(13) xor data(16) xor data(17) xor data(21);
        crcOut(14) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(5) xor crcIn(9) xor crcIn(10) xor crcIn(14) xor crcIn(17) xor crcIn(18) xor crcIn(22) xor data(0) xor data(1) xor data(3) xor data(5) xor data(9) xor data(10) xor data(14) xor data(17) xor data(18) xor data(22);
        crcOut(15) <= crcIn(1) xor crcIn(2) xor crcIn(4) xor crcIn(6) xor crcIn(10) xor crcIn(11) xor crcIn(15) xor crcIn(18) xor crcIn(19) xor crcIn(23) xor data(1) xor data(2) xor data(4) xor data(6) xor data(10) xor data(11) xor data(15) xor data(18) xor data(19) xor data(23);
        crcOut(16) <= crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(11) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(20) xor data(2) xor data(3) xor data(5) xor data(7) xor data(8) xor data(11) xor data(14) xor data(15) xor data(16) xor data(18) xor data(19) xor data(20);
        crcOut(17) <= crcIn(0) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(12) xor crcIn(15) xor crcIn(16) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(21) xor data(0) xor data(3) xor data(4) xor data(6) xor data(8) xor data(9) xor data(12) xor data(15) xor data(16) xor data(17) xor data(19) xor data(20) xor data(21);
        crcOut(18) <= crcIn(1) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(13) xor crcIn(16) xor crcIn(17) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(22) xor data(1) xor data(4) xor data(5) xor data(7) xor data(9) xor data(10) xor data(13) xor data(16) xor data(17) xor data(18) xor data(20) xor data(21) xor data(22);
        crcOut(19) <= crcIn(2) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(10) xor crcIn(11) xor crcIn(14) xor crcIn(17) xor crcIn(18) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor crcIn(23) xor data(2) xor data(5) xor data(6) xor data(8) xor data(10) xor data(11) xor data(14) xor data(17) xor data(18) xor data(19) xor data(21) xor data(22) xor data(23);
        crcOut(20) <= crcIn(3) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(11) xor crcIn(14) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(23) xor data(3) xor data(6) xor data(7) xor data(8) xor data(9) xor data(11) xor data(14) xor data(19) xor data(20) xor data(22) xor data(23);
        crcOut(21) <= crcIn(4) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(14) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(23) xor data(4) xor data(7) xor data(9) xor data(10) xor data(14) xor data(18) xor data(20) xor data(21) xor data(23);
        crcOut(22) <= crcIn(0) xor crcIn(5) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(18) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor data(0) xor data(5) xor data(10) xor data(11) xor data(12) xor data(14) xor data(18) xor data(19) xor data(21) xor data(22);
        crcOut(23) <= crcIn(0) xor crcIn(1) xor crcIn(6) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(23) xor data(0) xor data(1) xor data(6) xor data(11) xor data(12) xor data(13) xor data(15) xor data(19) xor data(20) xor data(22) xor data(23);
        crcOut(24) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(7) xor crcIn(8) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(23) xor data(0) xor data(1) xor data(2) xor data(7) xor data(8) xor data(13) xor data(15) xor data(16) xor data(18) xor data(20) xor data(21) xor data(23);
        crcOut(25) <= crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(9) xor crcIn(12) xor crcIn(15) xor crcIn(16) xor crcIn(17) xor crcIn(18) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor data(1) xor data(2) xor data(3) xor data(9) xor data(12) xor data(15) xor data(16) xor data(17) xor data(18) xor data(19) xor data(21) xor data(22);
        crcOut(26) <= crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(10) xor crcIn(13) xor crcIn(16) xor crcIn(17) xor crcIn(18) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(23) xor data(2) xor data(3) xor data(4) xor data(10) xor data(13) xor data(16) xor data(17) xor data(18) xor data(19) xor data(20) xor data(22) xor data(23);
        crcOut(27) <= crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(8) xor crcIn(11) xor crcIn(12) xor crcIn(15) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(21) xor crcIn(23) xor data(3) xor data(4) xor data(5) xor data(8) xor data(11) xor data(12) xor data(15) xor data(17) xor data(19) xor data(20) xor data(21) xor data(23);
        crcOut(28) <= crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(20) xor crcIn(21) xor crcIn(22) xor data(4) xor data(5) xor data(6) xor data(8) xor data(9) xor data(13) xor data(14) xor data(15) xor data(16) xor data(20) xor data(21) xor data(22);
        crcOut(29) <= crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(17) xor crcIn(21) xor crcIn(22) xor crcIn(23) xor data(5) xor data(6) xor data(7) xor data(9) xor data(10) xor data(14) xor data(15) xor data(16) xor data(17) xor data(21) xor data(22) xor data(23);
        crcOut(30) <= crcIn(6) xor crcIn(7) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(22) xor crcIn(23) xor data(6) xor data(7) xor data(10) xor data(11) xor data(12) xor data(14) xor data(16) xor data(17) xor data(22) xor data(23);
        crcOut(31) <= crcIn(7) xor crcIn(11) xor crcIn(13) xor crcIn(14) xor crcIn(17) xor crcIn(23) xor data(7) xor data(11) xor data(13) xor data(14) xor data(17) xor data(23);
        -- vsg_on
    end procedure;

    procedure crc_step_32 (
        signal crcIn  : in std_logic_vector(31 downto 0);
        signal data   : in std_logic_vector(31 downto 0);
        signal crcOut : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- vsg_off
        crcOut(0) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(16) xor crcIn(20) xor crcIn(22) xor crcIn(23) xor crcIn(26) xor data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(6) xor data(7) xor data(8) xor data(16) xor data(20) xor data(22) xor data(23) xor data(26);
        crcOut(1) <= crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(17) xor crcIn(21) xor crcIn(23) xor crcIn(24) xor crcIn(27) xor data(1) xor data(2) xor data(3) xor data(4) xor data(5) xor data(7) xor data(8) xor data(9) xor data(17) xor data(21) xor data(23) xor data(24) xor data(27);
        crcOut(2) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(18) xor crcIn(22) xor crcIn(24) xor crcIn(25) xor crcIn(28) xor data(0) xor data(2) xor data(3) xor data(4) xor data(5) xor data(6) xor data(8) xor data(9) xor data(10) xor data(18) xor data(22) xor data(24) xor data(25) xor data(28);
        crcOut(3) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(19) xor crcIn(23) xor crcIn(25) xor crcIn(26) xor crcIn(29) xor data(1) xor data(3) xor data(4) xor data(5) xor data(6) xor data(7) xor data(9) xor data(10) xor data(11) xor data(19) xor data(23) xor data(25) xor data(26) xor data(29);
        crcOut(4) <= crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(20) xor crcIn(24) xor crcIn(26) xor crcIn(27) xor crcIn(30) xor data(2) xor data(4) xor data(5) xor data(6) xor data(7) xor data(8) xor data(10) xor data(11) xor data(12) xor data(20) xor data(24) xor data(26) xor data(27) xor data(30);
        crcOut(5) <= crcIn(0) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(21) xor crcIn(25) xor crcIn(27) xor crcIn(28) xor crcIn(31) xor data(0) xor data(3) xor data(5) xor data(6) xor data(7) xor data(8) xor data(9) xor data(11) xor data(12) xor data(13) xor data(21) xor data(25) xor data(27) xor data(28) xor data(31);
        crcOut(6) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(9) xor crcIn(10) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(20) xor crcIn(23) xor crcIn(28) xor crcIn(29) xor data(0) xor data(2) xor data(3) xor data(9) xor data(10) xor data(12) xor data(13) xor data(14) xor data(16) xor data(20) xor data(23) xor data(28) xor data(29);
        crcOut(7) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(10) xor crcIn(11) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor crcIn(17) xor crcIn(21) xor crcIn(24) xor crcIn(29) xor crcIn(30) xor data(1) xor data(3) xor data(4) xor data(10) xor data(11) xor data(13) xor data(14) xor data(15) xor data(17) xor data(21) xor data(24) xor data(29) xor data(30);
        crcOut(8) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(22) xor crcIn(25) xor crcIn(30) xor crcIn(31) xor data(0) xor data(2) xor data(4) xor data(5) xor data(11) xor data(12) xor data(14) xor data(15) xor data(16) xor data(18) xor data(22) xor data(25) xor data(30) xor data(31);
        crcOut(9) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(31) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(12) xor data(13) xor data(15) xor data(17) xor data(19) xor data(20) xor data(22) xor data(31);
        crcOut(10) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(9) xor crcIn(13) xor crcIn(14) xor crcIn(18) xor crcIn(21) xor crcIn(22) xor crcIn(26) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(9) xor data(13) xor data(14) xor data(18) xor data(21) xor data(22) xor data(26);
        crcOut(11) <= crcIn(1) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(10) xor crcIn(14) xor crcIn(15) xor crcIn(19) xor crcIn(22) xor crcIn(23) xor crcIn(27) xor data(1) xor data(3) xor data(5) xor data(6) xor data(8) xor data(10) xor data(14) xor data(15) xor data(19) xor data(22) xor data(23) xor data(27);
        crcOut(12) <= crcIn(2) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(11) xor crcIn(15) xor crcIn(16) xor crcIn(20) xor crcIn(23) xor crcIn(24) xor crcIn(28) xor data(2) xor data(4) xor data(6) xor data(7) xor data(9) xor data(11) xor data(15) xor data(16) xor data(20) xor data(23) xor data(24) xor data(28);
        crcOut(13) <= crcIn(0) xor crcIn(3) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(10) xor crcIn(12) xor crcIn(16) xor crcIn(17) xor crcIn(21) xor crcIn(24) xor crcIn(25) xor crcIn(29) xor data(0) xor data(3) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(16) xor data(17) xor data(21) xor data(24) xor data(25) xor data(29);
        crcOut(14) <= crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(11) xor crcIn(13) xor crcIn(17) xor crcIn(18) xor crcIn(22) xor crcIn(25) xor crcIn(26) xor crcIn(30) xor data(0) xor data(1) xor data(4) xor data(6) xor data(8) xor data(9) xor data(11) xor data(13) xor data(17) xor data(18) xor data(22) xor data(25) xor data(26) xor data(30);
        crcOut(15) <= crcIn(1) xor crcIn(2) xor crcIn(5) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(12) xor crcIn(14) xor crcIn(18) xor crcIn(19) xor crcIn(23) xor crcIn(26) xor crcIn(27) xor crcIn(31) xor data(1) xor data(2) xor data(5) xor data(7) xor data(9) xor data(10) xor data(12) xor data(14) xor data(18) xor data(19) xor data(23) xor data(26) xor data(27) xor data(31);
        crcOut(16) <= crcIn(1) xor crcIn(4) xor crcIn(7) xor crcIn(10) xor crcIn(11) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(19) xor crcIn(22) xor crcIn(23) xor crcIn(24) xor crcIn(26) xor crcIn(27) xor crcIn(28) xor data(1) xor data(4) xor data(7) xor data(10) xor data(11) xor data(13) xor data(15) xor data(16) xor data(19) xor data(22) xor data(23) xor data(24) xor data(26) xor data(27) xor data(28);
        crcOut(17) <= crcIn(2) xor crcIn(5) xor crcIn(8) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(20) xor crcIn(23) xor crcIn(24) xor crcIn(25) xor crcIn(27) xor crcIn(28) xor crcIn(29) xor data(2) xor data(5) xor data(8) xor data(11) xor data(12) xor data(14) xor data(16) xor data(17) xor data(20) xor data(23) xor data(24) xor data(25) xor data(27) xor data(28) xor data(29);
        crcOut(18) <= crcIn(0) xor crcIn(3) xor crcIn(6) xor crcIn(9) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(17) xor crcIn(18) xor crcIn(21) xor crcIn(24) xor crcIn(25) xor crcIn(26) xor crcIn(28) xor crcIn(29) xor crcIn(30) xor data(0) xor data(3) xor data(6) xor data(9) xor data(12) xor data(13) xor data(15) xor data(17) xor data(18) xor data(21) xor data(24) xor data(25) xor data(26) xor data(28) xor data(29) xor data(30);
        crcOut(19) <= crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(7) xor crcIn(10) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(22) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(29) xor crcIn(30) xor crcIn(31) xor data(0) xor data(1) xor data(4) xor data(7) xor data(10) xor data(13) xor data(14) xor data(16) xor data(18) xor data(19) xor data(22) xor data(25) xor data(26) xor data(27) xor data(29) xor data(30) xor data(31);
        crcOut(20) <= crcIn(0) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(11) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(17) xor crcIn(19) xor crcIn(22) xor crcIn(27) xor crcIn(28) xor crcIn(30) xor crcIn(31) xor data(0) xor data(3) xor data(4) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(15) xor data(16) xor data(17) xor data(19) xor data(22) xor data(27) xor data(28) xor data(30) xor data(31);
        crcOut(21) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(12) xor crcIn(15) xor crcIn(17) xor crcIn(18) xor crcIn(22) xor crcIn(26) xor crcIn(28) xor crcIn(29) xor crcIn(31) xor data(0) xor data(2) xor data(3) xor data(5) xor data(12) xor data(15) xor data(17) xor data(18) xor data(22) xor data(26) xor data(28) xor data(29) xor data(31);
        crcOut(22) <= crcIn(2) xor crcIn(7) xor crcIn(8) xor crcIn(13) xor crcIn(18) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(26) xor crcIn(27) xor crcIn(29) xor crcIn(30) xor data(2) xor data(7) xor data(8) xor data(13) xor data(18) xor data(19) xor data(20) xor data(22) xor data(26) xor data(27) xor data(29) xor data(30);
        crcOut(23) <= crcIn(0) xor crcIn(3) xor crcIn(8) xor crcIn(9) xor crcIn(14) xor crcIn(19) xor crcIn(20) xor crcIn(21) xor crcIn(23) xor crcIn(27) xor crcIn(28) xor crcIn(30) xor crcIn(31) xor data(0) xor data(3) xor data(8) xor data(9) xor data(14) xor data(19) xor data(20) xor data(21) xor data(23) xor data(27) xor data(28) xor data(30) xor data(31);
        crcOut(24) <= crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(15) xor crcIn(16) xor crcIn(21) xor crcIn(23) xor crcIn(24) xor crcIn(26) xor crcIn(28) xor crcIn(29) xor crcIn(31) xor data(2) xor data(3) xor data(6) xor data(7) xor data(8) xor data(9) xor data(10) xor data(15) xor data(16) xor data(21) xor data(23) xor data(24) xor data(26) xor data(28) xor data(29) xor data(31);
        crcOut(25) <= crcIn(1) xor crcIn(2) xor crcIn(6) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(17) xor crcIn(20) xor crcIn(23) xor crcIn(24) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(29) xor crcIn(30) xor data(1) xor data(2) xor data(6) xor data(9) xor data(10) xor data(11) xor data(17) xor data(20) xor data(23) xor data(24) xor data(25) xor data(26) xor data(27) xor data(29) xor data(30);
        crcOut(26) <= crcIn(2) xor crcIn(3) xor crcIn(7) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(18) xor crcIn(21) xor crcIn(24) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(28) xor crcIn(30) xor crcIn(31) xor data(2) xor data(3) xor data(7) xor data(10) xor data(11) xor data(12) xor data(18) xor data(21) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(30) xor data(31);
        crcOut(27) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(6) xor crcIn(7) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(16) xor crcIn(19) xor crcIn(20) xor crcIn(23) xor crcIn(25) xor crcIn(27) xor crcIn(28) xor crcIn(29) xor crcIn(31) xor data(0) xor data(1) xor data(2) xor data(6) xor data(7) xor data(11) xor data(12) xor data(13) xor data(16) xor data(19) xor data(20) xor data(23) xor data(25) xor data(27) xor data(28) xor data(29) xor data(31);
        crcOut(28) <= crcIn(0) xor crcIn(4) xor crcIn(6) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(21) xor crcIn(22) xor crcIn(23) xor crcIn(24) xor crcIn(28) xor crcIn(29) xor crcIn(30) xor data(0) xor data(4) xor data(6) xor data(12) xor data(13) xor data(14) xor data(16) xor data(17) xor data(21) xor data(22) xor data(23) xor data(24) xor data(28) xor data(29) xor data(30);
        crcOut(29) <= crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(7) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor crcIn(17) xor crcIn(18) xor crcIn(22) xor crcIn(23) xor crcIn(24) xor crcIn(25) xor crcIn(29) xor crcIn(30) xor crcIn(31) xor data(0) xor data(1) xor data(5) xor data(7) xor data(13) xor data(14) xor data(15) xor data(17) xor data(18) xor data(22) xor data(23) xor data(24) xor data(25) xor data(29) xor data(30) xor data(31);
        crcOut(30) <= crcIn(3) xor crcIn(4) xor crcIn(7) xor crcIn(14) xor crcIn(15) xor crcIn(18) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(24) xor crcIn(25) xor crcIn(30) xor crcIn(31) xor data(3) xor data(4) xor data(7) xor data(14) xor data(15) xor data(18) xor data(19) xor data(20) xor data(22) xor data(24) xor data(25) xor data(30) xor data(31);
        crcOut(31) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(15) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor crcIn(25) xor crcIn(31) xor data(0) xor data(1) xor data(2) xor data(3) xor data(5) xor data(6) xor data(7) xor data(15) xor data(19) xor data(21) xor data(22) xor data(25) xor data(31);
        -- vsg_on
    end procedure;

    function keep2empty (
        k : in std_logic_vector(3 downto 0)
    ) return natural is
        variable k2e : natural range 0 to 3;
    begin
        -- count of empty keep signals
        case k is
            when "1111" =>
                k2e := 0;
            when "0111" =>
                k2e := 1;
            when "0011" =>
                k2e := 2;
            when "0001" =>
                k2e := 3;
            when others =>
                k2e := 3;
        end case;

        return k2e;
    end function;

begin

    -- Mask input data
    s_axis_tdata_masked(7 downto 0)   <= s_axis_tdata(7 downto 0) when s_axis_tkeep(0) = '1' else
                                         x"00";
    s_axis_tdata_masked(15 downto 8)  <= s_axis_tdata(15 downto 8) when s_axis_tkeep(1) = '1' else
                                         x"00";
    s_axis_tdata_masked(23 downto 16) <= s_axis_tdata(23 downto 16) when s_axis_tkeep(2) = '1' else
                                         x"00";
    s_axis_tdata_masked(31 downto 24) <= s_axis_tdata(31 downto 24) when s_axis_tkeep(3) = '1' else
                                         x"00";

    -- Two last word with FCS
    FCS_PROC : process (all) is
    begin
        -- FCS selector
        case s_empty_reg is
            when 3 =>
                fcs_output_txd_0 <= not crc_state_next(0)(23 downto 0) & s_tdata_reg(7 downto 0);
                fcs_output_txd_1 <= XGMII_IDLE & XGMII_IDLE & XGMII_TERM & not crc_state_reg(0)(31 downto 24);
                fcs_output_txc_0 <= "0000";
                fcs_output_txc_1 <= "1110";
                ifg_offset       <= 3;
                extra_cycle      <= '0';
            when 2 =>
                fcs_output_txd_0 <= not crc_state_next(1)(15 downto 0) & s_tdata_reg(15 downto 0);
                fcs_output_txd_1 <= XGMII_IDLE & XGMII_TERM & not crc_state_reg(1)(31 downto 16);
                fcs_output_txc_0 <= "0000";
                fcs_output_txc_1 <= "1100";
                ifg_offset       <= 2;
                extra_cycle      <= '0';
            when 1 =>
                fcs_output_txd_0 <= not crc_state_next(2)(7 downto 0) & s_tdata_reg(23 downto 0);
                fcs_output_txd_1 <= XGMII_TERM & not crc_state_reg(2)(31 downto 8);
                fcs_output_txc_0 <= "0000";
                fcs_output_txc_1 <= "1000";
                ifg_offset       <= 1;
                extra_cycle      <= '0';
            when 0 =>
                fcs_output_txd_0 <= s_tdata_reg;
                fcs_output_txd_1 <= not crc_state_reg(3);
                fcs_output_txc_0 <= "0000";
                fcs_output_txc_1 <= "0000";
                ifg_offset       <= 4;
                extra_cycle      <= '1';
        end case;

    end process FCS_PROC;

    COMB_PROC : process (all) is

        variable cfg_ifg_tmp : natural range 0 to 255;

    begin
        state_next <= state_reg;

        reset_crc  <= '0';
        update_crc <= '0';

        frame_next           <= frame_reg;
        frame_error_next     <= frame_error_reg;
        frame_min_count_next <= frame_min_count_reg;

        ifg_count_next          <= ifg_count_reg;
        deficit_idle_count_next <= deficit_idle_count_reg;

        s_axis_tready_next <= '0';

        s_tdata_next <= s_tdata_reg;
        s_empty_next <= s_empty_reg;

        -- XGMII idle
        xgmii_txd_next <= XGMII_IDLE & XGMII_IDLE & XGMII_IDLE & XGMII_IDLE;
        xgmii_txc_next <= "1111";

        start_packet_next    <= '0';
        error_underflow_next <= '0';

        if (s_axis_tvalid = '1' and s_axis_tready = '1') then
            frame_next <= not s_axis_tlast;
        end if;

        case state_reg is
            when IDLE =>
                -- idle state - wait for data
                frame_error_next <= '0';
                -- Min frame data length 64 - 4(FCS) - 4 (at least one word arrived)
                frame_min_count_next <= 64 - 4 - 4;

                reset_crc <= '1';

                s_tdata_next <= s_axis_tdata_masked;
                s_empty_next <= keep2empty(s_axis_tkeep);

                if (s_axis_tvalid = '1' and cfg_tx_enable = '1') then
                    -- XGMII start and preamble
                    xgmii_txd_next     <= ETH_PRE & ETH_PRE & ETH_PRE & XGMII_START;
                    xgmii_txc_next     <= "0001";
                    s_axis_tready_next <= '1';
                    state_next         <= PREAMBLE;
                else
                    ifg_count_next          <= 0;
                    deficit_idle_count_next <= 0;
                    state_next              <= IDLE;
                end if;
            when PREAMBLE =>
                -- send preamble
                reset_crc <= '1';

                s_tdata_next <= s_axis_tdata_masked;
                s_empty_next <= keep2empty(s_axis_tkeep);

                xgmii_txd_next <= ETH_SFD & ETH_PRE & ETH_PRE & ETH_PRE;
                xgmii_txc_next <= "0000";

                s_axis_tready_next <= '1';
                start_packet_next  <= '1';
                state_next         <= PAYLOAD;
            when PAYLOAD =>
                -- transfer payload
                update_crc         <= '1';
                s_axis_tready_next <= '1';

                if (frame_min_count_reg > 4) then
                    frame_min_count_next <= frame_min_count_reg - 4;
                else
                    frame_min_count_next <= 0;
                end if;

                xgmii_txd_next <= s_tdata_reg;
                xgmii_txc_next <= "0000";

                s_tdata_next <= s_axis_tdata_masked;
                s_empty_next <= keep2empty(s_axis_tkeep);

                if ((not s_axis_tvalid) = '1' or s_axis_tlast = '1') then
                    s_axis_tready_next   <= frame_next;
                    frame_error_next     <= '1' when ((not s_axis_tvalid) = '1' or s_axis_tuser(0) = '1') else '0';
                    error_underflow_next <= not s_axis_tvalid;

                    -- if (ENABLE_PADDING and frame_min_count_reg > 0) then
                    if (frame_min_count_reg > 0) then
                        if (frame_min_count_reg > 4) then
                            s_empty_next <= 0;
                            state_next   <= PAD;
                        else
                            if (keep2empty(s_axis_tkeep) > 4 - frame_min_count_reg) then
                                s_empty_next <= 4 - frame_min_count_reg;
                            end if;
                            state_next <= FCS_1;
                        end if;
                    else
                        state_next <= FCS_1;
                    end if;
                else
                    state_next <= PAYLOAD;
                end if;
            when PAD =>
                -- pad frame to MIN_FRAME_LENGTH
                s_axis_tready_next <= frame_next;

                xgmii_txd_next <= s_tdata_reg;
                xgmii_txc_next <= "0000";

                s_tdata_next <= x"00000000";
                s_empty_next <= 0;

                update_crc <= '1';

                if (frame_min_count_reg > 4) then
                    frame_min_count_next <= frame_min_count_reg - 4;
                    state_next           <= PAD;
                else
                    frame_min_count_next <= 0;
                    s_empty_next         <= 4 - frame_min_count_reg;
                    state_next           <= FCS_1;
                end if;
            when FCS_1 =>
                -- last cycle
                s_axis_tready_next <= frame_next;

                xgmii_txd_next <= fcs_output_txd_0;
                xgmii_txc_next <= fcs_output_txc_0;

                update_crc <= '1';

                cfg_ifg_tmp    := to_integer(unsigned(cfg_ifg)) when unsigned(cfg_ifg) > 12 else 12;
                ifg_count_next <= cfg_ifg_tmp - ifg_offset + deficit_idle_count_reg;
                if (frame_error_reg) then
                    state_next <= ERR;
                else
                    state_next <= FCS_2;
                end if;
            when FCS_2 =>
                -- last cycle
                s_axis_tready_next <= frame_next;

                xgmii_txd_next <= fcs_output_txd_1;
                xgmii_txc_next <= fcs_output_txc_1;

                if (extra_cycle = '1') then
                    state_next <= FCS_3;
                else
                    state_next <= IFG;
                end if;
            when FCS_3 =>
                -- last cycle
                s_axis_tready_next <= frame_next;

                xgmii_txd_next <= XGMII_IDLE & XGMII_IDLE & XGMII_IDLE & XGMII_TERM;
                xgmii_txc_next <= "1111";

                if (ifg_count_next > 3) then
                    state_next <= IFG;
                else
                    deficit_idle_count_next <= ifg_count_next;
                    ifg_count_next          <= 0;
                    s_axis_tready_next      <= '1';
                    state_next              <= IDLE;
                end if;
            when ERR =>
                -- terminate packet with error
                s_axis_tready_next <= frame_next;

                -- XGMII error
                xgmii_txd_next <= XGMII_TERM & XGMII_ERROR & XGMII_ERROR & XGMII_ERROR;
                xgmii_txc_next <= "1111";

                ifg_count_next <= 12;

                state_next <= IFG;
            when IFG =>
                -- send IFG
                s_axis_tready_next <= frame_next;

                -- XGMII idle
                xgmii_txd_next <= XGMII_IDLE & XGMII_IDLE & XGMII_IDLE & XGMII_IDLE;
                xgmii_txc_next <= "1111";

                if (ifg_count_reg > 4) then
                    ifg_count_next <= ifg_count_reg - 4;
                else
                    ifg_count_next <= 0;
                end if;

                if (ifg_count_next > 3 or frame_reg = '1') then
                    state_next <= IFG;
                else
                    deficit_idle_count_next <= ifg_count_next;
                    ifg_count_next          <= 0;
                    state_next              <= IDLE;
                end if;
        end case;

    end process COMB_PROC;

    SEQ_PROC : process (clk) is
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                state_reg <= IDLE;

                frame_reg       <= '0';
                frame_error_reg <= '0';

                ifg_count_reg          <= 0;
                deficit_idle_count_reg <= 0;

                s_axis_tready_reg <= '1';

                xgmii_txd_reg <= XGMII_IDLE & XGMII_IDLE & XGMII_IDLE & XGMII_IDLE;
                xgmii_txc_reg <= "1111";

                start_packet_reg    <= '0';
                error_underflow_reg <= '0';
            else
                state_reg <= state_next;

                frame_reg           <= frame_next;
                frame_error_reg     <= frame_error_next;
                frame_min_count_reg <= frame_min_count_next;

                ifg_count_reg          <= ifg_count_next;
                deficit_idle_count_reg <= deficit_idle_count_next;

                s_tdata_reg <= s_tdata_next;
                s_empty_reg <= s_empty_next;

                s_axis_tready_reg <= s_axis_tready_next;

                crc_state_reg(0) <= crc_state_next(0);
                crc_state_reg(1) <= crc_state_next(1);
                crc_state_reg(2) <= crc_state_next(2);

                if (update_crc) then
                    crc_state_reg(3) <= crc_state_next(3);
                end if;

                if (reset_crc) then
                    crc_state_reg(3) <= (others => '1');
                end if;

                xgmii_txd_reg <= xgmii_txd_next;
                xgmii_txc_reg <= xgmii_txc_next;

                start_packet_reg    <= start_packet_next;
                error_underflow_reg <= error_underflow_next;
            end if;
        end if;

    end process SEQ_PROC;

    crc_step_8(crc_state_reg(3), s_tdata_reg(7 downto 0), crc_state_next(0));
    crc_step_16(crc_state_reg(3), s_tdata_reg(15 downto 0), crc_state_next(1));
    crc_step_24(crc_state_reg(3), s_tdata_reg(23 downto 0), crc_state_next(2));
    crc_step_32(crc_state_reg(3), s_tdata_reg(31 downto 0), crc_state_next(3));

    s_axis_tready <= s_axis_tready_reg;

    xgmii_txd <= xgmii_txd_reg;
    xgmii_txc <= xgmii_txc_reg;

    start_packet    <= start_packet_reg;
    error_underflow <= error_underflow_reg;

end architecture rtl;
