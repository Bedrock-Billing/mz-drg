#!/usr/bin/env python3
"""
Compare Java CMS MCE output with Zig mz-drg MCE output.

Usage:
    python tests/compare_mce.py --file tests/test_claims.json
    python tests/compare_mce.py --count 100

This script:
1. Runs claims through the Java CMS MCE (via JPype)
2. Runs the same claims through the Zig mz-drg MCE (via ctypes)
3. Compares edit_type and per-edit counts
4. Reports matches/mismatches
"""

import msdrg
import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

import jpype

# Add project paths
PROJECT_ROOT = str(Path(__file__).parent.parent)
sys.path.insert(0, PROJECT_ROOT)
sys.path.insert(0, os.path.join(PROJECT_ROOT, "msdrg"))

import msdrg

JARS_DIR = os.path.join(PROJECT_ROOT, "jars")
DATA_DIR = os.path.join(PROJECT_ROOT, "data", "bin")
LIB_PATH = os.path.join(PROJECT_ROOT, "zig_src", "zig-out", "lib", "libmsdrg.so")


# ---------------------------------------------------------------------------
# JVM setup
# ---------------------------------------------------------------------------


def init_jvm():
    """Start the JVM with MCE classpath."""
    import glob

    jars = glob.glob(os.path.join(JARS_DIR, "*.jar"))
    classpath = ":".join(jars)
    if not jpype.isJVMStarted():
        jpype.startJVM(classpath=[classpath])
    # Import java.util.ArrayList after JVM starts
    global ArrayList
    ArrayList = jpype.JClass("java.util.ArrayList")


# ---------------------------------------------------------------------------
# Java MCE runner
# ---------------------------------------------------------------------------


def run_java_mce(claim, icd_version=10):
    """Run a claim through the Java CMS MCE and return edit info."""
    gov = jpype.JPackage("gov")
    com = jpype.JPackage("com")

    MceComponent = gov.cms.editor.mce.MceComponent
    MceRecord = gov.cms.editor.mce.transfer.MceRecord
    MceDiagnosisCode = gov.cms.editor.mce.model.MceDiagnosisCode
    MceProcedureCode = gov.cms.editor.mce.model.MceProcedureCode
    GfcPoa = com.mmm.his.cer.foundation.model.GfcPoa
    Integer = jpype.JClass("java.lang.Integer")

    # Build MceRecord
    discharge_date = str(claim.get("discharge_date", 20250101))
    age = claim.get("age", 0)
    sex = claim.get("sex", 0)  # 0=Male, 1=Female, 2=Unknown → Java: 1=Male, 2=Female
    sex_java = sex + 1 if sex in (0, 1) else 0
    discharge_status = claim.get("discharge_status", 1)
    length_of_stay = claim.get("length_of_stay", 7)  # default 7 days

    # PDX
    pdx_info = claim.get("pdx", {})
    pdx_code = pdx_info.get("code", "") if pdx_info else ""
    pdx_poa = _str_to_gfcpoa(pdx_info.get("poa", "Y") if pdx_info else "Y")

    # Build record using builder — use Integer for boxed types
    builder = MceRecord.builder()
    builder.withDischargeDate(discharge_date)
    builder.withIcdVersion(Integer(icd_version))
    builder.withAgeYears(Integer(age))
    builder.withSex(Integer(sex_java))
    builder.withDischargeStatus(Integer(discharge_status))
    builder.withLengthOfStay(Integer(length_of_stay))

    record = builder.build()

    # Add PDX
    if pdx_code:
        pdx = MceDiagnosisCode(pdx_code, pdx_poa, True)
        record.addCode(pdx)

    # Add SDX
    for sdx_info in claim.get("sdx", []):
        if not sdx_info:
            continue
        sdx_code = sdx_info.get("code", "")
        sdx_poa = _str_to_gfcpoa(sdx_info.get("poa", "Y"))
        if sdx_code:
            sdx = MceDiagnosisCode(sdx_code, sdx_poa, False)
            record.addCode(sdx)

    # Add procedures
    for proc_info in claim.get("procedures", []):
        if not proc_info:
            continue
        proc_code = (
            proc_info.get("code", "") if isinstance(proc_info, dict) else proc_info
        )
        if proc_code:
            proc = MceProcedureCode(proc_code)
            record.addCode(proc)

    # Run MCE
    component = MceComponent()
    component.process(record)

    # Extract output
    output = record.getMceOutput()
    if output is None:
        return {"edit_type": "NONE", "edits": {}, "error": "no output"}

    edit_type = str(output.getEditType())
    edit_counter = output.getEditCounter()

    # Convert edit counter to simple dict
    edits = {}
    if edit_counter is not None:
        for entry in edit_counter.entrySet():
            edit_name = str(entry.getKey())
            count = int(entry.getValue())
            if count > 0:
                edits[edit_name] = count

    return {"edit_type": edit_type, "edits": edits}


def _str_to_gfcpoa(poa_str):
    """Convert POA string to GfcPoa enum."""
    com = jpype.JPackage("com")
    GfcPoa = com.mmm.his.cer.foundation.model.GfcPoa
    if poa_str == "Y":
        return GfcPoa.Y
    elif poa_str == "N":
        return GfcPoa.N
    elif poa_str == "U":
        return GfcPoa.U
    elif poa_str == "W":
        return GfcPoa.W
    return GfcPoa.Y


# ---------------------------------------------------------------------------
# Zig MCE runner
# ---------------------------------------------------------------------------


def run_zig_mce(claim, icd_version=10):
    """Run a claim through the Zig MCE and return edit info."""
    # Build MCE input from claim
    mce_input = {
        "discharge_date": claim.get("discharge_date", 20250101),
        "icd_version": icd_version,
        "age": claim.get("age", 0),
        "sex": claim.get("sex", 0),
        "discharge_status": claim.get("discharge_status", 1),
    }

    pdx_info = claim.get("pdx", {})
    if pdx_info:
        mce_input["pdx"] = {
            "code": pdx_info.get("code", ""),
            "poa": pdx_info.get("poa", "Y"),
        }

    mce_input["sdx"] = []
    for sdx_info in claim.get("sdx", []):
        if sdx_info:
            mce_input["sdx"].append(
                {
                    "code": sdx_info.get("code", ""),
                    "poa": sdx_info.get("poa", "Y"),
                }
            )

    mce_input["procedures"] = []
    for proc_info in claim.get("procedures", []):
        if isinstance(proc_info, dict):
            mce_input["procedures"].append({"code": proc_info.get("code", "")})
        else:
            mce_input["procedures"].append({"code": proc_info})

    with msdrg.MceEditor(lib_path=LIB_PATH, data_dir=DATA_DIR) as mce:
        result = mce.edit(mce_input)

    edits = {}
    for e in result.get("edits", []):
        edits[e["name"]] = e["count"]

    return {"edit_type": result["edit_type"], "edits": edits}


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------


def compare_edit_maps(java_edits, zig_edits):
    """Compare Java and Zig edit maps. Returns (match, differences)."""
    all_keys = set(java_edits.keys()) | set(zig_edits.keys())
    diffs = []
    for key in sorted(all_keys):
        java_count = java_edits.get(key, 0)
        zig_count = zig_edits.get(key, 0)
        if java_count != zig_count:
            diffs.append(f"  {key}: Java={java_count}, Zig={zig_count}")
    return len(diffs) == 0, diffs


def run_comparison(claims, icd_version=10, verbose=False):
    """Run comparison on a list of claims."""
    stats = Counter()
    mismatches = []

    for i, claim in enumerate(claims):
        try:
            java_res = run_java_mce(claim, icd_version)
        except Exception as e:
            if verbose:
                print(f"  Claim {i}: Java error: {e}")
            stats["JAVA_ERROR"] += 1
            continue

        try:
            zig_res = run_zig_mce(claim, icd_version)
        except Exception as e:
            if verbose:
                print(f"  Claim {i}: Zig error: {e}")
            stats["ZIG_ERROR"] += 1
            continue

        # Compare edit types
        java_edit_type = java_res["edit_type"]
        zig_edit_type = zig_res["edit_type"]

        # Compare edit maps
        edit_match, edit_diffs = compare_edit_maps(java_res["edits"], zig_res["edits"])

        if java_edit_type == zig_edit_type and edit_match:
            stats["MATCH"] += 1
        else:
            stats["MISMATCH"] += 1
            mismatches.append(
                {
                    "index": i,
                    "claim": claim,
                    "java_edit_type": java_edit_type,
                    "zig_edit_type": zig_edit_type,
                    "java_edits": java_res["edits"],
                    "zig_edits": zig_res["edits"],
                    "edit_diffs": edit_diffs,
                }
            )

            if verbose or len(mismatches) <= 10:
                claim_id = claim.get("id", f"#{i}")
                print(f"\nMISMATCH [{claim_id}]:")
                print(f"  Edit type: Java={java_edit_type}, Zig={zig_edit_type}")
                if edit_diffs:
                    print("  Edit differences:")
                    for d in edit_diffs:
                        print(d)
                if not edit_diffs:
                    print("  (edit types differ but counts match)")

    return stats, mismatches


# ---------------------------------------------------------------------------
# Benchmarking
# ---------------------------------------------------------------------------


def benchmark_zig(claims, icd_version=10):
    """Benchmark the Zig MCE editor."""
    mce_editor = msdrg.MceEditor(lib_path=LIB_PATH, data_dir=DATA_DIR)

    # Pre-build all MCE inputs to exclude input construction from timing
    mce_inputs = []
    for claim in claims:
        mce_input = {
            "discharge_date": claim.get("discharge_date", 20250101),
            "icd_version": icd_version,
            "age": claim.get("age", 0),
            "sex": claim.get("sex", 0),
            "discharge_status": claim.get("discharge_status", 1),
        }
        pdx_info = claim.get("pdx", {})
        if pdx_info:
            mce_input["pdx"] = {
                "code": pdx_info.get("code", ""),
                "poa": pdx_info.get("poa", "Y"),
            }
        mce_input["sdx"] = [
            {"code": s.get("code", ""), "poa": s.get("poa", "Y")}
            for s in claim.get("sdx", []) if s
        ]
        mce_input["procedures"] = [
            {"code": p.get("code", "") if isinstance(p, dict) else p}
            for p in claim.get("procedures", [])
        ]
        mce_inputs.append(mce_input)

    start_time = datetime.now()
    for mce_input in mce_inputs:
        mce_editor.edit(mce_input)
    end_time = datetime.now()

    mce_editor.close()

    duration = (end_time - start_time).total_seconds()
    rate = len(claims) / duration if duration > 0 else 0
    print(
        f"Zig MCE processed {len(claims)} claims in {duration:.3f} seconds "
        f"({rate:.1f} claims/second)"
    )
    return duration


def benchmark_java(claims, icd_version=10):
    """Benchmark the Java CMS MCE editor."""
    gov = jpype.JPackage("gov")
    com = jpype.JPackage("com")

    MceComponent = gov.cms.editor.mce.MceComponent
    MceRecord = gov.cms.editor.mce.transfer.MceRecord
    MceDiagnosisCode = gov.cms.editor.mce.model.MceDiagnosisCode
    MceProcedureCode = gov.cms.editor.mce.model.MceProcedureCode
    Integer = jpype.JClass("java.lang.Integer")

    component = MceComponent()

    start_time = datetime.now()
    for claim in claims:
        discharge_date = str(claim.get("discharge_date", 20250101))
        age = claim.get("age", 0)
        sex = claim.get("sex", 0)
        sex_java = sex + 1 if sex in (0, 1) else 0
        discharge_status = claim.get("discharge_status", 1)
        length_of_stay = claim.get("length_of_stay", 7)

        builder = MceRecord.builder()
        builder.withDischargeDate(discharge_date)
        builder.withIcdVersion(Integer(icd_version))
        builder.withAgeYears(Integer(age))
        builder.withSex(Integer(sex_java))
        builder.withDischargeStatus(Integer(discharge_status))
        builder.withLengthOfStay(Integer(length_of_stay))
        record = builder.build()

        pdx_info = claim.get("pdx", {})
        if pdx_info:
            pdx_code = pdx_info.get("code", "")
            if pdx_code:
                pdx_poa = _str_to_gfcpoa(pdx_info.get("poa", "Y"))
                record.addCode(MceDiagnosisCode(pdx_code, pdx_poa, True))

        for sdx_info in claim.get("sdx", []):
            if not sdx_info:
                continue
            sdx_code = sdx_info.get("code", "")
            if sdx_code:
                sdx_poa = _str_to_gfcpoa(sdx_info.get("poa", "Y"))
                record.addCode(MceDiagnosisCode(sdx_code, sdx_poa, False))

        for proc_info in claim.get("procedures", []):
            if not proc_info:
                continue
            proc_code = (
                proc_info.get("code", "") if isinstance(proc_info, dict) else proc_info
            )
            if proc_code:
                record.addCode(MceProcedureCode(proc_code))

        component.process(record)

    end_time = datetime.now()

    duration = (end_time - start_time).total_seconds()
    rate = len(claims) / duration if duration > 0 else 0
    print(
        f"Java MCE processed {len(claims)} claims in {duration:.3f} seconds "
        f"({rate:.1f} claims/second)"
    )
    return duration


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Compare Java CMS MCE with Zig mz-drg MCE"
    )
    parser.add_argument("--file", type=str, help="Path to JSON claims file")
    parser.add_argument(
        "--count", type=int, default=10, help="Number of random claims to test"
    )
    parser.add_argument(
        "--icd-version", type=int, default=10, choices=[9, 10], help="ICD version"
    )
    parser.add_argument("--verbose", action="store_true", help="Print all mismatches")
    parser.add_argument(
        "--benchmark", action="store_true", help="Benchmark Zig vs Java MCE throughput"
    )
    args = parser.parse_args()

    init_jvm()

    # Load claims
    if args.file:
        print(f"Loading claims from {args.file}...")
        with open(args.file) as f:
            claims = json.load(f)
    else:
        # Generate simple test claims
        claims = generate_test_claims(args.count)
        print(f"Generated {len(claims)} test claims")

    if args.benchmark:
        print(f"Benchmarking with {len(claims)} claims...")
        print()
        print("Benchmarking Zig MCE...")
        zig_duration = benchmark_zig(claims, args.icd_version)
        print("Benchmarking Java MCE...")
        java_duration = benchmark_java(claims, args.icd_version)
        print()
        print("=" * 60)
        print("MCE Benchmark Results")
        print("=" * 60)
        if java_duration > 0 and zig_duration > 0:
            speedup = java_duration / zig_duration
            print(f"  Zig:    {zig_duration:.3f}s")
            print(f"  Java:   {java_duration:.3f}s")
            print(f"  Speedup: {speedup:.1f}x {'(Zig faster)' if speedup > 1 else '(Java faster)'}")
    else:
        print(f"Running {len(claims)} claims through Java CMS MCE and Zig mz-drg MCE...")
        print()

        stats, mismatches = run_comparison(claims, args.icd_version, args.verbose)

        # Summary
        print("=" * 60)
        print("MCE Comparison Results")
        print("=" * 60)
        print(f"  Total claims:  {sum(stats.values())}")
        print(f"  Match:         {stats['MATCH']}")
        print(f"  Mismatch:      {stats['MISMATCH']}")
        print(f"  Java Error:    {stats['JAVA_ERROR']}")
        print(f"  Zig Error:     {stats['ZIG_ERROR']}")

        total = sum(stats.values())
        if total > 0:
            match_pct = stats["MATCH"] / total * 100
            print(f"  Match rate:    {match_pct:.1f}%")

        if mismatches:
            print(f"\nFirst {min(5, len(mismatches))} mismatches:")
            for m in mismatches[:5]:
                claim_id = m["claim"].get("id", m["index"])
                print(
                    f"  [{claim_id}] Java={m['java_edit_type']}, Zig={m['zig_edit_type']}"
                )
                if m["edit_diffs"]:
                    for d in m["edit_diffs"][:3]:
                        print(f"   {d}")


if __name__ == "__main__":
    main()
