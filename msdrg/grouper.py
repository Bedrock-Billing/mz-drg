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
    tie_breaker: Literal["CLINICAL_SIGNIFICANCE", "ALPHABETICAL"]
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
            data_dir = find_data_dir()

        self.lib = get_lib(lib_path)
        self._version_cache: dict[int, int] = {}

        # --- Context ---
        self.lib.msdrg_context_init.argtypes = [ctypes.c_char_p]
        self.lib.msdrg_context_init.restype = ctypes.c_void_p

        self.lib.msdrg_context_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_context_free.restype = None

        # --- Version ---
        self.lib.msdrg_version_create.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        self.lib.msdrg_version_create.restype = ctypes.c_void_p

        self.lib.msdrg_version_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_version_free.restype = None

        # --- Input ---
        self.lib.msdrg_input_create.argtypes = []
        self.lib.msdrg_input_create.restype = ctypes.c_void_p

        self.lib.msdrg_input_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_input_free.restype = None

        self.lib.msdrg_input_set_pdx.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_uint8,
        ]
        self.lib.msdrg_input_set_pdx.restype = ctypes.c_bool

        self.lib.msdrg_input_set_admit_dx.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_uint8,
        ]
        self.lib.msdrg_input_set_admit_dx.restype = ctypes.c_bool

        self.lib.msdrg_input_add_sdx.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_uint8,
        ]
        self.lib.msdrg_input_add_sdx.restype = ctypes.c_bool

        self.lib.msdrg_input_add_procedure.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.msdrg_input_add_procedure.restype = ctypes.c_bool

        self.lib.msdrg_input_set_demographics.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
            ctypes.c_int32,
            ctypes.c_int32,
        ]
        self.lib.msdrg_input_set_demographics.restype = None

        self.lib.msdrg_input_set_hospital_status.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_input_set_hospital_status.restype = None

        self.lib.msdrg_input_set_tie_breaker.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_input_set_tie_breaker.restype = None

        # --- Grouping (structured) ---
        self.lib.msdrg_group.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        self.lib.msdrg_group.restype = ctypes.c_void_p

        # --- Grouping (JSON — backward compat) ---
        self.lib.msdrg_group_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.msdrg_group_json.restype = ctypes.c_void_p

        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        # --- Result ---
        self.lib.msdrg_result_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_free.restype = None

        # Scalar result getters
        self.lib.msdrg_result_get_initial_drg.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_initial_drg.restype = ctypes.c_int32

        self.lib.msdrg_result_get_final_drg.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_final_drg.restype = ctypes.c_int32

        self.lib.msdrg_result_get_initial_mdc.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_initial_mdc.restype = ctypes.c_int32

        self.lib.msdrg_result_get_final_mdc.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_final_mdc.restype = ctypes.c_int32

        self.lib.msdrg_result_get_return_code_name.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_return_code_name.restype = ctypes.c_void_p

        # Description getters
        self.lib.msdrg_result_get_initial_drg_description.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_initial_drg_description.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_final_drg_description.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_final_drg_description.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_initial_mdc_description.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_initial_mdc_description.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_final_mdc_description.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_final_mdc_description.restype = ctypes.c_void_p

        # PDX output getters
        self.lib.msdrg_result_has_pdx.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_has_pdx.restype = ctypes.c_bool

        self.lib.msdrg_result_get_pdx_code.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_pdx_code.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_pdx_mdc.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_pdx_mdc.restype = ctypes.c_int32

        self.lib.msdrg_result_get_pdx_severity.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_pdx_severity.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_pdx_drg_impact.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_pdx_drg_impact.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_pdx_poa_error.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_pdx_poa_error.restype = ctypes.c_void_p

        # SDX output getters
        self.lib.msdrg_result_get_sdx_count.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_sdx_count.restype = ctypes.c_int32

        self.lib.msdrg_result_get_sdx_code.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        self.lib.msdrg_result_get_sdx_code.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_sdx_mdc.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        self.lib.msdrg_result_get_sdx_mdc.restype = ctypes.c_int32

        self.lib.msdrg_result_get_sdx_severity.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_result_get_sdx_severity.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_sdx_drg_impact.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_result_get_sdx_drg_impact.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_sdx_poa_error.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_result_get_sdx_poa_error.restype = ctypes.c_void_p

        # Proc output getters
        self.lib.msdrg_result_get_proc_count.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_proc_count.restype = ctypes.c_int32

        self.lib.msdrg_result_get_proc_code.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        self.lib.msdrg_result_get_proc_code.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_proc_is_or.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_result_get_proc_is_or.restype = ctypes.c_bool

        self.lib.msdrg_result_get_proc_drg_impact.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_result_get_proc_drg_impact.restype = ctypes.c_void_p

        # Flag getters
        self.lib.msdrg_result_get_pdx_flags.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_result_get_pdx_flags.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_sdx_flags.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        self.lib.msdrg_result_get_sdx_flags.restype = ctypes.c_void_p

        self.lib.msdrg_result_get_proc_flags.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int32,
        ]
        self.lib.msdrg_result_get_proc_flags.restype = ctypes.c_void_p

        # --- Initialize context ---
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

    def _get_version(self, version: int) -> int:
        """Get or create a cached version handle."""
        if version not in self._version_cache:
            ver_ptr = self.lib.msdrg_version_create(self.ctx, version)
            if not ver_ptr:
                raise RuntimeError(
                    f"Unsupported version: {version}. "
                    f"Supported: {', '.join(str(v) for v in self.available_versions())}"
                )
            self._version_cache[version] = ver_ptr
        return self._version_cache[version]

    def _cstr(self, ptr: int) -> str | None:
        """Read a C string pointer, returning None for empty strings."""
        if not ptr:
            return None
        value = ctypes.cast(ptr, ctypes.c_char_p).value
        if value is None:
            return None
        s = value.decode("utf-8")
        return s if s else None

    def _build_input(self, claim_data: ClaimInput) -> int:
        """Create a MsdrgInput handle from a claim dict. Caller must free."""
        inp = self.lib.msdrg_input_create()
        if not inp:
            raise RuntimeError("Failed to create native input handle")
        try:
            # Demographics
            self.lib.msdrg_input_set_demographics(
                inp,
                claim_data.get("age", 0),
                claim_data.get("sex", 2),
                claim_data.get("discharge_status", 0),
            )

            # Hospital status
            hs = claim_data.get("hospital_status")
            if hs is not None:
                self.lib.msdrg_input_set_hospital_status(
                    inp, _HOSPITAL_STATUS_MAP.get(hs, 1)
                )

            # Tie breaker
            tb = claim_data.get("tie_breaker")
            if tb is not None:
                self.lib.msdrg_input_set_tie_breaker(inp, _TIE_BREAKER_MAP.get(tb, 0))

            # PDX
            pdx = claim_data.get("pdx")
            if pdx:
                if not self.lib.msdrg_input_set_pdx(
                    inp, pdx["code"].encode("utf-8"), _poa_byte(pdx.get("poa"))
                ):
                    raise ValueError(f"Invalid PDX code: {pdx['code']}")

            # Admit DX
            admit_dx = claim_data.get("admit_dx")
            if admit_dx:
                if not self.lib.msdrg_input_set_admit_dx(
                    inp,
                    admit_dx["code"].encode("utf-8"),
                    _poa_byte(admit_dx.get("poa")),
                ):
                    raise ValueError(f"Invalid admit DX code: {admit_dx['code']}")

            # Secondary diagnoses
            for sdx in claim_data.get("sdx", []):
                if not self.lib.msdrg_input_add_sdx(
                    inp, sdx["code"].encode("utf-8"), _poa_byte(sdx.get("poa"))
                ):
                    raise ValueError(f"Invalid SDX code: {sdx['code']}")

            # Procedures
            for proc in claim_data.get("procedures", []):
                if not self.lib.msdrg_input_add_procedure(
                    inp, proc["code"].encode("utf-8")
                ):
                    raise ValueError(f"Invalid procedure code: {proc['code']}")

            return inp
        except Exception:
            self.lib.msdrg_input_free(inp)
            raise

    def _read_result(self, result_ptr: int) -> GroupResult:
        """Read all fields from a MsdrgResult handle into a GroupResult dict."""
        lib = self.lib

        def _parse_flags(ptr: int) -> list[str]:
            """Parse comma-separated flags string into a list."""
            s = self._cstr(ptr)
            if not s:
                return []
            return s.split(",")

        # PDX output
        pdx_output: DiagnosisOutput | None = None
        if lib.msdrg_result_has_pdx(result_ptr):
            pdx_output = {
                "code": self._cstr(lib.msdrg_result_get_pdx_code(result_ptr)) or "",
                "mdc": lib.msdrg_result_get_pdx_mdc(result_ptr),
                "severity": self._cstr(lib.msdrg_result_get_pdx_severity(result_ptr))
                or "",
                "drg_impact": self._cstr(
                    lib.msdrg_result_get_pdx_drg_impact(result_ptr)
                )
                or "",
                "poa_error": self._cstr(lib.msdrg_result_get_pdx_poa_error(result_ptr))
                or "",
                "flags": _parse_flags(lib.msdrg_result_get_pdx_flags(result_ptr)),
            }
            # MDC of -1 means None
            if pdx_output["mdc"] == -1:
                pdx_output["mdc"] = None

        # SDX output
        sdx_count = lib.msdrg_result_get_sdx_count(result_ptr)
        sdx_output: list[DiagnosisOutput] = []
        for i in range(sdx_count):
            entry: DiagnosisOutput = {
                "code": self._cstr(lib.msdrg_result_get_sdx_code(result_ptr, i)) or "",
                "mdc": lib.msdrg_result_get_sdx_mdc(result_ptr, i),
                "severity": self._cstr(lib.msdrg_result_get_sdx_severity(result_ptr, i))
                or "",
                "drg_impact": self._cstr(
                    lib.msdrg_result_get_sdx_drg_impact(result_ptr, i)
                )
                or "",
                "poa_error": self._cstr(
                    lib.msdrg_result_get_sdx_poa_error(result_ptr, i)
                )
                or "",
                "flags": _parse_flags(lib.msdrg_result_get_sdx_flags(result_ptr, i)),
            }
            if entry["mdc"] == -1:
                entry["mdc"] = None
            sdx_output.append(entry)

        # Proc output
        proc_count = lib.msdrg_result_get_proc_count(result_ptr)
        proc_output: list[ProcedureOutput] = []
        for i in range(proc_count):
            proc_entry: ProcedureOutput = {
                "code": self._cstr(lib.msdrg_result_get_proc_code(result_ptr, i)) or "",
                "is_or": lib.msdrg_result_get_proc_is_or(result_ptr, i),
                "drg_impact": self._cstr(
                    lib.msdrg_result_get_proc_drg_impact(result_ptr, i)
                )
                or "",
                "flags": _parse_flags(lib.msdrg_result_get_proc_flags(result_ptr, i)),
            }
            proc_output.append(proc_entry)

        initial_drg = lib.msdrg_result_get_initial_drg(result_ptr)
        final_drg = lib.msdrg_result_get_final_drg(result_ptr)
        initial_mdc = lib.msdrg_result_get_initial_mdc(result_ptr)
        final_mdc = lib.msdrg_result_get_final_mdc(result_ptr)

        return {
            "initial_drg": initial_drg if initial_drg != -1 else None,
            "final_drg": final_drg if final_drg != -1 else None,
            "initial_mdc": initial_mdc if initial_mdc != -1 else None,
            "final_mdc": final_mdc if final_mdc != -1 else None,
            "initial_drg_description": self._cstr(
                lib.msdrg_result_get_initial_drg_description(result_ptr)
            ),
            "final_drg_description": self._cstr(
                lib.msdrg_result_get_final_drg_description(result_ptr)
            ),
            "initial_mdc_description": self._cstr(
                lib.msdrg_result_get_initial_mdc_description(result_ptr)
            ),
            "final_mdc_description": self._cstr(
                lib.msdrg_result_get_final_mdc_description(result_ptr)
            ),
            "return_code": self._cstr(lib.msdrg_result_get_return_code_name(result_ptr))
            or "OK",
            "pdx_output": pdx_output,
            "sdx_output": sdx_output,
            "proc_output": proc_output,
        }

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

    def group_structured(self, claim_data: ClaimInput) -> GroupResult:
        """
        Group a claim using the structured C API (individual getter/setter calls).

        This avoids JSON serialization but makes ~30 FFI calls per claim.
        Use ``group()`` for bulk processing (it's faster due to fewer FFI
        crossings). Use this when you need fine-grained control or want to
        avoid JSON parsing on the Zig side.

        Args:
            claim_data: Claim dictionary matching the ``ClaimInput`` schema.

        Returns:
            A ``GroupResult`` dictionary identical in shape to ``group()``.
        """
        if not self.ctx:
            raise RuntimeError("MsdrgGrouper has been closed. Create a new instance.")

        validate_claim(claim_data)

        version = claim_data.get("version")
        if version is None:
            raise ValueError("Claim must include 'version'")

        ver_ptr = self._get_version(version)
        inp = self._build_input(claim_data)

        try:
            result_ptr = self.lib.msdrg_group(ver_ptr, inp)

            if not result_ptr:
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
                return self._read_result(result_ptr)
            finally:
                self.lib.msdrg_result_free(result_ptr)
        finally:
            self.lib.msdrg_input_free(inp)


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
