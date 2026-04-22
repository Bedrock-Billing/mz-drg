# mz-drg

**High-performance CMS claim processing tools written in Zig with Python bindings.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org)
[![Python](https://img.shields.io/badge/Python-3.11+-green.svg)](https://python.org)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://Bedrock-Billing.github.io/mz-drg/)

---

mz-drg provides open-source reimplementations of CMS tools:

- **MS-DRG Grouper** — assigns Diagnosis Related Groups based on diagnoses, procedures, and demographics
- **Medicare Code Editor (MCE)** — validates ICD diagnosis and procedure codes against CMS edit rules
- **ICD-10 Converter** — maps codes between fiscal year versions using CMS conversion tables

All are written in [Zig](https://ziglang.org), callable from Python, and validated against the CMS reference Java implementations with a 100% match rate on 50,000+ claims.

## Why mz-drg?

The official CMS tools are Java applications. While accurate, they come with practical limitations:

| | Java (CMS) | mz-drg |
|---|---|---|
| **Startup** | JVM warmup, seconds | Instant |
| **Throughput (Ryzen 5 5600U)** | ~500 claims/sec | ~11,000+ claims/sec |
| **Memory** | JVM heap overhead | Minimal, memory-mapped data |
| **Dependencies** | JRE 17+, classpath management | Single shared library |
| **Python integration** | JPype bridge (fragile) | Native ctypes (simple) |
| **Embedding** | Requires JVM process | C ABI, any language |

Both engines are ported line-by-line from the decompiled Java source and validated claim-by-claim against the original.

## Quick start

### Install

```bash
pip install msdrg
```

### MS-DRG Grouper

```python
import msdrg

with msdrg.MsdrgGrouper() as grouper:
    result = grouper.group({
        "version": 431,
        "age": 65,
        "sex": 0,
        "discharge_status": 1,
        "pdx": {"code": "I5020"},
        "sdx": [{"code": "E1165"}],
        "procedures": []
    })

print(result["final_drg"])            # 293
print(result["final_mdc"])            # 5
print(result["final_drg_description"])  # "Heart Failure and Shock without CC/MCC"
```

### Medicare Code Editor

```python
import msdrg

with msdrg.MceEditor() as mce:
    result = mce.edit({
        "discharge_date": 20250101,
        "age": 65, "sex": 0, "discharge_status": 1,
        "pdx": {"code": "I5020"},
        "sdx": [{"code": "E1165"}],
        "procedures": []
    })

print(result["edit_type"])  # "NONE"
print(result["edits"])      # [] — no edits triggered
```

### Unified claim — same dict for both

```python
import msdrg

claim = {
    "version": 431,
    "discharge_date": 20250101,
    "age": 65, "sex": 0, "discharge_status": 1,
    "pdx": {"code": "I5020"},
    "sdx": [{"code": "E1165"}],
    "procedures": []
}

with msdrg.MsdrgGrouper() as g, msdrg.MceEditor() as mce:
    drg = g.group(claim)
    mce_result = mce.edit(claim)
```

### ICD-10 Code Conversion

```python
import msdrg

with msdrg.IcdConverter() as conv:
    # Convert a diagnosis code from FY2025 to FY2026
    new_code = conv.convert_dx("B880", source_year=2025, target_year=2026)
    print(new_code)  # "B8801"

    # Batch convert
    results = conv.convert_dx_batch(
        ["B880", "I5020", "A047"],
        source_year=2025, target_year=2026,
    )
```

### Grouper with auto-conversion

```python
with msdrg.MsdrgGrouper() as g:
    result = g.group({
        "version": 431,               # Target: FY2026
        "source_icd_version": 2025,   # Source: FY2025 codes
        "age": 65, "sex": 0, "discharge_status": 1,
        "pdx": {"code": "B880"},       # Auto-converted to B8801
    })

print(result["conversions"])
# [{"original": "B880", "converted": "B8801", "code_type": "dx", "field": "pdx"}]
```

## MS-DRG Grouper

### Input format

```python
{
    "version": 431,              # MS-DRG version (e.g. 400, 410, 421, 431)
    "age": 65,                   # Patient age in years
    "sex": 0,                    # 0=Male, 1=Female, 2=Unknown
    "discharge_status": 1,       # 1=Home/Self Care, 20=Died
    "hospital_status": "NOT_EXEMPT",  # "NOT_EXEMPT" (default), "EXEMPT", or "UNKNOWN"
    "tie_breaker": "CLINICAL_SIGNIFICANCE",  # "CLINICAL_SIGNIFICANCE" (default) or "ALPHABETICAL"
    "source_icd_version": 2025,  # Source ICD-10 year for code conversion (optional)
    "pdx": {                     # Principal diagnosis (required)
        "code": "I5020",
        "poa": "Y"               # Present on Admission: Y/N/U/W (optional)
    },
    "admit_dx": {                # Admission diagnosis (optional)
        "code": "R0602"
    },
    "sdx": [                     # Secondary diagnoses (optional)
        {"code": "E1165", "poa": "Y"},
        {"code": "I10", "poa": "Y"}
    ],
    "procedures": [              # Procedure codes (optional)
        {"code": "02703DZ"}
    ]
}
```

### Hospital status

The `hospital_status` field controls how Hospital-Acquired Condition (HAC) processing is applied, per CMS rules:

| Value | Behavior |
|-------|----------|
| `"NOT_EXEMPT"` | Standard HAC processing. Default. |
| `"EXEMPT"` | Hospital is exempt from POA reporting. No HAC/POA ungroupable conditions. |
| `"UNKNOWN"` | Stricter POA validation with specific ungroupable return codes. |

### Tie breaker

The `tie_breaker` field controls how the grouper resolves attribute matches when multiple secondary diagnoses could match the same DRG formula attribute. This determines which diagnosis "wins" during the marking phase.

| Value | Behavior |
|-------|----------|
| `"CLINICAL_SIGNIFICANCE"` | MCC diagnoses get first pick over CC, then by ICD code string. Default, matches CMS Java grouper. |
| `"ALPHABETICAL"` | Sort by ICD code string only, ignoring severity. |

### Output format

```python
{
    "initial_drg": 293,
    "final_drg": 293,
    "initial_mdc": 5,
    "final_mdc": 5,
    "initial_drg_description": "Heart Failure and Shock without CC/MCC",
    "final_drg_description": "Heart Failure and Shock without CC/MCC",
    "initial_mdc_description": "Diseases and Disorders of the Circulatory System",
    "final_mdc_description": "Diseases and Disorders of the Circulatory System",
    "return_code": "OK",
    "pdx_output": {
        "code": "I5020",
        "mdc": 5,
        "severity": "CC",
        "drg_impact": "BOTH",
        "poa_error": "POA_NOT_CHECKED",
        "flags": ["VALID", "MARKED_FOR_INITIAL", "MARKED_FOR_FINAL"]
    },
    "sdx_output": [...],
    "proc_output": [...],
    "conversions": []  # ICD version conversions (empty if source_icd_version not set)
}
```

### Supported DRG versions

| Version | CMS Fiscal Year |
|---------|----------------|
| 400     | FY 2023 (Oct 2022 – Apr 2023) |
| 401     | FY 2023 (Apr 2023 – Sep 2023) |
| 410     | FY 2024 (Oct 2023 – Apr 2024) |
| 411     | FY 2024 (Apr 2024 – Sep 2024) |
| 420     | FY 2025 (Oct 2024 – Apr 2025) |
| 421     | FY 2025 (Apr 2025 – Sep 2025) |
| 430     | FY 2026 (Oct 2025 – Apr 2026) |
| 431     | FY 2026 (Apr 2026 – Sep 2026) |

## Medicare Code Editor (MCE)

The MCE validates ICD diagnosis and procedure codes against CMS edit rules. It checks for sex conflicts, age conflicts, unacceptable principal diagnoses, E-codes as PDX, non-covered procedures, bilateral procedures, and more.

### Input format

```python
{
    "discharge_date": 20250101,  # YYYYMMDD integer (required for MCE)
    "icd_version": 10,           # 9 or 10 (default: 10)
    "age": 65,
    "sex": 0,                    # 0=Male, 1=Female, 2=Unknown
    "discharge_status": 1,
    "pdx": {"code": "I5020"},
    "admit_dx": {"code": "R0602"},
    "sdx": [{"code": "E1165"}],
    "procedures": [{"code": "02703DZ"}]
}
```

### Output format

```python
{
    "version": 20260930,
    "edit_type": "PREPAYMENT",    # NONE, PREPAYMENT, POSTPAYMENT, or BOTH
    "edits": [                    # List of triggered edits (empty if NONE)
        {
            "name": "E_CODE_AS_PDX",
            "count": 1,
            "code_type": "DIAGNOSIS",
            "edit_type": "PREPAYMENT"
        }
    ]
}
```

### Example — E-code as principal diagnosis

```python
import msdrg

with msdrg.MceEditor() as mce:
    result = mce.edit({
        "discharge_date": 20250101,
        "age": 65, "sex": 0, "discharge_status": 1,
        "pdx": {"code": "V0001XA"},  # E-code
        "sdx": [], "procedures": []
    })

print(result["edit_type"])  # "PREPAYMENT"
print(result["edits"][0]["name"])  # "E_CODE_AS_PDX"
```

### Supported edit types

The MCE detects ~35 edit types including:
- **INVALID_CODE** — code not in CMS master for date range
- **SEX_CONFLICT** — code restricted by patient sex
- **AGE_CONFLICT** — code restricted by patient age
- **E_CODE_AS_PDX** — E-code used as principal diagnosis
- **MANIFESTATION_AS_PDX** — manifestation code used as PDX
- **UNACCEPTABLE_PDX** — code unacceptable as principal diagnosis
- **NON_COVERED** — procedure not covered by Medicare
- **BILATERAL** — bilateral procedure without bilateral PDX
- **OPEN_BIOPSY** — open biopsy without prior biopsy

### MCE validation

The MCE implementation is validated against the CMS Java MCE 2.0 v43.1 with a 100% match rate on 50,000 test claims.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Python (msdrg)                                              │
│  ctypes ──► C API (c_api.zig, mce_c_api.zig)                │
│                │                                             │
│    ┌───────────┼─────────────────┐                           │
│    ▼           ▼                 ▼                           │
│  MS-DRG     MCE Editor     ICD-10 Converter                 │
│  Grouper    (MceComponent)  (ConversionData)                │
│    │           │                 │                           │
│    ▼           ▼                 ▼                           │
│  Chain of    Validation     Code Lookup:                    │
│  Links:      Pipeline:      Binary search                   │
│  Preprocess  Code Check     on sorted                       │
│  → Group     → Edit Rules   conversion                      │
│  → HAC       → Output       entries                         │
│  → Final DRG   Counts                                        │
│    │           │                 │                           │
│    ▼           ▼                 ▼                           │
│  Memory-mapped LMDB database (msdrg.mdb)                    │
└──────────────────────────────────────────────────────────────┘
```

Both engines share the same shared library and data files. The grouping pipeline is a chain of composable processors; the MCE is a linear validation pipeline. Both mirror the original Java architecture for validation purposes.

## Building from source

### Prerequisites

- **Zig 0.16+** — [download](https://ziglang.org/download/) or via package manager
- **Python 3.11+**
- **uv** (recommended) or **pip**

### Setup

```bash
git clone https://github.com/Bedrock-Billing/mz-drg.git
cd mz-drg

# Create venv and install
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

This compiles the Zig shared library and bundles all data files into the Python package.

### Run tests

```bash
# Zig unit tests (60+ tests)
cd zig_src && zig build test

# Python tests (MS-DRG + MCE)
python -m pytest tests/
```

### Data pipeline

The binary data files are prebuilt and included in the monolithic `data/msdrg.mdb` database. To regenerate it from the raw CMS CSVs:

```bash
bash scripts/setup_data.sh
```

This runs extract → import → compile → zig build in sequence. See `scripts/` for individual steps.

## Comparison testing

The `tests/` directory contains tools for validating mz-drg against the reference Java implementations.

```bash
# Generate random test claims
python tests/generate_test_claims.py --count 1000 --out tests/claims.json

# Compare MS-DRG grouper
python tests/compare_groupers.py --file tests/claims.json

# Compare MCE editor
python tests/compare_mce.py --file tests/claims.json

# Benchmark
python tests/compare_groupers.py --file tests/claims.json --benchmark
```

> The Java comparisons require JDK 17+ and the reference JARs in `jars/`. This is only needed for validation — the Python package itself has no Java dependency.

## C API

mz-drg exposes a C ABI for integration with any language. A complete header is auto-generated at `zig-out/include/msdrg.h` after building.

### JSON API (simple — single call)

```c
#include "msdrg.h"

void* ctx = msdrg_context_init("/path/to/data");
const char* result = msdrg_group_json(ctx, "{\"version\":431,...}");
msdrg_string_free(result);
msdrg_context_free(ctx);
```

### MCE Editor

```c
#include "msdrg.h"

MceContext mce = mce_context_init("/path/to/data");
const char* result = mce_edit_json(mce, "{\"discharge_date\":20250101,...}");
msdrg_string_free(result);
mce_context_free(mce);
```

### ICD-10 Code Conversion

```c
#include "msdrg.h"

MsdrgContext ctx = msdrg_context_init("/path/to/data");

// Convert a diagnosis code (FY2025 → FY2026)
const char* converted = msdrg_convert_dx(ctx, "B880", 2025, 2026);
// converted = "B8801"

// Convert a procedure code
const char* pr_conv = msdrg_convert_pr(ctx, "02703DZ", 2025, 2026);

msdrg_string_free(converted);
msdrg_string_free(pr_conv);
msdrg_context_free(ctx);
```

Functions are thread-safe after initialization. The context is immutable and can be shared across threads.

## Project structure

```
mz-drg/
├── msdrg/                       # Python package
│   ├── __init__.py
│   ├── grouper.py               # MsdrgGrouper class
│   ├── mce.py                   # MceEditor class
│   └── converter.py             # IcdConverter class
├── zig_src/                     # Zig source
│   ├── build.zig
│   ├── main.zig
│   └── src/
│       ├── c_api.zig            # MS-DRG C ABI exports
│       ├── json_api.zig         # MS-DRG JSON in/out
│       ├── msdrg.zig            # GrouperChain + version routing
│       ├── chain.zig            # Composable processor chain
│       ├── models.zig           # Data models
│       ├── preprocess.zig       # Exclusion & attribute handling
│       ├── grouping.zig         # DRG formula matching
│       ├── marking.zig          # Code marking logic
│       ├── hac.zig              # Hospital-Acquired Conditions
│       ├── conversion.zig       # ICD-10 code conversion
│       ├── mce.zig              # MCE main editor
│       ├── mce_c_api.zig        # MCE C ABI exports
│       ├── mce_json_api.zig     # MCE JSON in/out
│       ├── mce_data.zig         # MCE data loading
│       ├── mce_enums.zig        # MCE attributes & edits
│       ├── mce_editing.zig      # MCE edit rules
│       └── mce_validation.zig   # MCE validation logic
├── data/                        # Consolidated LMDB database (msdrg.mdb)
├── scripts/                     # Data extraction & compilation
│   ├── compile_icd_conversions.py  # ICD conversion table compiler
│   └── ...
├── tests/                       # Tests & comparison tools
│   ├── example.py               # All-components example
│   └── ...
├── pyproject.toml
└── setup.py
```

## License

MIT — see [LICENSE](LICENSE).

## Documentation

Full documentation is available at **[Bedrock-Billing.github.io/mz-drg](https://Bedrock-Billing.github.io/mz-drg/)**.

## Acknowledgments

This project is intended for healthcare IT professionals who need fast, embeddable, and auditable claim processing tools.

