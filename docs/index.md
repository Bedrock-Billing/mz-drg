# mz-drg

**High-performance CMS claim processing tools written in Zig with Python bindings.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/Bedrock-Billing/mz-drg/blob/main/LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org)
[![Python](https://img.shields.io/badge/Python-3.11+-green.svg)](https://python.org)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://Bedrock-Billing.github.io/mz-drg/)

---

mz-drg provides open-source reimplementations of CMS tools:

- **MS-DRG Grouper** — assigns Diagnosis Related Groups based on diagnoses, procedures, and demographics
- **Medicare Code Editor (MCE)** — validates ICD diagnosis and procedure codes against CMS edit rules
- **ICD-10 Converter** — maps codes between fiscal year versions using CMS conversion tables

All are written in [Zig](https://ziglang.org), callable from Python, and validated against the CMS reference Java implementations with a 100% match rate on 50,000+ claims.

## :zap: Why mz-drg?

The official CMS tools are Java applications. While accurate, they come with practical limitations:

- **JVM Overhead** — Requires seconds for JVM warmup and significant heap memory.
- **Throughput** — Java performance is typically ~500 claims/sec; `mz-drg` reaches **11,000+ claims/sec** on similar hardware.
- **Minimal Footprint** — Uses memory-mapped LMDB data with zero-copy access.
- **Embedding** — Simple C ABI enables integration with Python (ctypes), Rust, C++, and more.

## :rocket: Quick example

```python
import msdrg

# MS-DRG grouping
with msdrg.MsdrgGrouper() as g:
    result = g.group({
        "version": 431, "age": 65, "sex": 0, "discharge_status": 1,
        "pdx": {"code": "I5020"}, "sdx": [{"code": "E1165"}], "procedures": []
    })
    print(result["final_drg"])  # 293

# MCE validation
with msdrg.MceEditor() as mce:
    result = mce.edit({
        "discharge_date": 20250101, "age": 65, "sex": 0, "discharge_status": 1,
        "pdx": {"code": "I5020"}, "sdx": [], "procedures": []
    })
    print(result["edit_type"])  # "NONE"

# ICD-10 code conversion
with msdrg.IcdConverter() as conv:
    new_code = conv.convert_dx("B880", source_year=2025, target_year=2026)
    print(new_code)  # "B8801"
```

## :book: What's next?

- [Installation](getting-started/installation.md) — how to install the package
- [Quick Start](getting-started/quickstart.md) — first steps with all tools
- [MS-DRG Grouper](grouper/overview.md) — detailed grouper documentation
- [MCE Editor](mce/overview.md) — detailed MCE documentation
- [ICD-10 Converter](converter/overview.md) — code conversion between fiscal years
- [API Reference](api-reference.md) — full Python API documentation
- [Building from Source](dev/building.md) — for contributors
- [Changelog](changelog.md) — version history
