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

-- Ethernet frame
--  Field                       Length
--  Destination MAC address     6 octets
--  Source MAC address          6 octets
--  Ethertype                   2 octets

-- This module receives an Ethernet frame on an AXI stream interface, decodes
-- and strips the headers, then produces the header fields in parallel along
-- with the payload in a separate AXI stream.

library ieee;
    use ieee.std_logic_1164.all;

entity eth_header_rx is
    port (
        aclk    : in    std_logic;
        aresetn : in    std_logic;

        s_axis_tdata  : in    std_logic_vector(7 downto 0);
        s_axis_tvalid : in    std_logic;
        s_axis_tready : out   std_logic;
        s_axis_tlast  : in    std_logic;
        s_axis_tuser  : in    std_logic;

        m_eth_hdr_valid           : out   std_logic;
        m_eth_hdr_ready           : in    std_logic;
        m_eth_dst_mac             : out   std_logic_vector(47 downto 0);
        m_eth_src_mac             : out   std_logic_vector(47 downto 0);
        m_eth_type                : out   std_logic_vector(15 downto 0);
        m_eth_payload_axis_tdata  : out   std_logic_vector(7 downto 0);
        m_eth_payload_axis_tvalid : out   std_logic;
        m_eth_payload_axis_tready : in    std_logic;
        m_eth_payload_axis_tlast  : out   std_logic;
        m_eth_payload_axis_tuser  : out   std_logic_vector(0 downto 0)
    );
end entity eth_header_rx;

architecture rtl of eth_header_rx is

    type t_state is (DST_MAC, SRC_MAC, ETH_TYPE, ETH_PAYLOAD);

    type t_reg is record
        state          : t_state;
        hdr_valid      : std_logic;
        dst_mac        : std_logic_vector(47 downto 0);
        src_mac        : std_logic_vector(47 downto 0);
        eth_type       : std_logic_vector(15 downto 0);
        payload_tvalid : std_logic;
        payload_tdata  : std_logic_vector(7 downto 0);
        payload_tlast  : std_logic;
        payload_tuser  : std_logic_vector(0 downto 0);
        byte_cnt       : std_logic_vector(2 downto 0);
    end record t_reg;

    signal r      : t_reg;
    signal r_next : t_reg;

begin

    COMB_PROC : process (all) is

        variable s_axis_xfer    : boolean;
        variable last_mac_byte  : boolean;
        variable last_type_byte : boolean;

    begin
        r_next <= r;

        s_axis_xfer    := s_axis_tvalid = '1' and s_axis_tready = '1';
        last_mac_byte  := r.byte_cnt = "100";
        last_type_byte := r.byte_cnt = "001";

        if (s_axis_xfer and s_axis_tlast = '1') then
            r_next.byte_cnt <= (others => '0');
        elsif (s_axis_xfer) then
            r_next.byte_cnt <= r.byte_cnt(1 downto 0) & not r.byte_cnt(2);
        end if;

        case r.state is
            when DST_MAC =>
                if (s_axis_xfer and s_axis_tlast = '1') then
                    r_next.state <= DST_MAC;
                elsif (s_axis_xfer and last_mac_byte) then
                    r_next.state <= SRC_MAC;
                end if;
            when SRC_MAC =>
                if (s_axis_xfer and s_axis_tlast = '1') then
                    r_next.state <= DST_MAC;
                elsif (s_axis_xfer and last_mac_byte) then
                    r_next.state <= ETH_TYPE;
                end if;
            when ETH_TYPE =>
                if (s_axis_xfer and s_axis_tlast = '1') then
                    r_next.state <= DST_MAC;
                elsif (s_axis_xfer and last_type_byte) then
                    r_next.state <= ETH_PAYLOAD;
                end if;
            when ETH_PAYLOAD =>
                if (s_axis_xfer and s_axis_tlast = '1') then
                    r_next.state <= DST_MAC;
                end if;
        end case;

        if (s_axis_xfer and r.state = DST_MAC) then
            r_next.dst_mac <= r.dst_mac(39 downto 0) & s_axis_tdata;
        end if;

        if (s_axis_xfer and r.state = SRC_MAC) then
            r_next.src_mac <= r.src_mac(39 downto 0) & s_axis_tdata;
        end if;

        if (s_axis_xfer and r.state = ETH_TYPE) then
            r_next.eth_type <= r.eth_type(7 downto 0) & s_axis_tdata;
        end if;

        if (m_eth_hdr_valid = '1' and m_eth_hdr_ready = '1') then
            r_next.hdr_valid <= '0';
        elsif (s_axis_xfer and r.state = ETH_TYPE and last_type_byte) then
            r_next.hdr_valid <= '1';
        end if;

        if (s_axis_xfer and r.state = ETH_PAYLOAD) then
            r_next.payload_tvalid <= '1';
            r_next.payload_tdata  <= s_axis_tdata;
            if (s_axis_tlast = '1') then
                r_next.payload_tlast <= '1';
            end if;
        elsif (m_eth_payload_axis_tvalid = '1' and m_eth_payload_axis_tready = '1') then
            r_next.payload_tvalid <= '0';
            r_next.payload_tlast  <= '0';
        end if;

    end process COMB_PROC;

    SEQ_PROC : process (aclk, aresetn) is
    begin
        if (aresetn = '0') then
            r.state          <= DST_MAC;
            r.hdr_valid      <= '0';
            r.dst_mac        <= (others => '0');
            r.src_mac        <= (others => '0');
            r.eth_type       <= (others => '0');
            r.payload_tvalid <= '0';
            r.payload_tdata  <= (others => '0');
            r.payload_tlast  <= '0';
            r.payload_tuser  <= (others => '0');
            r.byte_cnt       <= (others => '0');
        elsif rising_edge(aclk) then
            r <= r_next;
        end if;

    end process SEQ_PROC;

    s_axis_tready <= m_eth_payload_axis_tready or not m_eth_payload_axis_tvalid when r.state = ETH_PAYLOAD else
                     m_eth_hdr_ready or not m_eth_hdr_valid;

    m_eth_hdr_valid           <= r.hdr_valid;
    m_eth_dst_mac             <= r.dst_mac;
    m_eth_src_mac             <= r.src_mac;
    m_eth_type                <= r.eth_type;
    m_eth_payload_axis_tdata  <= r.payload_tdata;
    m_eth_payload_axis_tvalid <= r.payload_tvalid;
    m_eth_payload_axis_tlast  <= r.payload_tlast;
    m_eth_payload_axis_tuser  <= r.payload_tuser;

end architecture rtl;
