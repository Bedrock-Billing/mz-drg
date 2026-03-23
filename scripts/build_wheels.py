#!/usr/bin/env python3
"""
Build prebuilt binary wheels for all supported platforms.

Usage:
    python scripts/build_wheels.py              # Build all targets
    python scripts/build_wheels.py linux        # Build only Linux targets
    python scripts/build_wheels.py x86_64-linux # Build specific target

Each wheel bundles the pre-compiled Zig shared library and data files,
so end users don't need Zig installed.

Output: dist/msdrg-0.1.0-<python_tag>-<abi_tag>-<platform_tag>.whl

Prerequisites:
    pip install wheel

Optional (for production-quality Linux wheels):
    pip install auditwheel   # Repairs wheels for manylinux compliance
    pip install delocate     # Repairs macOS wheels

Cross-compilation targets (all buildable from a single Linux machine):
    x86_64-linux-gnu         → manylinux_2_17_x86_64.whl
    aarch64-linux-gnu        → manylinux_2_17_aarch64.whl
    x86_64-windows-gnu       → win_amd64.whl
    x86_64-macos-none        → macosx_10_13_x86_64.whl
    aarch64-macos-none       → macosx_11_0_arm64.whl
"""

import argparse
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent.resolve()
ZIG_SRC_DIR = ROOT_DIR / "zig_src"
MSDRG_PKG_DIR = ROOT_DIR / "msdrg"
DATA_SRC_DIR = ROOT_DIR / "data" / "bin"
DIST_DIR = ROOT_DIR / "dist"

# Package metadata (keep in sync with pyproject.toml)
PACKAGE_NAME = "msdrg"
VERSION = "0.1.0"
PYTHON_TAG = "py3"
ABI_TAG = "none"

# Target configurations: (zig_target, lib_filename, wheel_platform_tag)
TARGETS = {
    "x86_64-linux": (
        "x86_64-linux-gnu",
        "libmsdrg.so",
        "manylinux_2_17_x86_64.manylinux2014_x86_64",
    ),
    "aarch64-linux": (
        "aarch64-linux-gnu",
        "libmsdrg.so",
        "manylinux_2_17_aarch64.manylinux2014_aarch64",
    ),
    "x86_64-windows": (
        "x86_64-windows-gnu",
        "msdrg.dll",
        "win_amd64",
    ),
    "x86_64-macos": (
        "x86_64-macos-none",
        "libmsdrg.dylib",
        "macosx_10_13_x86_64",
    ),
    "aarch64-macos": (
        "aarch64-macos-none",
        "libmsdrg.dylib",
        "macosx_11_0_arm64",
    ),
}


def get_lib_name_for_target(zig_target: str) -> str:
    """Get the shared library filename for a Zig target."""
    if "windows" in zig_target:
        return "msdrg.dll"
    elif "macos" in zig_target:
        return "libmsdrg.dylib"
    else:
        return "libmsdrg.so"


def find_built_lib(zig_target: str) -> Path:
    """Find the compiled library in zig-out/lib/ or zig-out/bin/."""
    lib_name = get_lib_name_for_target(zig_target)

    lib_path = ZIG_SRC_DIR / "zig-out" / "lib" / lib_name
    if lib_path.exists():
        return lib_path

    bin_path = ZIG_SRC_DIR / "zig-out" / "bin" / lib_name
    if bin_path.exists():
        return bin_path

    raise FileNotFoundError(
        f"Library {lib_name} not found in zig-out/lib/ or zig-out/bin/"
    )


def clean_zig_out():
    """Remove previous zig build output."""
    zig_out = ZIG_SRC_DIR / "zig-out"
    if zig_out.exists():
        shutil.rmtree(zig_out)


def build_zig_lib(zig_target: str, optimize: str = "ReleaseFast"):
    """Cross-compile the Zig shared library for a target."""
    clean_zig_out()

    cmd = ["zig", "build", f"-Doptimize={optimize}", f"-Dtarget={zig_target}"]
    print(f"  Running: {' '.join(cmd)}")
    subprocess.check_call(cmd, cwd=str(ZIG_SRC_DIR))


def build_wheel(platform_tag: str, lib_path: Path) -> Path:
    """
    Build a Python wheel for a specific platform.

    A wheel is a zip file with:
    - msdrg/           - the package
    - msdrg-<version>.dist-info/METADATA
    - msdrg-<version>.dist-info/WHEEL
    - msdrg-<version>.dist-info/RECORD
    """
    wheel_name = f"{PACKAGE_NAME}-{VERSION}-{PYTHON_TAG}-{ABI_TAG}-{platform_tag}.whl"
    DIST_DIR.mkdir(exist_ok=True)
    wheel_path = DIST_DIR / wheel_name

    with zipfile.ZipFile(wheel_path, "w", zipfile.ZIP_DEFLATED) as whl:
        # Add all Python source files
        for py_file in sorted(MSDRG_PKG_DIR.rglob("*.py")):
            arcname = str(py_file.relative_to(ROOT_DIR))
            whl.write(py_file, arcname)

        # Add the shared library
        lib_arcname = f"msdrg/_lib/{lib_path.name}"
        whl.write(lib_path, lib_arcname)

        # Add data files
        for data_file in sorted(DATA_SRC_DIR.glob("*.bin")):
            arcname = f"msdrg/data/{data_file.name}"
            whl.write(data_file, arcname)

        # Add dist-info
        dist_info_prefix = f"{PACKAGE_NAME}-{VERSION}.dist-info"

        # WHEEL
        wheel_content = f"""Wheel-Version: 1.0
Generator: msdrg-build
Root-Is-Purelib: false
Tag: {PYTHON_TAG}-{ABI_TAG}-{platform_tag}
"""
        whl.writestr(f"{dist_info_prefix}/WHEEL", wheel_content)

        # METADATA
        metadata_content = f"""Metadata-Version: 2.1
Name: {PACKAGE_NAME}
Version: {VERSION}
Summary: High-performance MS-DRG (Medicare Severity Diagnosis Related Groups) grouper
Home-page: https://github.com/Bedrock-Billing/mz-drg
License: MIT
Platform: any
Requires-Python: >=3.11
"""
        whl.writestr(f"{dist_info_prefix}/METADATA", metadata_content)

        # RECORD (hashes of all files)
        record_lines = []
        for info in whl.infolist():
            if info.filename == f"{dist_info_prefix}/RECORD":
                record_lines.append(f"{info.filename},,")
            else:
                data = whl.read(info.filename)
                import hashlib
                import base64

                digest = hashlib.sha256(data).digest()
                b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode()
                record_lines.append(f"{info.filename},sha256={b64},{info.file_size}")
        whl.writestr(f"{dist_info_prefix}/RECORD", "\n".join(record_lines) + "\n")

    return wheel_path


def try_auditwheel(wheel_path: Path, platform_tag: str) -> None:
    """Attempt to repair Linux wheel with auditwheel for manylinux compliance."""
    if "manylinux" not in platform_tag:
        return

    try:
        subprocess.check_call(
            [
                "auditwheel",
                "repair",
                "--plat",
                platform_tag.split(".")[0],  # e.g. manylinux_2_17_x86_64
                "--only-plat",
                "-w",
                str(DIST_DIR),
                str(wheel_path),
            ],
            stdout=subprocess.DEVNULL,
        )
        # auditwheel creates a new wheel with the proper name
        # Remove the original unrepaired wheel
        wheel_path.unlink()
        print(f"  Repaired with auditwheel ✓")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"  auditwheel not available or failed (wheel is still usable)")


def try_delocate(wheel_path: Path, platform_tag: str) -> None:
    """Attempt to repair macOS wheel with delocate."""
    if "macosx" not in platform_tag:
        return

    try:
        subprocess.check_call(
            ["delocate-wheel", "-w", str(DIST_DIR), str(wheel_path)],
            stdout=subprocess.DEVNULL,
        )
        print(f"  Repaired with delocate ✓")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"  delocate not available or failed (wheel is still usable)")


def build_target(target_name: str, optimize: str = "ReleaseFast"):
    """Build a wheel for a specific target."""
    zig_target, lib_name, platform_tag = TARGETS[target_name]

    print(f"\n{'=' * 60}")
    print(f"Building: {target_name}")
    print(f"  Zig target:    {zig_target}")
    print(f"  Platform tag:  {platform_tag}")
    print(f"{'=' * 60}")

    # 1. Cross-compile
    print(f"\n[1/3] Cross-compiling Zig library...")
    build_zig_lib(zig_target, optimize)

    # 2. Find the built library
    print(f"[2/3] Locating built library...")
    lib_path = find_built_lib(zig_target)
    print(f"  Found: {lib_path}")

    # 3. Build the wheel
    print(f"[3/3] Building wheel...")
    wheel_path = build_wheel(platform_tag, lib_path)
    size_mb = wheel_path.stat().st_size / (1024 * 1024)
    print(f"  Created: {wheel_path.name} ({size_mb:.1f} MB)")

    # 4. Optional repair
    if "linux" in target_name:
        try_auditwheel(wheel_path, platform_tag)
    elif "macos" in target_name:
        try_delocate(wheel_path, platform_tag)

    clean_zig_out()
    return wheel_path


def main():
    parser = argparse.ArgumentParser(description="Build prebuilt binary wheels")
    parser.add_argument(
        "targets",
        nargs="*",
        default=list(TARGETS.keys()),
        help=f"Targets to build (default: all). Choices: {', '.join(TARGETS.keys())}",
    )
    parser.add_argument(
        "--optimize",
        default="ReleaseFast",
        choices=["Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"],
        help="Zig optimization level (default: ReleaseFast)",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available targets and exit",
    )
    args = parser.parse_args()

    if args.list:
        print("Available targets:")
        for name, (zig_target, lib_name, platform_tag) in TARGETS.items():
            print(f"  {name:20s}  {zig_target:25s}  →  {platform_tag}")
        return

    # Validate targets
    for target in args.targets:
        if target not in TARGETS:
            print(f"Error: Unknown target '{target}'")
            print(f"Available: {', '.join(TARGETS.keys())}")
            sys.exit(1)

    DIST_DIR.mkdir(exist_ok=True)

    print(f"Building wheels for: {', '.join(args.targets)}")
    print(f"Output directory: {DIST_DIR.resolve()}")

    built = []
    for target in args.targets:
        wheel_path = build_target(target, args.optimize)
        built.append(wheel_path)

    # Summary
    print(f"\n{'=' * 60}")
    print(f"Built {len(built)} wheel(s):")
    for w in built:
        size_mb = w.stat().st_size / (1024 * 1024)
        print(f"  {w.name}  ({size_mb:.1f} MB)")
    print(f"\nTo install locally: pip install dist/<wheel>.whl")
    print(f"To upload to PyPI:  twine upload dist/*.whl")


if __name__ == "__main__":
    main()
