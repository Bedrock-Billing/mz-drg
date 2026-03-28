# Changelog

All notable changes to this project are documented here. This project adheres to [Semantic Versioning](https://semver.org/).

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
