# Changelog

All notable changes to this project are documented here. This project adheres to [Semantic Versioning](https://semver.org/).

---

## v0.1.8 — 2026-04-02

### Added

- **Expanded comparison testing** — `compare_groupers.py` now validates initial DRG, initial MDC, final DRG, and final MDC against the Java reference (previously only checked final DRG/MDC). The Java `process()` method now returns a structured dict with all four values.

- **New output fields** — `GroupResult` and the JSON API now expose `initial_base_drg`, `final_base_drg`, `initial_return_code`, `initial_severity`, and `final_severity`, matching fields available on the Java `MsdrgOutput` class.

### Input Validation

- **`hospital_status`** — must be `EXEMPT`, `NOT_EXEMPT`, or `UNKNOWN` (was silently defaulting to `NOT_EXEMPT`)
- **`tie_breaker`** — must be `CLINICAL_SIGNIFICANCE` or `ALPHABETICAL`
- **POA indicators** — must be `Y`, `N`, `U`, `W`, or space (unchecked)
- **Procedure `code`** — must be a string (was only checking existence)
- **MCE `icd_version`** — must be 9 or 10
- **MCE `discharge_date`** — must be YYYYMMDD between 20000101 and 21001231

---

## v0.1.7 — 2026-03-31

### Added

- :sparkles: **Clinical significance tie-breaking** — SDX codes are now sorted by severity (MCC > CC > other, then by ICD code string) before the marking phase. This matches the CMS Java grouper's `CLINICAL_SIGNIFICANCE` tie-breaking behavior, where the most clinically significant diagnosis gets first pick of matching attributes during DRG formula evaluation.

- **`tie_breaker` input field** — new optional per-request field on `ClaimInput`:
  ```python
  {"tie_breaker": "CLINICAL_SIGNIFICANCE"}  # default
  {"tie_breaker": "ALPHABETICAL"}            # ICD code string only
  ```
  The default (`CLINICAL_SIGNIFICANCE`) matches the CMS Java reference and is what all users should use unless specifically overriding.

- **`MarkingLogicTieBreaker` enum** — new enum in `models.zig` (`CLINICAL_SIGNIFICANCE`, `ALPHABETICAL`) stored on `RuntimeOptions`.

- **`msdrg_input_set_tie_breaker()`** — C API function for structured callers:
  ```c
  msdrg_input_set_tie_breaker(input, 0);  // 0=CLINICAL_SIGNIFICANCE, 1=ALPHABETICAL
  ```

- **`CodeSetup` preprocessing link** — new chain link inserted after `SdxAttributeProcessor` that sorts SDX codes (MCC > CC > other, by code string) and procedure codes (by code value) when `CLINICAL_SIGNIFICANCE` mode is active.

### Fixed

- :bug: **Stent marking: wrong attribute name case** — `markStents()` in `marking.zig` used `"nordrugstent"` and `"norstent"` (lowercase) instead of the correct `"NORdrugstent"` and `"NORstent"` (mixed case) from the data layer. The attribute cleanup after stent processing was silently failing, leaving stale attributes in the matched set.

- :bug: **Stent marking: missing secondary phase** — Implemented the missing secondary marking pass from the Java reference (`ProcedureFunctionMarking.java:61-73`). When the DRG formula matches both `arterial` and `NORdrugstent` (or `NORstent`), procedures with both attributes are now marked even if they lack the `STENT_4` flag.

### Performance

- :rocket: **~57% throughput increase** (7,000 → 11,000+ claims/sec). Two optimizations:

  **Mask-once architecture** — the attribute mask is now built once after preprocessing and reused across all grouping, marking, and HAC call sites. Previously, `buildMask()` was called ~14-20 times per claim (each doing ~200-400 HashMap insertions with heap-allocated keys). Now it builds twice total (once after preprocessing, once after HAC processing). This eliminated ~10,000+ redundant heap allocations per claim.

  **Zero-allocation attribute comparison** — replaced all `Attribute.toString()` + `allocator.free()` pairs in marking inner loops with `Attribute.matchesString()`, which compares directly using a stack buffer for prefixed attributes. Eliminated ~200 heap churn operations per claim from O(N×M×A) attribute matching loops.

- :rocket: **Dead code cleanup** — removed unused error sets, duplicate code blocks, dead imports, dead Python bindings, and the entire unused `msdrg_data.zig` module.

### Correctness

- :bug: **Discharge status enum synced to Java reference** — `DischargeStatus` enum in `models.zig` now matches `MsdrgDischargeStatus.java` exactly. Fixed enum name mismatches (`ANOTHER_TYPE_FACILITY` → `CUST_SUPP_CARE`, `LEFT_AMA` → `LEFT_AGAINST_MEDICAL_ADVICE`, etc.), added missing codes (69, 70), and fixed `formulaString` for NONE (was returning `"invalid_dstat"`, now returns null per Java).

- :bug: **Ungroupable claims now assign DRG 999** — when the grouper sets a non-OK return code (e.g. `HAC_STATUS_INVALID_MULT_HACS_POA_NOT_Y_W`, `INVALID_DISCHARGE_STATUS`), the final DRG is now set to 999 (ungroupable) and MDC to 0, matching CMS standard behavior. Previously, DRG/MDC were left as null.

- :bug: **Test claim generator fixed** — `generate_test_claims.py` now uses only the 36 valid CMS discharge status codes from `MsdrgDischargeStatus.java`. Previously, it included invalid codes (40, 41, 42) that caused spurious `INVALID_DISCHARGE_STATUS` mismatches in comparison testing.

- :bug: **Comparison test: discharge status passthrough** — `compare_groupers.py` previously forced all non-1/20 discharge statuses to HOME (1) when building Java input. Now passes the actual status through to `getEnumFromInt()`, ensuring both Java and Zig receive identical inputs.

- :bug: **Comparison test: PDX POA passthrough** — `compare_groupers.py` previously hardcoded `poa=Y` for all PDX codes. Now uses the claim's actual POA value.

### Removed

- **`python_client/` directory** — old standalone wrapper superseded by the proper `msdrg` package. Removed dead `msdrg.py` and `test_grouper.py` files, cleaned up fallback import in `compare_groupers.py`.

---

## v0.1.6 — 2026-03-30

### Added

- :sparkles: **Structured C API** — the C ABI now exposes a full structured API for building inputs and reading results without JSON serialization. This enables high-performance integration from C, C++, Rust, and other FFI-capable languages.

  **Input functions:**
  - `msdrg_input_create()` / `msdrg_input_free()` — opaque input handle
  - `msdrg_input_set_pdx()`, `msdrg_input_set_admit_dx()`, `msdrg_input_add_sdx()`, `msdrg_input_add_procedure()` — set claim codes
  - `msdrg_input_set_demographics()` — set age, sex, discharge status
  - `msdrg_input_set_hospital_status()` — set hospital status (EXEMPT/NOT_EXEMPT/UNKNOWN)

  **Version functions:**
  - `msdrg_version_create()` / `msdrg_version_free()` — create reusable version handle

  **Execution:**
  - `msdrg_group(version, input)` — execute grouping, returns opaque result handle

  **Result getters (47 total):**
  - Scalar: `msdrg_result_get_{initial,final}_{drg,mdc}`, `msdrg_result_get_return_code[_name]`
  - Descriptions: `msdrg_result_get_{initial,final}_{drg,mdc}_description`
  - PDX: `msdrg_result_has_pdx`, `msdrg_result_get_pdx_{code,mdc,severity,drg_impact,poa_error,flags}`
  - SDX: `msdrg_result_get_sdx_{count,code,mdc,severity,drg_impact,poa_error,flags}`
  - Procedures: `msdrg_result_get_proc_{count,code,is_or,drg_impact,is_valid,flags}`
  - `msdrg_result_free()` — release result

- :sparkles: **Auto-generated C header** — `zig build` now emits `zig-out/include/msdrg.h` with all 47 exported function declarations, `extern "C"` guards, and opaque handle typedefs. No manual synchronization required.

- :sparkles: **Python `group_structured()` method** — exposes the structured API path from Python for use cases that prefer direct FFI calls over JSON serialization. The default `group()` method continues to use the JSON path (faster for Python due to single FFI crossing).

### Changed

- Hospital status is now exposed per-request in the structured API (`msdrg_input_set_hospital_status`) rather than only through JSON parsing

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
