#!/usr/bin/env python3
"""
Extract and analyze MCE data from the CMS protobuf binary (mce.bin).

Usage:
    python scripts/extract_mce_data.py [--input mce.bin] [--summary] [--dump-codes TYPE]

This script:
1. Parses mce.bin (protobuf Root message)
2. Displays summary statistics
3. Optionally dumps specific code tables for inspection
"""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

# Add scripts dir to path for generated protobuf module
sys.path.insert(0, str(Path(__file__).parent))
import mce_pb2

DEFAULT_MCE_BIN = "java_code/mce/MCE-2.0-43.1.0.0-sources/mce.bin"


def date_to_int(date_str: str, termination: str) -> int:
    """Convert yyyyMMdd string to int. Empty string → termination date."""
    if not date_str:
        return int(termination) if termination else 99991231
    return int(date_str)


def parse_mce_bin(path: str) -> mce_pb2.Root:
    """Parse the mce.bin protobuf file."""
    with open(path, "rb") as f:
        data = f.read()
    root = mce_pb2.Root()
    root.ParseFromString(data)
    return root


def print_summary(root: mce_pb2.Root):
    """Print summary of all tables in the MCE data."""
    print(f"MCE Data Summary")
    print(f"  Version:           {root.version}")
    print(f"  Date format:       {root.dateFormat}")
    print(f"  Termination date:  {root.terminationDate}")
    print()

    # Code master tables
    tables = [
        ("i10Dx", root.i10DxMasterRoot, "ICD-10 Diagnosis"),
        ("i10Sg", root.i10SgMasterRoot, "ICD-10 Procedure (Surgical)"),
        ("i9Dx", root.i9DxMasterRoot, "ICD-9 Diagnosis"),
        ("i9Sg", root.i9SgMasterRoot, "ICD-9 Procedure (Surgical)"),
    ]

    for name, table, desc in tables:
        entries = table.codeMasterEntries
        print(f"  {desc} ({name}): {len(entries)} codes")

        # Count flags
        flag_counts = Counter()
        codes_with_flags = 0
        for e in entries:
            flags = [f for f in e.flags if f]
            if flags:
                codes_with_flags += 1
                for f in flags:
                    flag_counts[f] += 1

        print(f"    Codes with flags:  {codes_with_flags}")
        if flag_counts:
            top = flag_counts.most_common(5)
            print(f"    Top flags:         {', '.join(f'{f}({c})' for f, c in top)}")
        print()

    # Age ranges
    print(f"  Age Ranges: {len(root.ageRangeRoot.ageRangeEntries)} entries")
    for e in root.ageRangeRoot.ageRangeEntries:
        end = e.endDate or "ongoing"
        print(
            f"    {e.ageGroup:12s}: ages {e.startAge:3d}-{e.endAge:3d}  ({e.startDate} to {end})"
        )
    print()

    # Discharge status
    print(
        f"  Discharge Status: {len(root.dischargeStatusRoot.dischargeStatusEntries)} entries"
    )
    codes = sorted(set(e.code for e in root.dischargeStatusRoot.dischargeStatusEntries))
    print(f"    Codes: {codes}")
    print()

    # All flags
    all_flags = set()
    for _, table, _ in tables:
        for entry in table.codeMasterEntries:
            all_flags.update(f for f in entry.flags if f)
    print(f"  All unique flags ({len(all_flags)}):")
    for f in sorted(all_flags):
        print(f"    {f}")


def dump_codes(root: mce_pb2.Root, table_name: str, limit: int = 50):
    """Dump codes from a specific table."""
    table_map = {
        "i10dx": root.i10DxMasterRoot,
        "i10sg": root.i10SgMasterRoot,
        "i9dx": root.i9DxMasterRoot,
        "i9sg": root.i9SgMasterRoot,
    }

    table = table_map.get(table_name.lower())
    if table is None:
        print(f"Unknown table: {table_name}")
        print(f"Available: {', '.join(table_map.keys())}")
        return

    entries = table.codeMasterEntries
    print(f"Table {table_name}: {len(entries)} entries (showing first {limit})")
    print(f"{'Code':<12} {'Start':<10} {'End':<10} {'Flags'}")
    print("-" * 60)

    for e in entries[:limit]:
        flags = ", ".join(f for f in e.flags if f) or "(none)"
        print(f"{e.code:<12} {e.startDate:<10} {e.endDate or 'ongoing':<10} {flags}")


def export_json(root: mce_pb2.Root, output_path: str):
    """Export parsed data to JSON for inspection."""
    data = {
        "version": root.version,
        "dateFormat": root.dateFormat,
        "terminationDate": root.terminationDate,
        "i10dx": [
            {
                "code": e.code,
                "startDate": e.startDate,
                "endDate": e.endDate,
                "flags": [f for f in e.flags if f],
            }
            for e in root.i10DxMasterRoot.codeMasterEntries
        ],
        "i10sg": [
            {
                "code": e.code,
                "startDate": e.startDate,
                "endDate": e.endDate,
                "flags": [f for f in e.flags if f],
            }
            for e in root.i10SgMasterRoot.codeMasterEntries
        ],
        "i9dx": [
            {
                "code": e.code,
                "startDate": e.startDate,
                "endDate": e.endDate,
                "flags": [f for f in e.flags if f],
            }
            for e in root.i9DxMasterRoot.codeMasterEntries
        ],
        "i9sg": [
            {
                "code": e.code,
                "startDate": e.startDate,
                "endDate": e.endDate,
                "flags": [f for f in e.flags if f],
            }
            for e in root.i9SgMasterRoot.codeMasterEntries
        ],
        "ageRanges": [
            {
                "ageGroup": e.ageGroup,
                "startAge": e.startAge,
                "endAge": e.endAge,
                "startDate": e.startDate,
                "endDate": e.endDate,
            }
            for e in root.ageRangeRoot.ageRangeEntries
        ],
        "dischargeStatus": [
            {"code": e.code, "startDate": e.startDate, "endDate": e.endDate}
            for e in root.dischargeStatusRoot.dischargeStatusEntries
        ],
    }

    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"Exported to {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Extract and analyze MCE data")
    parser.add_argument("--input", default=DEFAULT_MCE_BIN, help="Path to mce.bin")
    parser.add_argument("--summary", action="store_true", help="Print summary")
    parser.add_argument(
        "--dump-codes",
        type=str,
        help="Dump codes from table (i10dx, i10sg, i9dx, i9sg)",
    )
    parser.add_argument("--dump-limit", type=int, default=50, help="Max codes to dump")
    parser.add_argument("--export-json", type=str, help="Export to JSON file")
    args = parser.parse_args()

    root = parse_mce_bin(args.input)

    if args.summary or (not args.dump_codes and not args.export_json):
        print_summary(root)

    if args.dump_codes:
        dump_codes(root, args.dump_codes, args.dump_limit)

    if args.export_json:
        export_json(root, args.export_json)


if __name__ == "__main__":
    main()
