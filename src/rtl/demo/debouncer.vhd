-- debouncer.vhd
-- Sinkronisasi 2-FF + debounce + pulsa satu clock pada tepi naik tombol.
-- DEBOUNCE_CYCLES: 125 MHz * 10 ms = 1_250_000 (default). Pakai nilai kecil di simulasi.
library ieee;
use ieee.std_logic_1164.all;

entity debouncer is
  generic (
    DEBOUNCE_CYCLES : positive := 1_250_000
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    btn_in    : in  std_logic;   -- tombol mentah (asinkron)
    btn_level : out std_logic;   -- level tombol yang sudah stabil
    btn_pulse : out std_logic    -- 1 clock saat tombol resmi ditekan
  );
end entity debouncer;

architecture rtl of debouncer is
  signal sync   : std_logic_vector(1 downto 0) := "00";
  signal stable : std_logic := '0';
  signal cnt    : natural range 0 to DEBOUNCE_CYCLES := 0;
  signal pulse  : std_logic := '0';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      sync  <= sync(0) & btn_in;
      pulse <= '0';
      if rst = '1' then
        stable <= '0';
        cnt    <= 0;
      elsif sync(1) = stable then
        cnt <= 0;
      elsif cnt = DEBOUNCE_CYCLES - 1 then
        stable <= sync(1);
        cnt    <= 0;
        pulse  <= sync(1);          -- hanya tepi naik yang menghasilkan pulsa
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  btn_level <= stable;
  btn_pulse <= pulse;
end architecture rtl;
