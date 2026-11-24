library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_crc32_eth is
    -- Testbench tidak memiliki port
end tb_crc32_eth;

architecture Behavioral of tb_crc32_eth is

    -- Deklarasi komponen yang akan diuji (UUT)
    component crc32_eth is
        Port (
            clk        : in  STD_LOGIC;
            rst        : in  STD_LOGIC;
            crc_init   : in  STD_LOGIC;
            data_valid : in  STD_LOGIC;
            data_in    : in  STD_LOGIC_VECTOR (7 downto 0);
            crc_out    : out STD_LOGIC_VECTOR (31 downto 0);
            crc_valid  : out STD_LOGIC
        );
    end component;

    -- Sinyal penghubung ke UUT
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal crc_init   : std_logic := '0';
    signal data_valid : std_logic := '0';
    signal data_in    : std_logic_vector(7 downto 0) := (others => '0');
    signal crc_out    : std_logic_vector(31 downto 0);
    signal crc_valid  : std_logic;

    constant CLK_PERIOD : time := 8 ns; -- 125 MHz (Zybo Z7)

    -- Array data uji ASCII "123456789"
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant TEST_DATA : byte_array_t(0 to 8) := (
        x"31", x"32", x"33", x"34", x"35", x"36", x"37", x"38", x"39"
    );

begin

    -- Instansiasi UUT
    uut: crc32_eth
        port map (
            clk        => clk,
            rst        => rst,
            crc_init   => crc_init,
            data_valid => data_valid,
            data_in    => data_in,
            crc_out    => crc_out,
            crc_valid  => crc_valid
        );

    -- Generator Clock
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Stimulus & Self-Checking Process
    stim_proc : process
        -- Prosedur helper untuk mengirim 1 byte sinkron dengan rising edge clock
        procedure send_byte(constant b : in std_logic_vector(7 downto 0)) is
        begin
            data_in    <= b;
            data_valid <= '1';
            wait until rising_edge(clk);
            wait for 1 ns; -- jeda kecil setelah clock edge agar stabil
        end procedure;

        -- Prosedur untuk mereset register CRC sebelum frame baru
        procedure init_crc is
        begin
            data_valid <= '0';
            crc_init   <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            crc_init   <= '0';
        end procedure;

    begin
        -- Reset awal sistem
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- TEST 1: Test vector standar ASCII "123456789" -> 0xCBF43926[cite: 1]
        -----------------------------------------------------------------------
        report "Memulai Test 1: Standard Vector 123456789...";
        init_crc;
        for i in TEST_DATA'range loop
            send_byte(TEST_DATA(i));
        end loop;
        data_valid <= '0';
        wait for 1 ns;

        assert crc_out = x"CBF43926"
            report "TEST 1 GAGAL! CRC diharapkan CBF43926"
            severity failure;
        report "TEST 1 BERHASIL! crc_out = 0xCBF43926" severity note;

        -----------------------------------------------------------------------
        -- TEST 2: Data "123456789" + FCS (Little-Endian) -> crc_valid = '1'[cite: 1]
        -----------------------------------------------------------------------
        report "Memulai Test 2: Validasi Magic Residue dengan FCS...";
        init_crc;
        for i in TEST_DATA'range loop
            send_byte(TEST_DATA(i));
        end loop;
        -- TODO 1: Kirim 4 byte FCS (0xCBF43926) secara little-endian (LSB dulu)[cite: 1]:
        -- Petunjuk: panggil send_byte(...) untuk x"26", lalu x"39", x"F4", x"CB"

        send_byte(x"26");
        send_byte(x"39");
        send_byte(x"F4");
        send_byte(x"CB");
        
        
        data_valid <= '0';
        wait for 1 ns;

        -- TODO 2: Tambahkan pernyataan assert untuk mengecek apakah crc_valid = '1'[cite: 1]
        -- assert ... report "TEST 2 GAGAL! ..." severity failure;
        assesrt crc_valid ='1' 
            report "TEST 2 GAGAL! Frame valid tapi crc_valid bernilai 0"
            severity failure;
        report "TEST 2 BERHASIL! Magic residue cocok (crc_valid = 1)" severity note;

        -----------------------------------------------------------------------
        -- TEST 3: Frame Rusak (1 bit flip pada FCS) -> crc_valid = '0'[cite: 1]
        -----------------------------------------------------------------------
        report "Memulai Test 3: Deteksi Error pada FCS rusak...";
        init_crc;
        for i in TEST_DATA'range loop
            send_byte(TEST_DATA(i));
        end loop;
        -- TODO 3: Kirim FCS yang sengaja dirusak 1 bit (misal byte terakhir x"CA")[cite: 1]
        -- lalu cek dengan assert bahwa crc_valid = '0'[cite: 1]
        send_byte(x"26");
        send_byte(x"39");
        send_byte(x"F4");
        send_byte(x"CA");
        
        data_valid <= '0';
        wait for 1 ns;

        assert crc_valid = '0'
            report "TEST 3 GAGAL! Frame rusak tapi crc_valid malah 1"
            severity failure;
        report "TEST 3 BERHASIL! Frame rusak terdeteksi (crc_valid=0)" severity note;

        report "SEMUA TEST CRC-32 SELESAI DAN LULUS!" severity note;
        wait; -- Hentikan simulasi
    end process;

end Behavioral;