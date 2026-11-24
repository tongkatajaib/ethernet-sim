library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity crc32_eth is
    Port (
        clk        : in  STD_LOGIC;
        rst        : in  STD_LOGIC; -- Reset sistem
        crc_init   : in  STD_LOGIC; -- Sinyal untuk mengulang CRC ke 0xFFFFFFFF (awal frame baru)
        data_valid : in  STD_LOGIC; -- '1' saat byte pada data_in valid
        data_in    : in  STD_LOGIC_VECTOR (7 downto 0);
        crc_out    : out STD_LOGIC_VECTOR (31 downto 0); -- Hasil akhir (setelah Final XOR)
        crc_valid  : out STD_LOGIC  -- '1' jika magic residue 0xDEBB20E3 tercapai
    );
end crc32_eth;

architecture Behavioral of crc32_eth is
    constant POLY_REFLECTED : std_logic_vector(31 downto 0) := x"EDB88320";
    constant MAGIC_RESIDUE  : std_logic_vector(31 downto 0) := x"DEBB20E3";
    signal crc_reg          : std_logic_vector(31 downto 0) := (others => '1');
begin

    process(clk)
        variable v_crc : std_logic_vector(31 downto 0);
        variable v_bit : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' or crc_init = '1' then
                crc_reg <= (others => '1'); -- Initial value 0xFFFFFFFF
            elsif data_valid = '1' then
                v_crc := crc_reg;
                -- TODO: Buat loop untuk 8 bit (i dari 0 sampai 7, LSB-first):
                for i in 0 to 7 loop
                    -- 1. Hitung v_bit := v_crc(0) xor data_in(i);
                    v_bit := v_crc(0) xor data_in(i);
                    -- 2. Geser v_crc ke kanan 1 bit ('0' & v_crc(31 downto 1));
                    v_crc := ('0' & v_crc(31 downto 1));
                    -- 3. Jika v_bit = '1', lakukan: v_crc := v_crc xor POLY_REFLECTED;
                    if v_bit='1' then
                        v_crc:= v_crc xor POLY_REFLECTED;
                    end if;
                end loop;
                crc_reg <= v_crc;
            end if;
        end if;
    end process;

    -- TODO: Assign crc_out (inversi dari crc_reg) dan crc_valid (cek terhadap MAGIC_RESIDUE)
    crc_out <= not crc_reg;
    crc_valid <= '1' when crc_reg = MAGIC_RESIDUE else '0';

end Behavioral;