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

entity axis_gmii_rx is
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
end entity axis_gmii_rx;

architecture rtl of axis_gmii_rx is

    constant ETH_PRE : std_logic_vector(7 downto 0) := x"55";
    constant ETH_SFD : std_logic_vector(7 downto 0) := x"D5";

    type fsm_type is (IDLE, PAYLOAD, WAIT_LAST);

    signal state_reg  : fsm_type;
    signal state_next : fsm_type;

    signal pre_cnt      : natural range 0 to 7;
    signal pre_cnt_next : natural range 0 to 7;

    signal reset_crc  : std_logic;
    signal update_crc : std_logic;
    signal crc_state  : std_logic_vector(31 downto 0);
    signal crc_next   : std_logic_vector(31 downto 0);

    signal gmii_rxd_d0 : std_logic_vector(7 downto 0);
    signal gmii_rxd_d1 : std_logic_vector(7 downto 0);
    signal gmii_rxd_d2 : std_logic_vector(7 downto 0);
    signal gmii_rxd_d3 : std_logic_vector(7 downto 0);
    signal gmii_rxd_d4 : std_logic_vector(7 downto 0);

    signal gmii_rx_dv_d0 : std_logic;
    signal gmii_rx_dv_d1 : std_logic;
    signal gmii_rx_dv_d2 : std_logic;
    signal gmii_rx_dv_d3 : std_logic;
    signal gmii_rx_dv_d4 : std_logic;

    signal gmii_rx_er_d0 : std_logic;
    signal gmii_rx_er_d1 : std_logic;
    signal gmii_rx_er_d2 : std_logic;
    signal gmii_rx_er_d3 : std_logic;
    signal gmii_rx_er_d4 : std_logic;

    signal m_axis_tdata_reg,    m_axis_tdata_next  : std_logic_vector(7 downto 0);
    signal m_axis_tvalid_reg,   m_axis_tvalid_next : std_logic;
    signal m_axis_tlast_reg,    m_axis_tlast_next  : std_logic;
    signal m_axis_tuser_reg,    m_axis_tuser_next  : std_logic;

    signal start_packet_reg,    start_packet_next    : std_logic;
    signal error_bad_frame_reg, error_bad_frame_next : std_logic;
    signal error_bad_fcs_reg,   error_bad_fcs_next   : std_logic;

    procedure crc_step (
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

begin

    COMB_PROC : process (all) is
    begin

        state_next   <= state_reg;
        pre_cnt_next <= pre_cnt;

        reset_crc  <= '0';
        update_crc <= '0';

        m_axis_tdata_next  <= (others => '0');
        m_axis_tvalid_next <= '0';
        m_axis_tlast_next  <= '0';
        m_axis_tuser_next  <= '0';

        start_packet_next    <= '0';
        error_bad_frame_next <= '0';
        error_bad_fcs_next   <= '0';

        case state_reg is

            when IDLE =>
                -- idle state - wait for packet
                reset_crc <= '1';

                if (gmii_rx_dv_d4 = '1' and gmii_rx_er_d4 /= '1' and gmii_rxd_d4 = ETH_PRE) then
                    pre_cnt_next <= pre_cnt + 1;
                else
                    pre_cnt_next <= 0;
                end if;

                if (gmii_rx_dv_d4 = '1' and gmii_rx_er_d4 /= '1' and gmii_rxd_d4 = ETH_SFD and pre_cnt = 7) then
                    start_packet_next <= '1';
                    state_next        <= PAYLOAD;
                end if;

            when PAYLOAD =>
                -- read payload
                update_crc <= '1';

                m_axis_tdata_next  <= gmii_rxd_d4;
                m_axis_tvalid_next <= '1';

                if (gmii_rx_dv_d4 = '1' and gmii_rx_er_d4 = '1') then
                    -- error
                    m_axis_tlast_next    <= '1';
                    m_axis_tuser_next    <= '1';
                    error_bad_frame_next <= '1';
                    state_next           <= WAIT_LAST;
                elsif (gmii_rx_dv /= '1') then
                    -- end of packet
                    m_axis_tlast_next <= '1';
                    -- crc checking
                    if (gmii_rx_er_d0 = '1' or gmii_rx_er_d1 ='1' or gmii_rx_er_d2 = '1' or gmii_rx_er_d3 = '1') then
                        -- error received in FCS bytes
                        m_axis_tuser_next    <= '1';
                        error_bad_frame_next <= '1';
                    elsif (gmii_rxd_d0 & gmii_rxd_d1 & gmii_rxd_d2 & gmii_rxd_d3 = (not crc_next)) then
                        -- FCS good
                        m_axis_tuser_next <= '0';
                    else
                        -- FCS bad
                        m_axis_tuser_next    <= '1';
                        error_bad_frame_next <= '1';
                        error_bad_fcs_next   <= '1';
                    end if;
                    state_next <= IDLE;
                end if;

            when WAIT_LAST =>
                -- wait for end of packet
                if (gmii_rx_dv /= '1') then
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

                start_packet_reg    <= '0';
                error_bad_frame_reg <= '0';
                error_bad_fcs_reg   <= '0';

                pre_cnt <= 0;

                gmii_rx_dv_d0 <= '0';
                gmii_rx_dv_d1 <= '0';
                gmii_rx_dv_d2 <= '0';
                gmii_rx_dv_d3 <= '0';
                gmii_rx_dv_d4 <= '0';

                crc_state <= (others => '1');
            else
                state_reg <= state_next;

                m_axis_tdata_reg  <= m_axis_tdata_next;
                m_axis_tvalid_reg <= m_axis_tvalid_next;
                m_axis_tlast_reg  <= m_axis_tlast_next;
                m_axis_tuser_reg  <= m_axis_tuser_next;

                gmii_rxd_d0 <= gmii_rxd;
                gmii_rxd_d1 <= gmii_rxd_d0;
                gmii_rxd_d2 <= gmii_rxd_d1;
                gmii_rxd_d3 <= gmii_rxd_d2;
                gmii_rxd_d4 <= gmii_rxd_d3;

                gmii_rx_dv_d0 <= gmii_rx_dv;
                gmii_rx_dv_d1 <= gmii_rx_dv_d0 and gmii_rx_dv;
                gmii_rx_dv_d2 <= gmii_rx_dv_d1 and gmii_rx_dv;
                gmii_rx_dv_d3 <= gmii_rx_dv_d2 and gmii_rx_dv;
                gmii_rx_dv_d4 <= gmii_rx_dv_d3 and gmii_rx_dv;

                gmii_rx_er_d0 <= gmii_rx_er;
                gmii_rx_er_d1 <= gmii_rx_er_d0;
                gmii_rx_er_d2 <= gmii_rx_er_d1;
                gmii_rx_er_d3 <= gmii_rx_er_d2;
                gmii_rx_er_d4 <= gmii_rx_er_d3;

                pre_cnt <= pre_cnt_next;

                if (reset_crc = '1') then
                    crc_state <= (others => '1');
                elsif (update_crc = '1') then
                    crc_state <= crc_next;
                end if;

                start_packet_reg    <= start_packet_next;
                error_bad_frame_reg <= error_bad_frame_next;
                error_bad_fcs_reg   <= error_bad_fcs_next;
            end if;
        end if;

    end process SEQ_PROC;

    crc_step(crc_state, gmii_rxd_d4, crc_next);

    m_axis_tdata  <= m_axis_tdata_reg;
    m_axis_tvalid <= m_axis_tvalid_reg;
    m_axis_tlast  <= m_axis_tlast_reg;
    m_axis_tuser  <= m_axis_tuser_reg;

    start_packet    <= start_packet_reg;
    error_bad_frame <= error_bad_frame_reg;
    error_bad_fcs   <= error_bad_fcs_reg;

end architecture rtl;
