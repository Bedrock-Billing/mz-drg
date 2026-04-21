# API Reference

Complete reference for the `msdrg` Python package.

---

## MS-DRG Grouper

### `MsdrgGrouper`

The main grouper class. Wraps the native Zig shared library for high-performance MS-DRG classification.

```python
class MsdrgGrouper(lib_path=None, data_dir=None)
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `lib_path` | `str \| None` | `None` | Path to the shared library. Auto-detected if not provided. |
| `data_dir` | `str \| None` | `None` | Path to the binary data directory. Auto-detected if not provided. |

**Methods:**

#### `group(claim_data)`

Group a claim through the MS-DRG classification pipeline (JSON API — fastest for Python).

```python
def group(self, claim_data: ClaimInput) -> GroupResult
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `claim_data` | `ClaimInput` | Claim dictionary (see below) |

**Returns:** `GroupResult` dictionary.

**Raises:** `RuntimeError` if the grouper has been closed or the native engine returns null.

#### `close()`

Explicitly free the grouper context and release resources.

#### Context manager

```python
with MsdrgGrouper() as g:
    result = g.group(...)
# g is automatically closed
```

---

### `create_claim()`

Convenience function to build a `ClaimInput` dict from simple arguments.

```python
def create_claim(
    version: int,
    age: int,
    sex: Literal[0, 1, 2],
    discharge_status: int,
    pdx: str,
    pdx_poa: str | None = None,
    sdx: list[str] | list[tuple[str, str]] | None = None,
    procedures: list[str] | None = None,
) -> ClaimInput
```

**Example:**

```python
claim = msdrg.create_claim(
    version=431, age=65, sex=0, discharge_status=1,
    pdx="I5020", sdx=["E1165", "I10"], procedures=["02703DZ"],
)
```

---

### Input Types

#### `ClaimInput`

```python
class ClaimInput(TypedDict, total=False):
    version: int                                          # MS-DRG version (required)
    age: int                                              # Patient age in years
    sex: Literal[0, 1, 2]                                 # 0=Male, 1=Female, 2=Unknown
    discharge_status: int                                 # CMS discharge status code
    hospital_status: Literal["EXEMPT", "NOT_EXEMPT", "UNKNOWN"]
    tie_breaker: Literal["CLINICAL_SIGNIFICANCE", "ALPHABETICAL"]
    source_icd_version: int                               # Source ICD-10 fiscal year for conversion
    pdx: DiagnosisInput                                   # Principal diagnosis (required)
    admit_dx: DiagnosisInput                              # Admission diagnosis
    sdx: list[DiagnosisInput]                             # Secondary diagnoses
    procedures: list[ProcedureInput]                      # Procedure codes
```

#### `DiagnosisInput`

```python
class DiagnosisInput(TypedDict, total=False):
    code: str       # ICD code, e.g. "I5020"
    poa: str        # Present on Admission: "Y", "N", "U", "W"
```

#### `ProcedureInput`

```python
class ProcedureInput(TypedDict):
    code: str       # Procedure code, e.g. "02703DZ"
```

---

### Output Types

#### `GroupResult`

```python
class GroupResult(TypedDict, total=False):
    initial_drg: int | None
    final_drg: int | None
    initial_mdc: int | None
    final_mdc: int | None
    initial_drg_description: str | None
    final_drg_description: str | None
    initial_mdc_description: str | None
    final_mdc_description: str | None
    return_code: str                        # "OK", "INVALID_PDX", "UNGROUPABLE", etc.
    pdx_output: DiagnosisOutput | None
    sdx_output: list[DiagnosisOutput]
    proc_output: list[ProcedureOutput]
    conversions: list[CodeConversion]       # ICD version conversions (empty if none)
```

#### `CodeConversion`

Returned in `GroupResult.conversions` when `source_icd_version` triggers code mapping:

```python
class CodeConversion(TypedDict):
    original: str           # The input code
    converted: str          # The mapped code
    code_type: str          # "dx" or "pr"
    field: str              # "pdx", "admit_dx", "sdx[0]", "procedures[1]", etc.
```

#### `DiagnosisOutput`

```python
class DiagnosisOutput(TypedDict, total=False):
    code: str
    mdc: int | None
    severity: str           # "CC", "MCC", "NON_CC"
    drg_impact: str         # "INITIAL", "FINAL", "BOTH", "NONE"
    poa_error: str          # "POA_NOT_CHECKED", "POA_MISSING", etc.
    flags: list[str]        # ["VALID", "MARKED_FOR_INITIAL", ...]
```

#### `ProcedureOutput`

```python
class ProcedureOutput(TypedDict, total=False):
    code: str
    is_or: bool             # True if this is an OR procedure
    drg_impact: str         # "INITIAL", "FINAL", "BOTH", "NONE"
    flags: list[str]
```

---

## Medicare Code Editor (MCE)

### `MceEditor`

The MCE validation client. Validates ICD codes against CMS edit rules.

```python
class MceEditor(lib_path=None, data_dir=None)
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `lib_path` | `str \| None` | `None` | Path to the shared library. Auto-detected if not provided. |
| `data_dir` | `str \| None` | `None` | Path to the MCE data directory. Auto-detected if not provided. |

**Methods:**

#### `edit(claim)`

Run the Medicare Code Editor on a claim.

```python
def edit(self, claim: MceInput) -> MceResult
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `claim` | `MceInput` | Claim dictionary with `discharge_date` (see below) |

**Returns:** `MceResult` dictionary.

**Raises:** `RuntimeError` if the editor has been closed or returns null.

#### `close()`

Explicitly free the MCE context and release resources.

#### Context manager

```python
with MceEditor() as mce:
    result = mce.edit(...)
# mce is automatically closed
```

---

### `create_mce_input()`

Convenience function to build an `MceInput` dict from simple arguments.

```python
def create_mce_input(
    discharge_date: int,
    age: int,
    sex: Literal[0, 1, 2],
    discharge_status: int,
    pdx: str,
    sdx: list[str] | None = None,
    procedures: list[str] | None = None,
) -> MceInput
```

**Example:**

```python
mce_claim = msdrg.create_mce_input(
    discharge_date=20250101, age=65, sex=0, discharge_status=1,
    pdx="V0001XA",
)
```

---

### Input Types

#### `MceInput`

```python
class MceInput(TypedDict, total=False):
    discharge_date: int                   # YYYYMMDD integer (required)
    icd_version: Literal[9, 10]           # Default: 10
    age: int
    sex: Literal[0, 1, 2]
    discharge_status: int
    pdx: MceDiagnosisInput
    admit_dx: MceDiagnosisInput
    sdx: list[MceDiagnosisInput]
    procedures: list[MceProcedureInput]
    # MS-DRG fields (ignored by MCE but safe to include)
    version: int
    hospital_status: str
```

#### `MceDiagnosisInput`

```python
class MceDiagnosisInput(TypedDict, total=False):
    code: str       # ICD code
    poa: str        # "Y", "N", "U", "W"
```

#### `MceProcedureInput`

```python
class MceProcedureInput(TypedDict):
    code: str       # Procedure code
```

---

### Output Types

#### `MceResult`

```python
class MceResult(TypedDict):
    version: int                    # Data file version (termination date)
    edit_type: str                  # "NONE", "PREPAYMENT", "POSTPAYMENT", "BOTH"
    edits: list[MceEditDetail]      # Triggered edits (empty if NONE)
```

#### `MceEditDetail`

```python
class MceEditDetail(TypedDict):
    name: str           # Edit name, e.g. "E_CODE_AS_PDX"
    count: int          # Number of codes triggering this edit
    code_type: str      # "DIAGNOSIS" or "PROCEDURE"
    edit_type: str      # "PREPAYMENT" or "POSTPAYMENT"
```

---

## ICD-10 Converter

### `IcdConverter`

Maps ICD-10-CM/PCS codes between fiscal year versions using CMS conversion tables.

```python
class IcdConverter(lib_path=None, data_dir=None)
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `lib_path` | `str \| None` | `None` | Path to the shared library. Auto-detected if not provided. |
| `data_dir` | `str \| None` | `None` | Path to the data directory. Auto-detected if not provided. |

**Methods:**

#### `convert_dx(code, source_year, target_year)`

Convert a single ICD-10-CM diagnosis code. Returns the original if no mapping exists.

```python
def convert_dx(self, code: str, source_year: int, target_year: int) -> str
```

#### `convert_pr(code, source_year, target_year)`

Convert a single ICD-10-PCS procedure code. Returns the original if no mapping exists.

```python
def convert_pr(self, code: str, source_year: int, target_year: int) -> str
```

#### `convert_dx_batch(codes, source_year, target_year)`

Convert a batch of diagnosis codes.

```python
def convert_dx_batch(
    self, codes: list[str], source_year: int, target_year: int
) -> list[ConversionResult]
```

#### `convert_pr_batch(codes, source_year, target_year)`

Convert a batch of procedure codes.

```python
def convert_pr_batch(
    self, codes: list[str], source_year: int, target_year: int
) -> list[ConversionResult]
```

#### `version_to_year(version)` / `year_to_version(year)`

Static methods to convert between MS-DRG version numbers and ICD-10 fiscal years.

```python
@staticmethod
def version_to_year(version: int) -> int   # 431 -> 2026

@staticmethod
def year_to_version(year: int) -> int      # 2026 -> 431
```

#### `close()` / Context manager

```python
with IcdConverter() as conv:
    result = conv.convert_dx("B880", source_year=2025, target_year=2026)
```

---

### Output Types

#### `ConversionResult`

```python
class ConversionResult(TypedDict):
    original: str       # Input code
    converted: str      # Mapped code (same as original if no mapping)
```

---

## Thread Safety

`MsdrgGrouper`, `MceEditor`, and `IcdConverter` contexts are all **immutable after initialization** and safe to share across threads. Each call to `group()`, `edit()`, and `convert_dx()`/`convert_pr()` is independently thread-safe.

!!! tip "Best Practice"
    Create one instance and reuse it. Initialization loads binary data via memory mapping — subsequent calls are fast and lock-free.

```python
# Good: one instance, many calls
g = MsdrgGrouper()
results = [g.group(claim) for claim in claims]
g.close()

# Bad: new instance per call (wasteful)
for claim in claims:
    with MsdrgGrouper() as g:
        result = g.group(claim)
```
