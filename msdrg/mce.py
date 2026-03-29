"""
MCE (Medicare Code Editor) - Python bindings for the Zig-based MCE.

The MCE validates ICD diagnosis and procedure codes against CMS edit rules.
It can be used alongside or independently of the MS-DRG grouper.
"""

import ctypes
import json
from typing import Literal, TypedDict

from msdrg._native import find_data_dir, get_lib


# ---------------------------------------------------------------------------
# Input types
# ---------------------------------------------------------------------------


class MceDiagnosisInput(TypedDict, total=False):
    """A diagnosis code for MCE editing."""

    code: str
    poa: str  # "Y", "N", "U", "W"


class MceProcedureInput(TypedDict):
    """A procedure code for MCE editing."""

    code: str


class MceInput(TypedDict, total=False):
    """
    Input claim for the Medicare Code Editor.

    This schema is a superset of ``ClaimInput`` — a single dict can be
    passed to both ``MceEditor.edit()`` and ``MsdrgGrouper.group()``.
    """

    discharge_date: int  # YYYYMMDD integer (required for MCE)
    icd_version: Literal[9, 10]
    age: int
    sex: Literal[0, 1, 2]
    discharge_status: int
    pdx: MceDiagnosisInput
    admit_dx: MceDiagnosisInput
    sdx: list[MceDiagnosisInput]
    procedures: list[MceProcedureInput]
    # The following fields are MS-DRG specific but harmless in MCE
    version: int
    hospital_status: str


# ---------------------------------------------------------------------------
# Output types
# ---------------------------------------------------------------------------


class MceEditDetail(TypedDict):
    """A single edit that was triggered."""

    name: str
    count: int
    code_type: str
    edit_type: str


class MceResult(TypedDict):
    """
    Result from ``MceEditor.edit()``.
    """

    version: int
    edit_type: str
    edits: list[MceEditDetail]


# ---------------------------------------------------------------------------
# MceEditor class
# ---------------------------------------------------------------------------


class MceEditor:
    """
    Medicare Code Editor client.

    Validates ICD codes against CMS edit rules. Can be used alongside
    ``MsdrgGrouper`` with the same claim dict.

    Args:
        lib_path: Optional path to the shared library.
        data_dir: Optional path to the MCE data directory.

    Example:
        >>> claim = {
        ...     "discharge_date": 20250101,
        ...     "age": 65, "sex": 0, "discharge_status": 1,
        ...     "pdx": {"code": "I5020"},
        ...     "sdx": [{"code": "E1165"}],
        ...     "procedures": [],
        ... }
        >>> with MceEditor() as mce:
        ...     result = mce.edit(claim)
        ...     print(result["edit_type"])  # "NONE" or "PREPAYMENT", etc.

        # Unified claim — same dict works for both:
        >>> claim["version"] = 431
        >>> with MsdrgGrouper() as g, MceEditor() as mce:
        ...     drg_result = g.group(claim)
        ...     mce_result = mce.edit(claim)
    """

    lib: ctypes.CDLL
    ctx: int | None

    def __init__(
        self,
        lib_path: str | None = None,
        data_dir: str | None = None,
    ) -> None:
        if data_dir is None:
            data_dir = find_data_dir()

        self.lib = get_lib(lib_path)

        # Define MCE function signatures
        self.lib.mce_context_init.argtypes = [ctypes.c_char_p]
        self.lib.mce_context_init.restype = ctypes.c_void_p

        self.lib.mce_context_free.argtypes = [ctypes.c_void_p]
        self.lib.mce_context_free.restype = None

        self.lib.mce_edit_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.mce_edit_json.restype = ctypes.c_void_p

        # msdrg_string_free is shared
        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        # Initialize context
        self.ctx = self.lib.mce_context_init(data_dir.encode("utf-8"))
        if not self.ctx:
            raise RuntimeError(
                "Failed to initialize MCE context. Check data directory."
            )

    def __del__(self) -> None:
        if hasattr(self, "ctx") and self.ctx:
            import warnings

            warnings.warn(
                "MceEditor was not closed. Use 'with' or call close() explicitly.",
                ResourceWarning,
                stacklevel=2,
            )
            self.close()

    def close(self) -> None:
        """Explicitly free the MCE context and release resources."""
        if hasattr(self, "ctx") and self.ctx:
            self.lib.mce_context_free(self.ctx)
            self.ctx = None

    def __repr__(self) -> str:
        status = "open" if self.ctx else "closed"
        return f"MceEditor({status})"

    def __enter__(self) -> "MceEditor":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def edit(self, claim: MceInput) -> MceResult:
        """
        Run the Medicare Code Editor on a claim.

        Args:
            claim: Claim dictionary. Must include ``discharge_date`` (YYYYMMDD).
                   Can include MS-DRG fields (``version``, ``hospital_status``)
                   which are ignored by the MCE.

        Returns:
            An ``MceResult`` with ``edit_type`` and per-edit counts.

        Raises:
            RuntimeError: If the editor returns null (unexpected).
        """
        if not self.ctx:
            raise RuntimeError("MceEditor has been closed. Create a new instance.")

        json_bytes = json.dumps(claim).encode("utf-8")

        result_ptr = self.lib.mce_edit_json(self.ctx, json_bytes)

        if not result_ptr:
            raise RuntimeError("MCE edit failed (returned null)")

        try:
            result_json = ctypes.cast(result_ptr, ctypes.c_char_p).value.decode("utf-8")
            return json.loads(result_json)
        finally:
            self.lib.msdrg_string_free(result_ptr)


def create_mce_input(
    discharge_date: int,
    age: int,
    sex: Literal[0, 1, 2],
    discharge_status: int,
    pdx: str,
    sdx: list[str] | None = None,
    procedures: list[str] | None = None,
) -> MceInput:
    """
    Build an MCE input dict from simple arguments.

    Args:
        discharge_date: YYYYMMDD integer (e.g. 20250101)
        age: Patient age in years
        sex: 0=Male, 1=Female, 2=Unknown
        discharge_status: 1=Home/Self Care, 20=Died
        pdx: Principal diagnosis code
        sdx: Secondary diagnosis codes
        procedures: Procedure codes

    Returns:
        An ``MceInput`` dict ready for ``MceEditor.edit()``
    """
    return {
        "discharge_date": discharge_date,
        "age": age,
        "sex": sex,
        "discharge_status": discharge_status,
        "pdx": {"code": pdx},
        "sdx": [{"code": c} for c in (sdx or [])],
        "procedures": [{"code": c} for c in (procedures or [])],
    }
