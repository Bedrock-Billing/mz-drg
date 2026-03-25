"""
MS-DRG Grouper - Python bindings for the Zig-based MS-DRG grouper.

This module provides the MsdrgGrouper class which wraps the native
Zig shared library via ctypes.
"""

import ctypes
import json
import os
import platform
from pathlib import Path
from typing import Literal, TypedDict


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
    discharge_status: Literal[1, 20]  # 1=Home/Self Care, 20=Died
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
# Library discovery (private helpers)
# ---------------------------------------------------------------------------


def _get_package_dir() -> Path:
    """Get the directory containing this package."""
    return Path(__file__).parent


def _get_lib_name() -> str:
    """Get the platform-specific shared library name."""
    system = platform.system()
    if system == "Darwin":
        return "libmsdrg.dylib"
    elif system == "Windows":
        return "msdrg.dll"
    else:
        return "libmsdrg.so"


def _find_library() -> str:
    """
    Find the shared library within the installed package.

    Search order:
    1. Package's _lib/ directory (installed package)
    2. Zig build output (development mode)
    """
    pkg_dir = _get_package_dir()
    lib_name = _get_lib_name()

    lib_path = pkg_dir / "_lib" / lib_name
    if lib_path.exists():
        return str(lib_path)

    dev_path = pkg_dir.parent / "zig_src" / "zig-out" / "lib" / lib_name
    if dev_path.exists():
        return str(dev_path)

    dev_bin_path = pkg_dir.parent / "zig_src" / "zig-out" / "bin" / lib_name
    if dev_bin_path.exists():
        return str(dev_bin_path)

    raise FileNotFoundError(
        f"Could not find {lib_name}. Searched:\n"
        f"  - {pkg_dir / '_lib' / lib_name}\n"
        f"  - {dev_path}\n"
        f"  - {dev_bin_path}\n"
        f"Make sure the package is installed correctly or run 'zig build' in zig_src/."
    )


def _find_data_dir() -> str:
    """
    Find the data directory within the installed package.

    Search order:
    1. Package's data/ directory (installed package)
    2. Repository data/bin/ directory (development mode)
    """
    pkg_dir = _get_package_dir()

    data_path = pkg_dir / "data"
    if data_path.exists() and any(data_path.iterdir()):
        return str(data_path)

    dev_path = pkg_dir.parent / "data" / "bin"
    if dev_path.exists():
        return str(dev_path)

    raise FileNotFoundError(
        f"Could not find data directory. Searched:\n"
        f"  - {pkg_dir / 'data'}\n"
        f"  - {dev_path}\n"
        f"Make sure the package is installed correctly."
    )


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
        if lib_path is None:
            lib_path = _find_library()
        if data_dir is None:
            data_dir = _find_data_dir()

        if not os.path.exists(lib_path):
            raise FileNotFoundError(f"Library not found at {lib_path}")

        self.lib = ctypes.CDLL(lib_path)

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
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

    def close(self) -> None:
        """Explicitly free the grouper context and release resources."""
        if hasattr(self, "ctx") and self.ctx:
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

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

        json_bytes = json.dumps(claim_data).encode("utf-8")

        result_ptr = self.lib.msdrg_group_json(self.ctx, json_bytes)

        if not result_ptr:
            raise RuntimeError("Grouping failed (returned null)")

        try:
            result_json = ctypes.cast(result_ptr, ctypes.c_char_p).value.decode("utf-8")
            return json.loads(result_json)
        finally:
            self.lib.msdrg_string_free(result_ptr)


# ---------------------------------------------------------------------------
# Convenience helpers
# ---------------------------------------------------------------------------


def create_claim(
    version: int,
    age: int,
    sex: Literal[0, 1, 2],
    discharge_status: Literal[1, 20],
    pdx: str,
    sdx: list[str] | None = None,
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
        discharge_status: 1=Home/Self Care, 20=Died
        pdx: Principal diagnosis code (e.g. "I5020")
        sdx: Secondary diagnosis codes
        procedures: Procedure codes

    Returns:
        A ``ClaimInput`` dictionary ready for ``MsdrgGrouper.group()``.

    Example:
        >>> claim = create_claim(
        ...     version=431, age=65, sex=0, discharge_status=1,
        ...     pdx="I5020", sdx=["E1165", "I10"], procedures=["02703DZ"],
        ... )
    """
    return {
        "version": version,
        "age": age,
        "sex": sex,
        "discharge_status": discharge_status,
        "pdx": {"code": pdx},
        "sdx": [{"code": c} for c in (sdx or [])],
        "procedures": [{"code": c} for c in (procedures or [])],
    }
