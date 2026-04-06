import logging
import re
from datetime import datetime
from io import BytesIO
from typing import Any
from zipfile import ZipFile

import requests

YEAR = 2026

logger = logging.getLogger(__name__)

CMS_URL = "https://www.cms.gov/files/zip/{year}-conversion-table.zip"
CMS_PCS_URL = "https://www.cms.gov/files/zip/{year}-icd-10-pcs-conversion-table.zip"


def expand_code_range(start_code: str, end_code: str) -> list[str]:
    """
    Expands a range of ICD codes.
    Example: expand_code_range("H02.101", "H02.106")
    Returns: ["H02.101", "H02.102", "H02.103", "H02.104", "H02.105", "H02.106"]
    """
    # Find the common prefix and the numeric suffixes
    common_prefix = ""
    min_len = min(len(start_code), len(end_code))
    for i in range(min_len):
        if start_code[i] == end_code[i]:
            common_prefix += start_code[i]
        else:
            break

    start_suffix_str = start_code[len(common_prefix) :]
    end_suffix_str = end_code[len(common_prefix) :]

    if start_suffix_str.isdigit() and end_suffix_str.isdigit():
        start_suffix = int(start_suffix_str)
        end_suffix = int(end_suffix_str)
        num_digits = len(start_suffix_str)

        return [
            f"{common_prefix}{str(i).zfill(num_digits)}"
            for i in range(start_suffix, end_suffix + 1)
        ]
    else:
        # Fallback for complex cases, just return start and end
        return [start_code, end_code]


def parse_icd_conversion_table(file_content: str) -> list[dict[str, Any]]:
    """
    Parses the ICD-10-CM conversion table content and returns a list of dictionaries.
    """
    parsed_data = []
    lines = file_content.splitlines()

    # Find the header row to start processing from the next line
    header_index = -1
    for i, line in enumerate(lines):
        if (
            "Current code assignment" in line
            and "Previous Code(s) Assignment" in line
        ):
            header_index = i
            break

    start_index = header_index + 1 if header_index != -1 else 0

    for line in lines[start_index:]:
        line = line.strip()
        if not line:
            continue

        # Split the line into columns based on multiple spaces or a tab
        parts = re.split(r"\s{2,}|\t", line, maxsplit=2)
        if len(parts) < 3:
            continue

        current_code, effective_date_str, prev_codes_str = parts
        current_code = current_code.strip()
        effective_date_str = effective_date_str.strip()
        prev_codes_str = prev_codes_str.strip()

        # Skip rows based on the conditions
        if (
            "none" in prev_codes_str.lower()
            or "categories" in prev_codes_str.lower()
        ):
            continue

        effective_date = None
        try:
            # If it's a year like '2017'
            year = int(effective_date_str)
            effective_date = datetime(year, 10, 1).date()
        except ValueError:
            # If it's a date like '01/01/21'
            try:
                dt_obj = datetime.strptime(effective_date_str, "%m/%d/%y")
                effective_date = dt_obj.date()
            except ValueError:
                # Fallback if the format is unexpected
                pass

        if not effective_date:
            continue

        # Clean and parse the "Previous Code(s) Assignment" column
        prev_codes_str = prev_codes_str.replace('"', "").replace(" and ", ", ")

        raw_codes = re.split(r"[;,]", prev_codes_str)
        final_codes = []

        for code in raw_codes:
            code = code.strip()
            if not code:
                continue

            if "-" in code:
                range_parts = code.split("-")
                if len(range_parts) == 2:
                    start_code, end_code = [p.strip() for p in range_parts]

                    if len(end_code) < len(start_code):
                        end_code = start_code[: -len(end_code)] + end_code

                    final_codes.extend(expand_code_range(start_code, end_code))
                else:
                    final_codes.append(code)  # Not a simple range
            else:
                final_codes.append(code)

        parsed_data.append(
            {
                "current_code": current_code,
                "effective_date": effective_date,
                "previous_codes": final_codes,
            }
        )

    return parsed_data

def parse_pcs_conversion_table(file_content: str) -> list[dict[str, Any]]:
    """Parses PCS text file content."""
    parsed_data = []
    lines = file_content.splitlines()

    # Skip header
    start_idx = 1 if len(lines) > 0 and "Current code" in lines[0] else 0

    for line in lines[start_idx:]:
        parts = line.strip().split("\t")
        if len(parts) < 7:
            continue  # Skip malformed lines

        current_code = parts[0]
        effective_year = parts[2]
        previous_codes = parts[3].split(",") if parts[3] else []
        effective_month_day = parts[7] if len(parts) == 8 else parts[6]

        if (
            current_code.lower() == "nopcs"
            or (
                len(previous_codes) > 4 and previous_codes[0].lower() == "nopcs"
            )  # check len to avoid error
            or (len(previous_codes) > 0 and current_code == previous_codes[0])
        ):
            continue  # Skip invalid codes

        if effective_year.isdigit() and len(effective_year) == 4:
            year = int(effective_year)
            if effective_month_day and "." in effective_month_day:
                try:
                    month, day = map(int, effective_month_day.split("."))
                except ValueError:
                    month, day = 1, 1
            else:
                month, day = 1, 1  # Default to January 1st if not provided

            effective_date = datetime(year, month, day).date()

            parsed_data.append(
                {
                    "current_code": current_code,
                    "effective_date": effective_date,
                    "previous_codes": previous_codes,
                    "code_type": 1,  # PCS
                }
            )
    return parsed_data

def _download_and_extract(
    url: str, conversion_type: str
) -> list[dict[str, Any]] | None:
    """
    Downloads the zip file and extracts the relevant text file.
    conversion_type: 'icd10cm' or 'icd10pcs'
    """
    try:
        logger.info(f"Downloading {url}...")
        response = requests.get(url, timeout=60)
        if response.status_code != 200:
            logger.warning(
                f"Failed to download {url}: Status {response.status_code}"
            )
            return None

        with ZipFile(BytesIO(response.content)) as z:
            # Find the text file that likely contains the conversion table
            # For CM: usually 'gem_i9gem.txt' or similar? No, conversion table is different.
            # It's usually "icd10cm_conversion_{year}.txt" or similar.
            # Let's search for a .txt file that seems right.

            target_file_name = None
            for name in z.namelist():
                if not name.lower().endswith(".txt"):
                    continue

                # Heuristics for finding the right file
                lower_name = name.lower()
                if (
                    conversion_type == "icd10cm"
                    and "conversion" in lower_name
                    and "pcs" not in lower_name
                ):
                    target_file_name = name
                    break
                elif (
                    conversion_type == "icd10pcs"
                    and "conversion" in lower_name
                    and "pcs" in lower_name
                ):
                    target_file_name = name
                    break
                # Fallback generic check if specific naming fails
                if conversion_type == "icd10cm" and "gem" in lower_name:
                    # Sometimes they might refer to GEMs, but we want conversion table specifically
                    pass

            if not target_file_name:
                # Try to find *any* txt file if specific match fails, but be careful
                for name in z.namelist():
                    if (
                        name.lower().endswith(".txt")
                        and "conversion" in name.lower()
                    ):
                        target_file_name = name
                        break

            if not target_file_name:
                logger.warning(
                    f"Could not find a suitable conversion text file in zip: {url}"
                )
                return None

            logger.info(f"Extracting {target_file_name}...")
            with z.open(target_file_name) as f:
                content = f.read().decode("utf-8", errors="replace")

                if conversion_type == "icd10cm":
                    return parse_icd_conversion_table(
                        content
                    )
                else:
                    return parse_pcs_conversion_table(
                        content
                    )

    except Exception as e:
        logger.error(f"Error downloading/extracting {url}: {e}")
        return None

if __name__ == "__main__":
    icd10cm_data = _download_and_extract(CMS_URL.format(year=YEAR), "icd10cm")
    icd10pcs_data = _download_and_extract(CMS_PCS_URL.format(year=YEAR), "icd10pcs")
    print(icd10cm_data)
