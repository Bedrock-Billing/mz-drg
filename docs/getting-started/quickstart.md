# Quick Start

## MS-DRG Grouper

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

Or use the convenience helper:

```python
claim = msdrg.create_claim(
    version=431, age=65, sex=0, discharge_status=1,
    pdx="I5020", sdx=["E1165"], procedures=["02703DZ"]
)
result = grouper.group(claim)
```

## MCE Editor

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
print(result["edits"])      # []
```

Or use the convenience helper:

```python
mce_claim = msdrg.create_mce_input(
    discharge_date=20250101, age=65, sex=0, discharge_status=1,
    pdx="I5020", sdx=["E1165"]
)
result = mce.edit(mce_claim)
```

## Unified claim

Both tools accept the same dictionary. Add `version` for the grouper and `discharge_date` for the MCE — each tool ignores the other's fields:

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

print(drg["final_drg"])       # 293
print(mce_result["edit_type"]) # "NONE"
```

## Context manager

Both classes support Python's `with` statement for automatic cleanup:

```python
with msdrg.MsdrgGrouper() as g:
    result = g.group(...)

# g is automatically closed — resources released
```

Or use `close()` explicitly:

```python
g = msdrg.MsdrgGrouper()
result = g.group(...)
g.close()
```

## Error handling

Both classes raise `RuntimeError` on failures:

```python
import msdrg

# Using a closed context
g = msdrg.MsdrgGrouper()
g.close()

try:
    g.group({"version": 431, "pdx": {"code": "I5020"}})
except RuntimeError as e:
    print(e)  # "MsdrgGrouper has been closed. Create a new instance."
```

!!! tip "Best practice"
    Create one `MsdrgGrouper` or `MceEditor` instance and reuse it across multiple calls. Initialization loads binary data via memory mapping — subsequent calls are fast.
