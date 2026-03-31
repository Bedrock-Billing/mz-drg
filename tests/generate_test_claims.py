"""
Generate random test claims for MS-DRG grouper validation against the Java reference.

Usage:
    python tests/generate_test_claims.py [--count 50000] [--out test_claims.json]

The generated claims cover a wide range of demographics, diagnoses, procedures,
POA indicators, hospital statuses, and discharge statuses to exercise all DRG
code paths for comprehensive comparison testing.
"""

import random
import json
import argparse

# Configuration
NUM_CLAIMS = 50_000
TARGET_VERSION = 431

# Grouper versions with their correct discharge dates
GROUPERS = {
    400: {"discharge_date": 20211001},
    401: {"discharge_date": 20220401},
    410: {"discharge_date": 20231001},
    411: {"discharge_date": 20240401},
    420: {"discharge_date": 20241001},
    421: {"discharge_date": 20250401},
    430: {"discharge_date": 20251001},
    431: {"discharge_date": 20260401},
}

# All valid CMS discharge status codes (from MsdrgDischargeStatus.java)
# These are the ONLY codes recognized by the Java reference grouper
VALID_DISCHARGE_STATUSES = [
    1,  # Home/Self Care
    2,  # Short-term hospital
    3,  # SNF
    4,  # Custodial/supportive care
    5,  # Cancer/children's hospital
    6,  # Home health service
    7,  # Left against medical advice
    20,  # Died
    21,  # Court/law enforcement
    30,  # Still a patient
    43,  # Federal hospital
    50,  # Hospice - home
    51,  # Hospice - medical facility
    61,  # Swing bed
    62,  # Rehab facility/rehab unit
    63,  # Long-term care hospital
    64,  # Nursing facility (Medicaid certified)
    65,  # Psychiatric hospital/unit
    66,  # Critical access hospital
    69,  # Designated disaster alternative care site
    70,  # Other institution
    81,  # Home/self care w/ planned readmission
    82,  # Short-term hospital w/ planned readmission
    83,  # SNF w/ planned readmission
    84,  # Custodial/supportive care w/ planned readmission
    85,  # Cancer/children's hospital w/ planned readmission
    86,  # Home health service w/ planned readmission
    87,  # Court/law enforcement w/ planned readmission
    88,  # Federal hospital w/ planned readmission
    89,  # Swing bed w/ planned readmission
    90,  # Rehab facility/unit w/ planned readmission
    91,  # LTCH w/ planned readmission
    92,  # Nursing facility (Medicaid certified) w/ planned readmission
    93,  # Psychiatric hospital/unit w/ planned readmission
    94,  # Critical access hospital w/ planned readmission
    95,  # Other institution w/ planned readmission
]
# Grouped by clinical category for diverse claim generation
SAMPLE_DX_CODES = {
    # MDC 1: Nervous System
    "neuro": ["G40011", "G40B09", "G4733", "G20", "G40909", "I639", "S060X0A", "G931"],
    # MDC 2: Eye
    "eye": ["H2510", "H2129", "H353233", "H4011X0", "S0510XA"],
    # MDC 3: ENT
    "ent": ["J069", "J189", "J441", "J4520", "H6692", "J0190", "C329", "K076"],
    # MDC 4: Respiratory
    "resp": ["J189", "J440", "J9600", "J8410", "J9311", "Z9981", "J9801"],
    # MDC 5: Circulatory
    "cardio": [
        "I5020",
        "I5030",
        "I2510",
        "I2109",
        "I4891",
        "I7100",
        "I726",
        "I10",
        "Z951",
    ],
    # MDC 6: Digestive
    "digest": ["K8011", "K3580", "K56609", "K7030", "C189", "K5731", "K210", "K810"],
    # MDC 7: Hepatobiliary
    "hepato": ["K7030", "K7460", "K810", "K830", "C220"],
    # MDC 8: Musculoskeletal
    "msk": ["M19229", "M1711", "M4806", "M545", "S52351C", "S72025D", "M24419"],
    # MDC 9: Skin
    "skin": ["L03116", "L89314", "L97316", "C44599", "T23409A"],
    # MDC 10: Endocrine
    "endocrine": ["E1165", "E039", "E0500", "E1010", "E66811", "E785"],
    # MDC 11: Kidney
    "kidney": ["N179", "N183", "N19", "N200", "N390", "E1122"],
    # MDC 12: Male
    "male": ["N400", "C61", "N200"],
    # MDC 13: Female
    "female": ["N8501", "N809", "C541", "O26851", "O7021"],
    # MDC 14: Pregnancy
    "pregnancy": ["O80", "O34219", "O26851", "O7021"],
    # MDC 15: Neonate
    "neonate": ["P0739", "P220", "Z3800", "P580"],
    # MDC 16: Blood
    "blood": ["D596", "D61818", "D6862", "D7589"],
    # MDC 17: Hematology/Oncology
    "heme_onc": ["C189", "C3490", "C50919", "D479", "Z5111"],
    # MDC 18: Infectious
    "infect": ["A419", "B951", "J159", "T80211A", "R6520"],
    # MDC 19: Mental Health
    "mental": ["F320", "F411", "F10239", "F209", "F1327"],
    # MDC 20: Alcohol/Drug
    "substance": ["F10239", "F1327", "F1920"],
    # MDC 21: Injury
    "injury": ["S52202H", "S42134P", "S72033A", "T07", "S022XXB", "V4324XA"],
    # MDC 22: Burns
    "burns": ["T23409A", "T3140", "T2010XA"],
    # MDC 23: Factors
    "factors": ["Z4889", "Z5111", "Z8673", "Z23"],
    # MDC 24: Multiple Trauma
    "trauma": ["T07", "S0636AS", "S32466D", "S55201A"],
    # MDC 25: HIV
    "hiv": ["B20", "Z21"],
}

# Common ICD-10-PCS procedure codes covering major DRG-relevant procedures
SAMPLE_PROC_CODES = {
    "cardio": [
        "02703DZ",
        "027034Z",
        "02713DZ",
        "027134Z",
        "02733DZ",
        "02733FZ",
        "021609P",
        "02703D6",
        "02703D7",
        "02100Z6",
    ],
    "ortho": [
        "0SRB0JZ",
        "0SRB0KZ",
        "0SRD0JZ",
        "0SPD4JC",
        "0PHJ4BZ",
        "0RG13J1",
        "0SR90JZ",
        "0SRB0JZ",
        "0QSH3BZ",
        "0QP60JZ",
    ],
    "general": [
        "0DTJ0ZZ",
        "0DB68ZZ",
        "0DB78ZZ",
        "0DNJ4ZZ",
        "0DJD8ZZ",
        "0DTC4ZZ",
        "0D9L8ZZ",
        "0DTJ4ZZ",
        "0DB63ZZ",
    ],
    "resp": ["0B110F4", "0B113F4", "0B114F4", "0BH17EZ", "0BH18EZ"],
    "neuro": ["00B60ZZ", "00B63ZZ", "00B64ZZ", "0016070", "0016370"],
    "kidney": ["0TS10ZZ", "0TB10ZZ", "0TT10ZZ", "0TB14ZZ"],
    "eye": ["08BQ0ZZ", "08DQ0ZZ", "08CQ0ZZ"],
    "imaging": ["B226Y0Z", "B311ZZZ", "BW20ZZZ"],
    "monitoring": ["4A023N7", "4A02X4G", "4A12X4G", "5A0211D"],
}

# All DX codes flattened
ALL_DX_CODES = []
for codes in SAMPLE_DX_CODES.values():
    ALL_DX_CODES.extend(codes)

# All proc codes flattened
ALL_PROC_CODES = []
for codes in SAMPLE_PROC_CODES.values():
    ALL_PROC_CODES.extend(codes)


def generate_claim(idx: int) -> dict:
    """Generate a single random test claim with diverse coverage."""
    version = random.choice(list(GROUPERS.keys()))
    age = random.randint(0, 124)
    sex = random.choice([0, 1, 2])  # 0=Male, 1=Female, 2=Unknown

    # Discharge status — only valid CMS codes from MsdrgDischargeStatus.java
    discharge_status = random.choice(VALID_DISCHARGE_STATUSES)

    hospital_status = random.choice(["NOT_EXEMPT", "EXEMPT", "UNKNOWN"])
    length_of_stay = random.randint(1, 45)

    # PDX — pick from diverse MDC categories
    pdx_code = random.choice(ALL_DX_CODES)
    pdx_poa = random.choice(["Y", "N", "U", "W"])

    # SDX — 0-9 secondary diagnoses with varied POA
    num_sdx = random.randint(0, 9)
    sdx_codes = random.sample(ALL_DX_CODES, min(num_sdx, len(ALL_DX_CODES)))
    sdx = []
    for code in sdx_codes:
        poa = random.choice(["Y", "N", "U", "W"])
        sdx.append({"code": code, "poa": poa})

    # Procedures — 0-10
    num_proc = random.randint(0, 10)
    procs = random.sample(ALL_PROC_CODES, min(num_proc, len(ALL_PROC_CODES)))

    # Admit DX — 30% of claims have it
    admit_dx = None
    if random.random() < 0.30:
        admit_dx = {
            "code": random.choice(ALL_DX_CODES),
            "poa": random.choice(["Y", "N", "U", "W"]),
        }

    claim = {
        "id": f"TEST-{idx + 1:04d}",
        "version": version,
        "discharge_date": GROUPERS[version]["discharge_date"],
        "age": age,
        "sex": sex,
        "discharge_status": discharge_status,
        "hospital_status": hospital_status,
        "length_of_stay": length_of_stay,
        "pdx": {"code": pdx_code, "poa": pdx_poa},
        "sdx": sdx,
        "procedures": [{"code": c} for c in procs],
    }

    if admit_dx:
        claim["admit_dx"] = admit_dx

    return claim


def generate_claims(count: int, output_file: str):
    """Generate a set of random test claims and write to JSON."""
    random.seed(42)  # Reproducible test data

    print(f"Generating {count} claims...")
    print(
        f"  {len(ALL_DX_CODES)} diagnosis codes across {len(SAMPLE_DX_CODES)} MDC categories"
    )
    print(
        f"  {len(ALL_PROC_CODES)} procedure codes across {len(SAMPLE_PROC_CODES)} categories"
    )
    print(f"  Versions: {sorted(GROUPERS.keys())}")
    print(f"  Sex: 0(Male), 1(Female), 2(Unknown)")
    print(f"  POA: Y, N, U, W")
    print(f"  Hospital status: EXEMPT, NOT_EXEMPT, UNKNOWN")
    print(f"  Discharge status: {len(VALID_DISCHARGE_STATUSES)} valid codes")
    print(f"  Admit DX: 30% of claims")

    claims = [generate_claim(i) for i in range(count)]

    with open(output_file, "w") as f:
        json.dump(claims, f, indent=2)
    print(f"Wrote {count} claims to {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate random MS-DRG test claims")
    parser.add_argument(
        "--count", type=int, default=NUM_CLAIMS, help="Number of claims to generate"
    )
    parser.add_argument(
        "--out", type=str, default="tests/test_claims.json", help="Output file path"
    )
    args = parser.parse_args()

    generate_claims(args.count, args.out)
