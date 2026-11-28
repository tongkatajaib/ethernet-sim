-- frame_sender.vhd
-- FSM yang mengirim satu frame dari frame_rom ke switch_core, satu byte per clock,
-- seperti yang dilakukan testbench.
--
-- Handshake: satu byte dianggap diterima core saat in_valid = '1' dan in_ready = '1'.
-- Sender menahan in_valid/in_data/in_last tetap stabil selama in_ready = '0'.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.frame_rom_pkg.all;

entity frame_sender is
  generic (
    PORT_W : positive := ROM_PORT_W
  );
  port (
    clk, rst      : in  std_logic;
    start         : in  std_logic;                       -- pulsa 1 clock (dari debouncer)
    frame_sel     : in  std_logic_vector(3 downto 0);    -- indeks frame (slide switch)
    -- ke frame_rom
    rom_frame_idx : out std_logic_vector(3 downto 0);
    rom_byte_idx  : out unsigned(ROM_STRIDE_LOG2-1 downto 0);
    rom_data      : in  std_logic_vector(7 downto 0);
    rom_len       : in  unsigned(10 downto 0);
    rom_ingress   : in  std_logic_vector(PORT_W-1 downto 0);
    -- ke switch_core
    in_valid      : out std_logic;
    in_data       : out std_logic_vector(7 downto 0);
    in_last       : out std_logic;
    in_port       : out std_logic_vector(PORT_W-1 downto 0);
    in_ready      : in  std_logic;
    -- status
    busy          : out std_logic;
    done          : out std_logic                        -- pulsa 1 clock setelah byte terakhir diterima
  );
end entity frame_sender;

architecture rtl of frame_sender is
  type state_t is (S_IDLE, S_PRIME, S_SEND, S_DONE);
  signal state   : state_t := S_IDLE;
  signal frame_r : std_logic_vector(3 downto 0) := (others => '0');
  signal idx     : unsigned(ROM_STRIDE_LOG2-1 downto 0) := (others => '0');
  signal is_last : std_logic;
  signal advance : std_logic;
begin
  -- Frame yang dipilih dikunci saat IDLE; metadata ROM mengikuti frame_r.
  rom_frame_idx <= frame_r;

  -- Alamat lookahead: bila byte sedang diterima core, ROM langsung membaca byte berikutnya
  -- sehingga throughput 1 byte/clock tanpa gelembung, dan tetap aman saat in_ready = '0'.
  advance      <= '1' when (state = S_SEND and in_ready = '1') else '0';
  rom_byte_idx <= idx + 1 when advance = '1' else idx;

  is_last <= '1' when (resize(idx, rom_len'length) + 1 = rom_len) else '0';

  in_valid <= '1' when state = S_SEND else '0';
  in_data  <= rom_data;
  in_last  <= is_last when state = S_SEND else '0';
  in_port  <= rom_ingress;
  busy     <= '0' when state = S_IDLE else '1';

  process (clk)
  begin
    if rising_edge(clk) then
      done <= '0';
      if rst = '1' then
        state   <= S_IDLE;
        idx     <= (others => '0');
        frame_r <= (others => '0');
      else
        case state is
          when S_IDLE =>
            frame_r <= frame_sel;
            idx     <= (others => '0');
            -- slot kosong (len = 0) diabaikan
            if start = '1' and rom_len /= 0 then
              state <= S_PRIME;
            end if;

          when S_PRIME =>               -- tunggu latensi baca ROM 1 clock
            state <= S_SEND;

          when S_SEND =>
            if in_ready = '1' then
              if is_last = '1' then
                state <= S_DONE;
              else
                idx <= idx + 1;
              end if;
            end if;

          when S_DONE =>
            done  <= '1';
            state <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
