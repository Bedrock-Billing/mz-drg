import jpype
import jpype.imports
from jpype.types import *
import os
import sys
import glob
import json
import argparse
from datetime import datetime

# Add python_client to path
sys.path.append(os.path.join(os.getcwd(), 'python_client'))
try:
    import msdrg
except ImportError:
    # Fallback if running from root
    sys.path.append(os.path.join(os.getcwd()))
    from python_client import msdrg

# Paths
PROJECT_ROOT = os.getcwd()
JARS_DIR = os.path.join(PROJECT_ROOT, 'jars')
DATA_DIR = os.path.join(PROJECT_ROOT, 'data', 'bin')

# Zig Library Path
LIB_PATH = os.path.join(PROJECT_ROOT, 'zig_src', 'zig-out', 'lib', 'libmsdrg.so')

class DrgClient():
    def __init__(self):
        self.load_classes()
        self.load_enums()
        self.load_drg_groupers()

    def create_drg_options(self, poa_exempt: bool) -> jpype.JObject:
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
        if poa_exempt:
            runtime_options.setPoaReportingExempt(self.hospital_status.EXEMPT)
        else:
            runtime_options.setPoaReportingExempt(self.hospital_status.NON_EXEMPT)
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
        exempt_drg_options = self.create_drg_options(poa_exempt=True)
        non_exempt_drg_options = self.create_drg_options(poa_exempt=False)
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
                print(f"Loaded DRG version: {curr_version}")
            except Exception as e:
                print(f"Failed to load DRG version {curr_version}: {e}")
                if curr_version > end_version:
                    break
                curr_version = self.increment_version(curr_version)
                continue
            curr_version = self.increment_version(curr_version)

    def create_drg_input(
        self, claim
    ) -> jpype.JObject | None:
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
            # try to convert to integer
            try:
                discharge_status = int(claim["discharge_status"])
                if discharge_status not in (1, 20):
                    discharge_status = 1
                input.withDischargeStatus(
                    self.drg_status.getEnumFromInt(discharge_status)
                )
            except ValueError:
                raise ValueError(f"Invalid patient status: {claim['discharge_status']}")
        else:
            input.withDischargeStatus(self.drg_status.HOME_SELFCARE_ROUTINE)

        if claim.get("adx", None) is not None:
            input.withAdmissionDiagnosisCode(
                self.drg_dx_class(claim["adx"]["code"].replace(".", ""),            
                    self.poa_values.Y)
            )

        if claim["pdx"]:
            input.withPrincipalDiagnosisCode(
                self.drg_dx_class(
                        claim["pdx"]["code"].replace(".", ""),
                    self.poa_values.Y,
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
                        self.drg_dx_class(dx["code"].replace(".", ""), 
                        poa_value,
                    )
                )
        if len(java_dxs) > 0:
            input.withSecondaryDiagnosisCodes(java_dxs)

        java_pxs = self.array_list_class()
        for px in claim["procedures"]:
                java_pxs.add(
                    self.drg_px_class(
                        px["code"].replace(".", "")
                    )
                )
        if len(java_pxs) > 0:
            input.withProcedureCodes(java_pxs)
        return input.build()

    def process(self, claim, version: str):
        i = self.create_drg_input(claim) 
        drg_component = self.drg_versions[version]["non_exempt"]
        drg_claim =self.drg_claim_class(i)
        drg_component.process(drg_claim)
        output = drg_claim.getOutput().get()
        return str(output.getFinalDrg().getValue()), str(output.getFinalMdc().getValue()), str(output.getFinalGrc().name())

def init_jvm():
    jars = glob.glob(os.path.join(JARS_DIR, "*.jar"))
    classes_dir = os.path.join(PROJECT_ROOT, 'classes')
    classpath = classes_dir + ":" + ":".join(jars)
    print(f"Starting JVM with classpath: {classpath}")
    if not jpype.isJVMStarted():
        jpype.startJVM(classpath=[classpath])

def run_zig_grouper(claim_data):
    ctx = msdrg.MsdrgGrouper(LIB_PATH, DATA_DIR)
    res = ctx.group(claim_data)
    return {
        "drg": res['final_drg'],
        "mdc": res['final_mdc'],
        "return_code": res['return_code'],
        "full_res": res
    }

def compare(java_client, claim, debug=False):    
    java_res = None
    zig_res = None
    
    try:
        java_res = java_client.process(claim, str(claim['version']))
    except Exception as e:
        print(f"Java Error: {e}")

    try:
        zig_res = run_zig_grouper(claim)
    except Exception as e:
        print(f"Zig Error: {e}")
        
    status = "ERROR"
    if java_res and zig_res:
        if zig_res["drg"] is None:
            print(claim)
            print(f"Zig DRG is None: {zig_res}")
            print(f"Java DRG: {java_res}")
        if int(java_res[0]) == int(zig_res['drg']) and int(java_res[1]) == int(zig_res['mdc']):
            status = "MATCH"
        else:
            status = "MISMATCH"
            print(f"MISMATCH: Java={java_res} Zig={zig_res}, Claim={claim}")
            raise Exception(f"MISMATCH: Java={java_res} Zig={zig_res}, Claim={claim}")
    
    return status, java_res, zig_res, claim

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
    
    version = claim_data['version']
    
    # Get Data Access
    data_access = DataBlob.getInstance()
    
    # Create Chain
    chain = GrouperChain.createChain(data_access, version)
    
    # Build Input
    # PDX
    pdx_code = claim_data['pdx']['code']
    pdx_input = MsdrgInputDxCode(pdx_code, GfcPoa.Y) 
    pdx = MsdrgDiagnosisCode(pdx_input)
    
    # SDX
    from java.util import ArrayList
    sdx_list = ArrayList()
    for sdx_c in claim_data['sdx']:
        poa_val = None
        if sdx_c['poa'] == "Y":
            poa_val = GfcPoa.Y
        elif sdx_c['poa'] == "N":
            poa_val = GfcPoa.N
        elif sdx_c['poa'] == "U":
            poa_val = GfcPoa.U
        elif sdx_c['poa'] == "W":
            poa_val = GfcPoa.W
        sdx_input = MsdrgInputDxCode(sdx_c['code'], poa_val)
        sdx_list.add(MsdrgDiagnosisCode(sdx_input))
        
    # Procedures
    proc_list = ArrayList()
    for proc_c in claim_data['procedures']:
        try:
            proc_input = MsdrgInputPrCode(proc_c['code'])
        except TypeError:
             proc_input = MsdrgInputPrCode(proc_c['code'], None)
             
        proc_list.add(MsdrgProcedureCode(proc_input))
        
    # Sex
    sex_map = {0: MsdrgSex.MALE, 1: MsdrgSex.FEMALE}
    sex = sex_map.get(claim_data['sex'], MsdrgSex.UNKNOWN)
    
    # Discharge Status
    dstat_map = {1: MsdrgDischargeStatus.HOME_SELFCARE_ROUTINE, 20: MsdrgDischargeStatus.DIED} 
    dstat = dstat_map.get(claim_data['discharge_status'], MsdrgDischargeStatus.HOME_SELFCARE_ROUTINE)
    
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
    
    return (
        final_res.getDrg(),
        final_res.getMdc(),
        str(final_res.getReturnCode())
    )

def benchmark_zig(claims):
    ctx = msdrg.MsdrgGrouper(LIB_PATH, DATA_DIR)
    start_time = datetime.now()
    for claim in claims:
        ctx.group(claim)
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()
    print(f"Zig Grouper processed {len(claims)} claims in {duration} seconds ({len(claims)/duration} claims/second)")

def benchmark_java(java_client, claims):
    start_time = datetime.now()
    for claim in claims:
        java_client.process(claim, str(claim['version']))
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()
    print(f"Java Grouper processed {len(claims)} claims in {duration} seconds ({len(claims)/duration} claims/second)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compare Java and Zig MS-DRG Groupers")
    parser.add_argument("--file", type=str, help="Path to JSON file containing claims")
    parser.add_argument("--benchmark", action="store_true", help="Benchmark the groupers")
    parser.add_argument("--debug", action="store_true", help="Enable Java Grouper tracing")
    args = parser.parse_args()

    init_jvm()
    
    client = DrgClient()
    claims = []
    if args.file:
        print(f"Loading claims from {args.file}...")
        with open(args.file, 'r') as f:
            claims = json.load(f)
    else:
        claims = [
            # Simple Hypertension
            {'version': 400, 'age': 65, 'sex': 0, 'discharge_status': 1, 'pdx': {'code': 'I10'}, 'sdx': [], 'procedures': []},
            # Heart Failure (I50.20) -> MDC 5
            {'version': 400, 'age': 65, 'sex': 0, 'discharge_status': 1, 'pdx': {'code': 'I5020'}, 'sdx': [], 'procedures': []},
            # Pneumonia (J18.9) -> MDC 4
            {'version': 400, 'age': 65, 'sex': 0, 'discharge_status': 1, 'pdx': {'code': 'J189'}, 'sdx': [], 'procedures': []},
        ]
    
    if not args.benchmark:
        stats = {"MATCH": 0, "MISMATCH": 0, "ERROR": 0}
        for c in claims:
            res ,j, z, c = compare(client, c, args.debug)
            if res == "MISMATCH":
                print(f"Java: {j}")
                print(f"Zig:  {z}")
                print(f"Claim: {c}")
                print("-" * 20)
            stats[res] += 1
            
        print("Summary:")
        print(stats)
    else:
        print("Benchmarking Zig Grouper...")
        benchmark_zig(claims)
        print("Benchmarking Java Grouper...")
        benchmark_java(client, claims)
