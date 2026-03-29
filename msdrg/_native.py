"""
Shared native library loading for the msdrg package.

Handles discovery and caching of the Zig shared library and data directory.
Both MsdrgGrouper and MceEditor use this module to avoid loading the .so
multiple times and to keep library management in one place.
"""

import ctypes
import os
import platform
import threading
from pathlib import Path


# ---------------------------------------------------------------------------
# Thread-safe library cache
# ---------------------------------------------------------------------------

_lock = threading.Lock()
_lib_cache: dict[str, ctypes.CDLL] = {}


def get_lib(lib_path: str | None = None) -> ctypes.CDLL:
    """
    Load or retrieve the cached shared library.

    The library is loaded once per resolved path and reused across all
    MsdrgGrouper and MceEditor instances. This avoids re-loading the .so
    on every instantiation and ensures both classes share the same handle.

    Args:
        lib_path: Optional explicit path to the shared library.
                  Auto-discovered if not provided.

    Returns:
        A ctypes.CDLL handle to the shared library.
    """
    if lib_path is None:
        lib_path = find_library()

    resolved = os.path.realpath(lib_path)

    if resolved not in _lib_cache:
        with _lock:
            # Double-check after acquiring lock
            if resolved not in _lib_cache:
                if not os.path.exists(resolved):
                    raise FileNotFoundError(f"Library not found at {resolved}")
                _lib_cache[resolved] = ctypes.CDLL(resolved)

    return _lib_cache[resolved]


# ---------------------------------------------------------------------------
# Path discovery
# ---------------------------------------------------------------------------


def _get_package_dir() -> Path:
    """Get the directory containing the msdrg package."""
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


def find_library() -> str:
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


def find_data_dir() -> str:
    """
    Find the data directory within the installed package.

    Both the MS-DRG grouper and MCE editor use the same data files.

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
