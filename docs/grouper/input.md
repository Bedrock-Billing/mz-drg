# Grouper Input Format

The `group()` method accepts a dictionary with the following fields:

```python
{
    "version": 431,
    "age": 65,
    "sex": 0,
    "discharge_status": 1,
    "hospital_status": "NOT_EXEMPT",
    "source_icd_version": 2025,
    "pdx": {"code": "I5020", "poa": "Y"},
    "admit_dx": {"code": "R0602"},
    "sdx": [
        {"code": "E1165", "poa": "Y"},
        {"code": "I10", "poa": "N"}
    ],
    "procedures": [{"code": "02703DZ"}]
}
```

## Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | int | Yes | MS-DRG version (400-431). See [Versions](versions.md). |
| `age` | int | Yes | Patient age in years (0-124) |
| `sex` | int | Yes | `0`=Male, `1`=Female, `2`=Unknown |
| `discharge_status` | int | Yes | CMS discharge status code (see below) |
| `hospital_status` | str | No | `"NOT_EXEMPT"` (default), `"EXEMPT"`, or `"UNKNOWN"`. See [Hospital Status](hospital-status.md). |
| `tie_breaker` | str | No | `"CLINICAL_SIGNIFICANCE"` (default) or `"ALPHABETICAL"`. See [Tie Breaker](#tie-breaker). |
| `source_icd_version` | int | No | Source ICD-10 fiscal year (e.g. `2025`) for automatic code conversion. See [ICD Converter](../converter/overview.md). |
| `pdx` | dict | Yes | Principal diagnosis |
| `admit_dx` | dict | No | Admission diagnosis |
| `sdx` | list | No | Secondary diagnoses (defaults to `[]`) |
| `procedures` | list | No | Procedure codes (defaults to `[]`) |

## Diagnosis format

Each diagnosis is a dict with a `code` and optional `poa` (Present on Admission) indicator:

```python
{"code": "I5020", "poa": "Y"}  # poa values: "Y", "N", "U", "W"
{"code": "I5020"}               # poa defaults to unchecked
```

## Procedure format

Each procedure is a dict with a `code`:

```python
{"code": "02703DZ"}
```

## Discharge status codes

The grouper primarily uses these values for DRG assignment logic:

| Code | Description |
|------|-------------|
| `1` | Home / Self Care |
| `20` | Died |

!!! note
    Other valid CMS discharge status codes (2–99) are accepted but do not alter grouping behavior in most DRG logic paths. The grouper specifically checks for status `20` (died) which affects certain DRG assignments.

## Tie breaker

The `tie_breaker` field controls how secondary diagnoses are prioritized during the marking phase. When multiple SDX codes could match the same DRG formula attribute, this determines which one "wins":

| Value | Behavior |
|-------|----------|
| `"CLINICAL_SIGNIFICANCE"` | Sort SDX codes: MCC first, then CC, then by ICD code string. **Default.** Matches CMS Java grouper behavior. |
| `"ALPHABETICAL"` | Sort SDX codes by ICD code string only. |

The CMS Java grouper defaults to `CLINICAL_SIGNIFICANCE`, which means the most severe diagnosis gets first pick of attribute matches. For example, if both an MCC and a CC diagnosis could contribute to the same formula attribute, the MCC wins and gets marked.

Procedure codes are also sorted by code value when `CLINICAL_SIGNIFICANCE` is active.
