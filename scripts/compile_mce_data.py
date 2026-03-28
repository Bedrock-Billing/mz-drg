#!/usr/bin/env python3
"""
Compile MCE data from protobuf (mce.bin) into binary lookup tables for Zig.

Usage:
    python scripts/compile_mce_data.py [--input mce.bin] [--output-dir data/bin]

Generates 6 binary files:
    mce_i10dx_master.bin    ICD-10 diagnosis codes
    mce_i10sg_master.bin    ICD-10 procedure codes
    mce_i9dx_master.bin     ICD-9 diagnosis codes
    mce_i9sg_master.bin     ICD-9 procedure codes
    mce_age_ranges.bin      Age range definitions
    mce_discharge_status.bin Valid discharge status codes

Binary format (code master):
    Header (32 bytes):
      magic:            u32  (0x4D434544 = "MCED")
      num_entries:      u32
      entries_offset:   u32
      strings_offset:   u32
      termination_date: i32
      pad:              12 bytes

    Entry (24 bytes each, sorted by code):
      code:        [8]u8   (null-padded ASCII)
      date_start:  i32     (YYYYMMDD)
      date_end:    i32     (YYYYMMDD, 99991231 for ongoing)
      flags_offset:u32     (offset into string block)
      flags_count: u16     (number of flags)
      pad:         2 bytes

    String block: flags as null-terminated strings (flag1\0flag2\0...)

Binary format (age ranges):
    Header (32 bytes):
      magic:            u32  (0x4D434147 = "MCAG")
      num_entries:      u32
      entries_offset:   u32
      strings_offset:   u32
      pad:              16 bytes

    Entry (20 bytes each):
      age_group_offset: u32
      age_group_len:    u32
      start_age:        i32
      end_age:          i32
      date_start:       i32
      date_end:         i32

Binary format (discharge status):
    Header (32 bytes):
      magic:            u32  (0x4D434453 = "MCDS")
      num_entries:      u32
      entries_offset:   u32
      pad:              20 bytes

    Entry (12 bytes each, sorted by code):
      code:        i32
      date_start:  i32
      date_end:    i32
"""

import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import mce_pb2

DEFAULT_MCE_BIN = "java_code/mce/MCE-2.0-43.1.0.0-sources/mce.bin"
DEFAULT_OUTPUT_DIR = "data/bin"

# Magic numbers
MAGIC_CODE_MASTER = 0x4D434544  # "MCED"
MAGIC_AGE_RANGE = 0x4D434147  # "MCAG"
MAGIC_DISCHARGE = 0x4D434453  # "MCDS"

ONGOING_DATE = 99991231


def date_to_int(date_str: str, termination: str) -> int:
    """Convert yyyyMMdd string to int."""
    if not date_str:
        return int(termination) if termination else ONGOING_DATE
    return int(date_str)


def encode_code(code: str) -> bytes:
    """Encode code string to 8-byte null-padded buffer."""
    b = code.encode("ascii")[:8]
    return b + b"\x00" * (8 - len(b))


def compile_code_master(table, termination: str, magic: int) -> bytes:
    """Compile a code master table to binary format."""
    entries = list(table.codeMasterEntries)
    # Sort by code for binary search
    entries.sort(key=lambda e: e.code)

    # Header: 32 bytes
    header_size = 32
    entry_size = 24
    entries_offset = header_size
    total_entries_size = len(entries) * entry_size

    # Build string block: flags as null-terminated strings
    string_block = bytearray()
    flag_cache = {}  # tuple(flags) -> (offset, count)

    entry_data = bytearray()
    for e in entries:
        flags_tuple = tuple(sorted(f for f in e.flags if f))

        if flags_tuple not in flag_cache:
            offset = len(string_block)
            count = len(flags_tuple)
            for flag in flags_tuple:
                string_block.extend(flag.encode("ascii") + b"\x00")
            flag_cache[flags_tuple] = (offset, count)

        offset, count = flag_cache[flags_tuple]
        date_start = date_to_int(e.startDate, termination)
        date_end = date_to_int(e.endDate, termination)

        entry_data.extend(encode_code(e.code))
        entry_data.extend(struct.pack("<iiIHxx", date_start, date_end, offset, count))

    strings_offset = entries_offset + total_entries_size

    # Build header
    header = struct.pack(
        "<IIIIi12x",
        magic,
        len(entries),
        entries_offset,
        strings_offset,
        int(termination) if termination else ONGOING_DATE,
    )

    return header + bytes(entry_data) + bytes(string_block)


def compile_age_ranges(root, termination: str) -> bytes:
    """Compile age ranges to binary format."""
    entries = list(root.ageRangeRoot.ageRangeEntries)

    header_size = 32
    entry_size = 24
    entries_offset = header_size

    # Build string block
    string_block = bytearray()
    entry_data = bytearray()

    for e in entries:
        age_group_bytes = e.ageGroup.encode("ascii") + b"\x00"
        offset = len(string_block)
        string_block.extend(age_group_bytes)

        date_start = date_to_int(e.startDate, termination)
        date_end = date_to_int(e.endDate, termination)

        entry_data.extend(
            struct.pack(
                "<IIiiii",
                offset,
                len(e.ageGroup),
                e.startAge,
                e.endAge,
                date_start,
                date_end,
            )
        )

    strings_offset = entries_offset + len(entries) * entry_size

    header = struct.pack(
        "<IIII16x",
        MAGIC_AGE_RANGE,
        len(entries),
        entries_offset,
        strings_offset,
    )

    return header + bytes(entry_data) + bytes(string_block)


def compile_discharge_status(root, termination: str) -> bytes:
    """Compile discharge status to binary format."""
    entries = list(root.dischargeStatusRoot.dischargeStatusEntries)
    entries.sort(key=lambda e: e.code)

    header_size = 32
    entry_size = 12
    entries_offset = header_size

    entry_data = bytearray()
    for e in entries:
        date_start = date_to_int(e.startDate, termination)
        date_end = date_to_int(e.endDate, termination)
        entry_data.extend(struct.pack("<iii", e.code, date_start, date_end))

    header = struct.pack(
        "<III20x",
        MAGIC_DISCHARGE,
        len(entries),
        entries_offset,
    )

    return header + bytes(entry_data)


def parse_mce_bin(path: str) -> mce_pb2.Root:
    """Parse mce.bin protobuf file."""
    with open(path, "rb") as f:
        data = f.read()
    root = mce_pb2.Root()
    root.ParseFromString(data)
    return root


def main():
    parser = argparse.ArgumentParser(description="Compile MCE data to binary")
    parser.add_argument("--input", default=DEFAULT_MCE_BIN, help="Path to mce.bin")
    parser.add_argument(
        "--output-dir", default=DEFAULT_OUTPUT_DIR, help="Output directory"
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    root = parse_mce_bin(args.input)
    termination = root.terminationDate

    print(f"MCE Version: {root.version}")
    print(f"Termination: {termination}")
    print()

    # Compile tables
    tables = [
        ("mce_i10dx_master.bin", root.i10DxMasterRoot, MAGIC_CODE_MASTER, "ICD-10 DX"),
        ("mce_i10sg_master.bin", root.i10SgMasterRoot, MAGIC_CODE_MASTER, "ICD-10 SG"),
        ("mce_i9dx_master.bin", root.i9DxMasterRoot, MAGIC_CODE_MASTER, "ICD-9 DX"),
        ("mce_i9sg_master.bin", root.i9SgMasterRoot, MAGIC_CODE_MASTER, "ICD-9 SG"),
    ]

    for filename, table, magic, desc in tables:
        data = compile_code_master(table, termination, magic)
        path = output_dir / filename
        path.write_bytes(data)
        print(
            f"  {desc:12s}: {len(table.codeMasterEntries):6d} codes → {path} ({len(data):,} bytes)"
        )

    # Age ranges
    age_data = compile_age_ranges(root, termination)
    age_path = output_dir / "mce_age_ranges.bin"
    age_path.write_bytes(age_data)
    print(
        f"  {'Age Ranges':12s}: {len(root.ageRangeRoot.ageRangeEntries):6d} entries → {age_path} ({len(age_data):,} bytes)"
    )

    # Discharge status
    ds_data = compile_discharge_status(root, termination)
    ds_path = output_dir / "mce_discharge_status.bin"
    ds_path.write_bytes(ds_data)
    print(
        f"  {'Disch Status':12s}: {len(root.dischargeStatusRoot.dischargeStatusEntries):6d} entries → {ds_path} ({len(ds_data):,} bytes)"
    )

    print(f"\nDone. {6} files written to {output_dir}/")


if __name__ == "__main__":
    main()
