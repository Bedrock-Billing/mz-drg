# Hospital Status

The `hospital_status` field controls Hospital-Acquired Condition (HAC) processing.

| Value | Behavior |
|-------|----------|
| `NOT_EXEMPT` | Standard HAC processing. Default. |
| `EXEMPT` | Hospital exempt from POA reporting. |
| `UNKNOWN` | Stricter POA validation. |

This is a per-request setting — each call to `group()` can use a different value.

!!! example
    ```python
    # Standard processing
    g.group({..., "hospital_status": "NOT_EXEMPT"})

    # Exempt hospital
    g.group({..., "hospital_status": "EXEMPT"})
    ```
