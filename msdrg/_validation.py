"""
Input validation for MS-DRG grouper and MCE editor claims.

Validates Python-side inputs before serialization to avoid opaque null
returns from the native Zig layer. Raises ``ValueError`` with clear,
field-level messages.
"""

from __future__ import annotations

from typing import Any


def _check_int(value: Any, field: str) -> None:
    """Raise if *value* is not an int (bool excluded)."""
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(
            f"'{field}' must be an int, got {type(value).__name__}: {value!r}"
        )


def _check_sex(value: Any) -> None:
    """Raise if *value* is not a valid sex code."""
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(
            f"'sex' must be an int (0=Male, 1=Female, 2=Unknown), "
            f"got {type(value).__name__}: {value!r}"
        )
    if value not in (0, 1, 2):
        raise ValueError(
            f"'sex' must be 0 (Male), 1 (Female), or 2 (Unknown), got {value!r}"
        )


def _check_diagnosis(value: Any, field: str) -> None:
    """Raise if *value* is not a valid diagnosis dict."""
    if not isinstance(value, dict):
        raise ValueError(
            f'\'{field}\' must be a dict like {{"code": "I5020"}}, '
            f"got {type(value).__name__}: {value!r}"
        )
    if "code" not in value:
        raise ValueError(
            f"'{field}' dict must have a 'code' key, got keys: {list(value.keys())}"
        )
    if not isinstance(value["code"], str):
        raise ValueError(
            f"'{field}[\"code\"]' must be a str, "
            f"got {type(value['code']).__name__}: {value['code']!r}"
        )
    if "poa" in value and value["poa"] is not None:
        if value["poa"] not in ("Y", "N", "U", "W", " "):
            raise ValueError(
                f"'{field}[\"poa\"]' must be one of Y, N, U, W, got {value['poa']!r}"
            )


def _check_diagnosis_list(value: Any, field: str) -> None:
    """Raise if *value* is not a list of diagnosis dicts."""
    if not isinstance(value, list):
        raise ValueError(
            f"'{field}' must be a list of dicts, got {type(value).__name__}: {value!r}"
        )
    for i, item in enumerate(value):
        _check_diagnosis(item, f"{field}[{i}]")


def _check_procedure_list(value: Any, field: str) -> None:
    """Raise if *value* is not a list of procedure dicts."""
    if not isinstance(value, list):
        raise ValueError(
            f"'{field}' must be a list of dicts, got {type(value).__name__}: {value!r}"
        )
    for i, item in enumerate(value):
        if not isinstance(item, dict):
            raise ValueError(
                f'\'{field}[{i}]\' must be a dict like {{"code": "02703DZ"}}, '
                f"got {type(item).__name__}: {item!r}"
            )
        if "code" not in item:
            raise ValueError(
                f"'{field}[{i}]' dict must have a 'code' key, got keys: {list(item.keys())}"
            )
        if not isinstance(item["code"], str):
            raise ValueError(
                f"'{field}[{i}][\"code\"]' must be a str, "
                f"got {type(item['code']).__name__}: {item['code']!r}"
            )


def validate_claim(claim: dict[str, Any]) -> None:
    """Validate an MS-DRG grouper claim input.

    Raises:
        ValueError: With a clear message identifying the invalid field.
    """
    if not isinstance(claim, dict):
        raise ValueError(f"Claim must be a dict, got {type(claim).__name__}")

    # Required fields
    if "pdx" not in claim:
        raise ValueError("Claim must include a 'pdx' field")

    # Type checks for present fields
    if "version" in claim:
        _check_int(claim["version"], "version")

    if "age" in claim:
        _check_int(claim["age"], "age")

    if "sex" in claim:
        _check_sex(claim["sex"])

    if "discharge_status" in claim:
        _check_int(claim["discharge_status"], "discharge_status")

    if "hospital_status" in claim:
        if claim["hospital_status"] not in ("EXEMPT", "NOT_EXEMPT", "UNKNOWN"):
            raise ValueError(
                f"'hospital_status' must be one of EXEMPT, NOT_EXEMPT, UNKNOWN, "
                f"got {claim['hospital_status']!r}"
            )

    if "tie_breaker" in claim:
        if claim["tie_breaker"] not in ("CLINICAL_SIGNIFICANCE", "ALPHABETICAL"):
            raise ValueError(
                f"'tie_breaker' must be one of CLINICAL_SIGNIFICANCE, ALPHABETICAL, "
                f"got {claim['tie_breaker']!r}"
            )

    _check_diagnosis(claim["pdx"], "pdx")

    if "admit_dx" in claim:
        _check_diagnosis(claim["admit_dx"], "admit_dx")

    if "sdx" in claim:
        _check_diagnosis_list(claim["sdx"], "sdx")

    if "procedures" in claim:
        _check_procedure_list(claim["procedures"], "procedures")


def validate_mce_claim(claim: dict[str, Any]) -> None:
    """Validate an MCE editor claim input.

    Raises:
        ValueError: With a clear message identifying the invalid field.
    """
    if not isinstance(claim, dict):
        raise ValueError(f"Claim must be a dict, got {type(claim).__name__}")

    # Required fields
    if "pdx" not in claim:
        raise ValueError("Claim must include a 'pdx' field")
    if "discharge_date" not in claim:
        raise ValueError("MCE claim must include a 'discharge_date' field")

    # Type checks
    _check_int(claim["discharge_date"], "discharge_date")
    ds_date = claim["discharge_date"]
    if ds_date < 20000101 or ds_date > 21001231:
        raise ValueError(
            f"'discharge_date' must be YYYYMMDD between 20000101 and 21001231, "
            f"got {ds_date}"
        )

    if "icd_version" in claim:
        _check_int(claim["icd_version"], "icd_version")
        if claim["icd_version"] not in (9, 10):
            raise ValueError(
                f"'icd_version' must be 9 or 10, got {claim['icd_version']}"
            )

    if "age" in claim:
        _check_int(claim["age"], "age")

    if "sex" in claim:
        _check_sex(claim["sex"])

    if "discharge_status" in claim:
        _check_int(claim["discharge_status"], "discharge_status")

    _check_diagnosis(claim["pdx"], "pdx")

    if "admit_dx" in claim:
        _check_diagnosis(claim["admit_dx"], "admit_dx")

    if "sdx" in claim:
        _check_diagnosis_list(claim["sdx"], "sdx")

    if "procedures" in claim:
        _check_procedure_list(claim["procedures"], "procedures")
