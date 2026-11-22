

-- CORE MODULE 
-- NOTICE ME! FREEze THIS MODULE!
--
-- part 1 : the switch_core Entity is an interface that will be used later on.

--
--(READ THIS for STUB)
-- part 2 : use `stub` as placeholder so that member 4 (whos responsible for demo) can
-- compile and start without waiting for other module
-- 
-- 
-- in stub: Every frame will be forwarded to every port except for ingress. 
-- Theres still no CRC, parsing, or leaning.




-- Cara beralih ke versi asli: tulis architecture "rtl" yang memakai
-- crc32_eth, ethernet_header_parser, frame_buffer, mac_table, dan
-- forwarding_engine, lalu pilih "rtl" saat instansiasi (atau hapus "stub").


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.switch_pkg.all;

entity switch_core is
  generic (
    N_PORTS       : positive := DEFAULT_N_PORTS;
    TABLE_ENTRIES : positive := MAC_TABLE_ENTRIES
  );
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;                 -- sync reset, active '1'

    -- Control
    table_clear    : in  std_logic;                 -- '1' will clear MAC TABle.

    -- Input frame: one byte per clock when in_valid = '1' && in_ready ='1' 
    -- Frame including FCS (the alst 4 byte ). in_last='1' on last byte .
    -- in_port must be stable while in one frame (got from first byte) 
    in_valid       : in  std_logic;
    in_ready       : out std_logic;
    in_data        : in  byte_t;
    in_last        : in  std_logic;
    in_port        : in  port_idx_t;

    -- Keputusan: satu pulsa out_valid='1' per frame (setelah frame selesai).
    --
    -- DECISION : one pulse out_valid='1' perframe (After frame done)

    -- out mask: dest. port (bit i = port i). Zero if filter or drop.
    out_valid      : out std_logic;
    out_mask       : out port_mask_t;
    out_status     : out frame_status_t;
    out_action     : out fwd_action_t;

    -- DEBUGGING SIGNAL 
    dbg_crc_ok     : out std_logic;
    dbg_lookup_hit : out std_logic;
    dbg_state      : out std_logic_vector(3 downto 0)
  );
end entity switch_core;




-- STUB arch

architecture stub of switch_core is

  type state_t is (S_RECEIVE, S_RESPOND);
  signal state      : state_t := S_RECEIVE;

  signal byte_count : natural range 0 to MAX_FRAME_BYTES + 1 := 0;
  signal len_final  : natural range 0 to MAX_FRAME_BYTES + 1 := 0;
  signal ingress_r  : port_idx_t := 0;

begin

  in_ready       <= '1' when state = S_RECEIVE else '0';

  dbg_crc_ok     <= '0';   -- REMEMBER NO CRC YET!
  dbg_lookup_hit <= '0';   --  REMEMBER NO  LOOKUP YET!
  dbg_state      <= "0000" when state = S_RECEIVE else "0001";

  process (clk)
    variable count_next : natural range 0 to MAX_FRAME_BYTES + 1;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state      <= S_RECEIVE;
        byte_count <= 0;
        len_final  <= 0;
        ingress_r  <= 0;
        out_valid  <= '0';
        out_mask   <= MASK_NONE;
        out_status <= ST_OK;
        out_action <= ACT_DROP;
      else
        out_valid <= '0';

        case state is

          when S_RECEIVE =>
            if in_valid = '1' then
              if byte_count = 0 then
                ingress_r <= in_port;
              end if;
              
              -- Length counting, a little bit saturated above MAX_FRAMEBTES
              if byte_count < MAX_FRAME_BYTES + 1 then
                count_next := byte_count + 1;
              else
                count_next := byte_count;
              end if;

              if in_last = '1' then
                len_final  <= count_next;
                byte_count <= 0;
                state      <= S_RESPOND;
              else
                byte_count <= count_next;
              end if;
            end if;

          when S_RESPOND =>
            out_valid <= '1';

            if len_final < MIN_FRAME_BYTES then
              out_mask   <= MASK_NONE;
              out_status <= ST_RUNT;
              out_action <= ACT_DROP;
            elsif len_final > MAX_FRAME_BYTES then
              out_mask   <= MASK_NONE;
              out_status <= ST_OVERSIZE;
              out_action <= ACT_DROP;
            else
              out_mask   <= flood_mask(ingress_r, N_PORTS);
              out_status <= ST_OK;
              out_action <= ACT_FLOOD;
            end if;

            state <= S_RECEIVE;

        end case;
      end if;
    end if;
  end process;

end architecture stub;