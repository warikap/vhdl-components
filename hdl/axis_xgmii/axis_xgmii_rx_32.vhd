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

entity axis_xgmii_rx_32 is
    port (
        clk : in    std_logic;
        rst : in    std_logic;

        xgmii_rxd : in    std_logic_vector(31 downto 0);
        xgmii_rxc : in    std_logic_vector(3 downto 0);

        m_axis_tdata  : out   std_logic_vector(31 downto 0);
        m_axis_tkeep  : out   std_logic_vector(3 downto 0);
        m_axis_tvalid : out   std_logic;
        m_axis_tlast  : out   std_logic;
        m_axis_tuser  : out   std_logic_vector(0 downto 0);

        cfg_rx_enable : in    std_logic;

        start_packet    : out   std_logic;
        error_bad_frame : out   std_logic;
        error_bad_fcs   : out   std_logic
    );
end entity axis_xgmii_rx_32;

architecture rtl of axis_xgmii_rx_32 is

    constant XGMII_IDLE  : std_logic_vector(7 downto 0) := x"07";
    constant XGMII_START : std_logic_vector(7 downto 0) := x"FB";
    constant XGMII_TERM  : std_logic_vector(7 downto 0) := x"FD";
    constant XGMII_ERROR : std_logic_vector(7 downto 0) := x"FE";

    type fsm_state_t is (IDLE, PREAMBLE, PAYLOAD, LAST);

    signal state_reg  : fsm_state_t;
    signal state_next : fsm_state_t;

    signal reset_crc      : std_logic;
    signal crc_state      : std_logic_vector(31 downto 0);
    signal crc_next       : std_logic_vector(31 downto 0);
    signal crc_valid      : std_logic_vector(3 downto 0);
    signal crc_valid_save : std_logic_vector(3 downto 0);

    signal framing_error_reg : std_logic;
    signal term_present_reg  : std_logic;
    signal term_lane_reg     : natural range 3 downto 0;
    signal term_lane_d0_reg  : natural range 3 downto 0;

    signal xgmii_rxd_d0 : std_logic_vector(31 downto 0);
    signal xgmii_rxd_d1 : std_logic_vector(31 downto 0);
    signal xgmii_rxd_d2 : std_logic_vector(31 downto 0);

    signal xgmii_start_d0 : std_logic;
    signal xgmii_start_d1 : std_logic;
    signal xgmii_start_d2 : std_logic;

    signal m_axis_tdata_reg,    m_axis_tdata_next  : std_logic_vector(31 downto 0);
    signal m_axis_tkeep_reg,    m_axis_tkeep_next  : std_logic_vector(3 downto 0);
    signal m_axis_tvalid_reg,   m_axis_tvalid_next : std_logic;
    signal m_axis_tlast_reg,    m_axis_tlast_next  : std_logic;
    signal m_axis_tuser_reg,    m_axis_tuser_next  : std_logic_vector(0 downto 0);

    signal start_packet_reg,    start_packet_next    : std_logic;
    signal error_bad_frame_reg, error_bad_frame_next : std_logic;
    signal error_bad_fcs_reg,   error_bad_fcs_next   : std_logic;

    procedure crc_step (
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

begin

    COMB_PROC : process (all) is
    begin
        state_next <= state_reg;

        reset_crc <= '0';

        m_axis_tdata_next  <= xgmii_rxd_d2;
        m_axis_tkeep_next  <= (others => '1');
        m_axis_tvalid_next <= '0';
        m_axis_tlast_next  <= '0';
        m_axis_tuser_next  <= (others => '0');

        start_packet_next    <= '0';
        error_bad_frame_next <= '0';
        error_bad_fcs_next   <= '0';

        case state_reg is
            when IDLE =>
                reset_crc <= '1';
                if (xgmii_start_d2 = '1' and cfg_rx_enable = '1') then
                    -- start condition
                    if (framing_error_reg = '1') then
                        -- control or error characters in first data word
                        state_next <= IDLE;
                    else
                        reset_crc  <= '0';
                        state_next <= PREAMBLE;
                    end if;
                end if;
            when PREAMBLE =>
                -- drop preamble
                if (framing_error_reg = '1') then
                    -- control or error characters in second data word
                    state_next <= IDLE;
                else
                    start_packet_next <= '1';
                    state_next        <= PAYLOAD;
                end if;
            when PAYLOAD =>
                -- read payload
                m_axis_tvalid_next <= '1';

                if (framing_error_reg = '1') then
                    -- control or error characters in packet
                    m_axis_tlast_next    <= '1';
                    m_axis_tuser_next(0) <= '1';
                    error_bad_frame_next <= '1';
                    reset_crc            <= '1';
                    state_next           <= IDLE;
                elsif (term_present_reg = '1') then
                    reset_crc <= '1';
                    if (term_lane_reg = 0) then
                        -- end this cycle
                        m_axis_tlast_next <= '1';
                        if (term_lane_reg = 0 and crc_valid_save(3) = '1') then
                        -- CRC valid
                        else
                            m_axis_tuser_next(0) <= '1';
                            error_bad_frame_next <= '1';
                            error_bad_fcs_next   <= '1';
                        end if;
                        state_next <= IDLE;
                    else
                        -- need extra cycle
                        state_next <= LAST;
                    end if;
                else
                    state_next <= PAYLOAD;
                end if;
            when LAST =>
                -- last cycle of packet
                m_axis_tkeep_next  <= "1111" srl (4 - term_lane_d0_reg);
                m_axis_tvalid_next <= '1';
                m_axis_tlast_next  <= '1';

                reset_crc <= '1';

                if ((term_lane_d0_reg = 1 and crc_valid_save(0) = '1') or
                    (term_lane_d0_reg = 2 and crc_valid_save(1) = '1') or
                    (term_lane_d0_reg = 3 and crc_valid_save(2) = '1')) then
                -- CRC valid
                else
                    m_axis_tuser_next(0) <= '1';
                    error_bad_frame_next <= '1';
                    error_bad_fcs_next   <= '1';
                end if;

                state_next <= IDLE;
        end case;

    end process COMB_PROC;

    SEQ_PROC : process (clk) is
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                state_reg <= IDLE;

                m_axis_tvalid_reg <= '0';

                start_packet_reg    <= '0';
                error_bad_frame_reg <= '0';
                error_bad_fcs_reg   <= '0';

                framing_error_reg <= '0';

                xgmii_start_d0 <= '0';
                xgmii_start_d1 <= '0';
                xgmii_start_d2 <= '0';

                crc_state <= (others => '1');
            else
                state_reg <= state_next;

                m_axis_tdata_reg  <= m_axis_tdata_next;
                m_axis_tkeep_reg  <= m_axis_tkeep_next;
                m_axis_tvalid_reg <= m_axis_tvalid_next;
                m_axis_tlast_reg  <= m_axis_tlast_next;
                m_axis_tuser_reg  <= m_axis_tuser_next;

                start_packet_reg    <= start_packet_next;
                error_bad_frame_reg <= error_bad_frame_next;
                error_bad_fcs_reg   <= error_bad_fcs_next;

                term_lane_reg     <= 0;
                term_present_reg  <= '0';
                framing_error_reg <= '1' when xgmii_rxc /= x"0" else '0';

                for i in 3 downto 0 loop

                    if (xgmii_rxc(i) = '1' and xgmii_rxd((i + 1) * 8 - 1 downto i * 8) = XGMII_TERM) then
                        term_lane_reg     <= i;
                        term_present_reg  <= '1';
                        framing_error_reg <= '1' when (xgmii_rxc and ("1111" srl (4 - i))) /= x"0" else '0';
                    end if;

                end loop;

                term_lane_d0_reg <= term_lane_reg;

                if (reset_crc = '1') then
                    crc_state <= (others => '1');
                else
                    crc_state <= crc_next;
                end if;

                crc_valid_save <= crc_valid;

                xgmii_rxd_d0(7 downto 0)   <= x"00" when xgmii_rxc(0) = '1' else xgmii_rxd(7 downto 0);
                xgmii_rxd_d0(15 downto 8)  <= x"00" when xgmii_rxc(1) = '1' else xgmii_rxd(15 downto 8);
                xgmii_rxd_d0(23 downto 16) <= x"00" when xgmii_rxc(2) = '1' else xgmii_rxd(23 downto 16);
                xgmii_rxd_d0(31 downto 24) <= x"00" when xgmii_rxc(3) = '1' else xgmii_rxd(31 downto 24);

                xgmii_rxd_d1 <= xgmii_rxd_d0;
                xgmii_rxd_d2 <= xgmii_rxd_d1;

                xgmii_start_d0 <= '1' when xgmii_rxc(0) = '1' and xgmii_rxd(7 downto 0) = XGMII_START else '0';
                xgmii_start_d1 <= xgmii_start_d0;
                xgmii_start_d2 <= xgmii_start_d1;
            end if;
        end if;

    end process SEQ_PROC;

    crc_step(crc_state, xgmii_rxd_d0, crc_next);
    crc_valid(3) <= '1' when crc_next = not x"2144df1c" else '0';
    crc_valid(2) <= '1' when crc_next = not x"c622f71d" else '0';
    crc_valid(1) <= '1' when crc_next = not x"b1c2a1a3" else '0';
    crc_valid(0) <= '1' when crc_next = not x"9d6cdf7e" else '0';

    m_axis_tdata  <= m_axis_tdata_reg;
    m_axis_tkeep  <= m_axis_tkeep_reg;
    m_axis_tvalid <= m_axis_tvalid_reg;
    m_axis_tlast  <= m_axis_tlast_reg;
    m_axis_tuser  <= m_axis_tuser_reg;

    start_packet    <= start_packet_reg;
    error_bad_frame <= error_bad_frame_reg;
    error_bad_fcs   <= error_bad_fcs_reg;

end architecture rtl;
