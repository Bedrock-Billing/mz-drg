# MCE Input Format

```python
{
    "discharge_date": 20250101,
    "icd_version": 10,
    "age": 65,
    "sex": 0,
    "discharge_status": 1,
    "pdx": {"code": "I5020"},
    "admit_dx": {"code": "R0602"},
    "sdx": [{"code": "E1165"}],
    "procedures": [{"code": "02703DZ"}]
}
```

## Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `discharge_date` | int | Yes | YYYYMMDD integer (e.g. `20250101`) |
| `icd_version` | int | No | `9` or `10` (default: `10`) |
| `age` | int | Yes | Patient age in years |
| `sex` | int | Yes | `0`=Male, `1`=Female, `2`=Unknown |
| `discharge_status` | int | Yes | Valid CMS discharge status code |
| `pdx` | dict | Yes | Principal diagnosis `{"code": "I5020"}` |
| `admit_dx` | dict | No | Admission diagnosis |
| `sdx` | list | No | Secondary diagnoses |
| `procedures` | list | No | Procedure codes |

## Diagnosis format

```python
{"code": "I5020", "poa": "Y"}  # poa is optional
{"code": "I5020"}               # poa defaults to unchecked
```

## Procedure format

```python
{"code": "02703DZ"}
```

!!! warning "Dict format required"
    Procedures must be passed as dicts (`{"code": "02703DZ"}`), not plain strings. This is consistent with the grouper input format.

## Unified claim

The MCE input is a superset of `ClaimInput`. A single dict with both `discharge_date` and `version` works with both tools — each ignores the other's fields:

```python
claim = {
    "version": 431,                # used by grouper, ignored by MCE
    "discharge_date": 20250101,    # used by MCE, ignored by grouper
    "age": 65, "sex": 0, "discharge_status": 1,
    "pdx": {"code": "I5020"},
    "sdx": [{"code": "E1165"}],
    "procedures": [{"code": "02703DZ"}]
}

with msdrg.MsdrgGrouper() as g, msdrg.MceEditor() as mce:
    drg = g.group(claim)
    mce_result = mce.edit(claim)
```
