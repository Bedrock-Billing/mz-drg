import jpype
import jpype.imports
import os
import sys
import glob
import json
import argparse
from datetime import datetime

import msdrg

# Paths
PROJECT_ROOT = os.getcwd()
JARS_DIR = os.path.join(PROJECT_ROOT, "jars")
DATA_DIR = os.path.join(PROJECT_ROOT, "data", "msdrg.mdb")

# Zig Library Path — cross-platform
if sys.platform == "darwin":
    LIB_NAME = "libmsdrg.dylib"
elif sys.platform == "win32":
    LIB_NAME = "msdrg.dll"
else:
    LIB_NAME = "libmsdrg.so"
LIB_PATH = os.path.join(PROJECT_ROOT, "zig_src", "zig-out", "lib", LIB_NAME)


class DrgClient:
    def __init__(self):
        self.load_classes()
        self.load_enums()
        self.load_drg_groupers()

    def create_drg_options(self, poa_exempt: str) -> jpype.JObject:
        try:
            runtime_options = jpype.JClass("gov.agency.msdrg.model.v2.RuntimeOptions")()
            drg_options = jpype.JClass("gov.agency.msdrg.model.v2.MsdrgRuntimeOption")()
            msdrg_option_flags = jpype.JClass("gov.agency.msdrg.model.v2.MsdrgOption")
        except Exception as e:
            raise RuntimeError(f"Failed to initialize RuntimeOptions: {e}")
        runtime_options.setComputeAffectDrg(self.affect_drg_option.COMPUTE)
        runtime_options.setMarkingLogicTieBreaker(
            self.logic_tiebreaker.CLINICAL_SIGNIFICANCE
        )
        if poa_exempt == "EXEMPT":
            runtime_options.setPoaReportingExempt(self.hospital_status.EXEMPT)
        elif poa_exempt == "NON_EXEMPT":
            runtime_options.setPoaReportingExempt(self.hospital_status.NON_EXEMPT)
        else:
            runtime_options.setPoaReportingExempt(self.hospital_status.UNKNOWN)
        drg_options.put(msdrg_option_flags.RUNTIME_OPTION_FLAGS, runtime_options)
        return drg_options

    def determine_end_version(self) -> str:
        """
        Max DRG version will be based on the current date
         Step 1.) Version = Year - 1983
         Step 2.) if month is October or later, then add 1 to version, and convert to string that ends with "0"
         Step 3.) if before October, but after March, then convert to string and end with "1"
         Step 4.) if before April, then subtract 1 from version, and convert to string that ends with "0"
         example date: 2025-07-30
         2025 - 1983 = 42
         Month is after March but before October, so we end with "1"
         Version = "421"
        """
        current_year = datetime.now().year
        version = current_year - 1983

        if datetime.now().month >= 10:
            version += 1
            return f"{version}0"
        elif datetime.now().month > 3:
            return f"{version}1"
        else:
            version -= 1
            return f"{version}0"

    def determine_drg_version(self, date: datetime) -> str:
        """
        Determine the DRG version based on the date provided.
        """
        if not isinstance(date, datetime):
            raise ValueError("Date must be a datetime object")

        year = date.year - 1983
        if date.month >= 10:
            return f"{year + 1}0"
        elif date.month > 3:
            return f"{year}1"
        else:
            return f"{year - 1}0"

    def load_classes(self):
        self.drg_claim_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.transfer.MsdrgClaim"
        )
        self.drg_input_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.transfer.input.MsdrgInput"
        )
        self.drg_dx_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.transfer.input.MsdrgInputDxCode"
        )
        self.drg_px_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.transfer.input.MsdrgInputPrCode"
        )
        self.array_list_class = jpype.JClass("java.util.ArrayList")
        self.runtime_options_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.RuntimeOptions"
        )
        self.drg_options_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.MsdrgRuntimeOption"
        )
        self.msdrg_option_flags_class = jpype.JClass(
            "gov.agency.msdrg.model.v2.MsdrgOption"
        )

    def increment_version(self, version: str) -> str:
        """
        If version ends with "1", increment the version by 9.
        If version ends with "0", increment the version by 1.
        """
        if version.endswith("1"):
            return str(int(version) + 9)
        elif version.endswith("0"):
            return str(int(version) + 1)
        return version

    def load_enums(self) -> None:
        # Get enumeration values needed for DRG Runtime options
        try:
            self.logic_tiebreaker = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MarkingLogicTieBreaker"
            )
            self.affect_drg_option = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgAffectDrgOptionFlag"
            )
            self.drg_status = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgDischargeStatus"
            )
            self.hospital_status = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgHospitalStatusOptionFlag"
            )
            self.sex = jpype.JClass("gov.agency.msdrg.model.v2.enumeration.MsdrgSex")
            self.poa_values = jpype.JClass("com.mmm.his.cer.foundation.model.GfcPoa")
            self.msdrg_grouping_impact = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgGroupingImpact"
            )
            self.poa_error_code = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgPoaErrorCode"
            )
            self.msdrg_severity_flag = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgCodeSeverityFlag"
            )
            self.msdrg_hac_status = jpype.JClass(
                "gov.agency.msdrg.model.v2.enumeration.MsdrgHacStatus"
            )

        except Exception as e:
            raise RuntimeError(f"Failed to initialize enumerations: {e}")

    def load_drg_groupers(self) -> None:
        end_version = self.determine_end_version()
        curr_version = "400"
        exempt_drg_options = self.create_drg_options(poa_exempt="EXEMPT")
        non_exempt_drg_options = self.create_drg_options(poa_exempt="NON_EXEMPT")
        # For UNKNOWN claims, use NON_EXEMPT as Java's reference behavior
        unknown_drg_options = self.create_drg_options(poa_exempt="UNKNOWN")
        self.drg_versions = {}
        while True:
            try:
                drg_component = jpype.JClass(
                    f"gov.agency.msdrg.v{curr_version}.MsdrgComponent"
                )
                self.drg_versions[curr_version] = {}
                self.drg_versions[curr_version]["exempt"] = drg_component(
                    exempt_drg_options
                )
                self.drg_versions[curr_version]["non_exempt"] = drg_component(
                    non_exempt_drg_options
                )
                self.drg_versions[curr_version]["unknown"] = drg_component(
                    unknown_drg_options
                )
                print(f"Loaded DRG version: {curr_version}")
            except Exception as e:
                print(f"Failed to load DRG version {curr_version}: {e}")
                if curr_version > end_version:
                    break
                curr_version = self.increment_version(curr_version)
                continue
            curr_version = self.increment_version(curr_version)

    def create_drg_input(self, claim) -> jpype.JObject | None:
        """
        Creates the DRG input object from the claim and mappings.
        """
        input = self.drg_input_class.builder()
        input.withAgeInYears(claim["age"])
        if claim.get("sex", None) is not None:
            if claim["sex"] == 0:
                input.withSex(self.sex.MALE)
            elif claim["sex"] == 1:
                input.withSex(self.sex.FEMALE)
            else:
                input.withSex(self.sex.UNKNOWN)

        if claim.get("discharge_status", None) is not None:
            try:
                discharge_status = int(claim["discharge_status"])
                input.withDischargeStatus(
                    self.drg_status.getEnumFromInt(discharge_status)
                )
            except ValueError:
                raise ValueError(
                    f"Invalid discharge status: {claim['discharge_status']}"
                )
        else:
            input.withDischargeStatus(self.drg_status.HOME_SELFCARE_ROUTINE)

        if claim.get("adx", None) is not None:
            input.withAdmissionDiagnosisCode(
                self.drg_dx_class(
                    claim["adx"]["code"].replace(".", ""), self.poa_values.Y
                )
            )

        if claim["pdx"]:
            pdx_poa_str = claim["pdx"].get("poa", "Y")
            pdx_poa = {
                "Y": self.poa_values.Y,
                "N": self.poa_values.N,
                "U": self.poa_values.U,
                "W": self.poa_values.W,
            }.get(pdx_poa_str, self.poa_values.Y)
            input.withPrincipalDiagnosisCode(
                self.drg_dx_class(
                    claim["pdx"]["code"].replace(".", ""),
                    pdx_poa,
                )
            )
        else:
            raise ValueError("Principal diagnosis must be provided")

        java_dxs = self.array_list_class()
        for dx in claim["sdx"]:
            if dx:
                if dx.get("poa", None) is not None:
                    if dx["poa"] == "Y":
                        poa_value = self.poa_values.Y
                    elif dx["poa"] == "N":
                        poa_value = self.poa_values.N
                    elif dx["poa"] == "U":
                        poa_value = self.poa_values.U
                    elif dx["poa"] == "W":
                        poa_value = self.poa_values.W
                    else:
                        poa_value = self.poa_values.U
                else:
                    poa_value = self.poa_values.Y
                java_dxs.add(
                    self.drg_dx_class(
                        dx["code"].replace(".", ""),
                        poa_value,
                    )
                )
        if len(java_dxs) > 0:
            input.withSecondaryDiagnosisCodes(java_dxs)

        java_pxs = self.array_list_class()
        for px in claim["procedures"]:
            java_pxs.add(self.drg_px_class(px["code"].replace(".", "")))
        if len(java_pxs) > 0:
            input.withProcedureCodes(java_pxs)
        return input.build()

    def process(self, claim, version: str, with_flags: bool = False):
        i = self.create_drg_input(claim)

        # Select grouper based on claim's hospital_status
        hs = claim.get("hospital_status", "NOT_EXEMPT")
        if hs == "EXEMPT":
            grouper_key = "exempt"
        elif hs == "UNKNOWN":
            grouper_key = "unknown"
        else:
            grouper_key = "non_exempt"

        drg_component = self.drg_versions[version][grouper_key]
        drg_claim = self.drg_claim_class(i)
        drg_component.process(drg_claim)
        output = drg_claim.getOutput().get()

        result = {
            "initial_drg": int(str(output.getInitialDrg().getValue())),
            "initial_mdc": int(str(output.getInitialMdc().getValue())),
            "final_drg": int(str(output.getFinalDrg().getValue())),
            "final_mdc": int(str(output.getFinalMdc().getValue())),
            "return_code": str(output.getFinalGrc().name()),
        }

        if with_flags:
            result["flags"] = extract_java_flags(output)

        return result

    def process_with_debug(self, claim, version: str, with_flags: bool = False):
        """Like ``process()`` but uses the lower-level GrouperChain +
        ProcessingContext API with an attached TraceConsumer so the Java
        grouper's trace messages (attribute assignments, formula evaluations,
        marking decisions) are printed to stdout. Slower than ``process()``
        because it builds the chain and context per claim instead of reusing
        the pre-built MsdrgComponent instances.

        Use this when debugging DRG differences between Zig and Java — the
        trace output shows exactly which attributes the Java grouper assigns
        to each diagnosis/procedure code, which can then be compared against
        the Zig grouper's behavior.
        """
        from java.util.function import Consumer

        @jpype.JImplements(Consumer)
        class TraceConsumer:
            @jpype.JOverride
            def accept(self, message):
                # Java trace messages typically start with "\n" and contain
                # tabs for indentation. Strip the leading newline so the
                # JAVA TRACE prefix sits on the same line as the content,
                # and indent multi-line continuations so the output is
                # readable. `message` arrives as a java.lang.String, so
                # convert to Python str first.
                if message is None:
                    return
                msg = str(message).lstrip("\n")
                if not msg:
                    return
                lines = msg.split("\n")
                print(f"JAVA TRACE: {lines[0]}")
                for line in lines[1:]:
                    if line:
                        print(f"           {line}")

        # Load version-specific classes via the same JPackage the MsdrgComponent
        # path uses, so we pick up the right GrouperChain/ProcessingContext/
        # ProcessingData/TraceUtility for the requested grouper version.
        pkg = jpype.JPackage(f"gov.agency.msdrg.v{version}")
        gov_pkg = jpype.JPackage("gov")
        com_pkg = jpype.JPackage("com")
        v_pkg = jpype.JPackage(f"gov.agency.msdrg.v{version}")

        GrouperChain = v_pkg.chain.GrouperChain
        ProcessingContext = v_pkg.chain.ProcessingContext
        ProcessingData = v_pkg.ProcessingData
        MsdrgDiagnosisCode = v_pkg.model.MsdrgDiagnosisCode
        MsdrgProcedureCode = v_pkg.model.MsdrgProcedureCode
        TraceUtility = v_pkg.TraceUtility
        MsdrgInputDxCode = (
            gov_pkg.agency.msdrg.model.v2.transfer.input.MsdrgInputDxCode
        )
        MsdrgInputPrCode = (
            gov_pkg.agency.msdrg.model.v2.transfer.input.MsdrgInputPrCode
        )
        MsdrgSex = gov_pkg.agency.msdrg.model.v2.enumeration.MsdrgSex
        MsdrgDischargeStatus = (
            gov_pkg.agency.msdrg.model.v2.enumeration.MsdrgDischargeStatus
        )
        MsdrgRuntimeOption = (
            gov_pkg.agency.msdrg.model.v2.MsdrgRuntimeOption
        )
        MsdrgOption = gov_pkg.agency.msdrg.model.v2.MsdrgOption
        RuntimeOptions = gov_pkg.agency.msdrg.model.v2.RuntimeOptions
        MarkingLogicTieBreaker = (
            gov_pkg.agency.msdrg.model.v2.enumeration.MarkingLogicTieBreaker
        )
        MsdrgAffectDrgOptionFlag = (
            gov_pkg.agency.msdrg.model.v2.enumeration.MsdrgAffectDrgOptionFlag
        )
        MsdrgHospitalStatusOptionFlag = (
            gov_pkg.agency.msdrg.model.v2.enumeration.MsdrgHospitalStatusOptionFlag
        )
        GfcPoa = com_pkg.mmm.his.cer.foundation.model.GfcPoa

        # Data access
        DataBlob = gov_pkg.agency.msdrg.access.DataBlob
        data_access = DataBlob.getInstance()

        # Build the chain for this version
        chain = GrouperChain.createChain(data_access, int(version))

        # Build input
        pdx_code = claim["pdx"]["code"]
        pdx_poa_str = claim["pdx"].get("poa", "Y")
        pdx_poa_map = {
            "Y": GfcPoa.Y, "N": GfcPoa.N, "U": GfcPoa.U, "W": GfcPoa.W,
        }
        pdx_poa = pdx_poa_map.get(pdx_poa_str, GfcPoa.Y)
        pdx = MsdrgDiagnosisCode(MsdrgInputDxCode(pdx_code, pdx_poa))

        sdx_poa_map = {
            "Y": GfcPoa.Y, "N": GfcPoa.N, "U": GfcPoa.U, "W": GfcPoa.W,
        }
        from java.util import ArrayList
        sdx_list = ArrayList()
        for sdx_c in claim.get("sdx", []):
            if not sdx_c:
                continue
            poa_val = sdx_poa_map.get(sdx_c.get("poa", "Y"), GfcPoa.Y)
            sdx_list.add(
                MsdrgDiagnosisCode(MsdrgInputDxCode(sdx_c["code"], poa_val))
            )

        proc_list = ArrayList()
        for proc_c in claim.get("procedures", []):
            try:
                proc_list.add(
                    MsdrgProcedureCode(MsdrgInputPrCode(proc_c["code"]))
                )
            except TypeError:
                proc_list.add(
                    MsdrgProcedureCode(
                        MsdrgInputPrCode(proc_c["code"], None)
                    )
                )

        sex_map = {0: MsdrgSex.MALE, 1: MsdrgSex.FEMALE}
        sex = sex_map.get(claim.get("sex"), MsdrgSex.UNKNOWN)

        dstat_map = {
            1: MsdrgDischargeStatus.HOME_SELFCARE_ROUTINE,
            20: MsdrgDischargeStatus.DIED,
        }
        dstat = dstat_map.get(
            claim.get("discharge_status"),
            MsdrgDischargeStatus.HOME_SELFCARE_ROUTINE,
        )

        # Build ProcessingData
        p_data_builder = ProcessingData.builder()
        p_data_builder.withPdx(pdx)
        p_data_builder.withSdxCodes(sdx_list)
        p_data_builder.withProcedures(proc_list)
        p_data_builder.withSex(sex)
        p_data_builder.withDischargeStatus(dstat)
        p_data = p_data_builder.build()

        # Build Context with trace + runtime options
        context_builder = ProcessingContext.builder()
        context_builder.withProcessingData(p_data)

        trace_utility = TraceUtility(TraceConsumer())
        context_builder.withTrace(trace_utility)

        # Runtime options (matches what create_drg_options does)
        runtime_options = RuntimeOptions()
        runtime_options.setComputeAffectDrg(
            MsdrgAffectDrgOptionFlag.COMPUTE
        )
        runtime_options.setMarkingLogicTieBreaker(
            MarkingLogicTieBreaker.CLINICAL_SIGNIFICANCE
        )
        hs_str = claim.get("hospital_status", "NOT_EXEMPT")
        if hs_str == "EXEMPT":
            runtime_options.setPoaReportingExempt(
                MsdrgHospitalStatusOptionFlag.EXEMPT
            )
        elif hs_str == "UNKNOWN":
            runtime_options.setPoaReportingExempt(
                MsdrgHospitalStatusOptionFlag.UNKNOWN
            )
        else:
            runtime_options.setPoaReportingExempt(
                MsdrgHospitalStatusOptionFlag.NON_EXEMPT
            )

        drg_options = MsdrgRuntimeOption()
        drg_options.put(MsdrgOption.RUNTIME_OPTION_FLAGS, runtime_options)

        context_builder.withRuntime(runtime_options)
        context = context_builder.build()

        # Execute
        result = chain.execute(context)

        # Extract result
        final_context = result.getContext()
        final_data = final_context.getProcessingData()
        final_res = final_data.getFinalResult()

        result_dict = {
            "initial_drg": int(str(final_res.getDrg())),
            "initial_mdc": int(str(final_res.getMdc())),
            "final_drg": int(str(final_res.getDrg())),
            "final_mdc": int(str(final_res.getMdc())),
            "return_code": str(final_res.getReturnCode()),
        }

        # For the debug path we only have the ProcessingContext result, not
        # the rich MsdrgOutput with pdx/sdx/proc output. Flag extraction
        # requires the MsdrgComponent path. If the caller asked for flags,
        # fall back to the fast path for that part.
        if with_flags:
            result_dict["flags"] = self.process(claim, version, with_flags=True)[
                "flags"
            ]

        return result_dict


# ---------------------------------------------------------------------------
# Flag-level comparison
# ---------------------------------------------------------------------------
#
# The DRG/MDC/return_code comparison in compare() only validates the final
# classification. The v44 CMS grouper changes live almost entirely in flag
# output (HAC statuses, procedure HAC usage, hacs_flags numbers), so DRG-only
# comparison would miss them. The helpers below extract the full structured
# output from both engines and compare field-by-field.
#
# Java → Zig enum name mapping for severity fields. The Zig per-dx severity
# is a 3-value enum (NONE/CC/MCC) and the Zig grouper_flags severity is the
# same 3-value enum. Java splits these into richer enums (MsdrgCodeSeverityFlag
# for per-dx with EXCLUDED variants, MsdrgSeverity for grouper_flags with
# NON_CC and NONE). Collapse the Java variants to the Zig names so the
# comparison is a direct string match.
_NORMALIZE_DX_SEVERITY = {
    "NEITHER": "NONE",
    "MCC": "MCC",
    "CC": "CC",
    "MCC_EXCLUDED_BY_DRG_LOGIC": "MCC",
    "MCC_EXCLUDED": "MCC",
    "CC_EXCLUDED_BY_DRG_LOGIC": "CC",
    "CC_EXCLUDED": "CC",
}

_NORMALIZE_GF_SEVERITY = {
    "MCC": "MCC",
    "CC": "CC",
    "NON_CC": "NONE",
    "NONE": "NONE",
}


# Canonical (normalized) shape — what compare_flags() operates on:
#
#   {
#     "pdx":   {"code", "severity", "drg_impact", "poa_error",
#               "hacs": sorted([{...}, ...])} | None,
#     "sdx":   [same shape as pdx],
#     "procs": [{"code", "is_or", "drg_impact", "hac_usage": sorted([...])}],
#     "grouper_flags": {"admit_dx_grouper_flag", "initial_drg_secondary_dx_cc_mcc",
#                       "final_drg_secondary_dx_cc_mcc",
#                       "num_hac_categories_satisfied", "hac_status_value"},
#   }
#
# Notes:
#   * Zig's per-dx `mdc` is not exposed on Java's MsdrgOutputDxCode, so it is
#     dropped from the canonical shape.
#   * Per-code CodeFlag (the `flags` list — VALID/EXCLUDED/MARKED_FOR_FINAL…)
#     is not part of the comparison: the Java output API (MsdrgOutputDxCode)
#     does not expose individual CodeFlag names, only the encoded legacy flag
#     string. The structured fields above (severity, drg_impact, poa_error,
#     hacs) capture the same information and are what v440 changes affect.
#   * hac_usage lists are compared as sorted sets so ordering doesn't matter.
#   * HAC numbers and statuses propagate naturally per version — for v431 both
#     engines zero the number in CRITERIA_NOT_MET/EXEMPT entries; for v440
#     both engines keep the real number. No version-aware normalization is
#     needed in the comparison itself.


def _java_dx_output(dx_out) -> dict:
    """Normalize a Java MsdrgOutputDxCode to the canonical dx dict shape."""
    if dx_out is None:
        return None
    flags = dx_out.getFlags() if hasattr(dx_out, "getFlags") else None
    if flags is None:
        # Fallback: reach into the wrapped flag object
        flags = dx_out
    code = str(dx_out.getInputDxCode().getValue())
    # Zig per-dx severity is the 3-value Severity enum (NONE/CC/MCC). Java
    # uses the richer MsdrgCodeSeverityFlag (NEITHER, MCC, CC, and the
    # _EXCLUDED_BY_DRG_LOGIC / _EXCLUDED variants). Collapse the excluded
    # variants to their base CC/MCC so the comparison matches.
    severity = _NORMALIZE_DX_SEVERITY[str(flags.getFinalSeverityUsage().name())]
    drg_impact = str(flags.getDiagnosisAffectsDrg().name())
    poa_error = str(flags.getPoaErrorCode().name())
    hacs_raw = list(flags.getHacs())
    hacs = []
    for h in hacs_raw:
        hacs.append({
            "hac_number": int(str(h.getHacNumber())),
            "hac_list": str(h.getHacList()) if h.getHacList() else "",
            "hac_status": str(h.getHacStatus().name()),
            "description": str(h.getDescription()) if h.getDescription() else "",
        })
    hacs.sort(key=lambda h: (h["hac_number"], h["hac_list"]))
    return {
        "code": code,
        "severity": severity,
        "drg_impact": drg_impact,
        "poa_error": poa_error,
        "hacs": hacs,
    }


def _java_proc_output(proc_out) -> dict:
    """Normalize a Java MsdrgOutputPrCode to the canonical proc dict shape."""
    if proc_out is None:
        return None
    flags = proc_out.getFlags() if hasattr(proc_out, "getFlags") else None
    if flags is None:
        flags = proc_out
    code = str(proc_out.getInputPrCode().getValue())
    is_or = bool(flags.isProcedureIsOperatingRoomProcedure())
    drg_impact = str(flags.getProcedureAffectsDrg().name())
    hac_usage_set = flags.getHacUsage()
    hac_usage = sorted(str(h.name()) for h in hac_usage_set)
    # Strip sentinel values that mean "no usage" — they are never set on the
    # Zig side and are not part of the user-visible comparison.
    hac_usage = [h for h in hac_usage if h not in ("BLANK", "HAC_NOT_USED")]
    return {
        "code": code,
        "is_or": is_or,
        "drg_impact": drg_impact,
        "hac_usage": hac_usage,
    }


def extract_java_flags(output) -> dict:
    """Pull pdx_output, sdx_output, proc_output, and grouper_flags from a Java
    MsdrgOutput and return a canonical dict matching the Zig output shape.
    """
    pdx = output.getPdxOutput()
    pdx_canon = _java_dx_output(pdx) if pdx is not None else None

    sdx_list = list(output.getSdxOutput())
    sdx_canon = [_java_dx_output(s) for s in sdx_list if s is not None]

    proc_list = list(output.getProcOutput())
    procs_canon = [_java_proc_output(p) for p in proc_list if p is not None]

    gf = output.getGrouperFlags()
    if gf is not None:
        grouper_flags = {
            "admit_dx_grouper_flag": str(gf.getAdmitDxGrouperFlag().name()),
            "initial_drg_secondary_dx_cc_mcc": _NORMALIZE_GF_SEVERITY[
                str(gf.getInitialDrgSecondaryDxCcMcc().name())
            ],
            "final_drg_secondary_dx_cc_mcc": _NORMALIZE_GF_SEVERITY[
                str(gf.getFinalDrgSecondaryDxCcMcc().name())
            ],
            "num_hac_categories_satisfied": int(gf.getNumHacCategoriesSatisfied()),
            "hac_status_value": str(gf.getHacStatusValue().name()),
        }
    else:
        grouper_flags = {
            "admit_dx_grouper_flag": "DX_NOT_GIVEN",
            "initial_drg_secondary_dx_cc_mcc": "NONE",
            "final_drg_secondary_dx_cc_mcc": "NONE",
            "num_hac_categories_satisfied": 0,
            "hac_status_value": "NOT_APPLICABLE",
        }

    return {
        "pdx": pdx_canon,
        "sdx": sdx_canon,
        "procs": procs_canon,
        "grouper_flags": grouper_flags,
    }


def _normalize_zig_flags(zig_full_res: dict) -> dict:
    """Strip the per-dx `mdc` field (Java doesn't expose it) and the per-code
    `flags` CodeFlag list (Java doesn't expose individual CodeFlag names), and
    otherwise project the Zig GroupResult into the canonical comparison shape.
    """
    def _dx(d: dict) -> dict:
        if d is None:
            return None
        out = {k: v for k, v in d.items() if k not in ("mdc", "flags")}
        out["hacs"] = sorted(
            out.get("hacs", []) or [],
            key=lambda h: (h.get("hac_number", 0), h.get("hac_list", "")),
        )
        return out

    def _proc(p: dict) -> dict:
        if p is None:
            return None
        out = {k: v for k, v in p.items() if k != "flags"}
        out["hac_usage"] = sorted(out.get("hac_usage", []) or [])
        out["hac_usage"] = [
            h for h in out["hac_usage"] if h not in ("BLANK", "HAC_NOT_USED")
        ]
        return out

    return {
        "pdx": _dx(zig_full_res.get("pdx_output")),
        "sdx": [_dx(s) for s in (zig_full_res.get("sdx_output") or [])],
        "procs": [_proc(p) for p in (zig_full_res.get("proc_output") or [])],
        "grouper_flags": dict(zig_full_res.get("grouper_flags") or {}),
    }


def _diff_dicts(path: str, a, b) -> list[str]:
    """Recursively diff two canonical values, returning a list of human-readable
    field paths where they differ. Lists are compared as sorted multisets
    (so flag ordering doesn't matter); dicts are recursed; everything else
    uses `==`.
    """
    diffs: list[str] = []
    if isinstance(a, dict) and isinstance(b, dict):
        keys = sorted(set(a.keys()) | set(b.keys()))
        for k in keys:
            if k not in a:
                diffs.append(f"{path}.{k}: missing on Java side (Zig={b[k]!r})")
            elif k not in b:
                diffs.append(f"{path}.{k}: missing on Zig side (Java={a[k]!r})")
            else:
                diffs.extend(_diff_dicts(f"{path}.{k}", a[k], b[k]))
        return diffs
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            diffs.append(f"{path}: list length {len(a)} vs {len(b)} (Java={a!r} Zig={b!r})")
            return diffs
        if all(isinstance(x, dict) for x in a) and all(isinstance(x, dict) for x in b):
            # Compare dicts of same index — canonical lists (flags, hac_usage,
            # hacs) are already sorted by the normalizers, so positional
            # comparison is correct here.
            for i, (x, y) in enumerate(zip(a, b)):
                diffs.extend(_diff_dicts(f"{path}[{i}]", x, y))
            return diffs
        if a != b:
            diffs.append(f"{path}: {a!r} != {b!r}")
        return diffs
    if a is None and b is None:
        return diffs
    if (a is None) != (b is None) or a != b:
        diffs.append(f"{path}: Java={a!r} != Zig={b!r}")
    return diffs


def _canonicalize_for_diff(canon: dict) -> dict:
    """Return a copy of `canon` with list-of-dicts fields sorted by a stable
    key, so compare_flags is order-independent. The normalizers already sort
    hacs and hac_usage, but callers may construct canonical dicts by hand
    (e.g. in tests) and we want the comparison to be robust either way.

    Also sorts the sdx and procs lists by `code` so that Java and Zig can
    return the same codes in different orders without producing false diffs.
    """
    def _sort_hacs_list(hacs):
        if not isinstance(hacs, list):
            return hacs
        return sorted(
            hacs,
            key=lambda h: (h.get("hac_number", 0), h.get("hac_list", "")),
        )

    def _sort_hac_usage(usage):
        return sorted(usage) if isinstance(usage, list) else usage

    def _walk(v):
        if isinstance(v, dict):
            return {k: _walk(val) for k, val in v.items()}
        if isinstance(v, list):
            # If it looks like a list of hac dicts, sort it.
            if v and all(isinstance(x, dict) and "hac_number" in x for x in v):
                return _sort_hacs_list(v)
            return v
        return v

    out = _walk(canon)

    # Sort sdx list by code so Java/Zig reordering doesn't cause false diffs.
    sdx = out.get("sdx")
    if isinstance(sdx, list):
        out["sdx"] = sorted(
            sdx, key=lambda d: d.get("code", "") if isinstance(d, dict) else ""
        )

    # Sort procs list by code. Procedure codes can repeat on a claim, so use
    # a stable secondary key (original index) to keep duplicates deterministic.
    procs = out.get("procs")
    if isinstance(procs, list):
        indexed = list(enumerate(procs))
        indexed.sort(
            key=lambda ip: (
                ip[1].get("code", "") if isinstance(ip[1], dict) else "",
                ip[0],
            )
        )
        out["procs"] = [p for _, p in indexed]

    # Apply hac_usage sorting to procs
    for proc in out.get("procs", []) or []:
        if isinstance(proc, dict) and "hac_usage" in proc:
            proc["hac_usage"] = _sort_hac_usage(proc["hac_usage"])

    # Apply hacs sorting to pdx/sdx dicts
    pdx = out.get("pdx")
    if isinstance(pdx, dict) and "hacs" in pdx:
        pdx["hacs"] = _sort_hacs_list(pdx["hacs"])
    for dx in out.get("sdx", []) or []:
        if isinstance(dx, dict) and "hacs" in dx:
            dx["hacs"] = _sort_hacs_list(dx["hacs"])

    return out


def compare_flags(java_canon: dict, zig_canon: dict) -> list[str]:
    """Return a list of field-level differences between canonicalized Java
    and Zig flag output. Empty list = perfect match.
    """
    java_sorted = _canonicalize_for_diff(java_canon)
    zig_sorted = _canonicalize_for_diff(zig_canon)
    return _diff_dicts("", java_sorted, zig_sorted)


def init_jvm():
    jars = glob.glob(os.path.join(JARS_DIR, "*.jar"))
    classes_dir = os.path.join(PROJECT_ROOT, "classes")
    classpath = classes_dir + ":" + ":".join(jars)
    print(f"Starting JVM with classpath: {classpath}")
    if not jpype.isJVMStarted():
        jpype.startJVM(classpath=[classpath])


def run_zig_grouper(grouper, claim_data):
    res = grouper.group(claim_data)
    return {
        "initial_drg": res["initial_drg"],
        "initial_mdc": res["initial_mdc"],
        "final_drg": res["final_drg"],
        "final_mdc": res["final_mdc"],
        "return_code": res["return_code"],
        "full_res": res,
    }


def compare(java_client, grouper, claim, debug=False, compare_flags_enabled=True):
    java_res = None
    zig_res = None

    try:
        if debug:
            # Use the lower-level GrouperChain + TraceConsumer path so Java
            # grouper trace messages (attribute assignments, formula
            # evaluations, marking decisions) are printed to stdout.
            java_res = java_client.process_with_debug(
                claim, str(claim["version"]),
                with_flags=compare_flags_enabled,
            )
        else:
            java_res = java_client.process(
                claim, str(claim["version"]),
                with_flags=compare_flags_enabled,
            )
    except Exception as e:
        print(f"Java Error: {e}")

    try:
        zig_res = run_zig_grouper(grouper, claim)
    except Exception as e:
        print(f"Zig Error: {e}")

    status = "ERROR"
    flag_diffs: list[str] = []
    if java_res and zig_res:
        zig_drg = zig_res["final_drg"]
        zig_mdc = zig_res["final_mdc"]

        if zig_drg is None or zig_mdc is None:
            # Zig returned a non-OK return code — DRG/MDC are None
            status = "UNGROUPABLE"
            print(
                f"UNGROUPABLE: Zig={zig_res['return_code']}, Java DRG={java_res['final_drg']} MDC={java_res['final_mdc']}, Claim={claim['id']}"
            )
        elif (
            java_res["final_drg"] == zig_drg
            and java_res["final_mdc"] == zig_mdc
            and java_res["initial_drg"] == zig_res["initial_drg"]
            and java_res["initial_mdc"] == zig_res["initial_mdc"]
        ):
            status = "MATCH"
        else:
            status = "MISMATCH"
            print(f"MISMATCH: Claim={claim['id']}")
            print(
                f"  Java: initial={java_res['initial_drg']}/{java_res['initial_mdc']} final={java_res['final_drg']}/{java_res['final_mdc']} rc={java_res['return_code']}"
            )
            print(
                f"  Zig:  initial={zig_res['initial_drg']}/{zig_res['initial_mdc']} final={zig_res['final_drg']}/{zig_res['final_mdc']} rc={zig_res['return_code']}"
            )

        # Flag-level comparison runs on every claim where both sides produced
        # a usable result, regardless of DRG/MDC match. Flag mismatches don't
        # change the primary status; they're tracked separately in flag_stats
        # and printed on demand. The most common case is a DRG match with a
        # flag diff — exactly the v440 HAC behavior changes.
        if (
            compare_flags_enabled
            and status != "ERROR"
            and "flags" in java_res
            and "full_res" in zig_res
        ):
            try:
                zig_canon = _normalize_zig_flags(zig_res["full_res"])
                flag_diffs = compare_flags(java_res["flags"], zig_canon)
            except Exception as e:
                flag_diffs = [f"<flag extraction failed: {e!r}>"]

    return status, java_res, zig_res, claim, flag_diffs


def run_java_grouper(claim_data, debug=False):
    # Import Java classes
    gov = jpype.JPackage("gov")
    com = jpype.JPackage("com")

    DataBlob = gov.agency.msdrg.access.DataBlob
    GrouperChain = gov.agency.msdrg.v400.chain.GrouperChain
    ProcessingContext = gov.agency.msdrg.v400.chain.ProcessingContext
    ProcessingData = gov.agency.msdrg.v400.ProcessingData
    MsdrgDiagnosisCode = gov.agency.msdrg.v400.model.MsdrgDiagnosisCode
    MsdrgProcedureCode = gov.agency.msdrg.v400.model.MsdrgProcedureCode
    MsdrgInputDxCode = gov.agency.msdrg.model.v2.transfer.input.MsdrgInputDxCode
    MsdrgInputPrCode = gov.agency.msdrg.model.v2.transfer.input.MsdrgInputPrCode
    MsdrgSex = gov.agency.msdrg.model.v2.enumeration.MsdrgSex
    MsdrgDischargeStatus = gov.agency.msdrg.model.v2.enumeration.MsdrgDischargeStatus
    TraceUtility = gov.agency.msdrg.v400.TraceUtility
    RuntimeOptions = gov.agency.msdrg.model.v2.RuntimeOptions

    GfcPoa = com.mmm.his.cer.foundation.model.GfcPoa

    version = claim_data["version"]

    # Get Data Access
    data_access = DataBlob.getInstance()

    # Create Chain
    chain = GrouperChain.createChain(data_access, version)

    # Build Input
    # PDX
    pdx_code = claim_data["pdx"]["code"]
    pdx_input = MsdrgInputDxCode(pdx_code, GfcPoa.Y)
    pdx = MsdrgDiagnosisCode(pdx_input)

    # SDX
    from java.util import ArrayList

    sdx_list = ArrayList()
    for sdx_c in claim_data["sdx"]:
        poa_val = None
        if sdx_c["poa"] == "Y":
            poa_val = GfcPoa.Y
        elif sdx_c["poa"] == "N":
            poa_val = GfcPoa.N
        elif sdx_c["poa"] == "U":
            poa_val = GfcPoa.U
        elif sdx_c["poa"] == "W":
            poa_val = GfcPoa.W
        sdx_input = MsdrgInputDxCode(sdx_c["code"], poa_val)
        sdx_list.add(MsdrgDiagnosisCode(sdx_input))

    # Procedures
    proc_list = ArrayList()
    for proc_c in claim_data["procedures"]:
        try:
            proc_input = MsdrgInputPrCode(proc_c["code"])
        except TypeError:
            proc_input = MsdrgInputPrCode(proc_c["code"], None)

        proc_list.add(MsdrgProcedureCode(proc_input))

    # Sex
    sex_map = {0: MsdrgSex.MALE, 1: MsdrgSex.FEMALE}
    sex = sex_map.get(claim_data["sex"], MsdrgSex.UNKNOWN)

    # Discharge Status
    dstat_map = {
        1: MsdrgDischargeStatus.HOME_SELFCARE_ROUTINE,
        20: MsdrgDischargeStatus.DIED,
    }
    dstat = dstat_map.get(
        claim_data["discharge_status"], MsdrgDischargeStatus.HOME_SELFCARE_ROUTINE
    )

    # Build ProcessingData
    p_data_builder = ProcessingData.builder()
    p_data_builder.withPdx(pdx)
    p_data_builder.withSdxCodes(sdx_list)
    p_data_builder.withProcedures(proc_list)
    p_data_builder.withSex(sex)
    p_data_builder.withDischargeStatus(dstat)

    p_data = p_data_builder.build()

    # Build Context
    context_builder = ProcessingContext.builder()
    context_builder.withProcessingData(p_data)

    if debug:

        @jpype.JImplements(jpype.JClass("java.util.function.Consumer"))
        class TraceConsumer:
            @jpype.JOverride
            def accept(self, message):
                print(f"JAVA TRACE: {message}")

        consumer = TraceConsumer()
        trace_utility = TraceUtility(consumer)
    else:
        trace_utility = TraceUtility()

    context_builder.withTrace(trace_utility)

    context_builder.withRuntime(RuntimeOptions())
    context = context_builder.build()

    # Execute
    result = chain.execute(context)

    # Extract Result
    final_context = result.getContext()
    final_data = final_context.getProcessingData()
    final_res = final_data.getFinalResult()

    return (final_res.getDrg(), final_res.getMdc(), str(final_res.getReturnCode()))


def benchmark_zig(claims):
    ctx = msdrg.MsdrgGrouper(LIB_PATH, DATA_DIR)
    start_time = datetime.now()
    for claim in claims:
        ctx.group(claim)
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()
    print(
        f"Zig Grouper processed {len(claims)} claims in {duration} seconds ({len(claims) / duration} claims/second)"
    )


def benchmark_java(java_client, claims):
    start_time = datetime.now()
    for claim in claims:
        java_client.process(claim, str(claim["version"]))
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()
    print(
        f"Java Grouper processed {len(claims)} claims in {duration} seconds ({len(claims) / duration} claims/second)"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compare Java and Zig MS-DRG Groupers")
    parser.add_argument("--file", type=str, help="Path to JSON file containing claims")
    parser.add_argument(
        "--benchmark", action="store_true", help="Benchmark the groupers"
    )
    parser.add_argument(
        "--debug", action="store_true", help="Enable Java Grouper tracing"
    )
    parser.add_argument(
        "--compare-flags", dest="compare_flags", action="store_true",
        default=True,
        help="Compare per-claim flag output (pdx/sdx/proc flags, HAC usage, "
             "grouper_flags) in addition to DRG/MDC/return_code. Default: on.",
    )
    parser.add_argument(
        "--no-compare-flags", dest="compare_flags", action="store_false",
        help="Disable per-claim flag comparison (DRG/MDC/return_code only).",
    )
    parser.add_argument(
        "--flag-report-limit", type=int, default=10,
        help="Maximum number of per-claim flag diffs to print in the summary "
             "(0 = suppress per-claim detail, only show counts). Default: 10.",
    )
    args = parser.parse_args()

    init_jvm()

    client = DrgClient()
    claims = []
    if args.file:
        print(f"Loading claims from {args.file}...")
        with open(args.file, "r") as f:
            claims = json.load(f)
    else:
        claims = [
            # Simple Hypertension
            {
                "version": 400,
                "age": 65,
                "sex": 0,
                "discharge_status": 1,
                "pdx": {"code": "I10"},
                "sdx": [],
                "procedures": [],
            },
            # Heart Failure (I50.20) -> MDC 5
            {
                "version": 400,
                "age": 65,
                "sex": 0,
                "discharge_status": 1,
                "pdx": {"code": "I5020"},
                "sdx": [],
                "procedures": [],
            },
            # Pneumonia (J18.9) -> MDC 4
            {
                "version": 400,
                "age": 65,
                "sex": 0,
                "discharge_status": 1,
                "pdx": {"code": "J189"},
                "sdx": [],
                "procedures": [],
            },
        ]

    # Create one shared Zig grouper instance (data loaded once)
    zig_grouper = msdrg.MsdrgGrouper(LIB_PATH, DATA_DIR)

    if not args.benchmark:
        stats = {"MATCH": 0, "MISMATCH": 0, "UNGROUPABLE": 0, "ERROR": 0}
        flag_stats = {"compared": 0, "flag_match": 0, "flag_diff": 0}
        flag_diff_samples: list[tuple[dict, list[str]]] = []

        for c in claims:
            res, j, z, c, flag_diffs = compare(
                client, zig_grouper, c, args.debug, args.compare_flags
            )
            if res == "MISMATCH":
                print(f"Java: {j}")
                print(f"Zig:  {z}")
                print(f"Claim: {c}")
                print("-" * 20)
            stats[res] += 1

            if args.compare_flags and res != "ERROR" and "flags" in (j or {}):
                flag_stats["compared"] += 1
                if flag_diffs:
                    flag_stats["flag_diff"] += 1
                    if len(flag_diff_samples) < args.flag_report_limit:
                        flag_diff_samples.append((c, flag_diffs))
                else:
                    flag_stats["flag_match"] += 1

        print("Summary (DRG/MDC/return_code):")
        print(stats)
        if args.compare_flags:
            print("Summary (flag-level):")
            print(flag_stats)
            if flag_diff_samples:
                print("\nFlag diff samples (first {} of {}):".format(
                    len(flag_diff_samples), flag_stats["flag_diff"]))
                for claim, diffs in flag_diff_samples:
                    print(f"\n  Claim {claim.get('id', '?')} v{claim.get('version', '?')}:")
                    for d in diffs[:20]:
                        print(f"    {d}")
                    if len(diffs) > 20:
                        print(f"    ... and {len(diffs) - 20} more diffs")
    else:
        print("Benchmarking Zig Grouper...")
        benchmark_zig(claims)
        print("Benchmarking Java Grouper...")
        benchmark_java(client, claims)

    zig_grouper.close()
