-- demo_top.vhd
-- Top-level demo Zybo Z7-10: ROM frame -> frame_sender -> switch_core -> result_display.
--
-- Kontrol:
--   SW[3:0] : indeks frame ROM (0..15)       BTN0 : kirim frame terpilih
--   BTN1    : kosongkan MAC table            BTN3 : reset sistem
--   LD0..LD3: egress mask (LD0 = port 0)     RGB  : hijau valid / merah drop / biru heartbeat
--
-- ASUMSI interface switch_core (sesuaikan jika berbeda):
--   generic N_PORTS
--   in : clk, rst, in_valid, in_data(7:0), in_last, in_port(ROM_PORT_W-1:0), table_clear
--   out: in_ready, out_valid, out_mask(N_PORTS-1:0), out_status(1:0)
--        out_status: "00" = valid, "01" = crc_error, "10" = drop
-- ROM dibuat untuk N_PORTS = 4 (lihat tools/gen_frames.py); jangan ubah N_PORTS tanpa
-- membangkitkan ulang frame_rom_pkg.vhd.
--
-- JANGAN menggerakkan PHYRSTB (E17) ke level rendah: clock 125 MHz (K17) berasal dari PHY.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.frame_rom_pkg.all;

entity demo_top is
  generic (
    N_PORTS         : positive := 4;
    DEBOUNCE_CYCLES : positive := 1_250_000;   -- 10 ms @125 MHz
    HOLD_CYCLES     : natural  := 0            -- 0 = tahan hasil sampai frame berikutnya
  );
  port (
    clk   : in  std_logic;                      -- 125 MHz (K17)
    sw    : in  std_logic_vector(3 downto 0);
    btn   : in  std_logic_vector(3 downto 0);
    led   : out std_logic_vector(3 downto 0);
    rgb_r : out std_logic;
    rgb_g : out std_logic;
    rgb_b : out std_logic
  );
end entity demo_top;

architecture rtl of demo_top is
  -- power-on reset pendek + tombol reset
  signal por_cnt   : unsigned(3 downto 0) := (others => '0');
  signal sys_rst   : std_logic;
  signal btn3_lvl  : std_logic;

  signal send_pulse  : std_logic;
  signal clear_pulse : std_logic;

  -- ROM <-> sender
  signal rom_frame_idx : std_logic_vector(3 downto 0);
  signal rom_byte_idx  : unsigned(ROM_STRIDE_LOG2-1 downto 0);
  signal rom_data      : std_logic_vector(7 downto 0);
  signal rom_len       : unsigned(10 downto 0);
  signal rom_ingress   : std_logic_vector(ROM_PORT_W-1 downto 0);
  signal exp_mask      : std_logic_vector(ROM_MASK_W-1 downto 0);
  signal exp_status    : std_logic_vector(1 downto 0);

  -- sender <-> core
  signal in_valid  : std_logic;
  signal in_data   : std_logic_vector(7 downto 0);
  signal in_last   : std_logic;
  signal in_port   : std_logic_vector(ROM_PORT_W-1 downto 0);
  signal in_ready  : std_logic;
  signal send_busy : std_logic;
  signal send_done : std_logic;

  -- core -> display
  signal out_valid  : std_logic;
  signal out_mask   : std_logic_vector(N_PORTS-1 downto 0);
  signal out_status : std_logic_vector(1 downto 0);

  -- sinyal untuk ILA (Set Up Debug / mark_debug)
  attribute mark_debug : string;
  attribute mark_debug of in_valid   : signal is "true";
  attribute mark_debug of in_data    : signal is "true";
  attribute mark_debug of in_last    : signal is "true";
  attribute mark_debug of in_port    : signal is "true";
  attribute mark_debug of in_ready   : signal is "true";
  attribute mark_debug of out_valid  : signal is "true";
  attribute mark_debug of out_mask   : signal is "true";
  attribute mark_debug of out_status : signal is "true";
  attribute mark_debug of exp_mask   : signal is "true";
  attribute mark_debug of exp_status : signal is "true";
begin
  ----------------------------------------------------------------------------
  -- Reset: power-on (16 clock) OR tombol BTN3 (sudah di-debounce)
  ----------------------------------------------------------------------------
  p_por : process (clk)
  begin
    if rising_edge(clk) then
      if por_cnt /= "1111" then
        por_cnt <= por_cnt + 1;
      end if;
    end if;
  end process p_por;

  sys_rst <= '1' when por_cnt /= "1111" else btn3_lvl;

  ----------------------------------------------------------------------------
  -- Debouncer tombol
  ----------------------------------------------------------------------------
  u_deb_send : entity work.debouncer
    generic map (DEBOUNCE_CYCLES => DEBOUNCE_CYCLES)
    port map (clk => clk, rst => sys_rst, btn_in => btn(0),
              btn_level => open, btn_pulse => send_pulse);

  u_deb_clear : entity work.debouncer
    generic map (DEBOUNCE_CYCLES => DEBOUNCE_CYCLES)
    port map (clk => clk, rst => sys_rst, btn_in => btn(1),
              btn_level => open, btn_pulse => clear_pulse);

  -- tombol reset: tidak di-reset oleh sys_rst (kalau tidak, level tidak bisa lepas)
  u_deb_rst : entity work.debouncer
    generic map (DEBOUNCE_CYCLES => DEBOUNCE_CYCLES)
    port map (clk => clk, rst => '0', btn_in => btn(3),
              btn_level => btn3_lvl, btn_pulse => open);

  ----------------------------------------------------------------------------
  -- ROM + sender
  ----------------------------------------------------------------------------
  u_rom : entity work.frame_rom
    port map (
      clk        => clk,
      frame_idx  => rom_frame_idx,
      byte_idx   => rom_byte_idx,
      data       => rom_data,
      frame_len  => rom_len,
      ingress    => rom_ingress,
      exp_mask   => exp_mask,
      exp_status => exp_status
    );

  u_sender : entity work.frame_sender
    generic map (PORT_W => ROM_PORT_W)
    port map (
      clk           => clk,
      rst           => sys_rst,
      start         => send_pulse,
      frame_sel     => sw,
      rom_frame_idx => rom_frame_idx,
      rom_byte_idx  => rom_byte_idx,
      rom_data      => rom_data,
      rom_len       => rom_len,
      rom_ingress   => rom_ingress,
      in_valid      => in_valid,
      in_data       => in_data,
      in_last       => in_last,
      in_port       => in_port,
      in_ready      => in_ready,
      busy          => send_busy,
      done          => send_done
    );

  ----------------------------------------------------------------------------
  -- Switch core
  ----------------------------------------------------------------------------
  u_core : entity work.switch_core
    generic map (N_PORTS => N_PORTS)
    port map (
      clk         => clk,
      rst         => sys_rst,
      in_valid    => in_valid,
      in_data     => in_data,
      in_last     => in_last,
      in_port     => in_port,
      in_ready    => in_ready,
      out_valid   => out_valid,
      out_mask    => out_mask,
      out_status  => out_status,
      table_clear => clear_pulse
    );

  ----------------------------------------------------------------------------
  -- Tampilan hasil
  ----------------------------------------------------------------------------
  u_display : entity work.result_display
    generic map (N_PORTS => N_PORTS, HOLD_CYCLES => HOLD_CYCLES)
    port map (
      clk        => clk,
      rst        => sys_rst,
      new_frame  => send_pulse,
      out_valid  => out_valid,
      out_mask   => out_mask,
      out_status => out_status,
      led        => led(N_PORTS-1 downto 0),
      rgb_r      => rgb_r,
      rgb_g      => rgb_g,
      rgb_b      => rgb_b
    );
end architecture rtl;
