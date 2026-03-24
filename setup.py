"""
Custom setup.py for building the msdrg package.

Compiles the Zig shared library and bundles data files during
'pip install' or 'python setup.py build_ext'.

Zig compiler search order:
1. ZIG environment variable (if set)
2. System 'zig' command (must be >= 0.16.0)
3. ziglang Python package (if compatible version installed)
"""

import os
import platform
import shutil
import subprocess
from pathlib import Path

from setuptools import setup
from setuptools.command.build_ext import build_ext

ROOT_DIR = Path(__file__).parent.resolve()
ZIG_SRC_DIR = ROOT_DIR / "zig_src"
DATA_SRC_DIR = ROOT_DIR / "data" / "bin"
MSDRG_PKG_DIR = ROOT_DIR / "msdrg"

MIN_ZIG_VERSION = (0, 16, 0)


def get_lib_name() -> str:
    """Get platform-specific shared library name."""
    system = platform.system()
    if system == "Darwin":
        return "libmsdrg.dylib"
    elif system == "Windows":
        return "msdrg.dll"
    else:
        return "libmsdrg.so"


def parse_zig_version(version_str: str) -> tuple[int, ...]:
    """Parse a zig version string like '0.16.0-dev.123+abc' into a tuple."""
    # Strip dev/nightly suffixes: "0.16.0-dev.123+abc" -> "0.16.0"
    clean = version_str.split("-")[0].split("+")[0]
    parts = clean.split(".")
    result = []
    for p in parts:
        try:
            result.append(int(p))
        except ValueError:
            break
    return tuple(result)


def check_zig_version(cmd: list[str]) -> tuple[bool, str]:
    """Check if a zig command meets the minimum version requirement."""
    try:
        result = subprocess.run(
            cmd + ["version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return False, "command failed"
        version_str = result.stdout.strip()
        version = parse_zig_version(version_str)
        if version >= MIN_ZIG_VERSION:
            return True, version_str
        return False, version_str
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return False, str(e)


def find_zig_command() -> list[str]:
    """
    Find a suitable zig compiler.
    Returns the command as a list of args.
    """
    min_ver = ".".join(str(x) for x in MIN_ZIG_VERSION)

    # 1. Check ZIG environment variable
    zig_env = os.environ.get("ZIG")
    if zig_env:
        ok, ver = check_zig_version([zig_env])
        if ok:
            print(f"Using zig from ZIG env var: {zig_env} (version {ver})")
            return [zig_env]
        print(f"Warning: ZIG={zig_env} but version {ver} < {min_ver}")

    # 2. Check system zig
    zig_path = shutil.which("zig")
    if zig_path:
        ok, ver = check_zig_version([zig_path])
        if ok:
            print(f"Using system zig: {zig_path} (version {ver})")
            return [zig_path]
        print(f"Warning: system zig {ver} < {min_ver}, trying alternatives...")

    # 3. Try ziglang Python package
    try:
        import ziglang

        zig_exe = Path(ziglang.__file__).parent / "zig"
        if zig_exe.exists():
            ok, ver = check_zig_version([str(zig_exe)])
            if ok:
                print(f"Using ziglang package (version {ver})")
                return [str(zig_exe)]
            print(f"Warning: ziglang provides zig {ver}, need >= {min_ver}")
    except ImportError:
        pass

    raise FileNotFoundError(
        f"Could not find Zig compiler >= {min_ver}.\n"
        f"Install options:\n"
        f"  1. Install Zig {min_ver}+ from https://ziglang.org/download/\n"
        f"  2. Set ZIG environment variable to the zig binary path\n"
        f"  3. Use: pip install --no-build-isolation . (with system zig in PATH)"
    )


class BuildZigExt(build_ext):
    """Custom build_ext that compiles the Zig shared library."""

    def run(self):
        self._build_zig_lib()
        self._copy_data_files()
        super().run()

    def _build_zig_lib(self):
        """Compile the Zig shared library."""
        lib_name = get_lib_name()
        zig_out_lib = ZIG_SRC_DIR / "zig-out" / "lib" / lib_name
        # On Windows, DLLs may end up in bin/ instead of lib/
        zig_out_bin = ZIG_SRC_DIR / "zig-out" / "bin" / lib_name

        # Clean previous build output
        for p in (zig_out_lib, zig_out_bin):
            if p.exists():
                p.unlink()

        print(f"Building Zig shared library ({lib_name})...")

        optimize = "ReleaseFast"

        zig_cmd = find_zig_command()
        cmd = zig_cmd + ["build", f"-Doptimize={optimize}"]

        print(f"Running: {' '.join(cmd)}")
        subprocess.check_call(
            cmd,
            cwd=str(ZIG_SRC_DIR),
        )

        # Find the built library (check lib/ then bin/)
        if zig_out_lib.exists():
            built_lib = zig_out_lib
        elif zig_out_bin.exists():
            built_lib = zig_out_bin
        else:
            raise RuntimeError(
                f"Zig build succeeded but library not found.\n"
                f"Searched:\n  - {zig_out_lib}\n  - {zig_out_bin}"
            )

        # Copy library to package _lib directory
        dest_lib_dir = MSDRG_PKG_DIR / "_lib"
        dest_lib_dir.mkdir(exist_ok=True)
        dest_lib = dest_lib_dir / lib_name

        print(f"Installing library: {dest_lib}")
        shutil.copy2(str(built_lib), str(dest_lib))

    def _copy_data_files(self):
        """Copy binary data files to the package data directory."""
        dest_data_dir = MSDRG_PKG_DIR / "data"
        dest_data_dir.mkdir(exist_ok=True)

        if not DATA_SRC_DIR.exists():
            raise FileNotFoundError(f"Data source directory not found: {DATA_SRC_DIR}")

        count = 0
        for bin_file in sorted(DATA_SRC_DIR.glob("*.bin")):
            dest = dest_data_dir / bin_file.name
            shutil.copy2(str(bin_file), str(dest))
            count += 1

        if count == 0:
            raise FileNotFoundError(f"No .bin files found in {DATA_SRC_DIR}")

        print(f"Installed {count} data files to {dest_data_dir}")


setup(
    cmdclass={"build_ext": BuildZigExt},
)
