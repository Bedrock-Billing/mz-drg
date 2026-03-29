# Changelog

All notable changes to this project are documented here. This project adheres to [Semantic Versioning](https://semver.org/).

---

## v0.1.5 — 2026-03-29

### Added

- :sparkles: **Input validation** — `group()` and `edit()` now validate inputs before FFI calls, raising `ValueError` with clear, field-level messages (e.g. `'sex' must be an int (0=Male, 1=Female, 2=Unknown), got str: 'M'`)
- :sparkles: **POA support in helpers** — `create_claim()` and `create_mce_input()` now accept `pdx_poa` and SDX tuples like `("E1165", "Y")` for present-on-admission indicators
- :sparkles: **`MsdrgGrouper.available_versions()`** — static method to programmatically discover supported DRG versions (400–431)
- :sparkles: **`orjson` acceleration** — if `orjson` is installed, JSON serialization/deserialization is 3–10× faster with zero code changes
- `ResourceWarning` emitted when `MsdrgGrouper` or `MceEditor` is garbage-collected without explicit `close()` or `with` block
- `__repr__` on `MsdrgGrouper` and `MceEditor` showing `open`/`closed` state
- MCE smoke test added to `build.yml` CI workflow
- MCE benchmark mode (`--benchmark`) in `tests/compare_mce.py`

### Changed

- **`discharge_status` type widened** from `Literal[1, 20]` to `int` — all CMS discharge status codes (01–99) are now accepted, matching Zig backend behavior
- **Error messages improved** — null returns from the native layer now include the input `version`, `pdx`, and `discharge_date` in the error, plus guidance on valid values

### Fixed

- :bug: **`build.yml` action versions** pinned to stable releases (`checkout@v4`, `setup-python@v5`, `upload/download-artifact@v4`) — previously referenced non-existent versions
- :bug: **`build.yml` branch triggers** — added `master` alongside `main` so CI actually runs on push
- **Eliminated `ctypes` module pollution** — `mce.py` no longer monkeypatches `ctypes._msdrg_lib`; library loading is now centralized in `msdrg/_native.py` with thread-safe caching
- **Shared library loaded once** — both `MsdrgGrouper` and `MceEditor` share a single `CDLL` handle via path-keyed cache, avoiding redundant loads

### Internal

- New modules: `msdrg/_native.py` (library discovery + cache), `msdrg/_json.py` (orjson fallback), `msdrg/_validation.py` (input checking)
- Removed duplicate `_find_mce_data_dir()` from `mce.py` (identical to `_find_data_dir()`)

---

## v0.1.4 — 2026-03-29

### Added

- :sparkles: **Medicare Code Editor (MCE)** — full MCE validation engine with Python bindings (`MceEditor`, `create_mce_input()`)

### Fixed

- Fix non-short-circuit logic for claims assigned to MDC 0 with an invalid PDX

---

## v0.1.3 — 2026-03-25

### Added

- :sparkles: **Hospital status support** — new `hospital_status` input field for HAC-exempt processing (`EXEMPT`, `NOT_EXEMPT`, `UNKNOWN`)
- Diagnosis filtering for SDX codes that meet HAC criteria under `NOT_EXEMPT` hospital status

### Changed

- README updated to clarify that Zig is **not** required for `pip install` (prebuilt wheels)
- Improved HAC documentation in README

---

## v0.1.2 — 2026-03-24

### Added

- :sparkles: **TypedDict request/response types** — `ClaimInput`, `GroupResult`, `DiagnosisInput`, `DiagnosisOutput`, `ProcedureInput`, `ProcedureOutput` for full type-checking support
- Python test suite (`pytest`) for MS-DRG grouper

### Fixed

- Zig C API: proper null checks, enum conversion, and arena allocator for JSON string allocation
- Fix segfault caused by use of grouper context after `close()`
- `pyproject.toml` is now the single source of truth for version definition

---

## v0.1.1 — 2026-03-23

### Fixed

- Update GitHub Actions workflow versions to latest
- Fix for accurate record file creation

---

## v0.1.0 — 2026-03-23

:tada: **Initial release**

- MS-DRG Grouper engine ported from CMS Java reference implementation
- Python bindings via ctypes with `MsdrgGrouper` class
- Support for DRG versions 400–431 (FY 2023–FY 2026)
- Cross-platform shared library (Linux, macOS, Windows)
- 100% match rate against CMS Java grouper on 50,000+ test claims
- Binary data pipeline for compiling CMS CSV data
- C ABI for integration with any language
