"""
Compile ICD-10-CM and ICD-10-PCS conversion tables into a single binary file.

Downloads CMS conversion tables for each adjacent year pair (e.g. 2023→2024,
2024→2025, 2025→2026), generates both forward (newer→older) and backward
(older→newer) mappings, and writes them into a single binary file per code type.

Usage:
    python scripts/compile_icd_conversions.py
"""

import logging
import os
import struct
from datetime import date
from typing import Any

from download_icd_conversions import (
    CMS_PCS_URL,
    CMS_URL,
    _download_and_extract,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_BIN_DIR = os.path.join(SCRIPT_DIR, "..", "data", "bin")

# MS-DRG versions we support
# (version, icd_year) — we need conversion tables between adjacent icd_years
SUPPORTED_YEARS = [2023, 2024, 2025, 2026]

# Direction constants (must match Zig conversion.zig)
DIRECTION_FORWARD = 0  # newer → older
DIRECTION_BACKWARD = 1  # older → newer


def pack_code(code: str) -> bytes:
    """Pack an ICD code into 8 bytes (null-padded, dots stripped)."""
    encoded = code.upper().replace(".", "").encode("ascii")
    if len(encoded) > 8:
        encoded = encoded[:8]
    return encoded.ljust(8, b"\x00")


def date_to_u32(d: date) -> int:
    """Convert a date to u32 (YYYYMMDD)."""
    return d.year * 10000 + d.month * 100 + d.day


def build_entries(
    cm_data: list[dict[str, Any]],
    pair_index: int,
) -> list[tuple]:
    """
    Build forward and backward entries from parsed conversion table data.

    Each CMS row: {current_code, effective_date, previous_codes: [str]}
    - Forward: current_code → previous_code (newer → older)
    - Backward: previous_code → current_code (older → newer)

    Returns list of (source_bytes, target_bytes, effective_date_u32, pair_index, direction)
    """
    entries = []

    for row in cm_data:
        current = row["current_code"]
        eff_date = row["effective_date"]
        eff_u32 = date_to_u32(eff_date)

        for prev in row["previous_codes"]:
            # Forward: current → previous (newer → older)
            entries.append(
                (
                    pack_code(current),
                    pack_code(prev),
                    eff_u32,
                    pair_index,
                    DIRECTION_FORWARD,
                )
            )
            # Backward: previous → current (older → newer)
            entries.append(
                (
                    pack_code(prev),
                    pack_code(current),
                    eff_u32,
                    pair_index,
                    DIRECTION_BACKWARD,
                )
            )

    return entries


def compile_conversions(
    conversion_type: str,  # "icd10cm" or "icd10pcs"
    url_template: str,
    output_filename: str,
    magic: int,
):
    """
    Download, parse, and compile conversion tables for all year pairs.
    """
    logger.info(f"Compiling {conversion_type} conversion tables...")

    all_entries: list[tuple] = []

    for i in range(len(SUPPORTED_YEARS) - 1):
        prev_year = SUPPORTED_YEARS[i]
        curr_year = SUPPORTED_YEARS[i + 1]
        logger.info(f"  Processing {prev_year}→{curr_year}...")

        url = url_template.format(year=curr_year)
        data = _download_and_extract(url, conversion_type)

        if data is None:
            logger.warning(f"  Failed to download {url}, skipping")
            continue

        logger.info(f"  Downloaded {len(data)} conversion entries")

        entries = build_entries(data, i)
        all_entries.extend(entries)
        logger.info(f"  Generated {len(entries)} mapping entries")

    # Sort: by pair_index first, then source_code for binary search
    all_entries.sort(key=lambda e: (e[3], e[0]))

    logger.info(f"Total entries: {len(all_entries)}")

    # Write binary
    output_path = os.path.join(DATA_BIN_DIR, output_filename)
    num_pairs = len(SUPPORTED_YEARS) - 1

    with open(output_path, "wb") as f:
        # Header: magic(u32) + num_pairs(u32) + entries_offset(u32) + years(u32[])
        header_size = (
            12 + num_pairs * 4
        )  # 12 bytes header + 4 bytes per pair (first year)
        num_entries = len(all_entries)

        f.write(struct.pack("<III", magic, num_pairs, header_size))

        # Year values: first year of each pair
        for i in range(num_pairs):
            f.write(struct.pack("<I", SUPPORTED_YEARS[i]))

        # Entry data
        for src, tgt, eff, pidx, direction in all_entries:
            f.write(src)
            f.write(tgt)
            f.write(struct.pack("<I", eff))
            f.write(struct.pack("<H", pidx))
            f.write(struct.pack("<B", direction))

    logger.info(f"Written to {output_path} ({os.path.getsize(output_path)} bytes)")


def main():
    os.makedirs(DATA_BIN_DIR, exist_ok=True)

    compile_conversions(
        "icd10cm",
        CMS_URL,
        "icd10cm_conversions.bin",
        0x49434443,  # "ICDC"
    )

    compile_conversions(
        "icd10pcs",
        CMS_PCS_URL,
        "icd10pcs_conversions.bin",
        0x49434450,  # "ICDP"
    )


if __name__ == "__main__":
    main()
