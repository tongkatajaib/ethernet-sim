--------------------------------------------------------------------------------
-- File        : tb_mac_table.vhd
-- Project     : FPGA-Based Layer-2 Ethernet Switching Core (Zybo Z7-10)
-- Description : Self-checking testbench untuk modul mac_table.vhd.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mac_table is
end entity tb_mac_table;

architecture sim of tb_mac_table is

    constant CLK_PERIOD : time     := 8 ns;  -- 125 MHz (clock Zybo Z7)
    constant N_PORTS    : positive := 4;
    constant TABLE_SIZE : positive := 16;

    -- Alamat MAC uji (bit I/G = 0 -> locally administered unicast)
    constant MAC_A : std_logic_vector(47 downto 0) := x"02000000000A";
    constant MAC_B : std_logic_vector(47 downto 0) := x"02000000000B";
    constant MAC_C : std_logic_vector(47 downto 0) := x"02000000000C";
    constant MAC_D : std_logic_vector(47 downto 0) := x"02000000000D";
    constant MAC_E : std_logic_vector(47 downto 0) := x"02000000000E";

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal clear       : std_logic := '0';
    signal learn_valid : std_logic := '0';
    signal learn_mac   : std_logic_vector(47 downto 0) := (others => '0');
    signal learn_port  : natural range 0 to N_PORTS - 1 := 0;
    signal lookup_mac  : std_logic_vector(47 downto 0) := (others => '0');
    signal lookup_hit  : std_logic;
    signal lookup_port : natural range 0 to N_PORTS - 1;
    signal entry_count : natural range 0 to TABLE_SIZE;

begin

    -- Instansiasi Unit Under Test (UUT)
    uut : entity work.mac_table
        generic map (
            N_PORTS    => N_PORTS,
            TABLE_SIZE => TABLE_SIZE
        )
        port map (
            clk         => clk,
            rst         => rst,
            clear       => clear,
            learn_valid => learn_valid,
            learn_mac   => learn_mac,
            learn_port  => learn_port,
            lookup_mac  => lookup_mac,
            lookup_hit  => lookup_hit,
            lookup_port => lookup_port,
            entry_count => entry_count
        );

    -- Pembangkit clock 125 MHz
    clk <= not clk after CLK_PERIOD / 2;

    -- Stimulus & Self-Checking Assertions
    p_stim : process

        procedure do_learn(
            constant mac_val  : in std_logic_vector(47 downto 0);
            constant port_val : in natural range 0 to N_PORTS - 1
        ) is
        begin
            wait until falling_edge(clk);
            learn_valid <= '1';
            learn_mac   <= mac_val;
            learn_port  <= port_val;
            wait until rising_edge(clk);
            wait for 1 ns;
            learn_valid <= '0';
        end procedure do_learn;

        procedure check_lookup(
            constant mac_val       : in std_logic_vector(47 downto 0);
            constant expected_hit  : in std_logic;
            constant expected_port : in natural range 0 to N_PORTS - 1;
            constant msg           : in string
        ) is
        begin
            lookup_mac <= mac_val;
            wait for 2 ns;  -- Tunggu propagasi lookup kombinasional
            assert lookup_hit = expected_hit
                report "FAIL [" & msg & "]: lookup_hit tidak sesuai! Expected="
                       & std_logic'image(expected_hit) & ", Got=" & std_logic'image(lookup_hit)
                severity failure;

            if expected_hit = '1' then
                assert lookup_port = expected_port
                    report "FAIL [" & msg & "]: lookup_port tidak sesuai! Expected="
                           & integer'image(expected_port) & ", Got=" & integer'image(lookup_port)
                    severity failure;
            end if;
        end procedure check_lookup;

        variable v_dyn_mac : std_logic_vector(47 downto 0);

    begin
        -- 1. Uji Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        wait until rising_edge(clk);
        wait for 1 ns;
        rst <= '0';

        assert entry_count = 0
            report "FAIL [Reset]: entry_count harus 0 setelah reset."
            severity failure;
        check_lookup(MAC_A, '0', 0, "Lookup setelah reset (miss)");

        -- 2. Uji Learning dasar & Lookup Hit / Miss
        do_learn(MAC_A, 0);
        assert entry_count = 1
            report "FAIL [Learn MAC_A]: entry_count harus 1."
            severity failure;
        check_lookup(MAC_A, '1', 0, "Lookup hit MAC_A di Port 0");
        check_lookup(MAC_B, '0', 0, "Lookup miss MAC_B sebelum dipelajari");

        -- 3. Uji Learning beberapa entri tambahan
        do_learn(MAC_B, 2);
        do_learn(MAC_C, 1);
        do_learn(MAC_D, 3);
        assert entry_count = 4
            report "FAIL [Multi-learn]: entry_count harus 4."
            severity failure;

        check_lookup(MAC_A, '1', 0, "Verifikasi MAC_A -> Port 0");
        check_lookup(MAC_B, '1', 2, "Verifikasi MAC_B -> Port 2");
        check_lookup(MAC_C, '1', 1, "Verifikasi MAC_C -> Port 1");
        check_lookup(MAC_D, '1', 3, "Verifikasi MAC_D -> Port 3");

        -- 4. Uji Station Move (MAC_A berpindah dari Port 0 ke Port 3)
        do_learn(MAC_A, 3);
        assert entry_count = 4
            report "FAIL [Station Move]: entry_count tidak boleh bertambah saat update port."
            severity failure;
        check_lookup(MAC_A, '1', 3, "Station move MAC_A ke Port 3");

        -- 5. Uji Tidak Belajar saat learn_valid = '0' (simulasi frame CRC error)
        wait until falling_edge(clk);
        learn_valid <= '0';
        learn_mac   <= MAC_E;
        learn_port  <= 1;
        wait until rising_edge(clk);
        wait for 1 ns;

        assert entry_count = 4
            report "FAIL [Invalid Frame Guard]: entry_count berubah saat learn_valid = '0'."
            severity failure;
        check_lookup(MAC_E, '0', 0, "MAC_E tidak boleh dipelajari saat learn_valid = '0'");

        -- 6. Uji Clear Tabel (simulasi tombol BTN1)
        wait until falling_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        clear <= '0';

        assert entry_count = 0
            report "FAIL [Clear]: entry_count harus 0 setelah clear."
            severity failure;
        check_lookup(MAC_A, '0', 0, "MAC_A harus miss setelah clear");
        check_lookup(MAC_B, '0', 0, "MAC_B harus miss setelah clear");

        -- 7. Uji Kapasitas Penuh & FIFO Replacement (16 entri + 1 entri baru)
        for i in 0 to TABLE_SIZE - 1 loop
            v_dyn_mac := x"0211223300" & std_logic_vector(to_unsigned(i, 8));
            do_learn(v_dyn_mac, i mod N_PORTS);
        end loop;

        assert entry_count = TABLE_SIZE
            report "FAIL [Table Full]: entry_count harus mencapai TABLE_SIZE (16)."
            severity failure;

        -- Tambahkan entri ke-17 -> harus menimpa entri pertama (indeks 0)
        v_dyn_mac := x"0211223300FF";
        do_learn(v_dyn_mac, 2);

        assert entry_count = TABLE_SIZE
            report "FAIL [FIFO Replacement]: entry_count tetap TABLE_SIZE setelah replacement."
            severity failure;
        check_lookup(v_dyn_mac, '1', 2, "Entri baru ke-17 harus ditemukan di Port 2");
        check_lookup(x"021122330000", '0', 0, "Entri tertua (0x00) harus tergantikan");
        check_lookup(x"021122330001", '1', 1, "Entri kedua (0x01) harus tetap ada");

        report "=== SEMUA PENGUJIAN tb_mac_table BERHASIL (PASSED) ===" severity note;
        wait;
    end process p_stim;

end architecture sim;