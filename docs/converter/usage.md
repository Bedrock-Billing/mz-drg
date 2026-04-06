# Converter Usage

## Standalone converter

Use `IcdConverter` to map codes independently of the grouper.

### Single code conversion

```python
import msdrg

with msdrg.IcdConverter() as conv:
    # Convert a diagnosis code from FY2025 to FY2026
    result = conv.convert_dx("B880", source_year=2025, target_year=2026)
    print(result)  # "B8801"

    # Convert a procedure code from FY2026 back to FY2025
    result = conv.convert_pr("02703EZ", source_year=2026, target_year=2025)
    print(result)  # "02703DZ"
```

If no mapping exists, the original code is returned:

```python
result = conv.convert_dx("I5020", source_year=2025, target_year=2026)
print(result)  # "I5020" — unchanged
```

Dots are stripped automatically (CMS tables use `B88.01`, grouper uses `B8801`):

```python
result = conv.convert_dx("B88.0", source_year=2025, target_year=2026)
print(result)  # "B8801"
```

### Batch conversion

```python
with msdrg.IcdConverter() as conv:
    results = conv.convert_dx_batch(
        ["B880", "I5020", "A047"],
        source_year=2025,
        target_year=2026,
    )
    for r in results:
        print(f"{r['original']:>10s} -> {r['converted']}")

#        B880 -> B8801
#       I5020 -> I5020
#        A047 -> A0471
```

### Version helpers

Convert between MS-DRG version numbers and ICD-10 fiscal years:

```python
IcdConverter.version_to_year(431)   # 2026
IcdConverter.version_to_year(420)   # 2025
IcdConverter.year_to_version(2026)  # 431
IcdConverter.year_to_version(2025)  # 421
```

---

## Grouper integration

Set `source_icd_version` on a claim to auto-convert codes before grouping. The grouper converts all diagnosis and procedure codes, then groups with the mapped codes.

### Basic usage

```python
import msdrg

with msdrg.MsdrgGrouper() as g:
    result = g.group({
        "version": 431,               # Target: FY2026
        "source_icd_version": 2025,   # Source: FY2025 codes
        "age": 65,
        "sex": 0,
        "discharge_status": 1,
        "pdx": {"code": "B880"},      # FY2025 code
    })

print(result["final_drg"])   # 607
print(result["final_mdc"])   # 9
```

### With `create_claim()`

```python
claim = msdrg.create_claim(
    version=431,
    source_icd_version=2025,   # codes are FY2025
    age=65, sex=0, discharge_status=1,
    pdx="B880", sdx=["I5020"], procedures=["02703DZ"],
)

with msdrg.MsdrgGrouper() as g:
    result = g.group(claim)
```

### Conversion output

The result includes a `conversions` field showing which codes were actually mapped:

```python
result["conversions"]
# [
#   {"original": "B880", "converted": "B8801", "code_type": "dx", "field": "pdx"},
#   {"original": "02703DZ", "converted": "02703EZ", "code_type": "pr", "field": "procedures[0]"}
# ]
```

Each entry includes:

| Field | Description |
|-------|-------------|
| `original` | The input code |
| `converted` | The mapped code |
| `code_type` | `"dx"` or `"pr"` |
| `field` | Which claim field: `"pdx"`, `"admit_dx"`, `"sdx[0]"`, `"procedures[1]"`, etc. |

If no codes were converted, `conversions` is an empty list.

### Structured API

Conversion also works with `group_structured()`:

```python
with msdrg.MsdrgGrouper() as g:
    result = g.group_structured({
        "version": 431,
        "source_icd_version": 2025,
        "pdx": {"code": "B880"},
    })
    # result["conversions"] is populated the same way
```

### No conversion when source matches target

When `source_icd_version` equals the grouper's year, no conversion is performed:

```python
# V43 = FY2026, source = FY2026 — no conversion needed
result = g.group({
    "version": 431,
    "source_icd_version": 2026,
    "pdx": {"code": "I5020"},
})
# result["conversions"] == []
```

### No conversion when omitted

When `source_icd_version` is not set, codes are used as-is:

```python
result = g.group({
    "version": 431,
    # no source_icd_version — codes assumed to be FY2026
    "pdx": {"code": "I5020"},
})
# result["conversions"] == []
```

---

## One-to-many mappings

When CMS splits a code (e.g., `B88.0` becomes `B88.01` and `B88.09`), the backward mapping (old → new) picks the first target code alphabetically. Forward mapping (new → old) is always unambiguous.

```python
with msdrg.IcdConverter() as conv:
    # B88.0 split into B88.01 and B88.09 in FY2026
    conv.convert_dx("B880", source_year=2025, target_year=2026)
    # "B8801" (first target)

    # Each new code maps back to the old one
    conv.convert_dx("B8801", source_year=2026, target_year=2025)
    # "B880"

    conv.convert_dx("B8809", source_year=2026, target_year=2025)
    # "B880"
```

!!! tip
    For critical conversions where clinical specificity matters, review one-to-many mappings manually. The converter picks the first match, which may not always be the clinically appropriate choice.
