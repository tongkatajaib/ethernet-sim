--------------------------------------------------------------------------------
-- File        : forwarding_engine.vhd
-- Project     : FPGA-Based Layer-2 Ethernet Switching Core (Zybo Z7-10)
-- Description : Menentukan egress port mask dan status keputusan forwarding.
--               Aturan:
--               1. CRC error                   -> Drop (mask = 0)
--               2. Broadcast (FF:FF:FF:FF:FF:FF)-> Flood semua port selain ingress
--               3. Multicast (dst_mac(40)='1') -> Flood semua port selain ingress
--               4. Known unicast (port sama)   -> Filter (mask = 0)
--               5. Known unicast (port beda)   -> Forward hanya ke lookup_port
--               6. Unknown unicast             -> Flood semua port selain ingress
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity forwarding_engine is
    generic (
        N_PORTS : positive := 4
    );
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;

        -- Sinyal pemicu evaluasi keputusan
        eval_valid     : in  std_logic;
        crc_valid      : in  std_logic;

        -- Informasi header & hasil lookup MAC table
        dst_mac        : in  std_logic_vector(47 downto 0);
        ingress_port   : in  natural range 0 to N_PORTS - 1;
        lookup_hit     : in  std_logic;
        lookup_port    : in  natural range 0 to N_PORTS - 1;

        -- Keluaran keputusan forwarding
        decision_valid : out std_logic;
        egress_mask    : out std_logic_vector(N_PORTS - 1 downto 0);
        is_dropped     : out std_logic;  -- '1' jika frame dibuang karena CRC error
        is_filtered    : out std_logic   -- '1' jika tujuan berada di ingress_port
    );
end entity forwarding_engine;

architecture rtl of forwarding_engine is

    constant BROADCAST_MAC : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";

    -- Fungsi bantu membentuk mask flood ke seluruh port kecuali ingress_port
    function make_flood_mask(
        in_p : natural range 0 to N_PORTS - 1
    ) return std_logic_vector is
        variable v_mask : std_logic_vector(N_PORTS - 1 downto 0);
    begin
        for p in 0 to N_PORTS - 1 loop
            if p = in_p then
                v_mask(p) := '0';
            else
                v_mask(p) := '1';
            end if;
        end loop;
        return v_mask;
    end function make_flood_mask;

begin

    p_forward : process(clk)
        variable v_is_broadcast : boolean;
        variable v_is_multicast : boolean;
        variable v_mask         : std_logic_vector(N_PORTS - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                decision_valid <= '0';
                egress_mask    <= (others => '0');
                is_dropped     <= '0';
                is_filtered    <= '0';

            else
                decision_valid <= eval_valid;

                if eval_valid = '1' then
                    -- Bit ke-40 adalah bit LSB pada byte pertama Ethernet (bit I/G)
                    v_is_broadcast := (dst_mac = BROADCAST_MAC);
                    v_is_multicast := (dst_mac(40) = '1');
                    v_mask         := (others => '0');

                    if crc_valid = '0' then
                        -- 1. CRC/FCS tidak valid -> Drop
                        egress_mask <= (others => '0');
                        is_dropped  <= '1';
                        is_filtered <= '0';

                    elsif v_is_broadcast or v_is_multicast then
                        -- 2 & 3. Broadcast dan Multicast -> Flood selain ingress
                        egress_mask <= make_flood_mask(ingress_port);
                        is_dropped  <= '0';
                        is_filtered <= '0';

                    elsif lookup_hit = '1' then
                        if lookup_port = ingress_port then
                            -- 4. Known unicast pada ingress port sama -> Filter
                            egress_mask <= (others => '0');
                            is_dropped  <= '0';
                            is_filtered <= '1';
                        else
                            -- 5. Known unicast ke port lain -> Forward spesifik
                            v_mask(lookup_port) := '1';
                            egress_mask         <= v_mask;
                            is_dropped          <= '0';
                            is_filtered         <= '0';
                        end if;

                    else
                        -- 6. Unknown unicast -> Flood selain ingress
                        egress_mask <= make_flood_mask(ingress_port);
                        is_dropped  <= '0';
                        is_filtered <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process p_forward;

end architecture rtl;