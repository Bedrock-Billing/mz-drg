# ICD-10 Code Converter

The ICD-10 converter maps diagnosis and procedure codes between fiscal year versions using CMS conversion tables. This lets you group claims coded in one year's ICD-10 version through a different year's MS-DRG grouper.

## Why convert codes?

CMS updates ICD-10-CM and ICD-10-PCS codes every October 1 (the start of each federal fiscal year). Codes are added, deleted, split, and renamed. A claim coded with FY 2025 codes may not be recognized by the V43 (FY 2026) grouper, and vice versa.

Common scenarios:

- **Backward mapping** — a claim coded in FY 2026 that needs to be grouped with the V42 (FY 2025) grouper
- **Forward mapping** — a claim coded in FY 2025 that needs to be grouped with the V43 (FY 2026) grouper
- **Cross-year analytics** — comparing DRG assignments across fiscal years using consistent codes

## How it works

```mermaid
graph LR
    A[Claim Codes<br>FY 2025] --> B[ICD Converter]
    B -->|"CMS conversion<br>table lookup"| C[Mapped Codes<br>FY 2026]
    C --> D[MS-DRG Grouper<br>V43]
    D --> E[DRG Assignment]
```

The converter uses CMS ICD-10 conversion tables which map each "current" code to its "previous" equivalent (and vice versa). At compile time, both directions are generated:

- **Forward** (newer → older): e.g., `B8801` → `B880`
- **Backward** (older → newer): e.g., `B880` → `B8801`

When a code has no mapping (most codes don't change year to year), the original code is returned unchanged.

## Two ways to use it

### 1. Standalone converter

Call `IcdConverter` directly to map codes without grouping:

```python
import msdrg

with msdrg.IcdConverter() as conv:
    new_code = conv.convert_dx("B880", source_year=2025, target_year=2026)
    # "B8801"
```

See [Usage](usage.md#standalone-converter) for full examples.

### 2. Automatic in the grouper

Set `source_icd_version` on a claim and the grouper converts codes before grouping:

```python
with msdrg.MsdrgGrouper() as g:
    result = g.group({
        "version": 431,
        "source_icd_version": 2025,  # FY2025 codes → FY2026
        "pdx": {"code": "B880"},      # auto-converted to B8801
    })

result["conversions"]
# [{"original": "B880", "converted": "B8801", "code_type": "dx", "field": "pdx"}]
```

See [Usage](usage.md#grouper-integration) for full examples.

## Data source

Conversion data comes from the CMS ICD-10-CM and ICD-10-PCS Conversion Tables, published annually at [cms.gov](https://www.cms.gov/medicare/coding-billing/icd-10-codes). The tables are compiled into a single binary file per code type:

| File | Magic | Description |
|------|-------|-------------|
| `icd10cm_conversions.bin` | `ICDC` | Diagnosis code mappings |
| `icd10pcs_conversions.bin` | `ICDP` | Procedure code mappings |

To regenerate the binary files from the latest CMS tables:

```bash
python scripts/compile_icd_conversions.py
```

## Version to year mapping

| MS-DRG Version | ICD-10 Fiscal Year |
|----------------|-------------------|
| 400 / 401 | FY 2023 |
| 410 / 411 | FY 2024 |
| 420 / 421 | FY 2025 |
| 430 / 431 | FY 2026 |

!!! note
    The converter is an optional component. If conversion binary files are not present, the grouper works normally without conversion. When `source_icd_version` is omitted from the claim, no conversion occurs.
