"""
msdrg - MS-DRG Grouper and Medicare Code Editor Python bindings

High-performance MS-DRG classification and MCE validation engines
implemented in Zig with Python bindings via ctypes.

Usage::

    import msdrg

    # MS-DRG grouping
    with msdrg.MsdrgGrouper() as g:
        drg_result = g.group(msdrg.create_claim(
            version=431, age=65, sex=0, discharge_status=1,
            pdx="I5020", sdx=["E1165"],
        ))

    # Medicare Code Editing
    with msdrg.MceEditor() as mce:
        mce_result = mce.edit(msdrg.create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1,
            pdx="V0001XA",  # E-code as PDX triggers edit
        ))

    # Unified claim — same dict for both:
    claim = {"version": 431, "discharge_date": 20250101, ...}
    drg = g.group(claim)
    mce = mce.edit(claim)
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

from msdrg.mce import (
    MceDiagnosisInput,
    MceEditDetail,
    MceEditor,
    MceInput,
    MceProcedureInput,
    MceResult,
    create_mce_input,
)

from importlib.metadata import version as _get_version, PackageNotFoundError

try:
    __version__: str = _get_version("msdrg")
except PackageNotFoundError:
    __version__ = "0.0.0"

__all__ = [
    # MS-DRG
    "MsdrgGrouper",
    "create_claim",
    "ClaimInput",
    "DiagnosisInput",
    "ProcedureInput",
    "GroupResult",
    "DiagnosisOutput",
    "ProcedureOutput",
    # MCE
    "MceEditor",
    "create_mce_input",
    "MceInput",
    "MceDiagnosisInput",
    "MceProcedureInput",
    "MceResult",
    "MceEditDetail",
]
