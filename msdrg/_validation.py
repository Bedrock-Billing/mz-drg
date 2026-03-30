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
