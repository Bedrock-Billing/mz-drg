# mz-drg

**High-performance CMS claim processing tools written in Zig with Python bindings.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org)
[![Python](https://img.shields.io/badge/Python-3.11+-green.svg)](https://python.org)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://Bedrock-Billing.github.io/mz-drg/)

---

mz-drg provides open-source reimplementations of two CMS tools:

- **MS-DRG Grouper** — assigns Diagnosis Related Groups based on diagnoses, procedures, and demographics
- **Medicare Code Editor (MCE)** — validates ICD diagnosis and procedure codes against CMS edit rules

Both are written in [Zig](https://ziglang.org), callable from Python, and validated against the CMS reference Java implementations with a 100% match rate on 50,000+ claims.

## Why mz-drg?

The official CMS tools are Java applications. While accurate, they come with practical limitations:

| | Java (CMS) | mz-drg |
|---|---|---|
| **Startup** | JVM warmup, seconds | Instant |
| **Throughput (Ryzen 5 5600U)** | ~500 claims/sec | ~7,000+ claims/sec |
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
        "age": 65,
        "sex": 0,
        "discharge_status": 1,
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
    "proc_output": [...]
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

The MCE implementation is validated against the CMS Java MCE 2.0 v43.1 with a 100% match rate on 50l,000 test claims.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Python (msdrg)                                      │
│  ctypes ──► C API (c_api.zig, mce_c_api.zig)        │
│                │                                     │
│    ┌───────────┴───────────┐                         │
│    ▼                       ▼                         │
│  MS-DRG Grouper         MCE Editor                  │
│  (GrouperChain)         (MceComponent)              │
│    │                       │                         │
│    ▼                       ▼                         │
│  Chain of Links:        Validation Pipeline:        │
│  Preprocess → Group     Code Check → Edit Rules     │
│  → HAC → Final DRG      → Output Counts            │
│    │                       │                         │
│    ▼                       ▼                         │
│  Memory-mapped .bin files (22 total)                │
└──────────────────────────────────────────────────────┘
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

The binary data files (`data/bin/*.bin`) are prebuilt and included in the repository. To regenerate them from the raw CMS CSVs:

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

void* ctx = msdrg_context_init("/path/to/data/bin");
const char* result = msdrg_group_json(ctx, "{\"version\":431,...}");
msdrg_string_free(result);
msdrg_context_free(ctx);
```

### Structured API (no JSON — fine-grained control)

```c
#include "msdrg.h"

MsdrgContext ctx = msdrg_context_init("/path/to/data/bin");
MsdrgVersion ver = msdrg_version_create(ctx, 431);
MsdrgInput inp = msdrg_input_create();

msdrg_input_set_pdx(inp, "I5020", 'Y');
msdrg_input_add_sdx(inp, "E1165", 'Y');
msdrg_input_set_demographics(inp, 65, 0, 1);

MsdrgResult res = msdrg_group(ver, inp);
int32_t drg = msdrg_result_get_final_drg(res);
int32_t mdc = msdrg_result_get_final_mdc(res);
const char* desc = msdrg_result_get_final_drg_description(res);

msdrg_result_free(res);
msdrg_input_free(inp);
msdrg_version_free(ver);
msdrg_context_free(ctx);
```

The structured API gives C/C++/Rust callers direct access to all 47 result fields without JSON parsing overhead. For Python, the JSON API (`group()`) is faster due to fewer FFI crossings. See `zig-out/include/msdrg.h` for the full function reference.

### MCE Editor

```c
#include "msdrg.h"

MceContext mce = mce_context_init("/path/to/data/bin");
const char* result = mce_edit_json(mce, "{\"discharge_date\":20250101,...}");
msdrg_string_free(result);
mce_context_free(mce);
```

Functions are thread-safe after initialization. The context is immutable and can be shared across threads.

## Project structure

```
mz-drg/
├── msdrg/                       # Python package
│   ├── __init__.py
│   ├── grouper.py               # MsdrgGrouper class
│   └── mce.py                   # MceEditor class
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
│       ├── mce.zig              # MCE main editor
│       ├── mce_c_api.zig        # MCE C ABI exports
│       ├── mce_json_api.zig     # MCE JSON in/out
│       ├── mce_data.zig         # MCE data loading
│       ├── mce_enums.zig        # MCE attributes & edits
│       ├── mce_editing.zig      # MCE edit rules
│       └── mce_validation.zig   # MCE validation logic
├── data/bin/                    # Prebuilt binary data (22 files)
├── scripts/                     # Data extraction & compilation
├── tests/                       # Comparison & benchmark tools
├── pyproject.toml
└── setup.py
```

## License

MIT — see [LICENSE](LICENSE).

## Documentation

Full documentation is available at **[Bedrock-Billing.github.io/mz-drg](https://Bedrock-Billing.github.io/mz-drg/)**.

## Acknowledgments

This project is intended for healthcare IT professionals who need fast, embeddable, and auditable claim processing tools.
