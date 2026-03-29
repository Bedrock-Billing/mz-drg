import sqlite3
import struct
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")


def compile_table(table_name, output_filename, magic):
    print(f"Compiling {table_name}...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute(
        f"SELECT key, version_start, version_end, value FROM {table_name} ORDER BY key, version_start"
    )

    entries = []

    for code, v_start, v_end, value in cursor:
        entries.append(
            {
                "code": code,
                "v_start": int(v_start),
                "v_end": int(v_end),
                "value": int(value),
            }
        )

    print(f"Processed {len(entries)} entries for {table_name}.")

    output_path = os.path.join(DATA_BIN_DIR, output_filename)
    with open(output_path, "wb") as f:
        # Header
        # Magic: u32
        # Num Entries: u32
        # Entries Offset: u32

        num_entries = len(entries)
        header_size = 12
        entries_offset = header_size

        f.write(struct.pack("<III", magic, num_entries, entries_offset))

        # Write Entries
        # Code: 8 bytes (padded)
        # V_Start: i32
        # V_End: i32
        # Value: i32

        for e in entries:
            code_bytes = e["code"].encode("utf-8").ljust(8, b"\x00")[:8]
            f.write(code_bytes)
            f.write(struct.pack("<iii", e["v_start"], e["v_end"], e["value"]))

    print(f"Written to {output_path}")
    conn.close()


def main():
    # PRAT = 0x50524154
    compile_table("procedureAttributes", "procedure_attributes.bin", 0x50524154)
    # EXID = 0x45584944
    compile_table("exclusionIds", "exclusion_ids.bin", 0x45584944)


if __name__ == "__main__":
    main()
