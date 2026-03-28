# Grouper Output Format

`group()` returns a dictionary with the grouping result:

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

## Top-level fields

| Field | Type | Description |
|-------|------|-------------|
| `initial_drg` | int \| null | DRG before HAC processing |
| `final_drg` | int \| null | DRG after HAC processing |
| `initial_mdc` | int \| null | MDC before HAC processing |
| `final_mdc` | int \| null | MDC after HAC processing |
| `initial_drg_description` | str \| null | Description of initial DRG |
| `final_drg_description` | str \| null | Description of final DRG |
| `initial_mdc_description` | str \| null | Description of initial MDC |
| `final_mdc_description` | str \| null | Description of final MDC |
| `return_code` | str | Processing status (see below) |
| `pdx_output` | dict \| null | Detailed output for principal diagnosis |
| `sdx_output` | list | Detailed output for each secondary diagnosis |
| `proc_output` | list | Detailed output for each procedure |

## Diagnosis output

Each entry in `pdx_output` and `sdx_output` contains:

| Field | Type | Description |
|-------|------|-------------|
| `code` | str | The diagnosis code |
| `mdc` | int \| null | MDC assignment for this code |
| `severity` | str | `"MCC"`, `"CC"`, or `"NON_CC"` |
| `drg_impact` | str | `"INITIAL"`, `"FINAL"`, `"BOTH"`, or `"NONE"` |
| `poa_error` | str | `"POA_NOT_CHECKED"`, `"POA_MISSING"`, etc. |
| `flags` | list[str] | Processing flags (e.g. `"VALID"`, `"MARKED_FOR_INITIAL"`) |

## Procedure output

Each entry in `proc_output` contains:

| Field | Type | Description |
|-------|------|-------------|
| `code` | str | The procedure code |
| `is_or` | bool | `true` if this is an OR (operating room) procedure |
| `drg_impact` | str | `"INITIAL"`, `"FINAL"`, `"BOTH"`, or `"NONE"` |
| `flags` | list[str] | Processing flags |

## Return codes

| Code | Meaning |
|------|---------| 
| `OK` | Normal processing |
| `INVALID_PDX` | PDX not valid for version |
| `UNGROUPABLE` | Claim cannot be grouped (e.g. HAC issues) |
| `DX_CANNOT_BE_PDX` | E-code used as PDX |
| `HAC_MISSING_ONE_POA` | HAC code missing POA |

!!! tip
    When `initial_drg` and `final_drg` differ, HAC processing changed the DRG assignment. Compare them to understand the HAC impact on the claim.
