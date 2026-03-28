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

import argparse
import json
import os
import sys
from collections import Counter
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


def generate_test_claims(count):
    """Generate simple test claims covering various edit scenarios."""
    claims = []

    # Valid claim (no edits)
    claims.append(
        {
            "id": "TEST-001",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020", "poa": "Y"},
            "sdx": [{"code": "E1165", "poa": "Y"}],
            "procedures": [],
        }
    )

    # E-code as PDX
    claims.append(
        {
            "id": "TEST-002",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "V0001XA", "poa": "Y"},
            "sdx": [],
            "procedures": [],
        }
    )

    # Newborn code with adult age
    claims.append(
        {
            "id": "TEST-003",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "A33", "poa": "Y"},
            "sdx": [],
            "procedures": [],
        }
    )

    # Unacceptable PDX
    claims.append(
        {
            "id": "TEST-004",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "Z9989", "poa": "Y"},
            "sdx": [],
            "procedures": [],
        }
    )

    # Non-specific PDX (non-died)
    claims.append(
        {
            "id": "TEST-005",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "B349", "poa": "Y"},
            "sdx": [],
            "procedures": [],
        }
    )

    # Non-specific PDX (died) — should NOT trigger
    claims.append(
        {
            "id": "TEST-006",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 20,
            "pdx": {"code": "B349", "poa": "Y"},
            "sdx": [],
            "procedures": [],
        }
    )

    # Duplicate SDX == PDX
    claims.append(
        {
            "id": "TEST-007",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020", "poa": "Y"},
            "sdx": [{"code": "I5020", "poa": "Y"}],
            "procedures": [],
        }
    )

    # Female code with male sex (use date in active range)
    claims.append(
        {
            "id": "TEST-008",
            "discharge_date": 20240101,
            "age": 25,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020", "poa": "Y"},
            "sdx": [{"code": "A34", "poa": "Y"}],
            "procedures": [],
        }
    )

    # MSP code
    claims.append(
        {
            "id": "TEST-009",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020", "poa": "Y"},
            "sdx": [{"code": "Z96641", "poa": "Y"}],
            "procedures": [],
        }
    )

    # Manifestation as PDX
    claims.append(
        {
            "id": "TEST-010",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "J9601", "poa": "Y"},
            "sdx": [],
            "procedures": [],
        }
    )

    # Procedure with non-covered attribute
    claims.append(
        {
            "id": "TEST-011",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020", "poa": "Y"},
            "sdx": [],
            "procedures": [{"code": "0DT80ZZ"}],
        }
    )

    # Procedure with bilateral attribute
    claims.append(
        {
            "id": "TEST-012",
            "discharge_date": 20250101,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "M1711", "poa": "Y"},  # MDC08 code
            "sdx": [],
            "procedures": [{"code": "0SRB0J9"}, {"code": "0SRB0JA"}],
        }
    )

    return claims


if __name__ == "__main__":
    main()
