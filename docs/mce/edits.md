# Supported Edit Types

The MCE detects ~35 edit types from the CMS Java MCE 2.0. The tables below list the key edits by category.

## Diagnosis edits

| Edit | Type | Trigger |
|------|------|---------|
| `INVALID_CODE` | PREPAYMENT | Code not in CMS master for discharge date |
| `SEX_CONFLICT` | PREPAYMENT | Code restricted by patient sex |
| `AGE_CONFLICT` | PREPAYMENT | Code restricted by patient age |
| `E_CODE_AS_PDX` | PREPAYMENT | External cause code used as principal diagnosis |
| `MANIFESTATION_AS_PDX` | PREPAYMENT | Manifestation code used as PDX |
| `UNACCEPTABLE_PDX` | PREPAYMENT | Code unacceptable as principal diagnosis |
| `NONSPECIFIC_PDX` | POSTPAYMENT | Non-specific PDX (suppressed if patient died) |
| `DUPLICATE_OF_PDX` | PREPAYMENT | Secondary diagnosis is same as PDX |
| `REQUIRES_SDX` | PREPAYMENT | PDX requires an accompanying secondary diagnosis |
| `QUESTIONABLE_ADMISSION` | PREPAYMENT | Questionable admission diagnosis code |
| `WRONG_PROCEDURE_PERFORMED` | PREPAYMENT | Wrong procedure performed flag |
| `UNSPECIFIED` | PREPAYMENT | Unspecified diagnosis code |
| `MEDICARE_IS_SECONDARY_PAYER` | POSTPAYMENT | Medicare Secondary Payer flag |

## Procedure edits

| Edit | Type | Trigger |
|------|------|---------|
| `NON_COVERED` | PREPAYMENT | Procedure not covered by Medicare |
| `LIMITED_COVERAGE` | PREPAYMENT | Limited coverage procedure |
| `BILATERAL` | POSTPAYMENT | Bilateral procedure without bilateral PDX |
| `OPEN_BIOPSY` | POSTPAYMENT | Open biopsy without prior closed biopsy |
| `INCONSISTENT_WITH_LENGTH_OF_STAY` | PREPAYMENT | Procedure inconsistent with LOS |
| `NONSPECIFIC_OR` | POSTPAYMENT | Non-specific OR procedure |
| `QUESTIONABLE_OBSTETRIC_ADMISSION` | PREPAYMENT | C-section or vaginal delivery admission |

## Validation edits

| Edit | Type | Trigger |
|------|------|---------|
| `INVALID_AGE` | PREPAYMENT | Age out of valid range |
| `INVALID_SEX` | PREPAYMENT | Invalid sex value |
| `INVALID_DISCHARGE_STATUS` | PREPAYMENT | Invalid discharge status code |

## Example

```python
import msdrg

with msdrg.MceEditor() as mce:
    # E-code as principal diagnosis triggers an edit
    result = mce.edit({
        "discharge_date": 20250101,
        "age": 65, "sex": 0, "discharge_status": 1,
        "pdx": {"code": "V0001XA"},
        "sdx": [], "procedures": []
    })

print(result["edit_type"])         # "PREPAYMENT"
print(result["edits"][0]["name"])   # "E_CODE_AS_PDX"
print(result["edits"][0]["count"])  # 1
```

!!! note
    The full list of ~35 edit types is defined in the CMS MCE 2.0 specification. The edits listed above are the most commonly encountered. Additional edits exist for specialized clinical scenarios and are fully implemented in the engine.
