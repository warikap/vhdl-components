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

entity uart_rx is
    port (
        aclk    : in    std_logic;
        aresetn : in    std_logic;

        m_axis_tdata  : out   std_logic_vector(7 downto 0);
        m_axis_tvalid : out   std_logic;
        m_axis_tready : in    std_logic;

        rxd : in    std_logic;

        busy          : out   std_logic;
        overrun_error : out   std_logic;
        frame_error   : out   std_logic;

        prescale : in    std_logic_vector(15 downto 0)
    );
end entity uart_rx;

architecture rtl of uart_rx is

    type t_reg is record
        tdata         : std_logic_vector(7 downto 0);
        tvalid        : std_logic;
        busy          : std_logic;
        overrun_error : std_logic;
        frame_error   : std_logic;
        data          : std_logic_vector(7 downto 0);
        prescale      : unsigned(15 downto 0);
        bit_cnt       : unsigned(3 downto 0);
    end record t_reg;

    signal r       : t_reg;
    signal r_next  : t_reg;
    signal rxd_reg : std_logic_vector(1 downto 0);

begin

    COMB_PROC : process (all) is

        variable r_tmp : t_reg;

    begin
        r_tmp := r;

        if (m_axis_tvalid and m_axis_tready) then
            r_tmp.tvalid := '0';
        end if;

        if (r.prescale > 0) then
            r_tmp.prescale := r.prescale - 1;
        elsif (r.bit_cnt > 0) then
            if (r.bit_cnt > 8+1) then
                if (rxd_reg(1) = '0') then
                    r_tmp.bit_cnt  := r.bit_cnt - 1;
                    r_tmp.prescale := unsigned(prescale) - 1;
                else
                    r_tmp.bit_cnt  := (others => '0');
                    r_tmp.prescale := (others => '0');
                end if;
            elsif (r.bit_cnt > 1) then
                r_tmp.bit_cnt  := r.bit_cnt - 1;
                r_tmp.prescale := unsigned(prescale) - 1;
                r_tmp.data     := rxd_reg(1) & r.data(7 downto 1);
            elsif (r.bit_cnt = 1) then
                r_tmp.bit_cnt := r.bit_cnt - 1;
                if (rxd_reg(1) = '1') then
                    r_tmp.tdata         := r.data;
                    r_tmp.tvalid        := '1';
                    r_tmp.overrun_error := r.tvalid;
                else
                    r_tmp.frame_error := '1';
                end if;
            end if;
        else
            r_tmp.busy := '0';
            if (rxd_reg(1) = '0') then
                r_tmp.prescale := (unsigned(prescale) srl 1) - 1;
                r_tmp.bit_cnt  := x"A";
                r_tmp.data     := (others => '0');
                r_tmp.busy     := '1';
            end if;
        end if;

        r_next <= r_tmp;

    end process COMB_PROC;

    SEQ_PROC : process (aclk, aresetn) is
    begin
        if (aresetn = '0') then
            rxd_reg         <= (others => '1');
            r.tvalid        <= '0';
            r.busy          <= '0';
            r.overrun_error <= '0';
            r.frame_error   <= '0';
            r.prescale      <= (others => '0');
            r.bit_cnt       <= (others => '0');
        elsif rising_edge(aclk) then
            rxd_reg <= rxd_reg(0) & rxd;

            r <= r_next;
        end if;

    end process SEQ_PROC;

    m_axis_tdata  <= r.tdata;
    m_axis_tvalid <= r.tvalid;
    busy          <= r.busy;
    overrun_error <= r.overrun_error;
    frame_error   <= r.frame_error;

end architecture rtl;
