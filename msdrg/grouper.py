"""
MS-DRG Grouper - Python bindings for the Zig-based MS-DRG grouper.

This module provides the MsdrgGrouper class which wraps the native
Zig shared library via ctypes.
"""

import ctypes
import json
import os
import platform
import sys
from pathlib import Path


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
    else:  # Linux and others
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

    # 1. Check installed package location
    lib_path = pkg_dir / "_lib" / lib_name
    if lib_path.exists():
        return str(lib_path)

    # 2. Check development zig build output
    dev_path = pkg_dir.parent / "zig_src" / "zig-out" / "lib" / lib_name
    if dev_path.exists():
        return str(dev_path)

    # 3. Windows may put DLLs in bin/ instead of lib/
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

    # 1. Check installed package location
    data_path = pkg_dir / "data"
    if data_path.exists() and any(data_path.iterdir()):
        return str(data_path)

    # 2. Check development location
    dev_path = pkg_dir.parent / "data" / "bin"
    if dev_path.exists():
        return str(dev_path)

    raise FileNotFoundError(
        f"Could not find data directory. Searched:\n"
        f"  - {pkg_dir / 'data'}\n"
        f"  - {dev_path}\n"
        f"Make sure the package is installed correctly."
    )


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
        >>> grouper = MsdrgGrouper()
        >>> result = grouper.group({
        ...     "version": 431,
        ...     "age": 65,
        ...     "sex": 0,
        ...     "discharge_status": 1,
        ...     "pdx": {"code": "I5020"},
        ...     "sdx": [],
        ...     "procedures": []
        ... })
        >>> print(result["final_drg"])
    """

    def __init__(self, lib_path: str | None = None, data_dir: str | None = None):
        if lib_path is None:
            lib_path = _find_library()
        if data_dir is None:
            data_dir = _find_data_dir()

        if not os.path.exists(lib_path):
            raise FileNotFoundError(f"Library not found at {lib_path}")

        self.lib = ctypes.CDLL(lib_path)

        # Define C function signatures
        self.lib.msdrg_context_init.argtypes = [ctypes.c_char_p]
        self.lib.msdrg_context_init.restype = ctypes.c_void_p

        self.lib.msdrg_context_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_context_free.restype = None

        self.lib.msdrg_group_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.msdrg_group_json.restype = ctypes.c_void_p

        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        # Initialize context
        self.ctx = self.lib.msdrg_context_init(data_dir.encode("utf-8"))
        if not self.ctx:
            raise RuntimeError(
                "Failed to initialize MS-DRG context. Check data directory."
            )

    def __del__(self):
        if hasattr(self, "ctx") and self.ctx:
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

    def close(self):
        """Explicitly free the grouper context."""
        if hasattr(self, "ctx") and self.ctx:
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def group(self, claim_data: dict) -> dict:
        """
        Group a claim using the JSON API.

        Args:
            claim_data: Dictionary containing claim data with keys:
                - version (int): MS-DRG version (e.g. 431)
                - age (int): Patient age in years
                - sex (int): 0=Male, 1=Female
                - discharge_status (int): 1=Home/Self Care, 20=Died
                - pdx (dict): Principal diagnosis with "code" key
                - sdx (list): Secondary diagnoses, each with "code" key
                - procedures (list): Procedures, each with "code" key

        Returns:
            Dictionary containing grouping result with keys:
                - initial_drg: Initial DRG assignment
                - final_drg: Final DRG assignment
                - initial_mdc: Initial MDC
                - final_mdc: Final MDC
                - return_code: Processing return code
        """
        json_bytes = json.dumps(claim_data).encode("utf-8")

        result_ptr = self.lib.msdrg_group_json(self.ctx, json_bytes)

        if not result_ptr:
            raise RuntimeError("Grouping failed (returned null)")

        try:
            result_json = ctypes.cast(result_ptr, ctypes.c_char_p).value.decode("utf-8")
            return json.loads(result_json)
        finally:
            self.lib.msdrg_string_free(result_ptr)


def create_claim(
    version: int,
    age: int,
    sex: int,
    discharge_status: int,
    pdx: str,
    sdx: list[str] | None = None,
    procedures: list[str] | None = None,
) -> dict:
    """
    Helper to create a claim dictionary.

    Args:
        version: MS-DRG version (e.g. 431)
        age: Patient age in years
        sex: 0=Male, 1=Female
        discharge_status: 1=Home/Self Care, 20=Died
        pdx: Principal diagnosis code
        sdx: List of secondary diagnosis codes
        procedures: List of procedure codes

    Returns:
        Dictionary ready for MsdrgGrouper.group()
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
