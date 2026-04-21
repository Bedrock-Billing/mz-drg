"""
MS-DRG Grouper - Python bindings for the Zig-based MS-DRG grouper.

This module provides the MsdrgGrouper class which wraps the native
Zig shared library via ctypes.
"""

import ctypes
import copy
from pathlib import Path
from typing import Literal, TypedDict

from msdrg._json import dumps as _dumps, loads as _loads
from msdrg._native import find_data_path, get_lib
from msdrg._validation import validate_claim


# MS-DRG version → ICD-10 fiscal year
_VERSION_TO_YEAR: dict[int, int] = {
    400: 2023,
    401: 2023,
    410: 2024,
    411: 2024,
    420: 2025,
    421: 2025,
    430: 2026,
    431: 2026,
}


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
    tie_breaker: Literal["CLINICAL_SIGNIFICANCE", "ALPHABETICAL"]
    source_icd_version: int  # Source ICD-10 fiscal year (e.g. 2025) for code conversion
    pdx: DiagnosisInput
    admit_dx: DiagnosisInput
    sdx: list[DiagnosisInput]
    procedures: list[ProcedureInput]


# ---------------------------------------------------------------------------
# Output types
# ---------------------------------------------------------------------------


class HacOutputs(TypedDict, total=False):
    """HAC status for a diagnosis code."""

    hac_number: int
    hac_list: str
    hac_status: str
    description: str


class DiagnosisOutput(TypedDict, total=False):
    """Grouper output for a single diagnosis code."""

    code: str
    mdc: int | None
    severity: str
    drg_impact: str
    poa_error: str
    flags: list[str]
    hacs: list[HacOutputs]


class ProcedureOutput(TypedDict, total=False):
    """Grouper output for a single procedure code."""

    code: str
    is_or: bool
    drg_impact: str
    flags: list[str]


class AdmitDxGrouperFlag(TypedDict, total=False):
    DX_INVALID = "DX_INVALID"
    DX_VALID = "DX_VALID"
    DX_NOT_GIVEN = "DX_NOT_GIVEN"


class HacStatus(TypedDict, total=False):
    NOT_APPLICABLE = "NOT_APPLICABLE"
    FINAL_DRG_NO_CHANGE = "FINAL_DRG_NO_CHANGE"
    FINAL_DRG_CHANGES = "FINAL_DRG_CHANGES"
    FINAL_DRG_UNGROUPABLE = "FINAL_DRG_UNGROUPABLE"


class Severity(TypedDict, total=False):
    NONE = "NONE"
    CC = "CC"
    MCC = "MCC"


class GrouperFlagsOutput(TypedDict, total=False):
    """Grouper flags for a claim."""

    admit_dx_grouper_flag: AdmitDxGrouperFlag
    initial_drg_secondary_dx_cc_mcc: Severity
    final_drg_secondary_dx_cc_mcc: Severity
    num_hac_categories_satisfied: int
    hac_status_value: HacStatus


class CodeConversion(TypedDict):
    """A single code conversion performed before grouping."""

    original: str
    converted: str
    code_type: str  # "dx" or "pr"
    field: str  # "pdx", "admit_dx", "sdx", "procedures"


class GroupResult(TypedDict, total=False):
    """
    Result from ``MsdrgGrouper.group()``.

    Contains the DRG assignment, MDC, descriptions, and per-code detail.
    """

    initial_drg: int | None
    initial_mdc: int | None
    initial_base_drg: int | None
    initial_drg_description: str | None
    initial_mdc_description: str | None
    initial_return_code: str
    initial_severity: str
    final_drg: int | None
    final_mdc: int | None
    final_base_drg: int | None
    final_drg_description: str | None
    final_mdc_description: str | None
    return_code: str
    final_severity: str
    pdx_output: DiagnosisOutput | None
    sdx_output: list[DiagnosisOutput]
    proc_output: list[ProcedureOutput]
    grouper_flags: GrouperFlagsOutput
    conversions: list[CodeConversion]  # ICD version conversions (empty if none)


# ---------------------------------------------------------------------------
# Main grouper class
# ---------------------------------------------------------------------------

# Hospital status integer mapping (must match Zig HospitalStatusOptionFlag)
_HOSPITAL_STATUS_MAP: dict[str, int] = {
    "EXEMPT": 0,
    "NOT_EXEMPT": 1,
    "UNKNOWN": 2,
}

_TIE_BREAKER_MAP: dict[str, int] = {
    "CLINICAL_SIGNIFICANCE": 0,
    "ALPHABETICAL": 1,
}


def _poa_byte(poa: str | None) -> int:
    """Convert a POA string to the single byte the native API expects."""
    if poa and len(poa) > 0:
        return ord(poa[0])
    return ord(" ")


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
            data_path = find_data_path()
        else:
            # For backward compatibility, if data_dir is provided, use it.
            # It could be a directory containing msdrg.mdb or the file itself.
            p = Path(data_dir)
            if p.is_dir():
                data_path = str(p / "msdrg.mdb")
            else:
                data_path = data_dir

        self.lib = get_lib(lib_path)
        self._version_cache: dict[int, int] = {}

        # --- Context ---
        self.lib.msdrg_context_init.argtypes = [ctypes.c_char_p]
        self.lib.msdrg_context_init.restype = ctypes.c_void_p

        self.lib.msdrg_context_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_context_free.restype = None

        # --- Grouping (JSON) ---
        self.lib.msdrg_group_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.msdrg_group_json.restype = ctypes.c_void_p

        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        # --- Conversion functions ---
        self.lib.msdrg_convert_dx.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_uint32,
            ctypes.c_uint32,
        ]
        self.lib.msdrg_convert_dx.restype = ctypes.c_void_p

        self.lib.msdrg_convert_pr.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_uint32,
            ctypes.c_uint32,
        ]
        self.lib.msdrg_convert_pr.restype = ctypes.c_void_p

        # --- Initialize context ---
        self.ctx = self.lib.msdrg_context_init(data_path.encode("utf-8"))
        if not self.ctx:
            raise RuntimeError(
                "Failed to initialize MS-DRG context. Check data file."
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
        if hasattr(self, "_version_cache"):
            for ver_ptr in self._version_cache.values():
                self.lib.msdrg_version_free(ver_ptr)
            self._version_cache.clear()
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

    def _convert_code(
        self, code: str, source_year: int, target_year: int, is_dx: bool
    ) -> str:
        """Convert a single code using the native converter. Returns original if no mapping."""
        fn = self.lib.msdrg_convert_dx if is_dx else self.lib.msdrg_convert_pr
        ptr = fn(self.ctx, code.encode("utf-8"), source_year, target_year)
        if ptr:
            try:
                result = ctypes.cast(ptr, ctypes.c_char_p).value
                if result:
                    return result.decode("utf-8") or code
            finally:
                self.lib.msdrg_string_free(ptr)
        return code

    def _maybe_convert_claim(
        self, claim_data: ClaimInput
    ) -> tuple[ClaimInput, list[CodeConversion]]:
        """
        If source_icd_version is set, convert all codes to the target version.

        Returns:
            A tuple of (converted_claim, conversions). The claim is a deep copy
            if conversion occurred, otherwise the original. Conversions lists
            each code that was actually changed.
        """
        source_year = claim_data.get("source_icd_version")
        if source_year is None:
            return claim_data, []

        version = claim_data.get("version")
        if version is None:
            return claim_data, []

        target_year = _VERSION_TO_YEAR.get(version)
        if target_year is None or source_year == target_year:
            return claim_data, []

        claim = copy.deepcopy(claim_data)
        conversions: list[CodeConversion] = []

        def _convert_field(code_obj: dict, field: str, code_type: str) -> None:
            original = code_obj.get("code")
            if original is None:
                return
            converted = self._convert_code(
                original, source_year, target_year, is_dx=(code_type == "dx")
            )
            if converted != original:
                conversions.append(
                    {
                        "original": original,
                        "converted": converted,
                        "code_type": code_type,
                        "field": field,
                    }
                )
            code_obj["code"] = converted

        # PDX
        pdx = claim.get("pdx")
        if pdx:
            _convert_field(pdx, "pdx", "dx")

        # Admit DX
        admit = claim.get("admit_dx")
        if admit:
            _convert_field(admit, "admit_dx", "dx")

        # SDX
        for i, sdx in enumerate(claim.get("sdx", [])):
            _convert_field(sdx, f"sdx[{i}]", "dx")

        # Procedures
        for i, proc in enumerate(claim.get("procedures", [])):
            _convert_field(proc, f"procedures[{i}]", "pr")

        return claim, conversions

    def group(self, claim_data: ClaimInput) -> GroupResult:
        """
        Group a claim through the MS-DRG classification pipeline.

        Uses the JSON string API path (single FFI crossing, fastest for
        bulk processing).

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

        # Convert codes if source_icd_version is set
        claim_data, conversions = self._maybe_convert_claim(claim_data)

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
            result: GroupResult = _loads(result_json)
            result["conversions"] = conversions
            return result
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
    source_icd_version: int | None = None,
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
        source_icd_version: Source ICD-10 fiscal year for code conversion
             (e.g. 2025 to convert FY2025 codes to the grouper's version)

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

        >>> # With ICD version conversion:
        >>> claim = create_claim(
        ...     version=431, source_icd_version=2025,
        ...     age=65, sex=0, discharge_status=1,
        ...     pdx="I5020", sdx=["E1165"],
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

    claim: ClaimInput = {
        "version": version,
        "age": age,
        "sex": sex,
        "discharge_status": discharge_status,
        "pdx": pdx_dict,
        "sdx": sdx_list,
        "procedures": [{"code": c} for c in (procedures or [])],
    }
    if source_icd_version is not None:
        claim["source_icd_version"] = source_icd_version

    return claim
