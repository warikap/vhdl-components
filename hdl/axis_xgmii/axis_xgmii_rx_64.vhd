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

entity axis_xgmii_rx_64 is
    port (
        clk : in    std_logic;
        rst : in    std_logic;

        xgmii_rxd : in    std_logic_vector(63 downto 0);
        xgmii_rxc : in    std_logic_vector(7 downto 0);

        m_axis_tdata  : out   std_logic_vector(63 downto 0);
        m_axis_tkeep  : out   std_logic_vector(7 downto 0);
        m_axis_tvalid : out   std_logic;
        m_axis_tlast  : out   std_logic;
        m_axis_tuser  : out   std_logic_vector(0 downto 0);

        cfg_rx_enable : in    std_logic;

        start_packet    : out   std_logic_vector(1 downto 0);
        error_bad_frame : out   std_logic;
        error_bad_fcs   : out   std_logic
    );
end entity axis_xgmii_rx_64;

architecture rtl of axis_xgmii_rx_64 is

    constant XGMII_IDLE  : std_logic_vector(7 downto 0) := x"07";
    constant XGMII_START : std_logic_vector(7 downto 0) := x"FB";
    constant XGMII_TERM  : std_logic_vector(7 downto 0) := x"FD";
    constant XGMII_ERROR : std_logic_vector(7 downto 0) := x"FE";

    type fsm_state_t is (IDLE, PAYLOAD, LAST);

    signal state_reg  : fsm_state_t;
    signal state_next : fsm_state_t;

    signal reset_crc      : std_logic;
    signal crc_state      : std_logic_vector(31 downto 0);
    signal crc_next       : std_logic_vector(31 downto 0);
    signal crc_valid      : std_logic_vector(7 downto 0);
    signal crc_valid_save : std_logic_vector(7 downto 0);

    signal lanes_swapped : std_logic;
    signal swap_rxd      : std_logic_vector(31 downto 0);
    signal swap_rxc      : std_logic_vector(3 downto 0);
    signal swap_rxc_term : std_logic_vector(3 downto 0);

    signal xgmii_rxd_masked     : std_logic_vector(63 downto 0);
    signal xgmii_term_lane      : std_logic_vector(7 downto 0);
    signal term_lane_reg        : natural range 7 downto 0;
    signal term_lane_d0_reg     : natural range 7 downto 0;
    signal term_present_reg     : std_logic;
    signal framing_error_reg    : std_logic;
    signal framing_error_d0_reg : std_logic;

    signal xgmii_rxd_d0 : std_logic_vector(63 downto 0);
    signal xgmii_rxd_d1 : std_logic_vector(63 downto 0);

    signal xgmii_rxc_d0 : std_logic_vector(7 downto 0);

    signal xgmii_start_swap : std_logic;
    signal xgmii_start_d0   : std_logic;
    signal xgmii_start_d1   : std_logic;

    signal m_axis_tdata_reg,    m_axis_tdata_next  : std_logic_vector(63 downto 0);
    signal m_axis_tkeep_reg,    m_axis_tkeep_next  : std_logic_vector(7 downto 0);
    signal m_axis_tvalid_reg,   m_axis_tvalid_next : std_logic;
    signal m_axis_tlast_reg,    m_axis_tlast_next  : std_logic;
    signal m_axis_tuser_reg,    m_axis_tuser_next  : std_logic_vector(0 downto 0);

    signal start_packet_reg : std_logic_vector(1 downto 0);

    signal error_bad_frame_reg, error_bad_frame_next : std_logic;
    signal error_bad_fcs_reg,   error_bad_fcs_next   : std_logic;

    procedure crc_step (
        signal crcIn  : in std_logic_vector(31 downto 0);
        signal data   : in std_logic_vector(63 downto 0);
        signal crcOut : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- vsg_off
        crcOut(0) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(27) xor crcIn(30) xor data(1) xor data(3) xor data(4) xor data(6) xor data(9) xor data(10) xor data(11) xor data(14) xor data(16) xor data(17) xor data(19) xor data(20) xor data(27) xor data(30) xor data(32) xor data(33) xor data(34) xor data(35) xor data(36) xor data(38) xor data(39) xor data(40) xor data(48) xor data(52) xor data(54) xor data(55) xor data(58);
        crcOut(1) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(15) xor crcIn(17) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(28) xor crcIn(31) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(10) xor data(11) xor data(12) xor data(15) xor data(17) xor data(18) xor data(20) xor data(21) xor data(28) xor data(31) xor data(33) xor data(34) xor data(35) xor data(36) xor data(37) xor data(39) xor data(40) xor data(41) xor data(49) xor data(53) xor data(55) xor data(56) xor data(59);
        crcOut(2) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor crcIn(29) xor data(0) xor data(1) xor data(3) xor data(5) xor data(6) xor data(8) xor data(11) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19) xor data(21) xor data(22) xor data(29) xor data(32) xor data(34) xor data(35) xor data(36) xor data(37) xor data(38) xor data(40) xor data(41) xor data(42) xor data(50) xor data(54) xor data(56) xor data(57) xor data(60);
        crcOut(3) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(23) xor crcIn(30) xor data(0) xor data(1) xor data(2) xor data(4) xor data(6) xor data(7) xor data(9) xor data(12) xor data(13) xor data(14) xor data(17) xor data(19) xor data(20) xor data(22) xor data(23) xor data(30) xor data(33) xor data(35) xor data(36) xor data(37) xor data(38) xor data(39) xor data(41) xor data(42) xor data(43) xor data(51) xor data(55) xor data(57) xor data(58) xor data(61);
        crcOut(4) <= crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(10) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(23) xor crcIn(24) xor crcIn(31) xor data(0) xor data(1) xor data(2) xor data(3) xor data(5) xor data(7) xor data(8) xor data(10) xor data(13) xor data(14) xor data(15) xor data(18) xor data(20) xor data(21) xor data(23) xor data(24) xor data(31) xor data(34) xor data(36) xor data(37) xor data(38) xor data(39) xor data(40) xor data(42) xor data(43) xor data(44) xor data(52) xor data(56) xor data(58) xor data(59) xor data(62);
        crcOut(5) <= crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(11) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor crcIn(24) xor crcIn(25) xor data(1) xor data(2) xor data(3) xor data(4) xor data(6) xor data(8) xor data(9) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(21) xor data(22) xor data(24) xor data(25) xor data(32) xor data(35) xor data(37) xor data(38) xor data(39) xor data(40) xor data(41) xor data(43) xor data(44) xor data(45) xor data(53) xor data(57) xor data(59) xor data(60) xor data(63);
        crcOut(6) <= crcIn(1) xor crcIn(2) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor crcIn(19) xor crcIn(22) xor crcIn(23) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(30) xor data(1) xor data(2) xor data(5) xor data(6) xor data(7) xor data(11) xor data(12) xor data(14) xor data(15) xor data(19) xor data(22) xor data(23) xor data(25) xor data(26) xor data(27) xor data(30) xor data(32) xor data(34) xor data(35) xor data(41) xor data(42) xor data(44) xor data(45) xor data(46) xor data(48) xor data(52) xor data(55) xor data(60) xor data(61);
        crcOut(7) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(20) xor crcIn(23) xor crcIn(24) xor crcIn(26) xor crcIn(27) xor crcIn(28) xor crcIn(31) xor data(0) xor data(2) xor data(3) xor data(6) xor data(7) xor data(8) xor data(12) xor data(13) xor data(15) xor data(16) xor data(20) xor data(23) xor data(24) xor data(26) xor data(27) xor data(28) xor data(31) xor data(33) xor data(35) xor data(36) xor data(42) xor data(43) xor data(45) xor data(46) xor data(47) xor data(49) xor data(53) xor data(56) xor data(61) xor data(62);
        crcOut(8) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(21) xor crcIn(24) xor crcIn(25) xor crcIn(27) xor crcIn(28) xor crcIn(29) xor data(1) xor data(3) xor data(4) xor data(7) xor data(8) xor data(9) xor data(13) xor data(14) xor data(16) xor data(17) xor data(21) xor data(24) xor data(25) xor data(27) xor data(28) xor data(29) xor data(32) xor data(34) xor data(36) xor data(37) xor data(43) xor data(44) xor data(46) xor data(47) xor data(48) xor data(50) xor data(54) xor data(57) xor data(62) xor data(63);
        crcOut(9) <= crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(11) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(28) xor crcIn(29) xor data(1) xor data(2) xor data(3) xor data(5) xor data(6) xor data(8) xor data(11) xor data(15) xor data(16) xor data(18) xor data(19) xor data(20) xor data(22) xor data(25) xor data(26) xor data(27) xor data(28) xor data(29) xor data(32) xor data(34) xor data(36) xor data(37) xor data(39) xor data(40) xor data(44) xor data(45) xor data(47) xor data(49) xor data(51) xor data(52) xor data(54) xor data(63);
        crcOut(10) <= crcIn(1) xor crcIn(2) xor crcIn(7) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(21) xor crcIn(23) xor crcIn(26) xor crcIn(28) xor crcIn(29) xor data(1) xor data(2) xor data(7) xor data(10) xor data(11) xor data(12) xor data(14) xor data(21) xor data(23) xor data(26) xor data(28) xor data(29) xor data(32) xor data(34) xor data(36) xor data(37) xor data(39) xor data(41) xor data(45) xor data(46) xor data(50) xor data(53) xor data(54) xor data(58);
        crcOut(11) <= crcIn(2) xor crcIn(3) xor crcIn(8) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(22) xor crcIn(24) xor crcIn(27) xor crcIn(29) xor crcIn(30) xor data(2) xor data(3) xor data(8) xor data(11) xor data(12) xor data(13) xor data(15) xor data(22) xor data(24) xor data(27) xor data(29) xor data(30) xor data(33) xor data(35) xor data(37) xor data(38) xor data(40) xor data(42) xor data(46) xor data(47) xor data(51) xor data(54) xor data(55) xor data(59);
        crcOut(12) <= crcIn(3) xor crcIn(4) xor crcIn(9) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(23) xor crcIn(25) xor crcIn(28) xor crcIn(30) xor crcIn(31) xor data(3) xor data(4) xor data(9) xor data(12) xor data(13) xor data(14) xor data(16) xor data(23) xor data(25) xor data(28) xor data(30) xor data(31) xor data(34) xor data(36) xor data(38) xor data(39) xor data(41) xor data(43) xor data(47) xor data(48) xor data(52) xor data(55) xor data(56) xor data(60);
        crcOut(13) <= crcIn(4) xor crcIn(5) xor crcIn(10) xor crcIn(13) xor crcIn(14) xor crcIn(15) xor crcIn(17) xor crcIn(24) xor crcIn(26) xor crcIn(29) xor crcIn(31) xor data(4) xor data(5) xor data(10) xor data(13) xor data(14) xor data(15) xor data(17) xor data(24) xor data(26) xor data(29) xor data(31) xor data(32) xor data(35) xor data(37) xor data(39) xor data(40) xor data(42) xor data(44) xor data(48) xor data(49) xor data(53) xor data(56) xor data(57) xor data(61);
        crcOut(14) <= crcIn(5) xor crcIn(6) xor crcIn(11) xor crcIn(14) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(25) xor crcIn(27) xor crcIn(30) xor data(5) xor data(6) xor data(11) xor data(14) xor data(15) xor data(16) xor data(18) xor data(25) xor data(27) xor data(30) xor data(32) xor data(33) xor data(36) xor data(38) xor data(40) xor data(41) xor data(43) xor data(45) xor data(49) xor data(50) xor data(54) xor data(57) xor data(58) xor data(62);
        crcOut(15) <= crcIn(6) xor crcIn(7) xor crcIn(12) xor crcIn(15) xor crcIn(16) xor crcIn(17) xor crcIn(19) xor crcIn(26) xor crcIn(28) xor crcIn(31) xor data(6) xor data(7) xor data(12) xor data(15) xor data(16) xor data(17) xor data(19) xor data(26) xor data(28) xor data(31) xor data(33) xor data(34) xor data(37) xor data(39) xor data(41) xor data(42) xor data(44) xor data(46) xor data(50) xor data(51) xor data(55) xor data(58) xor data(59) xor data(63);
        crcOut(16) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(13) xor crcIn(14) xor crcIn(18) xor crcIn(19) xor crcIn(29) xor crcIn(30) xor data(1) xor data(3) xor data(4) xor data(6) xor data(7) xor data(8) xor data(9) xor data(10) xor data(11) xor data(13) xor data(14) xor data(18) xor data(19) xor data(29) xor data(30) xor data(33) xor data(36) xor data(39) xor data(42) xor data(43) xor data(45) xor data(47) xor data(48) xor data(51) xor data(54) xor data(55) xor data(56) xor data(58) xor data(59) xor data(60);
        crcOut(17) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(14) xor crcIn(15) xor crcIn(19) xor crcIn(20) xor crcIn(30) xor crcIn(31) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(9) xor data(10) xor data(11) xor data(12) xor data(14) xor data(15) xor data(19) xor data(20) xor data(30) xor data(31) xor data(34) xor data(37) xor data(40) xor data(43) xor data(44) xor data(46) xor data(48) xor data(49) xor data(52) xor data(55) xor data(56) xor data(57) xor data(59) xor data(60) xor data(61);
        crcOut(18) <= crcIn(1) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(20) xor crcIn(21) xor crcIn(31) xor data(1) xor data(3) xor data(5) xor data(6) xor data(8) xor data(9) xor data(10) xor data(11) xor data(12) xor data(13) xor data(15) xor data(16) xor data(20) xor data(21) xor data(31) xor data(32) xor data(35) xor data(38) xor data(41) xor data(44) xor data(45) xor data(47) xor data(49) xor data(50) xor data(53) xor data(56) xor data(57) xor data(58) xor data(60) xor data(61) xor data(62);
        crcOut(19) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(21) xor crcIn(22) xor data(0) xor data(2) xor data(4) xor data(6) xor data(7) xor data(9) xor data(10) xor data(11) xor data(12) xor data(13) xor data(14) xor data(16) xor data(17) xor data(21) xor data(22) xor data(32) xor data(33) xor data(36) xor data(39) xor data(42) xor data(45) xor data(46) xor data(48) xor data(50) xor data(51) xor data(54) xor data(57) xor data(58) xor data(59) xor data(61) xor data(62) xor data(63);
        crcOut(20) <= crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(12) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(23) xor crcIn(27) xor crcIn(30) xor data(4) xor data(5) xor data(6) xor data(7) xor data(8) xor data(9) xor data(12) xor data(13) xor data(15) xor data(16) xor data(18) xor data(19) xor data(20) xor data(22) xor data(23) xor data(27) xor data(30) xor data(32) xor data(35) xor data(36) xor data(37) xor data(38) xor data(39) xor data(43) xor data(46) xor data(47) xor data(48) xor data(49) xor data(51) xor data(54) xor data(59) xor data(60) xor data(62) xor data(63);
        crcOut(21) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(8) xor crcIn(11) xor crcIn(13) xor crcIn(21) xor crcIn(23) xor crcIn(24) xor crcIn(27) xor crcIn(28) xor crcIn(30) xor crcIn(31) xor data(0) xor data(1) xor data(3) xor data(4) xor data(5) xor data(7) xor data(8) xor data(11) xor data(13) xor data(21) xor data(23) xor data(24) xor data(27) xor data(28) xor data(30) xor data(31) xor data(32) xor data(34) xor data(35) xor data(37) xor data(44) xor data(47) xor data(49) xor data(50) xor data(54) xor data(58) xor data(60) xor data(61) xor data(63);
        crcOut(22) <= crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(8) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(16) xor crcIn(17) xor crcIn(19) xor crcIn(20) xor crcIn(22) xor crcIn(24) xor crcIn(25) xor crcIn(27) xor crcIn(28) xor crcIn(29) xor crcIn(30) xor crcIn(31) xor data(2) xor data(3) xor data(5) xor data(8) xor data(10) xor data(11) xor data(12) xor data(16) xor data(17) xor data(19) xor data(20) xor data(22) xor data(24) xor data(25) xor data(27) xor data(28) xor data(29) xor data(30) xor data(31) xor data(34) xor data(39) xor data(40) xor data(45) xor data(50) xor data(51) xor data(52) xor data(54) xor data(58) xor data(59) xor data(61) xor data(62);
        crcOut(23) <= crcIn(0) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(17) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(23) xor crcIn(25) xor crcIn(26) xor crcIn(28) xor crcIn(29) xor crcIn(30) xor crcIn(31) xor data(0) xor data(3) xor data(4) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(17) xor data(18) xor data(20) xor data(21) xor data(23) xor data(25) xor data(26) xor data(28) xor data(29) xor data(30) xor data(31) xor data(32) xor data(35) xor data(40) xor data(41) xor data(46) xor data(51) xor data(52) xor data(53) xor data(55) xor data(59) xor data(60) xor data(62) xor data(63);
        crcOut(24) <= crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(16) xor crcIn(17) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(22) xor crcIn(24) xor crcIn(26) xor crcIn(29) xor crcIn(31) xor data(3) xor data(5) xor data(6) xor data(7) xor data(9) xor data(11) xor data(12) xor data(13) xor data(16) xor data(17) xor data(18) xor data(20) xor data(21) xor data(22) xor data(24) xor data(26) xor data(29) xor data(31) xor data(34) xor data(35) xor data(38) xor data(39) xor data(40) xor data(41) xor data(42) xor data(47) xor data(48) xor data(53) xor data(55) xor data(56) xor data(58) xor data(60) xor data(61) xor data(63);
        crcOut(25) <= crcIn(1) xor crcIn(3) xor crcIn(7) xor crcIn(8) xor crcIn(9) xor crcIn(11) xor crcIn(12) xor crcIn(13) xor crcIn(16) xor crcIn(18) xor crcIn(20) xor crcIn(21) xor crcIn(22) xor crcIn(23) xor crcIn(25) xor data(1) xor data(3) xor data(7) xor data(8) xor data(9) xor data(11) xor data(12) xor data(13) xor data(16) xor data(18) xor data(20) xor data(21) xor data(22) xor data(23) xor data(25) xor data(33) xor data(34) xor data(38) xor data(41) xor data(42) xor data(43) xor data(49) xor data(52) xor data(55) xor data(56) xor data(57) xor data(58) xor data(59) xor data(61) xor data(62);
        crcOut(26) <= crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(17) xor crcIn(19) xor crcIn(21) xor crcIn(22) xor crcIn(23) xor crcIn(24) xor crcIn(26) xor data(0) xor data(2) xor data(4) xor data(8) xor data(9) xor data(10) xor data(12) xor data(13) xor data(14) xor data(17) xor data(19) xor data(21) xor data(22) xor data(23) xor data(24) xor data(26) xor data(34) xor data(35) xor data(39) xor data(42) xor data(43) xor data(44) xor data(50) xor data(53) xor data(56) xor data(57) xor data(58) xor data(59) xor data(60) xor data(62) xor data(63);
        crcOut(27) <= crcIn(0) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(17) xor crcIn(18) xor crcIn(19) xor crcIn(22) xor crcIn(23) xor crcIn(24) xor crcIn(25) xor crcIn(30) xor data(0) xor data(4) xor data(5) xor data(6) xor data(13) xor data(15) xor data(16) xor data(17) xor data(18) xor data(19) xor data(22) xor data(23) xor data(24) xor data(25) xor data(30) xor data(32) xor data(33) xor data(34) xor data(38) xor data(39) xor data(43) xor data(44) xor data(45) xor data(48) xor data(51) xor data(52) xor data(55) xor data(57) xor data(59) xor data(60) xor data(61) xor data(63);
        crcOut(28) <= crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(9) xor crcIn(10) xor crcIn(11) xor crcIn(18) xor crcIn(23) xor crcIn(24) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(30) xor crcIn(31) xor data(3) xor data(4) xor data(5) xor data(7) xor data(9) xor data(10) xor data(11) xor data(18) xor data(23) xor data(24) xor data(25) xor data(26) xor data(27) xor data(30) xor data(31) xor data(32) xor data(36) xor data(38) xor data(44) xor data(45) xor data(46) xor data(48) xor data(49) xor data(53) xor data(54) xor data(55) xor data(56) xor data(60) xor data(61) xor data(62);
        crcOut(29) <= crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(8) xor crcIn(10) xor crcIn(11) xor crcIn(12) xor crcIn(19) xor crcIn(24) xor crcIn(25) xor crcIn(26) xor crcIn(27) xor crcIn(28) xor crcIn(31) xor data(4) xor data(5) xor data(6) xor data(8) xor data(10) xor data(11) xor data(12) xor data(19) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(31) xor data(32) xor data(33) xor data(37) xor data(39) xor data(45) xor data(46) xor data(47) xor data(49) xor data(50) xor data(54) xor data(55) xor data(56) xor data(57) xor data(61) xor data(62) xor data(63);
        crcOut(30) <= crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor crcIn(10) xor crcIn(12) xor crcIn(13) xor crcIn(14) xor crcIn(16) xor crcIn(17) xor crcIn(19) xor crcIn(25) xor crcIn(26) xor crcIn(28) xor crcIn(29) xor crcIn(30) xor data(0) xor data(1) xor data(3) xor data(4) xor data(5) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(16) xor data(17) xor data(19) xor data(25) xor data(26) xor data(28) xor data(29) xor data(30) xor data(35) xor data(36) xor data(39) xor data(46) xor data(47) xor data(50) xor data(51) xor data(52) xor data(54) xor data(56) xor data(57) xor data(62) xor data(63);
        crcOut(31) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(8) xor crcIn(9) xor crcIn(10) xor crcIn(13) xor crcIn(15) xor crcIn(16) xor crcIn(18) xor crcIn(19) xor crcIn(26) xor crcIn(29) xor crcIn(31) xor data(0) xor data(2) xor data(3) xor data(5) xor data(8) xor data(9) xor data(10) xor data(13) xor data(15) xor data(16) xor data(18) xor data(19) xor data(26) xor data(29) xor data(31) xor data(32) xor data(33) xor data(34) xor data(35) xor data(37) xor data(38) xor data(39) xor data(47) xor data(51) xor data(53) xor data(54) xor data(57) xor data(63);
        -- vsg_on
    end procedure;

begin

    MASK_INPUT : for i in 0 to 7 generate
        xgmii_rxd_masked((i+1)*8-1 downto i*8) <= x"00" when xgmii_rxc(i) = '1' else xgmii_rxd((i+1)*8-1 downto i*8);

        xgmii_term_lane(i) <= '1' when xgmii_rxc(i) = '1' and xgmii_rxd((i+1)*8-1 downto i*8) = XGMII_TERM else '0';
    end generate MASK_INPUT;

    COMB_PROC : process (all) is
    begin
        state_next <= state_reg;

        reset_crc <= '0';

        m_axis_tdata_next  <= xgmii_rxd_d1;
        m_axis_tkeep_next  <= (others => '1');
        m_axis_tvalid_next <= '0';
        m_axis_tlast_next  <= '0';
        m_axis_tuser_next  <= (others => '0');

        error_bad_frame_next <= '0';
        error_bad_fcs_next   <= '0';

        case state_reg is
            when IDLE =>
                -- idle state - wait for packet
                reset_crc <= '1';

                if (xgmii_start_d1 = '1' and cfg_rx_enable = '1') then
                    -- start condition
                    reset_crc  <= '0';
                    state_next <= PAYLOAD;
                else
                    state_next <= IDLE;
                end if;
            when PAYLOAD =>
                -- read payload
                m_axis_tdata_next    <= xgmii_rxd_d1;
                m_axis_tkeep_next    <= x"FF";
                m_axis_tvalid_next   <= '1';
                m_axis_tlast_next    <= '0';
                m_axis_tuser_next(0) <= '0';

                if (framing_error_reg = '1' or framing_error_d0_reg = '1') then
                    -- control or error characters in packet
                    m_axis_tlast_next    <= '1';
                    m_axis_tuser_next(0) <= '1';
                    error_bad_frame_next <= '1';
                    reset_crc            <= '1';
                    state_next           <= IDLE;
                elsif (term_present_reg = '1') then
                    reset_crc <= '1';
                    if (term_lane_reg <= 4) then
                        -- end this cycle
                        m_axis_tkeep_next <= x"FF" srl (8-4-term_lane_reg);
                        m_axis_tlast_next <= '1';
                        if ((term_lane_reg = 0 and crc_valid_save(7) = '1') or
                            (term_lane_reg = 1 and crc_valid(0) = '1') or
                            (term_lane_reg = 2 and crc_valid(1) = '1') or
                            (term_lane_reg = 3 and crc_valid(2) = '1') or
                            (term_lane_reg = 4 and crc_valid(3) = '1')) then
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
                m_axis_tdata_next    <= xgmii_rxd_d1;
                m_axis_tkeep_next    <= x"FF" srl (8+4-term_lane_d0_reg);
                m_axis_tvalid_next   <= '1';
                m_axis_tlast_next    <= '1';
                m_axis_tuser_next(0) <= '0';

                reset_crc <= '1';

                if ((term_lane_d0_reg = 5 and crc_valid_save(4) = '1') or
                    (term_lane_d0_reg = 6 and crc_valid_save(5) = '1') or
                    (term_lane_d0_reg = 7 and crc_valid_save(6) = '1')) then
                -- CRC valid
                else
                    m_axis_tuser_next(0) <= '1';
                    error_bad_frame_next <= '1';
                    error_bad_fcs_next   <= '1';
                end if;

                if (xgmii_start_d1 = '1' and cfg_rx_enable = '1') then
                    -- start condition
                    reset_crc  <= '0';
                    state_next <= PAYLOAD;
                else
                    state_next <= IDLE;
                end if;
        end case;

    end process COMB_PROC;

    SEQ_PROC : process (clk) is
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                state_reg <= IDLE;

                m_axis_tvalid_reg <= '0';

                start_packet_reg    <= (others => '0');
                error_bad_frame_reg <= '0';
                error_bad_fcs_reg   <= '0';

                xgmii_rxc_d0 <= (others => '0');

                xgmii_start_swap <= '0';
                xgmii_start_d0   <= '0';
                xgmii_start_d1   <= '0';

                lanes_swapped <= '0';

                crc_state <= (others => '1');
            else
                state_reg <= state_next;

                m_axis_tdata_reg  <= m_axis_tdata_next;
                m_axis_tkeep_reg  <= m_axis_tkeep_next;
                m_axis_tvalid_reg <= m_axis_tvalid_next;
                m_axis_tlast_reg  <= m_axis_tlast_next;
                m_axis_tuser_reg  <= m_axis_tuser_next;

                start_packet_reg    <= (others => '0');
                error_bad_frame_reg <= error_bad_frame_next;
                error_bad_fcs_reg   <= error_bad_fcs_next;

                swap_rxd      <= xgmii_rxd_masked(63 downto 32);
                swap_rxc      <= xgmii_rxc(7 downto 4);
                swap_rxc_term <= xgmii_term_lane(7 downto 4);

                xgmii_start_swap <= '0';
                xgmii_start_d0   <= xgmii_start_swap;

                -- lane swapping and termination character detection
                if (lanes_swapped = '1') then
                    xgmii_rxd_d0 <= xgmii_rxd_masked(31 downto 0) & swap_rxd;
                    xgmii_rxc_d0 <= xgmii_rxc(3 downto 0) & swap_rxc;

                    term_lane_reg     <= 0;
                    term_present_reg  <= '0';
                    framing_error_reg <= '1' when (xgmii_rxc(3 downto 0) & swap_rxc) /= x"00" else '0';

                    for i in 7 downto 0 loop

                        if (((xgmii_term_lane(3 downto 0) & swap_rxc_term) and (x"01" sll i)) /= x"00") then
                            term_lane_reg     <= i;
                            term_present_reg  <= '1';
                            framing_error_reg <= '1' when ((xgmii_rxc(3 downto 0) & swap_rxc) and (x"FF" srl (8-i))) /= x"00" else '0';
                            lanes_swapped     <= '0';
                        end if;

                    end loop;

                else
                    xgmii_rxd_d0 <= xgmii_rxd_masked;
                    xgmii_rxc_d0 <= xgmii_rxc;

                    term_lane_reg     <= 0;
                    term_present_reg  <= '0';
                    framing_error_reg <= '1' when xgmii_rxc /= x"00" else '0';

                    for i in 7 downto 0 loop

                        if (xgmii_rxc(i) = '1' and xgmii_rxd((i+1)*8-1 downto i*8) = XGMII_TERM) then
                            term_lane_reg     <= i;
                            term_present_reg  <= '1';
                            framing_error_reg <= '1' when (xgmii_rxc and (x"FF" srl (8-i))) /= x"00" else '0';
                            lanes_swapped     <= '0';
                        end if;

                    end loop;

                end if;

                -- start control character detection
                if (xgmii_rxc(0) = '1' and xgmii_rxd(7 downto 0) = XGMII_START) then
                    lanes_swapped <= '0';

                    xgmii_start_d0 <= '1';

                    term_lane_reg     <= 0;
                    term_present_reg  <= '0';
                    framing_error_reg <= '1' when xgmii_rxc(7 downto 0) /= x"00" else '0';
                elsif (xgmii_rxc(4) = '1' and xgmii_rxd(39 downto 32) = XGMII_START) then
                    lanes_swapped <= '1';

                    xgmii_start_swap <= '1';

                    term_lane_reg     <= 0;
                    term_present_reg  <= '0';
                    framing_error_reg <= '1' when xgmii_rxc(7 downto 5) /= "000" else '0';
                end if;

                if (xgmii_start_swap = '1') then
                    start_packet_reg <= "10";
                end if;

                if (xgmii_start_d0 = '1' and lanes_swapped = '0') then
                    start_packet_reg <= "01";
                end if;

                term_lane_d0_reg     <= term_lane_reg;
                framing_error_d0_reg <= framing_error_reg;

                if (reset_crc = '1') then
                    crc_state <= (others => '1');
                else
                    crc_state <= crc_next;
                end if;

                crc_valid_save <= crc_valid;

                xgmii_rxd_d1   <= xgmii_rxd_d0;
                xgmii_start_d1 <= xgmii_start_d0;
            end if;
        end if;

    end process SEQ_PROC;

    crc_step(crc_state, xgmii_rxd_d0, crc_next);
    crc_valid(7) <= '1' when crc_next = not x"2144df1c" else '0';
    crc_valid(6) <= '1' when crc_next = not x"c622f71d" else '0';
    crc_valid(5) <= '1' when crc_next = not x"b1c2a1a3" else '0';
    crc_valid(4) <= '1' when crc_next = not x"9d6cdf7e" else '0';
    crc_valid(3) <= '1' when crc_next = not x"6522df69" else '0';
    crc_valid(2) <= '1' when crc_next = not x"e60914ae" else '0';
    crc_valid(1) <= '1' when crc_next = not x"e38a6876" else '0';
    crc_valid(0) <= '1' when crc_next = not x"6b87b1ec" else '0';

    m_axis_tdata  <= m_axis_tdata_reg;
    m_axis_tkeep  <= m_axis_tkeep_reg;
    m_axis_tvalid <= m_axis_tvalid_reg;
    m_axis_tlast  <= m_axis_tlast_reg;
    m_axis_tuser  <= m_axis_tuser_reg;

    start_packet    <= start_packet_reg;
    error_bad_frame <= error_bad_frame_reg;
    error_bad_fcs   <= error_bad_fcs_reg;

end architecture rtl;
