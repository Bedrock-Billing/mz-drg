"""
msdrg - MS-DRG Grouper Python bindings

A high-performance MS-DRG (Medicare Severity Diagnosis Related Groups)
grouper implemented in Zig with Python bindings via ctypes.

Usage::

    import msdrg

    with msdrg.MsdrgGrouper() as g:
        result = g.group(msdrg.create_claim(
            version=431, age=65, sex=0, discharge_status=1,
            pdx="I5020", sdx=["E1165"],
        ))
        print(result["final_drg"])
"""

from msdrg.grouper import (
    ClaimInput,
    DiagnosisInput,
    DiagnosisOutput,
    GroupResult,
    MsdrgGrouper,
    ProcedureInput,
    ProcedureOutput,
    create_claim,
)

__version__ = "0.1.1"

__all__ = [
    # Main class
    "MsdrgGrouper",
    "create_claim",
    # Input types
    "ClaimInput",
    "DiagnosisInput",
    "ProcedureInput",
    # Output types
    "GroupResult",
    "DiagnosisOutput",
    "ProcedureOutput",
]
