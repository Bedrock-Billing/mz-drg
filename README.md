# mz-drg

**A high-performance MS-DRG grouper written in Zig with Python bindings.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org)
[![Python](https://img.shields.io/badge/Python-3.11+-green.svg)](https://python.org)

---

mz-drg is an open-source reimplementation of the CMS MS-DRG (Medicare Severity Diagnosis Related Groups) classification engine, written in [Zig](https://ziglang.org) and callable from Python. It takes patient claim data — diagnoses, procedures, demographics — and assigns the appropriate DRG, MDC, severity, and return codes.

**It is validated against 50,000+ claims against the reference Java grouper with a 100% match rate.**

## Why mz-drg?

The official CMS MS-DRG grouper is a Java application. While accurate, it comes with practical limitations:

| | Java Grouper | mz-drg |
|---|---|---|
| **Startup** | JVM warmup, seconds | Instant |
| **Throughput (tested on a Ryzen 5 5600U laptop)** | ~500 claims/sec | ~7,000+ claims/sec | 
| **Memory** | JVM heap overhead | Minimal, memory-mapped data |
| **Dependencies** | JRE 17+, classpath management | Single shared library |
| **Python integration** | JPype bridge (fragile) | Native ctypes (simple) |
| **Embedding** | Requires JVM process | C ABI, any language |

mz-drg is not a black-box reimplementation. The grouping logic — preprocessing, exclusion handling, diagnosis clustering, severity assignment, formula evaluation, rerouting, marking, and final grouping — is ported line-by-line from the decompiled Java source and validated claim-by-claim against the original.

## Quick start

### Install

```bash
pip install msdrg
```

> **Requires Zig 0.16+** at build time. Install from [ziglang.org/download](https://ziglang.org/download/) or set the `ZIG` environment variable to point to your zig binary.

### Use

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

### Helper function

```python
import msdrg

claim = msdrg.create_claim(
    version=431,
    age=65,
    sex=0,
    discharge_status=1,
    pdx="I5020",
    sdx=["E1165", "I10"],
    procedures=["02703DZ"],
)

with msdrg.MsdrgGrouper() as g:
    result = g.group(claim)
```

## Input format

The `group()` method accepts a dictionary:

```python
{
    "version": 431,              # MS-DRG version (e.g. 400, 410, 421, 431)
    "age": 65,                   # Patient age in years
    "sex": 0,                    # 0=Male, 1=Female, 2=Unknown
    "discharge_status": 1,       # 1=Home/Self Care, 20=Died
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

## Output format

`group()` returns a dictionary:

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

## Supported DRG versions

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

Pass the version number in the claim's `version` field.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Python (msdrg)                                 │
│  ctypes ──► C API (c_api.zig)                   │
│                │                                │
│                ▼                                │
│  GrouperChain  (data loader + version router)   │
│       │                                         │
│       ▼                                         │
│  Chain of Links:                                │
│  ┌──────────────────────────────────────────┐   │
│  │ Preprocess  →  Exclusions  →  Grouping   │   │
│  │    ↓              ↓              ↓       │   │
│  │ Attributes    Cluster Map    Formulas    │   │
│  │    ↓              ↓              ↓       │   │
│  │ Diagnosis     Marking       Final DRG    │   │
│  └──────────────────────────────────────────┘   │
│       │                                         │
│       ▼                                         │
│  Memory-mapped binary data (16 .bin files)      │
└─────────────────────────────────────────────────┘
```

The grouper loads 16 precompiled binary data files at startup (diagnosis definitions, DRG formulas, cluster maps, exclusion groups, etc.) via memory mapping. The grouping pipeline is a chain of composable processors, each transforming the claim context. This design mirrors the original Java architecture for validation purposes.

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

This compiles the Zig shared library and bundles the data files into the Python package.

### Run tests

```bash
# Zig unit tests (27 tests)
cd zig_src && zig build test

# Python smoke test
python -c "import msdrg; print(msdrg.MsdrgGrouper().group({'version': 431, 'age': 65, 'sex': 0, 'discharge_status': 1, 'pdx': {'code': 'I5020'}, 'sdx': [], 'procedures': []}))"
```

### Data pipeline

The binary data files (`data/bin/*.bin`) are prebuilt and included in the repository. To regenerate them from the raw CMS CSVs:

```bash
bash scripts/setup_data.sh
```

This runs extract → import → compile → zig build in sequence. See `scripts/` for individual steps.

## Comparison testing

The `tests/` directory contains tools for validating mz-drg against the reference Java grouper.

```bash
# Generate random test claims
python tests/generate_test_claims.py --count 1000 --out tests/claims.json

# Compare Java vs Zig output
python tests/compare_groupers.py --file tests/claims.json

# Benchmark both
python tests/compare_groupers.py --file tests/claims.json --benchmark
```

> The Java comparison requires JDK 17+ and the reference JARs in `jars/`. This is only needed for validation — the Python package itself has no Java dependency.

## C API

mz-drg exposes a C ABI for integration with any language. See `zig_src/src/c_api.zig` for the full API.

```c
// Initialize (loads all data, pre-builds chains)
void* ctx = msdrg_context_init("/path/to/data/bin");

// Group a claim via JSON
const char* result_json = msdrg_group_json(ctx, "{\"version\":431,...}");

// Free
msdrg_string_free(result_json);
msdrg_context_free(ctx);
```

Functions are thread-safe after initialization. The context is immutable and can be shared across threads.

## Project structure

```
mz-drg/
├── msdrg/                    # Python package
│   ├── __init__.py
│   └── grouper.py            # MsdrgGrouper class
├── zig_src/                  # Zig source
│   ├── build.zig
│   ├── main.zig
│   └── src/
│       ├── c_api.zig         # C ABI exports
│       ├── json_api.zig      # JSON in/out
│       ├── msdrg.zig         # GrouperChain + version routing
│       ├── chain.zig         # Composable processor chain
│       ├── models.zig        # Data models
│       ├── preprocess.zig    # Exclusion & attribute handling
│       ├── grouping.zig      # DRG formula matching
│       ├── marking.zig       # Code marking logic
│       ├── hac.zig           # Hospital-Acquired Conditions
│       └── ...               # 20+ modules, ~8,500 lines
├── data/bin/                 # Prebuilt binary data (16 files)
├── scripts/                  # Data extraction & compilation
├── tests/                    # Comparison & benchmark tools
├── python_client/            # Legacy Python wrapper
├── pyproject.toml
└── setup.py
```

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

This project is intended for healthcare IT professionals who need a fast, embeddable, and auditable DRG classification engine.
