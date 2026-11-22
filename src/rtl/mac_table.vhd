--------------------------------------------------------------------------------
-- File        : mac_table.vhd
-- Project     : FPGA-Based Layer-2 Ethernet Switching Core (Zybo Z7-10)
-- Description : MAC Address Table dengan linear lookup, dynamic learning,
--               station move update, FIFO replacement, dan synchronous clear.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_table is
    generic (
        N_PORTS    : positive := 4;
        TABLE_SIZE : positive := 16
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        clear       : in  std_logic;  -- Mengosongkan tabel (mis. dari tombol BTN1)

        -- Antarmuka MAC Learning (hanya diaktifkan jika frame valid / CRC lolos)
        learn_valid : in  std_logic;
        learn_mac   : in  std_logic_vector(47 downto 0);
        learn_port  : in  natural range 0 to N_PORTS - 1;

        -- Antarmuka MAC Lookup
        lookup_mac  : in  std_logic_vector(47 downto 0);
        lookup_hit  : out std_logic;
        lookup_port : out natural range 0 to N_PORTS - 1;

        -- Status observasi (opsional untuk ILA / debug)
        entry_count : out natural range 0 to TABLE_SIZE
    );
end entity mac_table;

architecture rtl of mac_table is

    type mac_array_t  is array (0 to TABLE_SIZE - 1) of std_logic_vector(47 downto 0);
    type port_array_t is array (0 to TABLE_SIZE - 1) of natural range 0 to N_PORTS - 1;

    signal table_valid : std_logic_vector(0 to TABLE_SIZE - 1) := (others => '0');
    signal table_mac   : mac_array_t  := (others => (others => '0'));
    signal table_port  : port_array_t := (others => 0);

    -- Pointer penggantian FIFO apabila seluruh entri tabel penuh
    signal replace_ptr : natural range 0 to TABLE_SIZE - 1 := 0;

begin

    ----------------------------------------------------------------------------
    -- Proses 1: MAC Learning, Station Move, dan Clear (Sinkron)
    -- Aturan penting: switch_core hanya boleh mengaktifkan learn_valid = '1'
    -- setelah frame lolos validasi CRC-32.
    ----------------------------------------------------------------------------
    p_learn : process(clk)
        variable v_found     : boolean;
        variable v_found_idx : natural range 0 to TABLE_SIZE - 1;
        variable v_has_free  : boolean;
        variable v_free_idx  : natural range 0 to TABLE_SIZE - 1;
    begin
        if rising_edge(clk) then
            if (rst = '1') or (clear = '1') then
                table_valid <= (others => '0');
                table_mac   <= (others => (others => '0'));
                table_port  <= (others => 0);
                replace_ptr <= 0;

            elsif learn_valid = '1' then
                v_found     := false;
                v_found_idx := 0;
                v_has_free  := false;
                v_free_idx  := 0;

                -- Cari apakah MAC sudah ada di tabel dan catat slot kosong pertama
                for i in 0 to TABLE_SIZE - 1 loop
                    if table_valid(i) = '1' then
                        if table_mac(i) = learn_mac then
                            v_found     := true;
                            v_found_idx := i;
                        end if;
                    else
                        if not v_has_free then
                            v_has_free := true;
                            v_free_idx := i;
                        end if;
                    end if;
                end loop;

                if v_found then
                    -- Station move atau refresh port: perbarui port tanpa duplikasi entri
                    table_port(v_found_idx) <= learn_port;

                elsif v_has_free then
                    -- Masukkan ke slot kosong yang tersedia
                    table_valid(v_free_idx) <= '1';
                    table_mac(v_free_idx)   <= learn_mac;
                    table_port(v_free_idx)  <= learn_port;

                else
                    -- Tabel penuh: timpa entri tertua menggunakan pointer FIFO
                    table_valid(replace_ptr) <= '1';
                    table_mac(replace_ptr)   <= learn_mac;
                    table_port(replace_ptr)  <= learn_port;

                    if replace_ptr = TABLE_SIZE - 1 then
                        replace_ptr <= 0;
                    else
                        replace_ptr <= replace_ptr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_learn;

    ----------------------------------------------------------------------------
    -- Proses 2: Linear Lookup (Kombinasional, bebas latch)
    ----------------------------------------------------------------------------
    p_lookup : process(table_valid, table_mac, table_port, lookup_mac)
    begin
        lookup_hit  <= '0';
        lookup_port <= 0;

        for i in 0 to TABLE_SIZE - 1 loop
            if (table_valid(i) = '1') and (table_mac(i) = lookup_mac) then
                lookup_hit  <= '1';
                lookup_port <= table_port(i);
            end if;
        end loop;
    end process p_lookup;

    ----------------------------------------------------------------------------
    -- Proses 3: Menghitung jumlah entri aktif di tabel
    ----------------------------------------------------------------------------
    p_count : process(table_valid)
        variable v_cnt : natural range 0 to TABLE_SIZE;
    begin
        v_cnt := 0;
        for i in 0 to TABLE_SIZE - 1 loop
            if table_valid(i) = '1' then
                v_cnt := v_cnt + 1;
            end if;
        end loop;
        entry_count <= v_cnt;
    end process p_count;

end architecture rtl;