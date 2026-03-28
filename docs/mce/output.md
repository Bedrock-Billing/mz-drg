# MCE Output Format

```python
{
    "version": 20260930,
    "edit_type": "PREPAYMENT",
    "edits": [
        {
            "name": "E_CODE_AS_PDX",
            "count": 1,
            "code_type": "DIAGNOSIS",
            "edit_type": "PREPAYMENT"
        }
    ]
}
```

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | int | Data file version (termination date) |
| `edit_type` | str | Overall type: NONE, PREPAYMENT, POSTPAYMENT, or BOTH |
| `edits` | list | List of triggered edits (empty if NONE) |

## Edit type determination

- **NONE** — no edits triggered
- **PREPAYMENT** — only prepayment edits triggered
- **POSTPAYMENT** — only postpayment edits triggered
- **BOTH** — both types triggered
