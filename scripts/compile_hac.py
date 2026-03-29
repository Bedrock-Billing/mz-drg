import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")


def add_string(pool, mapping, s):
    if s in mapping:
        return mapping[s]
    offset = len(pool)
    encoded = s.encode("utf-8")
    pool.extend(encoded)
    mapping[s] = (offset, len(encoded))
    return offset, len(encoded)


def compile_hac_descriptions():
    print("Compiling HAC Descriptions...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute(
        "SELECT key, version_start, version_end, value FROM hacDescriptions ORDER BY CAST(key AS INTEGER), version_start"
    )

    entries = []
    string_pool = bytearray()
    string_map = {}

    for key, v_start, v_end, desc in cursor:
        s_off, s_len = add_string(string_pool, string_map, desc)
        entries.append(
            {
                "id": int(key),
                "v_start": int(v_start),
                "v_end": int(v_end),
                "desc_offset": s_off,
                "desc_len": s_len,
            }
        )

    output_path = os.path.join(DATA_BIN_DIR, "hac_descriptions.bin")
    with open(output_path, "wb") as f:
        magic = 0x48414344  # HACD
        num_entries = len(entries)
        header_size = 16  # Magic(4) + Num(4) + EntriesOff(4) + StringsOff(4)

        # Entry size: id(2) + pad(2) + v_start(4) + v_end(4) + desc_off(4) + desc_len(4) = 20 bytes
        entries_offset = header_size
        strings_offset = entries_offset + (num_entries * 20)

        f.write(
            struct.pack("<IIII", magic, num_entries, entries_offset, strings_offset)
        )

        for e in entries:
            abs_desc_off = strings_offset + e["desc_offset"]
            f.write(
                struct.pack(
                    "<HxxIIII",
                    e["id"],
                    e["v_start"],
                    e["v_end"],
                    abs_desc_off,
                    e["desc_len"],
                )
            )

        f.write(string_pool)

    print(f"Written {output_path} ({num_entries} entries)")
    conn.close()


def compile_hac_formulas():
    print("Compiling HAC Formulas...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute(
        "SELECT key, version_start, version_end, value FROM hacFormulas ORDER BY CAST(key AS INTEGER), version_start"
    )

    entries = []
    string_pool = bytearray()
    string_map = {}
    list_data = bytearray()

    for key, v_start, v_end, value_json in cursor:
        items = json.loads(value_json)

        list_offset = len(list_data)
        count = len(items)

        for item in items:
            formula = item.get("formula", "")
            s_off, s_len = add_string(string_pool, string_map, formula)
            # Store relative offset for now
            list_data.extend(struct.pack("<II", s_off, s_len))

        entries.append(
            {
                "id": int(key),
                "v_start": int(v_start),
                "v_end": int(v_end),
                "list_offset": list_offset,
                "count": count,
            }
        )

    output_path = os.path.join(DATA_BIN_DIR, "hac_formulas.bin")
    with open(output_path, "wb") as f:
        magic = 0x48414346  # HACF
        num_entries = len(entries)

        # Header: Magic(4) + Num(4) + EntriesOff(4) + ListOff(4) + StringsOff(4)
        header_size = 20

        # Entry size: id(2) + count(2) + v_start(4) + v_end(4) + list_off(4) = 16 bytes
        entries_offset = header_size
        list_data_offset = entries_offset + (num_entries * 16)
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

        for e in entries:
            abs_list_off = list_data_offset + e["list_offset"]
            f.write(
                struct.pack(
                    "<HHIII",
                    e["id"],
                    e["count"],
                    e["v_start"],
                    e["v_end"],
                    abs_list_off,
                )
            )

        # Write List Data (adjust string offsets)
        for i in range(0, len(list_data), 8):
            rel_off, length = struct.unpack("<II", list_data[i : i + 8])
            abs_off = strings_offset + rel_off
            f.write(struct.pack("<II", abs_off, length))

        f.write(string_pool)

    print(f"Written {output_path} ({num_entries} entries)")
    conn.close()


def compile_hac_operands():
    print("Compiling HAC Operands...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute(
        "SELECT key, version_start, version_end, value FROM hacOperands ORDER BY key, version_start"
    )

    entries = []
    list_data = bytearray()

    for code, v_start, v_end, value_json in cursor:
        data = json.loads(value_json)
        hac_ids = data.get("hacNumbers", [])

        list_offset = len(list_data)
        count = len(hac_ids)

        for h_id in hac_ids:
            list_data.append(int(h_id))  # u8

        entries.append(
            {
                "code": code,
                "v_start": int(v_start),
                "v_end": int(v_end),
                "list_offset": list_offset,
                "count": count,
            }
        )

    output_path = os.path.join(DATA_BIN_DIR, "hac_operands.bin")
    with open(output_path, "wb") as f:
        magic = 0x4841434F  # HACO
        num_entries = len(entries)

        # Header: Magic(4) + Num(4) + EntriesOff(4) + ListOff(4)
        header_size = 16

        # Entry size: Code(8) + v_start(4) + v_end(4) + list_off(4) + count(4) = 24 bytes
        entries_offset = header_size
        list_data_offset = entries_offset + (num_entries * 24)

        f.write(
            struct.pack("<IIII", magic, num_entries, entries_offset, list_data_offset)
        )

        for e in entries:
            code_bytes = e["code"].encode("utf-8").ljust(8, b"\x00")[:8]
            abs_list_off = list_data_offset + e["list_offset"]
            f.write(code_bytes)
            f.write(
                struct.pack("<iiII", e["v_start"], e["v_end"], abs_list_off, e["count"])
            )

        f.write(list_data)

    print(f"Written {output_path} ({num_entries} entries)")
    conn.close()


def main():
    compile_hac_descriptions()
    compile_hac_formulas()
    compile_hac_operands()


if __name__ == "__main__":
    main()
