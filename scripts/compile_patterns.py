import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")


def compile_table(table_name, output_filename, magic):
    print(f"Compiling {table_name}...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute(f"SELECT key, value FROM {table_name} ORDER BY CAST(key AS INTEGER)")

    entries = []
    string_pool = bytearray()
    string_map = {}

    # Data block to store the lists of string refs
    # We will store sequences of (offset, len) in a separate bytearray "list_data"
    list_data = bytearray()

    def add_string(s):
        if s in string_map:
            return string_map[s]
        offset = len(string_pool)
        encoded = s.encode("utf-8")
        string_pool.extend(encoded)
        string_map[s] = (offset, len(encoded))
        return offset, len(encoded)

    for key, value_json in cursor:
        pattern_id = int(key)
        attributes = json.loads(value_json)

        # Start of this list in the list_data block
        list_offset = len(list_data)
        count = len(attributes)

        for attr in attributes:
            s_off, s_len = add_string(attr)
            # Write StringRef (offset, len) to list_data
            # We will adjust s_off later to be absolute
            list_data.extend(struct.pack("<II", s_off, s_len))

        entries.append(
            {
                "id": pattern_id,
                "count": count,
                "offset": list_offset,  # Relative to start of list_data
            }
        )

    print(f"Processed {len(entries)} patterns.")
    print(f"String Pool: {len(string_pool)} bytes")

    output_path = os.path.join(DATA_BIN_DIR, output_filename)
    with open(output_path, "wb") as f:
        # Header
        # Magic: u32
        # Num Entries: u32
        # Entries Offset: u32
        # List Data Offset: u32
        # String Pool Offset: u32

        num_entries = len(entries)
        header_size = 20
        entry_size = 12  # id(4) + count(4) + offset(4)

        entries_offset = header_size
        list_data_offset = entries_offset + (num_entries * entry_size)
        strings_offset = list_data_offset + len(list_data)

        f.write(
            struct.pack(
                "<IIIII",
                magic,
                num_entries,
                entries_offset,
                list_data_offset,
                strings_offset,
            )
        )

        # Write Entries
        for e in entries:
            # The offset in the entry points to the list_data
            # We want it to be absolute file offset
            abs_offset = list_data_offset + e["offset"]
            f.write(struct.pack("<III", e["id"], e["count"], abs_offset))

        # Write List Data
        # The list data contains StringRefs (offset, len).
        # The offsets are currently relative to string pool start.
        # Make them absolute (strings_offset + rel_offset).

        for i in range(0, len(list_data), 8):
            rel_off, length = struct.unpack("<II", list_data[i : i + 8])
            abs_off = strings_offset + rel_off
            f.write(struct.pack("<II", abs_off, length))

        # Write String Pool
        f.write(string_pool)

    print(f"Written to {output_path}")
    conn.close()


def main():
    # Magic numbers:
    # DXPT = 0x44585054
    # PRPT = 0x50525054
    compile_table("dxPatterns", "dx_patterns.bin", 0x44585054)
    compile_table("prPatterns", "pr_patterns.bin", 0x50525054)


if __name__ == "__main__":
    main()
