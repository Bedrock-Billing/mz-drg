import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
BIN_PATH = os.path.join(SCRIPT_DIR, "..", "data", "bin", "drg_formulas.bin")


def compile_drg_formulas():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    print("Loading DRG Formulas...")
    cursor.execute(
        "SELECT key, version_start, version_end, value FROM drgFormulas ORDER BY CAST(key AS INTEGER), version_start"
    )

    entries = []
    all_formulas = []
    string_pool = bytearray()
    string_map = {}  # Dedup strings

    def add_string(s):
        if s in string_map:
            return string_map[s]
        offset = len(string_pool)
        encoded = s.encode("utf-8")
        string_pool.extend(encoded)
        string_map[s] = (offset, len(encoded))
        return offset, len(encoded)

    suppression_pool = bytearray()

    for key, v_start, v_end, value_json in cursor:
        mdc = int(key)
        formulas_json = json.loads(value_json)
        formulas_json = sorted(
            formulas_json, key=lambda x: (int(x.get("mdc", 0)), int(x.get("rank", 0)))
        )

        formula_list_start_index = len(all_formulas)
        formula_count = len(formulas_json)

        for f in formulas_json:
            # Handle Strings
            form_str = f.get("formula", "")
            f_off, f_len = add_string(form_str)

            surgical_str = f.get("surgical", "NA")
            surgical_bytes = surgical_str.encode("utf-8").ljust(8, b"\0")[:8]

            # Handle Suppression List
            supp_list = f.get("severitySuppressionOperand", [])
            # Filter out empty strings if any
            supp_list = [s for s in supp_list if s]

            supp_offset = len(suppression_pool)
            supp_count = len(supp_list)

            for s in supp_list:
                s_off, s_len = add_string(s)
                # Write (offset, len) to suppression pool
                suppression_pool.extend(struct.pack("<II", s_off, s_len))

            all_formulas.append(
                {
                    "mdc": int(f.get("mdc", 0)),
                    "rank": int(f.get("rank", 0)),
                    "baseDrg": int(f.get("baseDrg", 0)),
                    "drg": int(f.get("drg", 0)),
                    "surgical": surgical_bytes,
                    "reRouteMdcId": int(f.get("reRouteMdcId", 0)),
                    "drgSeverity": int(f.get("drgSeverity", 0)),
                    "formula_offset": f_off,
                    "formula_len": f_len,
                    "supp_offset": supp_offset,
                    "supp_count": supp_count,
                }
            )

        entries.append(
            {
                "mdc": mdc,
                "v_start": int(v_start),
                "v_end": int(v_end),
                "start_index": formula_list_start_index,
                "count": formula_count,
            }
        )

    print(f"Processed {len(entries)} MDC versions.")
    print(f"Total Formulas: {len(all_formulas)}")
    print(f"String Pool Size: {len(string_pool)} bytes")

    with open(BIN_PATH, "wb") as f:
        # Header
        # Magic: 0x464F524D (FORM)
        magic = 0x464F524D
        num_entries = len(entries)
        num_formulas = len(all_formulas)

        # Layout:
        # Header (24 bytes)
        # Entries Array
        # Formulas Array
        # Suppression Pool
        # String Pool

        header_size = 24
        entry_size = 20  # mdc(4) + v_start(4) + v_end(4) + start_index(4) + count(4)
        formula_size = 48  # mdc(4) + rank(4) + base(4) + drg(4) + surg(8) + route(4) + sev(4) + f_off(4) + f_len(4) + s_off(4) + s_cnt(4)

        entries_offset = header_size
        formulas_offset = entries_offset + (num_entries * entry_size)
        suppression_offset = formulas_offset + (num_formulas * formula_size)
        strings_offset = suppression_offset + len(suppression_pool)
        # Ensure formulas are sorted by mdc, rank so they are processed in correct order within grouper

        f.write(
            struct.pack(
                "<IIIIII",
                magic,
                num_entries,
                num_formulas,
                entries_offset,
                formulas_offset,
                strings_offset,
            )
        )

        # Write Entries
        for e in entries:
            f.write(
                struct.pack(
                    "<IIIII",
                    e["mdc"],
                    e["v_start"],
                    e["v_end"],
                    e["start_index"],
                    e["count"],
                )
            )

        # Write Formulas
        for form in all_formulas:
            # Adjust offsets to be absolute file offsets
            abs_f_off = strings_offset + form["formula_offset"]
            abs_s_off = suppression_offset + form["supp_offset"]

            f.write(
                struct.pack(
                    "<IIII8sIIIIII",
                    form["mdc"],
                    form["rank"],
                    form["baseDrg"],
                    form["drg"],
                    form["surgical"],
                    form["reRouteMdcId"],
                    form["drgSeverity"],
                    abs_f_off,
                    form["formula_len"],
                    abs_s_off,
                    form["supp_count"],
                )
            )

        for i in range(0, len(suppression_pool), 8):
            s_off, s_len = struct.unpack("<II", suppression_pool[i : i + 8])
            f.write(struct.pack("<II", strings_offset + s_off, s_len))

        # Write String Pool
        f.write(string_pool)

    print(f"Written to {BIN_PATH}")
    conn.close()


if __name__ == "__main__":
    compile_drg_formulas()
