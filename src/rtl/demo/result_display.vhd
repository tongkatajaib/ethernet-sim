-- result_display.vhd
-- Menampilkan hasil keputusan switch di LED.
--   led[i]  : egress mask (satu LED per port), steady
--   RGB     : hijau = frame valid diproses, merah = frame di-drop (CRC error),
--             biru berkedip pelan (heartbeat) saat tidak ada hasil -> bukti clock hidup.
-- Warna RGB di-PWM 25 % (Zybo Z7: duty maks. ~50 %, steady '1' terlalu terang).
-- Hasil ditahan sampai pengiriman frame berikutnya (new_frame) atau HOLD_CYCLES
-- clock (HOLD_CYCLES = 0 -> tahan tanpa batas waktu).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity result_display is
  generic (
    N_PORTS     : positive := 4;
    HOLD_CYCLES : natural  := 0
  );
  port (
    clk, rst   : in  std_logic;
    new_frame  : in  std_logic;                            -- hapus tampilan (saat kirim frame baru)
    out_valid  : in  std_logic;
    out_mask   : in  std_logic_vector(N_PORTS-1 downto 0);
    out_status : in  std_logic_vector(1 downto 0);         -- "00" valid, selain itu = error/drop
    led        : out std_logic_vector(N_PORTS-1 downto 0);
    rgb_r      : out std_logic;
    rgb_g      : out std_logic;
    rgb_b      : out std_logic
  );
end entity result_display;

architecture rtl of result_display is
  constant STATUS_VALID : std_logic_vector(1 downto 0) := "00";

  signal mask_r  : std_logic_vector(N_PORTS-1 downto 0) := (others => '0');
  signal ok_r    : std_logic := '0';
  signal err_r   : std_logic := '0';
  signal timer   : natural range 0 to HOLD_CYCLES := 0;
  signal pwm_cnt : unsigned(7 downto 0)  := (others => '0');
  signal hb_cnt  : unsigned(26 downto 0) := (others => '0');
  signal pwm_on  : std_logic;
  signal hb      : std_logic;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      pwm_cnt <= pwm_cnt + 1;
      hb_cnt  <= hb_cnt + 1;

      if rst = '1' or new_frame = '1' then
        mask_r <= (others => '0');
        ok_r   <= '0';
        err_r  <= '0';
        timer  <= 0;
      elsif out_valid = '1' then
        mask_r <= out_mask;
        timer  <= 0;
        if out_status = STATUS_VALID then
          ok_r  <= '1';
          err_r <= '0';
        else
          ok_r  <= '0';
          err_r <= '1';
        end if;
      elsif HOLD_CYCLES > 0 and (ok_r = '1' or err_r = '1') then
        if timer = HOLD_CYCLES then
          mask_r <= (others => '0');
          ok_r   <= '0';
          err_r  <= '0';
          timer  <= 0;
        else
          timer <= timer + 1;
        end if;
      end if;
    end if;
  end process;

  pwm_on <= '1' when pwm_cnt(7 downto 6) = "00" else '0';   -- duty 25 %
  hb     <= hb_cnt(26);                                      -- ~0,9 Hz @125 MHz

  led   <= mask_r;
  rgb_g <= ok_r  and pwm_on;
  rgb_r <= err_r and pwm_on;
  rgb_b <= hb and pwm_on and not ok_r and not err_r;
end architecture rtl;
