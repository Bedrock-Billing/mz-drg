# Code Review Guide: Reference Data Migration to LMDB (Finalized)

## Overview
This document summarizes the transition of the `mz-drg` library from a multi-file binary lookup system (~24 `.bin` files) to a single, high-performance LMDB database (`msdrg.mdb`). The library uses LMDB as a **structured memory-mapped container** for zero-copy binary blobs, while retaining hand-optimized Zig binary search logic for sub-microsecond lookups.

## 1. Zero-Copy Architecture (Optimization Pass 2)

### 1.1 `align(1)` Compiler-Enforced Safety
The primary architectural pivot was moving away from heap-allocating "alignment fixes" (which caused memory leaks and system-call bottlenecks) to strict unaligned typing.
- **`common.MappedFile.getSlice`**: Returns `[]align(1) const T`.
- **Impact**: Zig's compiler now handles unaligned memory reads using specialized CPU instructions. This ensures **zero heap allocations** and **zero memory copies** during the entire lookup lifecycle.
- **Safety**: Every data access path in the library (`cluster.zig`, `diagnosis.zig`, etc.) has been updated to propagate `align(1)` pointers, making the type system aware of the memory map's natural alignment.

### 1.2 Natural Alignment via Dual-Padding
To maximize throughput, we attempt to force LMDB into providing naturally aligned pointers:
- **Key Padding**: `scripts/package_lmdb.py` pads all keys (e.g., `"diagnosis\x00\x00\x00"`) to 8-byte boundaries. 
- **Value Padding**: All values are padded to 8-byte boundaries.
- **Lookup Padding**: `zig_src/src/db.zig` applies identical 8-byte padding to keys at lookup time.
- **Result**: Because LMDB node headers are aligned, 8-byte keys/values ensure the resulting pointers are almost always 8-byte aligned in practice, allowing the CPU to use the fastest possible execution paths.

## 2. LMDB Lifecycle & Transaction Management
- **`Database` (`src/db.zig`)**: Opens the environment once with `MDB_RDONLY | MDB_NOSUBDIR | MDB_NOLOCK`. 
- **Thread Safety**: `MDB_NOLOCK` is used to remove OS file-lock overhead, which is safe for our read-only analytical workload.
- **Pointer Stability**: The library initiates a single long-lived transaction. This guarantees that the pointers returned by LMDB remain stable and valid for the entire lifetime of the `MsdrgGrouper` object.

## 3. Build & Packaging Integration

### 3.1 Standardized Python Build (`setup.py`)
The build process was finalized to ensure compatibility with `pip`, `build`, and `uv`:
- **Triggering Build**: Added a dummy `Extension("msdrg._lib", sources=[])` to `setup()`. This ensures that `setuptools` correctly invokes the `build_ext` command and our custom Zig compiler logic.
- **Wheel Layout**: `BuildZigExt` now installs `libmsdrg.so` and `msdrg.mdb` directly into `self.build_lib`. This ensures that the generated `.whl` files are correctly architecture-tagged (e.g., `linux_x86_64`) and contain the necessary binary artifacts in the correct internal paths.
- **Source Distributions**: `MANIFEST.in` includes all Zig source files AND the vendored LMDB C sources (`*.c`, `*.h`) to allow building from source.

### 3.2 Automated Data Pipeline
- **`package_lmdb.py`**: Automatically consolidates all intermediate `.bin` files into the monolithic `msdrg.mdb`.
- **Path Resolution**: `msdrg/_native.py` prioritizes resolving the `.mdb` file within the package's `data/` subdirectory.

## 4. Verification State
- **Zig Tests**: All unit tests pass, including the `align(1)` type-safety verification.
- **Python Tests**: All 92 integration tests pass (Grouper, MCE, and ICD Conversions), confirming bit-identical results with the pre-migration state.

## 5. Implementation Notes for Final Review
1. **Zero Allocations**: Confirm that `std.heap.page_allocator` is no longer used in any hot path (lookups).
2. **Key Padding**: Verify that `package_lmdb.py` and `db.zig` use the same 8-byte padding logic.
3. **Library Pathing**: Integration tests (`tests/test_hac_scenarios.py`) were updated to use the unified `data/` directory instead of the legacy `data/bin/`.
