import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")

def main():
    print("Compiling genderMdcs...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute("SELECT key, version_start, version_end, value FROM genderMdcs ORDER BY key, version_start")
    
    entries = []
    
    for code, v_start, v_end, value_json in cursor:
        data = json.loads(value_json)
        entries.append({
            "code": code,
            "v_start": int(v_start),
            "v_end": int(v_end),
            "male_mdc": int(data.get("maleMdc", 0)),
            "female_mdc": int(data.get("femaleMdc", 0))
        })
        
    print(f"Processed {len(entries)} gender MDC entries.")
    
    output_path = os.path.join(DATA_BIN_DIR, "gender_mdcs.bin")
    with open(output_path, "wb") as f:
        # Header
        # Magic: u32 (GEND = 0x47454E44)
        # Num Entries: u32
        # Entries Offset: u32
        
        magic = 0x47454E44
        num_entries = len(entries)
        header_size = 12
        entries_offset = header_size
        
        f.write(struct.pack("<III", magic, num_entries, entries_offset))
        
        # Write Entries
        # Code: 8 bytes (padded)
        # V_Start: i32
        # V_End: i32
        # Male MDC: i32
        # Female MDC: i32
        
        for e in entries:
            code_bytes = e["code"].encode('utf-8').ljust(8, b'\x00')[:8]
            f.write(code_bytes)
            f.write(struct.pack("<iiii", e["v_start"], e["v_end"], e["male_mdc"], e["female_mdc"]))
            
    print(f"Written to {output_path}")
    conn.close()

if __name__ == "__main__":
    main()
