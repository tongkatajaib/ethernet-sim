

-- standard PACKAGE FOR other MODULES





-- NOTICE ME EVERYON!!!!
-- CHANGES IN TTHIS packeg COULD AFFECT ALL OF OUR MODULE
-- ONLY CHANGE IN PULL REQUEST

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


-- PACKAGE HELPER! DON'T FORGET TO use this!!!
package switch_pkg is

  -- please READ the comments everyone!
  
  -- PORT config
  -- MAX_PORTS      : Max WIDTH OF VECTOR MASK AND RANGE IN PORT INDEX 
  -- DEFAULT_N_PORTS: NUMBER OF PORTS USED(generic N_PORTS di tiap module nantinya).
  -- BIT MASK ABOVE N_PORTS IS ALWAYS `0`
  constant MAX_PORTS       : positive := 8;
  constant DEFAULT_N_PORTS : positive := 4;

  --- MAC TABLE CONFIGURATION
  constant MAC_TABLE_ENTRIES : positive := 16;

  -- CONSTANT RELATED TO FRAME
  constant ETH_HEADER_BYTES : positive := 14;    -- dst(6) + src(6) + type(2)
  constant FCS_BYTES        : positive := 4;
  constant MIN_FRAME_BYTES  : positive := 64;    -- INCLUSED FCS
  constant MAX_FRAME_BYTES  : positive := 1518;  -- INCLUDE  FCS, NO VLAN HEADER!!
  constant FRAME_BUF_BYTES  : positive := 2048;  -- frame_buffer WIDTH

  -- CONSTANT RELATED TO CRC32
  constant CRC32_INIT     : std_logic_vector(31 downto 0) := x"FFFFFFFF";
  constant CRC32_POLY_REV : std_logic_vector(31 downto 0) := x"EDB88320";
  constant CRC32_XOR_OUT  : std_logic_vector(31 downto 0) := x"FFFFFFFF";
 
  -- IF frame (inslucding fcs) is processed and frame is valid, register CRC
  -- 
  -- (before final XOR) ends here, verify with test vector
  constant CRC32_RESIDUE  : std_logic_vector(31 downto 0) := x"DEBB20E3";

  --Data type
  subtype byte_t      is std_logic_vector(7 downto 0);

  -- MAC address 48 bit. fIrst byte sent is the MSB 
  --   mac(47 downto 40) = byte 0, ..., mac(7 downto 0) = byte 5.
  --  multicast/group bit = LSB byte 0 = mac(40).
  subtype mac_addr_t  is std_logic_vector(47 downto 0);

  subtype port_idx_t  is natural range 0 to MAX_PORTS - 1;
  subtype port_mask_t is std_logic_vector(MAX_PORTS - 1 downto 0);

  constant MAC_BROADCAST : mac_addr_t  := x"FFFFFFFFFFFF";
  constant MASK_NONE     : port_mask_t := (others => '0');

  -- Frame validation status
  type frame_status_t is (
    ST_OK,          -- A valid frame
    ST_CRC_ERROR,   -- Unmatched FCS.
    ST_RUNT,        -- size less than MIN_FRAME_BYTES.
    ST_OVERSIZE     -- more than   MAX_FRAME_BYTES
  );

  -- Forwarding decision
  type fwd_action_t is (
    ACT_FORWARD,    -- known unicast: send to one port
    ACT_FLOOD,      -- unknown unicast / broadcast: all port EXCEPT ingreess (incoming ).
    ACT_FILTER,     -- don't forward
    ACT_DROP        -- for Invalid frame,
  );


 -- -- Helper
  -- Ceiling log2 (clog2(1) = 0, clog2(8) = 3, clog2(9) = 4).
  function clog2(n : positive) return natural;

  -- True jika MAC = FF:FF:FF:FF:FF:FF.
  function is_broadcast(mac : mac_addr_t) return boolean;
  -- True jika bit multicast (group) terset. Broadcast juga termasuk.
  function is_multicast(mac : mac_addr_t) return boolean;

  -- Mask dengan satu bit '1' pada posisi idx.
  function port_to_mask(idx : port_idx_t) return port_mask_t;

  -- Semua port 0 .. n_ports-1 kecuali ingress.
  function flood_mask(ingress : port_idx_t; n_ports : positive)
    return port_mask_t;

end package switch_pkg;






package body switch_pkg is

  function clog2(n : positive) return natural is
    variable r : natural := 0;
    variable v : natural := 1;
  begin
    while v < n loop
      v := v * 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function is_broadcast(mac : mac_addr_t) return boolean is
  begin
    return mac = MAC_BROADCAST;
  end function;

  function is_multicast(mac : mac_addr_t) return boolean is
  begin
    return mac(40) = '1';
  end function;

  function port_to_mask(idx : port_idx_t) return port_mask_t is
    variable m : port_mask_t := (others => '0');
  begin
    m(idx) := '1';
    return m;
  end function;

  function flood_mask(ingress : port_idx_t; n_ports : positive)
    return port_mask_t is
    variable m : port_mask_t := (others => '0');
  begin
    for i in 0 to MAX_PORTS - 1 loop
      if i < n_ports and i /= ingress then
        m(i) := '1';
      end if;
    end loop;
    return m;
  end function;

end package body switch_pkg;