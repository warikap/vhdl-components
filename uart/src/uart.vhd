library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart is
    generic(
        DIVISOR : natural := 137
    );
    port (
        aclk    : in std_logic;
        aresetn : in std_logic;

        s_axis_tdata    : in std_logic_vector(7 downto 0);
        s_axis_tvalid   : in std_logic;
        s_axis_tready   : out std_logic;

        -- m_axis_tdata    : out std_logic_vector(7 downto 0);
        -- m_axis_tvalid   : out std_logic;
        -- m_axis_tready   : in std_logic;
        -- m_axis_tuser    : out std_logic;

        m_txd   : out std_logic
    );
end uart;

architecture rtl of uart is

    signal tx_cnt       : natural range 0 to DIVISOR;
    signal tx_tick      : std_logic := '0';

    signal tx_reg       : std_logic_vector(9 downto 0);
    signal tx_bit_cnt   : natural range 0 to 9;

begin

TX_TICK_PROC : process(aclk, aresetn) 
begin
    if aresetn = '0' then
        tx_cnt <= DIVISOR - 1;
    elsif rising_edge(aclk) then
        if tx_tick = '1' then
            tx_cnt <= DIVISOR - 1;
        else
            tx_cnt <= tx_cnt - 1;
        end if;
    end if;
end process;

tx_tick <= '1' when tx_cnt = 0 else '0';

TX_DATA_PROC : process(aclk, aresetn)
begin
    if aresetn = '0' then
        tx_reg <= (others => '1');
        tx_bit_cnt <= 0;
    elsif rising_edge(aclk) then
        if s_axis_tvalid = '1' and s_axis_tready = '1' and tx_tick = '1' then
            tx_reg <= '1' & s_axis_tdata & '0';
            tx_bit_cnt <= 9;
        elsif tx_tick = '1' and tx_bit_cnt /= 0 then
            tx_reg <= '1' & tx_reg(9 downto 1);
            tx_bit_cnt <= tx_bit_cnt - 1;
        else
            tx_reg <= tx_reg;
            tx_bit_cnt <= tx_bit_cnt;
        end if;
    end if;
end process;

s_axis_tready <= '1' when tx_bit_cnt = 0 and tx_tick = '1' else '0';
m_txd <= tx_reg(0);

end architecture;
