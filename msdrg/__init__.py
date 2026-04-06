"""
msdrg - MS-DRG Grouper, Medicare Code Editor, and ICD Converter Python bindings

High-performance MS-DRG classification, MCE validation, and ICD-10 code
conversion engines implemented in Zig with Python bindings via ctypes.

Usage::

    import msdrg

    # MS-DRG grouping
    with msdrg.MsdrgGrouper() as g:
        drg_result = g.group(msdrg.create_claim(
            version=431, age=65, sex=0, discharge_status=1,
            pdx="I5020", sdx=["E1165"],
        ))

    # MS-DRG grouping with ICD version conversion (e.g. FY2025 codes into V43)
    with msdrg.MsdrgGrouper() as g:
        drg_result = g.group(msdrg.create_claim(
            version=431, source_icd_version=2025,
            age=65, sex=0, discharge_status=1,
            pdx="I5020", sdx=["E1165"],
        ))

    # Medicare Code Editing
    with msdrg.MceEditor() as mce:
        mce_result = mce.edit(msdrg.create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1,
            pdx="V0001XA",  # E-code as PDX triggers edit
        ))

    # ICD-10 code conversion (standalone)
    with msdrg.IcdConverter() as conv:
        new_code = conv.convert_dx("A000", source_year=2025, target_year=2026)

    # Unified claim — same dict for both:
    claim = {"version": 431, "discharge_date": 20250101, ...}
    drg = g.group(claim)
    mce = mce.edit(claim)
"""

from msdrg.grouper import (
    ClaimInput,
    CodeConversion,
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

from msdrg.converter import (
    ConversionResult,
    IcdConverter,
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
    # ICD Converter
    "IcdConverter",
    "ConversionResult",
    "CodeConversion",
]
