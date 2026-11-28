import os
import struct
import zlib
from pathlib import Path

# Otomatis mendeteksi folder root proyek (1 tingkat di atas folder tools/)
ROOT_DIR = Path(__file__).resolve().parent.parent
VECTORS_DIR = ROOT_DIR / "sim" / "vectors"
DEMO_RTL_DIR = ROOT_DIR / "src" / "rtl" / "demo"

# Definisi MAC Address dummy untuk 9 skenario demo (Bagian 8.2 dokumen)
MAC_A = "AA:AA:AA:AA:AA:01"
MAC_B = "BB:BB:BB:BB:BB:02"
MAC_C = "CC:CC:CC:CC:CC:03"
MAC_D = "DD:DD:DD:DD:DD:04"
MAC_E = "EE:EE:EE:EE:EE:05"
MAC_F = "FF:FF:FF:FF:FF:06"
MAC_BCAST = "FF:FF:FF:FF:FF:FF"

def mac_to_bytes(mac_str: str) -> bytes:
    """Mengubah string 'AA:BB:CC:DD:EE:FF' menjadi 6 byte raw."""
    return bytes(int(b, 16) for b in mac_str.split(":"))

def build_ethernet_frame(dst_mac: str, src_mac: str, ethertype: int, payload: bytes, corrupt_fcs: bool = False) -> bytes:
    """Merakit frame Ethernet II minimal 64 byte (termasuk 4 byte FCS little-endian)."""
    header = mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + struct.pack(">H", ethertype)
    frame_no_fcs = header + payload

    # TODO 1: Padding frame_no_fcs dengan byte 0x00 jika panjangnya kurang dari 60 byte
    # (karena Ethernet minimal 64 byte termasuk 4 byte FCS)
    if len(frame_no_fcs) < 60:
        frame_no_fcs += b"\x00" * (60 - len(frame_no_fcs))

    # TODO 2: Hitung CRC-32 menggunakan zlib.crc32(frame_no_fcs) & 0xFFFFFFFF
    # lalu ubah menjadi 4 byte little-endian dengan struct.pack("<I", crc_val)
    crc_val = zlib.crc32(frame_no_fcs) & 0xFFFFFFFF# <-- ganti dengan perhitungan zlib.crc32
    fcs_bytes = struct.pack("<I", crc_val ) # <-- ganti dengan struct.pack("<I", ...)

    if corrupt_fcs:
        # Flip 1 bit pada byte terakhir FCS untuk simulasi frame rusak
        fcs_bytes = fcs_bytes[:-1] + bytes([fcs_bytes[-1] ^ 0x01])

    return frame_no_fcs + fcs_bytes

# 9 Skenario uji sesuai Tabel Bagian 8.2 dokumen spesifikasi (N_PORTS = 4)
# Format tuple: (ingress_port, dst_mac, src_mac, corrupt_fcs, expected_mask_bin, expected_status, deskripsi)
SCENARIOS = [
    (0, MAC_B,     MAC_A, False, "1110", "VALID",     "0: A->B (B unknown -> flood port 1,2,3)"),
    (2, MAC_A,     MAC_B, False, "0001", "VALID",     "1: B->A (A known port 0)"),
    (1, MAC_BCAST, MAC_C, False, "1101", "VALID",     "2: C->Broadcast (flood port 0,2,3)"),
    (0, MAC_B,     MAC_A, False, "0100", "VALID",     "3: A->B (B known port 2)"),
    (0, MAC_A,     MAC_D, False, "0000", "FILTER",    "4: D->A (A di port 0 == ingress -> filter)"),
    (1, MAC_B,     MAC_E, True,  "0000", "CRC_ERROR", "5: E->B FCS rusak (drop, E tidak dipelajari)"),
    (3, MAC_E,     MAC_F, False, "0111", "VALID",     "6: F->E (E unknown -> flood port 0,1,2)"),
    (3, MAC_B,     MAC_A, False, "0100", "VALID",     "7: A->B (station move A ke port 3)"),
    (1, MAC_A,     MAC_C, False, "1000", "VALID",     "8: C->A (A known port 3)"),
]

def export_vhdl_rom(frames_data, out_path=DEMO_RTL_DIR / "frame_rom_pkg.vhd"):
    """Mengekspor 9 frame uji menjadi package konstanta VHDL untuk frame_rom.vhd."""
    lines = [
        "library IEEE;",
        "use IEEE.STD_LOGIC_1164.ALL;",
        "",
        "package frame_rom_pkg is",
        "    type rom_byte_array_t is array (0 to 63) of std_logic_vector(7 downto 0);",
        "    type rom_entry_t is record",
        "        ingress_port : natural range 0 to 3;",
        "        frame_len    : natural range 0 to 64;",
        "        data         : rom_byte_array_t;",
        "    end record;",
        f"    type rom_table_t is array (0 to {len(frames_data)-1}) of rom_entry_t;",
        "",
        "    constant C_FRAME_ROM : rom_table_t := ("
    ]

    for idx, (ingress, raw_frame) in enumerate(frames_data):
        hex_items = ", ".join(f'x"{b:02X}"' for b in raw_frame)
        comma = "," if idx < len(frames_data) - 1 else ""
        lines.append(
            f"        {idx} => (ingress_port => {ingress}, frame_len => {len(raw_frame)}, data => ({hex_items})){comma}"
        )

    lines.extend([
        "    );",
        "end package frame_rom_pkg;"
    ])

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Berhasil menghasilkan konstanta VHDL ROM ke {out_path}")


def main():
    VECTORS_DIR.mkdir(parents=True, exist_ok=True)
    DEMO_RTL_DIR.mkdir(parents=True, exist_ok=True)

    vector_lines = []
    rom_frames = []

    for idx, (ingress, dst, src, corrupt, mask, status, desc) in enumerate(SCENARIOS):
        payload = f"FRAME_{idx}".encode("ascii")
        raw_frame = build_ethernet_frame(dst, src, 0x0800, payload, corrupt_fcs=corrupt)
        hex_str = " ".join(f"{b:02X}" for b in raw_frame)

        # Simpan untuk ethernet_frames.txt
        vector_lines.append(f"{idx} {ingress} {len(raw_frame)} {mask} {status} {hex_str}")
        # Simpan pasangan (ingress, raw_frame) untuk ROM VHDL
        rom_frames.append((ingress, raw_frame))

    # Tulis file vektor simulasi
    vector_file = VECTORS_DIR / "ethernet_frames.txt"
    with open(vector_file, "w") as f:
        f.write("\n".join(vector_lines) + "\n")
    print(f"Berhasil menghasilkan {len(SCENARIOS)} frame uji ke {vector_file}")

    # Tulis package konstanta ROM untuk board demo
    export_vhdl_rom(rom_frames)

if __name__ == "__main__":
    main()