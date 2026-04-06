"""
ICD-10 Code Converter — maps ICD-10-CM/PCS codes between fiscal year versions.

Wraps the native Zig conversion engine which uses CMS ICD-10 conversion tables
to map codes forward or backward between fiscal years.
"""

import ctypes
from typing import TypedDict

from msdrg._native import find_data_dir, get_lib


# MS-DRG version to ICD-10 fiscal year
VERSION_TO_YEAR: dict[int, int] = {
    400: 2023,
    401: 2023,
    410: 2024,
    411: 2024,
    420: 2025,
    421: 2025,
    430: 2026,
    431: 2026,
}

YEAR_TO_VERSION: dict[int, int] = {
    2023: 401,
    2024: 411,
    2025: 421,
    2026: 431,
}


class ConversionResult(TypedDict):
    """Result of a single code conversion."""

    original: str
    converted: str  # same as original if no mapping found


class IcdConverter:
    """
    ICD-10 code converter between fiscal year versions.

    Uses CMS ICD-10 conversion tables to map diagnosis and procedure codes
    forward or backward between fiscal years. If no mapping exists for a code,
    the original code is returned unchanged.

    Args:
        lib_path: Optional path to shared library (auto-detected).
        data_dir: Optional path to data directory (auto-detected).

    Example:
        >>> with IcdConverter() as conv:
        ...     # Convert a single DX code from FY2025 to FY2026
        ...     result = conv.convert_dx("A000", source_year=2025, target_year=2026)
        ...     print(result)
        ...
        ...     # Batch convert multiple codes
        ...     results = conv.convert_dx_batch(
        ...         ["I5020", "E1165"],
        ...         source_year=2025, target_year=2026,
        ...     )
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

        # --- Context (same as grouper, loads all data including conversions) ---
        self.lib.msdrg_context_init.argtypes = [ctypes.c_char_p]
        self.lib.msdrg_context_init.restype = ctypes.c_void_p

        self.lib.msdrg_context_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_context_free.restype = None

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

        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        # --- Initialize context ---
        self.ctx = self.lib.msdrg_context_init(data_dir.encode("utf-8"))
        if not self.ctx:
            raise RuntimeError(
                "Failed to initialize ICD converter context. Check data directory."
            )

    def __del__(self) -> None:
        if hasattr(self, "ctx") and self.ctx:
            import warnings

            warnings.warn(
                "IcdConverter was not closed. Use 'with' or call close() explicitly.",
                ResourceWarning,
                stacklevel=2,
            )
            self.close()

    def close(self) -> None:
        """Explicitly free the converter context and release resources."""
        if hasattr(self, "ctx") and self.ctx:
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

    def __repr__(self) -> str:
        status = "open" if self.ctx else "closed"
        return f"IcdConverter({status})"

    def __enter__(self) -> "IcdConverter":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    @staticmethod
    def version_to_year(version: int) -> int:
        """Convert an MS-DRG version number to ICD-10 fiscal year."""
        year = VERSION_TO_YEAR.get(version)
        if year is None:
            raise ValueError(
                f"Unknown version: {version}. "
                f"Supported: {', '.join(str(v) for v in sorted(VERSION_TO_YEAR))}"
            )
        return year

    @staticmethod
    def year_to_version(year: int) -> int:
        """Convert an ICD-10 fiscal year to the latest MS-DRG version for that year."""
        ver = YEAR_TO_VERSION.get(year)
        if ver is None:
            raise ValueError(
                f"Unknown year: {year}. "
                f"Supported: {', '.join(str(y) for y in sorted(YEAR_TO_VERSION))}"
            )
        return ver

    def _cstr(self, ptr: int) -> str | None:
        """Read a C string pointer, returning None for null or empty."""
        if not ptr:
            return None
        value = ctypes.cast(ptr, ctypes.c_char_p).value
        if value is None:
            return None
        s = value.decode("utf-8")
        return s if s else None

    def convert_dx(
        self,
        code: str,
        source_year: int,
        target_year: int,
    ) -> str:
        """
        Convert a single ICD-10-CM diagnosis code between fiscal years.

        If no mapping exists, returns the original code unchanged.

        Args:
            code: ICD-10-CM diagnosis code (e.g. "I5020").
            source_year: Source ICD-10 fiscal year (e.g. 2025).
            target_year: Target ICD-10 fiscal year (e.g. 2026).

        Returns:
            The converted code, or the original if no mapping found.
        """
        if not self.ctx:
            raise RuntimeError("IcdConverter has been closed. Create a new instance.")

        ptr = self.lib.msdrg_convert_dx(
            self.ctx,
            code.encode("utf-8"),
            source_year,
            target_year,
        )
        if ptr:
            try:
                result = self._cstr(ptr)
                return result or code
            finally:
                self.lib.msdrg_string_free(ptr)
        return code

    def convert_pr(
        self,
        code: str,
        source_year: int,
        target_year: int,
    ) -> str:
        """
        Convert a single ICD-10-PCS procedure code between fiscal years.

        If no mapping exists, returns the original code unchanged.

        Args:
            code: ICD-10-PCS procedure code (e.g. "02703DZ").
            source_year: Source ICD-10 fiscal year (e.g. 2025).
            target_year: Target ICD-10 fiscal year (e.g. 2026).

        Returns:
            The converted code, or the original if no mapping found.
        """
        if not self.ctx:
            raise RuntimeError("IcdConverter has been closed. Create a new instance.")

        ptr = self.lib.msdrg_convert_pr(
            self.ctx,
            code.encode("utf-8"),
            source_year,
            target_year,
        )
        if ptr:
            try:
                result = self._cstr(ptr)
                return result or code
            finally:
                self.lib.msdrg_string_free(ptr)
        return code

    def convert_dx_batch(
        self,
        codes: list[str],
        source_year: int,
        target_year: int,
    ) -> list[ConversionResult]:
        """
        Convert a batch of ICD-10-CM diagnosis codes.

        Args:
            codes: List of ICD-10-CM codes.
            source_year: Source ICD-10 fiscal year.
            target_year: Target ICD-10 fiscal year.

        Returns:
            List of ConversionResult dicts with original and converted codes.
        """
        return [
            {
                "original": code,
                "converted": self.convert_dx(code, source_year, target_year),
            }
            for code in codes
        ]

    def convert_pr_batch(
        self,
        codes: list[str],
        source_year: int,
        target_year: int,
    ) -> list[ConversionResult]:
        """
        Convert a batch of ICD-10-PCS procedure codes.

        Args:
            codes: List of ICD-10-PCS codes.
            source_year: Source ICD-10 fiscal year.
            target_year: Target ICD-10 fiscal year.

        Returns:
            List of ConversionResult dicts with original and converted codes.
        """
        return [
            {
                "original": code,
                "converted": self.convert_pr(code, source_year, target_year),
            }
            for code in codes
        ]
