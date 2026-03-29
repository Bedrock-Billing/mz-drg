import sqlite3
import struct
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")


def main():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    if not os.path.exists(DATA_BIN_DIR):
        os.makedirs(DATA_BIN_DIR)

    # 1. Load and Index Cluster Information
    print("Indexing Cluster Information...")
    cursor.execute("SELECT key, value FROM clusterInformation ORDER BY key")

    cluster_map = {}  # Z@ID -> Integer ID
    cluster_data_list = []  # List of (key, data_dict)

    # ID 0 is reserved/null
    next_id = 1

    for key, value_json in cursor:
        cluster_map[key] = next_id
        cluster_data_list.append((key, json.loads(value_json)))
        next_id += 1

    num_clusters = len(cluster_data_list)
    print(f"Indexed {num_clusters} clusters.")

    # 2. Compile Cluster Info (CLIN)
    print("Compiling Cluster Info...")

    string_pool = bytearray()
    string_map = {}

    def add_string(s):
        if s in string_map:
            return string_map[s]
        offset = len(string_pool)
        encoded = s.encode("utf-8")
        string_pool.extend(encoded)
        string_map[s] = (offset, len(encoded))
        return offset, len(encoded)

    info_data = bytearray()
    info_offsets = []

    for key, data in cluster_data_list:
        # Record start offset of this cluster's data
        info_offsets.append(len(info_data))

        # Name
        n_off, n_len = add_string(key)
        info_data.extend(struct.pack("<II", n_off, n_len))

        # Suppression MDCs
        supp_mdcs = data.get("suppressionMdcs", [])
        info_data.append(len(supp_mdcs))  # supp_count: u8
        for mdc in supp_mdcs:
            info_data.append(int(mdc))  # mdc: u8

        # Choices
        choices = data.get("choices", [])
        info_data.append(len(choices))  # choice_count: u8

        for c in choices:
            info_data.append(int(c.get("choice", 0)))  # choice_id: u8

            codes = c.get("codes", [])
            info_data.append(len(codes))  # code_count: u8

            for code in codes:
                s_off, s_len = add_string(code)
                # We will adjust s_off later
                info_data.extend(struct.pack("<II", s_off, s_len))

    # Write cluster_info.bin
    with open(os.path.join(DATA_BIN_DIR, "cluster_info.bin"), "wb") as f:
        magic = 0x434C494E  # CLIN

        # Header: Magic(4), NumClusters(4), OffsetsOffset(4), DataOffset(4), StringsOffset(4)
        header_size = 20
        offsets_size = num_clusters * 4

        offsets_offset = header_size
        data_offset = offsets_offset + offsets_size
        strings_offset = data_offset + len(info_data)

        f.write(
            struct.pack(
                "<IIIII",
                magic,
                num_clusters,
                offsets_offset,
                data_offset,
                strings_offset,
            )
        )

        # Write Offsets (Absolute)
        for off in info_offsets:
            f.write(struct.pack("<I", data_offset + off))

        # Write Data

        final_data = bytearray()

        for key, data in cluster_data_list:
            # Name
            n_off, n_len = add_string(key)
            abs_n_off = strings_offset + n_off
            final_data.extend(struct.pack("<II", abs_n_off, n_len))

            supp_mdcs = data.get("suppressionMdcs", [])
            final_data.append(len(supp_mdcs))
            for mdc in supp_mdcs:
                final_data.append(int(mdc))

            choices = data.get("choices", [])
            final_data.append(len(choices))

            for c in choices:
                final_data.append(int(c.get("choice", 0)))
                codes = c.get("codes", [])
                final_data.append(len(codes))
                for code in codes:
                    s_off, s_len = add_string(code)
                    abs_s_off = strings_offset + s_off
                    final_data.extend(struct.pack("<II", abs_s_off, s_len))

        f.write(final_data)
        f.write(string_pool)

    print(f"Written cluster_info.bin ({len(string_pool)} bytes strings)")

    # 3. Compile Cluster Map (CLMP)
    print("Compiling Cluster Map...")
    cursor.execute(
        "SELECT key, version_start, version_end, value FROM clusterIds ORDER BY key"
    )

    map_entries = []
    list_data = bytearray()

    for code, v_start, v_end, value_json in cursor:
        cluster_ids = json.loads(value_json)

        list_offset = len(list_data)
        count = len(cluster_ids)

        for c_key in cluster_ids:
            c_id = cluster_map.get(c_key, 0)
            if c_id == 0:
                print(f"Warning: Unknown cluster {c_key}")
            list_data.extend(struct.pack("<H", c_id))  # u16

        map_entries.append(
            {
                "code": code,
                "v_start": int(v_start),
                "v_end": int(v_end),
                "offset": list_offset,
                "count": count,
            }
        )

    # Write cluster_map.bin
    with open(os.path.join(DATA_BIN_DIR, "cluster_map.bin"), "wb") as f:
        magic = 0x434C4D50  # CLMP
        num_entries = len(map_entries)

        # Header: Magic(4), NumEntries(4), EntriesOffset(4), ListDataOffset(4)
        header_size = 16
        entries_offset = header_size
        # Entry size: Code(8) + VStart(4) + VEnd(4) + Offset(4) + Count(4) = 24 bytes
        list_data_offset = entries_offset + (num_entries * 24)

        f.write(
            struct.pack("<IIII", magic, num_entries, entries_offset, list_data_offset)
        )

        for e in map_entries:
            code_bytes = e["code"].encode("utf-8").ljust(8, b"\x00")[:8]
            abs_offset = list_data_offset + e["offset"]
            f.write(code_bytes)
            f.write(
                struct.pack("<iiII", e["v_start"], e["v_end"], abs_offset, e["count"])
            )

        f.write(list_data)

    print(f"Written cluster_map.bin ({len(map_entries)} entries)")
    conn.close()


if __name__ == "__main__":
    main()
