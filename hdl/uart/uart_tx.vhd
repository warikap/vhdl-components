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

entity uart_tx is
    port (
        aclk    : in    std_logic;
        aresetn : in    std_logic;

        s_axis_tdata  : in    std_logic_vector(7 downto 0);
        s_axis_tvalid : in    std_logic;
        s_axis_tready : out   std_logic;

        txd : out   std_logic;

        busy : out   std_logic;

        prescale : in    std_logic_vector(15 downto 0)
    );
end entity uart_tx;

architecture rtl of uart_tx is

    type t_reg is record
        tready   : std_logic;
        data     : std_logic_vector(9 downto 0);
        busy     : std_logic;
        prescale : unsigned(15 downto 0);
        bit_cnt  : unsigned(3 downto 0);
    end record t_reg;

    signal r      : t_reg;
    signal r_next : t_reg;

begin

    COMB_PROC : process (all) is

        variable r_tmp : t_reg;

    begin
        r_tmp := r;

        if (r.prescale > 0) then
            r_tmp.tready   := '0';
            r_tmp.prescale := r.prescale - 1;
        elsif (r.bit_cnt = 0) then
            r_tmp.tready := '1';
            r_tmp.busy   := '0';

            if (s_axis_tvalid = '1') then
                r_tmp.tready   := not r.tready;
                r_tmp.prescale := unsigned(prescale) - 1;
                r_tmp.bit_cnt  := x"9";
                r_tmp.data     := "1" & s_axis_tdata & "0";
                r_tmp.busy     := '1';
            end if;
        else
            if (r.bit_cnt > 0) then
                r_tmp.bit_cnt  := r.bit_cnt - 1;
                r_tmp.prescale := unsigned(prescale) - 1;
                r_tmp.data     := "0" & r.data(9 downto 1);
            end if;
        end if;

        r_next <= r_tmp;

    end process COMB_PROC;

    SEQ_PROC : process (aclk, aresetn) is
    begin
        if (aresetn = '0') then
            r.tready   <= '1';
            r.data     <= (others => '1');
            r.busy     <= '0';
            r.prescale <= (others => '0');
            r.bit_cnt  <= (others => '0');
        elsif rising_edge(aclk) then
            r <= r_next;
        end if;

    end process SEQ_PROC;

    s_axis_tready <= r.tready;
    txd           <= r.data(0);
    busy          <= r.busy;

end architecture rtl;
