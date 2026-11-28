-- frame_rom.vhd
-- ROM frame uji (termasuk FCS) + metadata per frame.
-- Isi ROM berasal dari frame_rom_pkg.vhd yang DIHASILKAN oleh tools/gen_frames.py.
--
-- Data byte : pembacaan sinkron (latensi 1 clock) -> dapat diinfer sebagai BRAM.
-- Metadata  : kombinatorial dari frame_idx (tabel kecil, jadi LUT).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.frame_rom_pkg.all;

entity frame_rom is
  port (
    clk        : in  std_logic;
    frame_idx  : in  std_logic_vector(3 downto 0);
    byte_idx   : in  unsigned(ROM_STRIDE_LOG2-1 downto 0);
    -- data (valid 1 clock setelah frame_idx/byte_idx)
    data       : out std_logic_vector(7 downto 0);
    -- metadata
    frame_len  : out unsigned(10 downto 0);               -- jumlah byte (0 = slot kosong)
    ingress    : out std_logic_vector(ROM_PORT_W-1 downto 0);
    exp_mask   : out std_logic_vector(ROM_MASK_W-1 downto 0);
    exp_status : out std_logic_vector(1 downto 0)
  );
end entity frame_rom;

architecture rtl of frame_rom is
  signal addr : unsigned(ROM_STRIDE_LOG2+3 downto 0);
  signal fidx : integer range 0 to ROM_FRAME_COUNT-1;
begin
  addr <= unsigned(frame_idx) & byte_idx;
  fidx <= to_integer(unsigned(frame_idx));

  p_data : process (clk)
  begin
    if rising_edge(clk) then
      data <= ROM_BYTES(to_integer(addr));
    end if;
  end process p_data;

  frame_len  <= to_unsigned(ROM_LEN(fidx), frame_len'length);
  ingress    <= ROM_PORT(fidx);
  exp_mask   <= ROM_EXP_MASK(fidx);
  exp_status <= ROM_EXP_STATUS(fidx);
end architecture rtl;
