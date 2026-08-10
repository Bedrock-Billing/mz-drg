# Supported DRG Versions

| Version | CMS Fiscal Year |
|---------|----------------|
| 400 | FY 2023 (Oct 2022 – Apr 2023) |
| 401 | FY 2023 (Apr 2023 – Sep 2023) |
| 410 | FY 2024 (Oct 2023 – Apr 2024) |
| 411 | FY 2024 (Apr 2024 – Sep 2024) |
| 420 | FY 2025 (Oct 2024 – Apr 2025) |
| 421 | FY 2025 (Apr 2025 – Sep 2025) |
| 430 | FY 2026 (Oct 2025 – Apr 2026) |
| 431 | FY 2026 (Apr 2026 – Sep 2026) |
| 440 | FY 2027 (Oct 2026 – Mar 2027) |

Pass the version number in the claim's `version` field.

!!! note
    Most version differences come from the binary data files (diagnosis definitions, DRG formulas, etc.). CMS v44 also introduced version-specific HAC processing behavior, which is gated in the engine by the requested grouper version.
