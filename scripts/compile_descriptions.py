import sqlite3
import struct
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")

def add_string(pool, mapping, s):
    if s in mapping:
        return mapping[s]
    offset = len(pool)
    encoded = s.encode('utf-8')
    pool.extend(encoded)
    mapping[s] = (offset, len(encoded))
    return offset, len(encoded)

def compile_table(table_name, output_filename, magic):
    print(f"Compiling {table_name}...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute(f"SELECT key, version_start, version_end, value FROM {table_name} ORDER BY CAST(key AS INTEGER), version_start")
    
    entries = []
    string_pool = bytearray()
    string_map = {}
    
    for key, v_start, v_end, desc in cursor:
        s_off, s_len = add_string(string_pool, string_map, desc)
        entries.append({
            "id": int(key),
            "v_start": int(v_start),
            "v_end": int(v_end),
            "desc_offset": s_off,
            "desc_len": s_len
        })
        
    output_path = os.path.join(DATA_BIN_DIR, output_filename)
    with open(output_path, "wb") as f:
        num_entries = len(entries)
        header_size = 16 # Magic(4) + Num(4) + EntriesOff(4) + StringsOff(4)
        
        # Entry size: id(2) + pad(2) + v_start(4) + v_end(4) + desc_off(4) + desc_len(4) = 20 bytes
        entries_offset = header_size
        strings_offset = entries_offset + (num_entries * 20)
        
        f.write(struct.pack("<IIII", magic, num_entries, entries_offset, strings_offset))
        
        for e in entries:
            abs_desc_off = strings_offset + e["desc_offset"]
            f.write(struct.pack("<HxxIIII", e["id"], e["v_start"], e["v_end"], abs_desc_off, e["desc_len"]))
            
        f.write(string_pool)
        
    print(f"Written {output_path} ({num_entries} entries)")
    conn.close()

def main():
    # BDRG = 0x42445247
    compile_table("baseDrgDescriptions", "base_drg_descriptions.bin", 0x42445247)
    # DRGD = 0x44524744
    compile_table("drgDescriptions", "drg_descriptions.bin", 0x44524744)
    # MDCD = 0x4D444344
    compile_table("mdcDescriptions", "mdc_descriptions.bin", 0x4D444344)

if __name__ == "__main__":
    main()
