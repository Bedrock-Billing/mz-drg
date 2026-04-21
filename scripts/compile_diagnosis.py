import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
BIN_PATH = os.path.join(SCRIPT_DIR, "..", "data", "bin", "diagnosis.bin")


def compile_diagnosis():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 1. Load Schemes
    print("Loading Schemes...")
    cursor.execute("SELECT key, value FROM schemeIndex ORDER BY CAST(key AS INTEGER)")
    schemes = []
    scheme_key_to_index = {}
    index = 0
    for key, value_json in cursor:
        obj = json.loads(value_json)
        schemes.append(obj)
        scheme_key_to_index[int(key)] = index
        index += 1

    num_schemes = len(schemes)
    print(f"Loaded {num_schemes} schemes.")

    # 2. Load Diagnoses
    print("Loading Diagnoses...")
    cursor.execute(
        "SELECT key, version_start, version_end, value FROM diagnosisAll ORDER BY key, version_start"
    )
    diagnoses = []
    for key, v_start, v_end, value in cursor:
        # value is the scheme_id
        scheme_key = int(value)
        if scheme_key in scheme_key_to_index:
            scheme_index = scheme_key_to_index[scheme_key]
            diagnoses.append(
                {
                    "code": key,
                    "v_start": int(v_start),
                    "v_end": int(v_end),
                    "scheme_id": scheme_index,
                }
            )
        else:
            print(f"Warning: Scheme key {scheme_key} not found for diagnosis {key}")

    num_diagnoses = len(diagnoses)
    print(f"Loaded {num_diagnoses} diagnoses.")

    with open(BIN_PATH, "wb") as f:
        # Header
        # Magic: 0x44494147 (DIAG)
        magic = 0x44494147

        # Calculate offsets
        # Header size: 4 (magic) + 4 (num_schemes) + 4 (num_diagnoses) + 4 (schemes_offset) + 4 (diagnoses_offset) = 20 bytes
        header_size = 20

        schemes_offset = header_size
        # Scheme struct size: mdc(4) + severity(4) + op(4) + hac(4) + dxcat(4) = 20 bytes
        scheme_struct_size = 20
        schemes_size = num_schemes * scheme_struct_size

        diagnoses_offset = schemes_offset + schemes_size

        # Write Header
        f.write(
            struct.pack(
                "<IIIII",
                magic,
                num_schemes,
                num_diagnoses,
                schemes_offset,
                diagnoses_offset,
            )
        )

        # Write Schemes
        for s in schemes:
            # mdc: i32
            # severity: [4]u8
            # operandsPattern: i32
            # hacOperandPattern: i32
            # dxCatListPattern: i32

            severity_bytes = s["severity"].encode("utf-8").ljust(4, b"\0")

            f.write(
                struct.pack(
                    "<I4sIII",
                    s["mdc"],
                    severity_bytes,
                    s["operandsPattern"],
                    s["hacOperandPattern"],
                    s["dxCatListPattern"],
                )
            )

        # Write Diagnoses
        for d in diagnoses:
            # code: [8]u8
            # v_start: i32
            # v_end: i32
            # scheme_id: i32

            code_bytes = d["code"].encode("utf-8").ljust(8, b"\0")

            f.write(
                struct.pack(
                    "<8sIII", code_bytes, d["v_start"], d["v_end"], d["scheme_id"]
                )
            )

    print(f"Written to {BIN_PATH}")
    conn.close()


if __name__ == "__main__":
    compile_diagnosis()
