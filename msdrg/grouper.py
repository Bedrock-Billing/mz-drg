"""
MS-DRG Grouper - Python bindings for the Zig-based MS-DRG grouper.

This module provides the MsdrgGrouper class which wraps the native
Zig shared library via ctypes.
"""

import ctypes
from typing import Literal, TypedDict

from msdrg._json import dumps as _dumps, loads as _loads
from msdrg._native import find_data_dir, get_lib
from msdrg._validation import validate_claim


# ---------------------------------------------------------------------------
# Input types
# ---------------------------------------------------------------------------


class DiagnosisInput(TypedDict, total=False):
    """A diagnosis code with optional present-on-admission indicator."""

    code: str
    poa: str  # "Y", "N", "U", "W"


class ProcedureInput(TypedDict):
    """A procedure code."""

    code: str


class ClaimInput(TypedDict, total=False):
    """
    Input claim for the MS-DRG grouper.

    All fields except ``version`` and ``pdx`` are optional.
    """

    version: int
    age: int
    sex: Literal[0, 1, 2]  # 0=Male, 1=Female, 2=Unknown
    discharge_status: int  # CMS discharge status code (e.g. 1, 2, 3, ... 20, etc.)
    hospital_status: Literal["EXEMPT", "NOT_EXEMPT", "UNKNOWN"]
    pdx: DiagnosisInput
    admit_dx: DiagnosisInput
    sdx: list[DiagnosisInput]
    procedures: list[ProcedureInput]


# ---------------------------------------------------------------------------
# Output types
# ---------------------------------------------------------------------------


class DiagnosisOutput(TypedDict, total=False):
    """Grouper output for a single diagnosis code."""

    code: str
    mdc: int | None
    severity: str
    drg_impact: str
    poa_error: str
    flags: list[str]


class ProcedureOutput(TypedDict, total=False):
    """Grouper output for a single procedure code."""

    code: str
    is_or: bool
    drg_impact: str
    flags: list[str]


class GroupResult(TypedDict, total=False):
    """
    Result from ``MsdrgGrouper.group()``.

    Contains the DRG assignment, MDC, descriptions, and per-code detail.
    """

    initial_drg: int | None
    final_drg: int | None
    initial_mdc: int | None
    final_mdc: int | None
    initial_drg_description: str | None
    final_drg_description: str | None
    initial_mdc_description: str | None
    final_mdc_description: str | None
    return_code: str
    pdx_output: DiagnosisOutput | None
    sdx_output: list[DiagnosisOutput]
    proc_output: list[ProcedureOutput]


# ---------------------------------------------------------------------------
# Main grouper class
# ---------------------------------------------------------------------------


class MsdrgGrouper:
    """
    MS-DRG Grouper client.

    Wraps the native Zig shared library to provide high-performance
    MS-DRG grouping.

    Args:
        lib_path: Optional path to the shared library. If not provided,
                  auto-detected from the installed package.
        data_dir: Optional path to the data directory. If not provided,
                  auto-detected from the installed package.

    Example:
        >>> with MsdrgGrouper() as g:
        ...     result = g.group({
        ...         "version": 431,
        ...         "age": 65,
        ...         "sex": 0,
        ...         "discharge_status": 1,
        ...         "pdx": {"code": "I5020"},
        ...         "sdx": [],
        ...         "procedures": [],
        ...     })
        ...     print(result["final_drg"])
    """

    lib: ctypes.CDLL
    ctx: int | None

    def __init__(
        self,
        lib_path: str | None = None,
        data_dir: str | None = None,
    ) -> None:
        if data_dir is None:
            data_dir = find_data_dir()

        self.lib = get_lib(lib_path)

        self.lib.msdrg_context_init.argtypes = [ctypes.c_char_p]
        self.lib.msdrg_context_init.restype = ctypes.c_void_p

        self.lib.msdrg_context_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_context_free.restype = None

        self.lib.msdrg_group_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.msdrg_group_json.restype = ctypes.c_void_p

        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        self.ctx = self.lib.msdrg_context_init(data_dir.encode("utf-8"))
        if not self.ctx:
            raise RuntimeError(
                "Failed to initialize MS-DRG context. Check data directory."
            )

    def __del__(self) -> None:
        if hasattr(self, "ctx") and self.ctx:
            import warnings

            warnings.warn(
                "MsdrgGrouper was not closed. Use 'with' or call close() explicitly.",
                ResourceWarning,
                stacklevel=2,
            )
            self.close()

    def close(self) -> None:
        """Explicitly free the grouper context and release resources."""
        if hasattr(self, "ctx") and self.ctx:
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

    def __repr__(self) -> str:
        status = "open" if self.ctx else "closed"
        return f"MsdrgGrouper({status})"

    @staticmethod
    def available_versions() -> list[int]:
        """Return the list of supported MS-DRG grouper versions.

        Each version corresponds to a CMS fiscal year release:

        - **400/401** — FY 2023 (Oct 2022–Sep 2023)
        - **410/411** — FY 2024 (Oct 2023–Sep 2024)
        - **420/421** — FY 2025 (Oct 2024–Sep 2025)
        - **430/431** — FY 2026 (Oct 2025–Sep 2026)

        Even versions (400, 410, …) are the base release; odd versions
        (401, 411, …) include mid-year updates.
        """
        return [400, 401, 410, 411, 420, 421, 430, 431]

    def __enter__(self) -> "MsdrgGrouper":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def group(self, claim_data: ClaimInput) -> GroupResult:
        """
        Group a claim through the MS-DRG classification pipeline.

        Args:
            claim_data: Claim dictionary. Use ``create_claim()`` to build
                        one, or pass a dict matching the ``ClaimInput`` schema.

        Returns:
            A ``GroupResult`` dictionary with DRG/MDC assignments,
            descriptions, and per-code detail.

        Raises:
            RuntimeError: If the grouper has been closed, or if the native
                          grouper returns null (unexpected).
        """
        if not self.ctx:
            raise RuntimeError("MsdrgGrouper has been closed. Create a new instance.")

        validate_claim(claim_data)

        json_bytes = _dumps(claim_data)

        result_ptr = self.lib.msdrg_group_json(self.ctx, json_bytes)

        if not result_ptr:
            version = claim_data.get("version", "?")
            pdx = claim_data.get("pdx", {})
            pdx_code = pdx.get("code", "?") if isinstance(pdx, dict) else "?"
            raise RuntimeError(
                f"Grouping failed (returned null). "
                f"version={version}, pdx='{pdx_code}'. "
                f"Check that the version is supported "
                f"({', '.join(str(v) for v in self.available_versions())}) "
                f"and the PDX code is a valid ICD-10-CM code."
            )

        try:
            result_json = ctypes.cast(result_ptr, ctypes.c_char_p).value.decode("utf-8")
            return _loads(result_json)
        finally:
            self.lib.msdrg_string_free(result_ptr)


# ---------------------------------------------------------------------------
# Convenience helpers
# ---------------------------------------------------------------------------


def create_claim(
    version: int,
    age: int,
    sex: Literal[0, 1, 2],
    discharge_status: int,
    pdx: str,
    pdx_poa: str | None = None,
    sdx: list[str] | list[tuple[str, str]] | None = None,
    procedures: list[str] | None = None,
) -> ClaimInput:
    """
    Build a claim dictionary from simple arguments.

    This is a convenience wrapper that constructs the nested dict structure
    expected by :meth:`MsdrgGrouper.group`.

    Args:
        version: MS-DRG version (e.g. 431)
        age: Patient age in years
        sex: 0=Male, 1=Female, 2=Unknown
        discharge_status: CMS discharge status code (e.g. 1=Home, 20=Died)
        pdx: Principal diagnosis code (e.g. "I5020")
        pdx_poa: POA indicator for the PDX ("Y", "N", "U", "W", or None)
        sdx: Secondary diagnoses — strings ("I5020") or tuples ("I5020", "Y")
             for POA support
        procedures: Procedure codes

    Returns:
        A ``ClaimInput`` dictionary ready for ``MsdrgGrouper.group()``.

    Example:
        >>> claim = create_claim(
        ...     version=431, age=65, sex=0, discharge_status=1,
        ...     pdx="I5020", sdx=["E1165", "I10"], procedures=["02703DZ"],
        ... )

        >>> # With POA indicators:
        >>> claim = create_claim(
        ...     version=431, age=65, sex=0, discharge_status=1,
        ...     pdx="I5020", pdx_poa="Y",
        ...     sdx=[("E1165", "Y"), ("I10", "N")],
        ... )
    """
    pdx_dict: DiagnosisInput = {"code": pdx}
    if pdx_poa is not None:
        pdx_dict["poa"] = pdx_poa

    sdx_list: list[DiagnosisInput] = []
    for item in sdx or []:
        if isinstance(item, tuple):
            sdx_list.append({"code": item[0], "poa": item[1]})
        else:
            sdx_list.append({"code": item})

    return {
        "version": version,
        "age": age,
        "sex": sex,
        "discharge_status": discharge_status,
        "pdx": pdx_dict,
        "sdx": sdx_list,
        "procedures": [{"code": c} for c in (procedures or [])],
    }
