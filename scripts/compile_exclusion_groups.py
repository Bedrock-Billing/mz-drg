import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
BIN_PATH = os.path.join(SCRIPT_DIR, "..", "data", "bin", "exclusion_groups.bin")


def compile_exclusion_groups():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT key, value FROM exclusionGroups ORDER BY key")
    rows = cursor.fetchall()

    num_groups = len(rows)
    print(f"Compiling {num_groups} groups...")

    with open(BIN_PATH, "wb") as f:
        # 1. Write Header
        # Magic: 0x4D534452 (MSDR)
        # Num Groups: u32
        magic = 0x4D534452
        f.write(struct.pack("<II", magic, num_groups))

        # 2. Reserve space for Index
        # Each index entry: key(i32), count(u32), offset(u32) = 12 bytes
        index_start = f.tell()
        index_size = num_groups * 12
        f.seek(index_size, 1)  # Skip ahead

        # 3. Write Data
        indices = []
        for key, value_json in rows:
            codes = json.loads(value_json)
            count = len(codes)
            offset = f.tell()

            # Write codes
            for code in codes:
                # Pad to 8 bytes
                code_bytes = code.encode("utf-8").ljust(8, b"\0")
                f.write(code_bytes)

            indices.append((int(key), count, offset))

        # 4. Fill Index
        f.seek(index_start)
        for key, count, offset in indices:
            f.write(struct.pack("<III", key, count, offset))

    print(f"Written to {BIN_PATH}")
    conn.close()


if __name__ == "__main__":
    compile_exclusion_groups()
