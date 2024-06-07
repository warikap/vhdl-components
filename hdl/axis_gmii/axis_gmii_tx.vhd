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

entity axis_gmii_tx is
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
end entity axis_gmii_tx;

architecture rtl of axis_gmii_tx is

    constant MIN_FRAME_LENGTH : natural range 0 to 64               := 64;
    constant FCS_LENGTH       : natural range 0 to MIN_FRAME_LENGTH := 4;
    constant ETH_PRE          : std_logic_vector(7 downto 0)        := x"55";
    constant ETH_SFD          : std_logic_vector(7 downto 0)        := x"D5";
    constant IFG_DELAY        : natural range 0 to 12               := 12;

    type t_state is (IDLE, PREAMBLE, PAYLOAD, LAST, PAD, FCS, WAIT_END, IFG);

    signal state_reg,           state_next : t_state;

    signal reset_crc  : std_logic;
    signal update_crc : std_logic;
    signal crc_state  : std_logic_vector(31 downto 0);
    signal crc_next   : std_logic_vector(31 downto 0);

    signal frame_ptr_reg,       frame_ptr_next       : natural range 0 to 12;
    signal frame_min_count_reg, frame_min_count_next : natural range 0 to MIN_FRAME_LENGTH;

    signal s_tdata_reg,         s_tdata_next       : std_logic_vector(7 downto 0);
    signal s_axis_tready_reg,   s_axis_tready_next : std_logic;

    signal gmii_txd_reg,        gmii_txd_next   : std_logic_vector(7 downto 0);
    signal gmii_tx_en_reg,      gmii_tx_en_next : std_logic;
    signal gmii_tx_er_reg,      gmii_tx_er_next : std_logic;

    procedure crc_step (
        signal crcIn  : in std_logic_vector(31 downto 0);
        signal data   : in std_logic_vector(7 downto 0);
        signal crcOut : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- vsg_off
        crcOut(0) <= crcIn(2) xor crcIn(8) xor data(2);
        crcOut(1) <= crcIn(0) xor crcIn(3) xor crcIn(9) xor data(0) xor data(3);
        crcOut(2) <= crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(10) xor data(0) xor data(1) xor data(4);
        crcOut(3) <= crcIn(1) xor crcIn(2) xor crcIn(5) xor crcIn(11) xor data(1) xor data(2) xor data(5);
        crcOut(4) <= crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(12) xor data(0) xor data(2) xor data(3) xor data(6);
        crcOut(5) <= crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(7) xor crcIn(13) xor data(1) xor data(3) xor data(4) xor data(7);
        crcOut(6) <= crcIn(4) xor crcIn(5) xor crcIn(14) xor data(4) xor data(5);
        crcOut(7) <= crcIn(0) xor crcIn(5) xor crcIn(6) xor crcIn(15) xor data(0) xor data(5) xor data(6);
        crcOut(8) <= crcIn(1) xor crcIn(6) xor crcIn(7) xor crcIn(16) xor data(1) xor data(6) xor data(7);
        crcOut(9) <= crcIn(7) xor crcIn(17) xor data(7);
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
        state_next <= state_reg;

        reset_crc  <= '0';
        update_crc <= '0';

        frame_ptr_next       <= frame_ptr_reg;
        frame_min_count_next <= frame_min_count_reg;

        s_tdata_next       <= s_tdata_reg;
        s_axis_tready_next <= '0';

        gmii_txd_next   <= (others => '0');
        gmii_tx_en_next <= '0';
        gmii_tx_er_next <= '0';

        case state_reg is
            when IDLE =>
                -- idle state - wait for packet
                reset_crc <= '1';

                frame_ptr_next <= 1;

                frame_min_count_next <= MIN_FRAME_LENGTH - FCS_LENGTH - 1;

                if (s_axis_tvalid = '1') then
                    gmii_txd_next   <= ETH_PRE;
                    gmii_tx_en_next <= '1';
                    state_next      <= PREAMBLE;
                end if;
            when PREAMBLE =>
                -- send preamble
                reset_crc <= '1';

                frame_ptr_next <= frame_ptr_reg + 1;

                gmii_txd_next   <= ETH_PRE;
                gmii_tx_en_next <= '1';

                if (frame_ptr_reg = 6) then
                    s_axis_tready_next <= '1';
                    s_tdata_next       <= s_axis_tdata;
                elsif (frame_ptr_reg = 7) then
                    -- end of preamble; start payload
                    frame_ptr_next <= 0;

                    s_axis_tready_next <= '1';
                    s_tdata_next       <= s_axis_tdata;

                    gmii_txd_next <= ETH_SFD;
                    state_next    <= PAYLOAD;
                end if;
            when PAYLOAD =>
                -- send payload
                update_crc         <= '1';
                s_axis_tready_next <= '1';

                if (frame_min_count_reg /= 0) then
                    frame_min_count_next <= frame_min_count_reg - 1;
                end if;

                gmii_txd_next   <= s_tdata_reg;
                gmii_tx_en_next <= '1';

                s_tdata_next <= s_axis_tdata;

                if (s_axis_tvalid = '1') then
                    if (s_axis_tlast) then
                        s_axis_tready_next <= not s_axis_tready_reg;

                        state_next <= LAST;
                    end if;
                else
                    -- tvalid deassert, fail frame
                    gmii_tx_er_next <= '1';

                    state_next <= WAIT_END;
                end if;
            when LAST =>
                -- last payload word
                update_crc <= '1';

                gmii_txd_next   <= s_tdata_reg;
                gmii_tx_en_next <= '1';

                if (frame_min_count_reg /= 0) then
                    frame_min_count_next <= frame_min_count_reg - 1;

                    s_tdata_next <= x"00";

                    state_next <= PAD;
                else
                    frame_ptr_next <= 0;

                    state_next <= FCS;
                end if;
            when PAD =>
                -- send padding
                update_crc <= '1';

                gmii_txd_next   <= (others => '0');
                gmii_tx_en_next <= '1';

                s_tdata_next <= (others => '0');

                if (frame_min_count_reg /= 0) then
                    frame_min_count_next <= frame_min_count_reg - 1;
                else
                    frame_ptr_next <= 0;

                    state_next <= FCS;
                end if;
            when FCS =>
                -- send FCS
                frame_ptr_next <= frame_ptr_reg + 1;

                if (frame_ptr_reg = 0) then
                    gmii_txd_next <= (not crc_state(7 downto 0));
                elsif (frame_ptr_reg = 1) then
                    gmii_txd_next <= (not crc_state(15 downto 8));
                elsif (frame_ptr_reg = 2) then
                    gmii_txd_next <= (not crc_state(23 downto 16));
                elsif (frame_ptr_reg = 3) then
                    gmii_txd_next <= (not crc_state(31 downto 24));
                else
                    gmii_txd_next <= (others => '0');
                end if;

                gmii_tx_en_next <= '1';

                if (frame_ptr_reg = 3) then
                    frame_ptr_next <= 0;
                    state_next     <= IFG;
                end if;
            when WAIT_END =>
                -- wait for end of frame
                frame_ptr_next <= frame_ptr_reg + 1;

                s_axis_tready_next <= '1';

                if (s_axis_tvalid = '1' and s_axis_tlast = '1') then
                    s_axis_tready_next <= '0';
                    if (frame_ptr_reg < IFG_DELAY - 1) then
                        state_next <= IFG;
                    else
                        state_next <= IDLE;
                    end if;
                end if;
            when IFG =>
                -- send IFG
                frame_ptr_next <= frame_ptr_reg + 1;

                if (frame_ptr_reg = IFG_DELAY - 1) then
                    state_next <= IDLE;
                end if;
        end case;

    end process COMB_PROC;

    SEQ_PROC : process (clk) is
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                state_reg <= IDLE;

                frame_ptr_reg       <= 0;
                frame_min_count_reg <= 0;

                s_tdata_reg       <= (others => '0');
                s_axis_tready_reg <= '0';

                gmii_txd_reg   <= (others => '0');
                gmii_tx_en_reg <= '0';
                gmii_tx_er_reg <= '0';

                crc_state <= (others => '1');
            else
                state_reg <= state_next;

                frame_ptr_reg       <= frame_ptr_next;
                frame_min_count_reg <= frame_min_count_next;

                s_tdata_reg       <= s_tdata_next;
                s_axis_tready_reg <= s_axis_tready_next;

                gmii_txd_reg   <= gmii_txd_next;
                gmii_tx_en_reg <= gmii_tx_en_next;
                gmii_tx_er_reg <= gmii_tx_er_next;

                if (reset_crc = '1') then
                    crc_state <= (others => '1');
                elsif (update_crc = '1') then
                    crc_state <= crc_next;
                end if;
            end if;
        end if;

    end process SEQ_PROC;

    crc_step(crc_state, s_tdata_reg, crc_next);

    s_axis_tready <= s_axis_tready_reg;

    gmii_txd   <= gmii_txd_reg;
    gmii_tx_en <= gmii_tx_en_reg;
    gmii_tx_er <= gmii_tx_er_reg;

end architecture rtl;
