"""
Generate random test claims for MS-DRG grouper validation against the Java reference.

Usage:
    python tests/generate_test_claims.py [--count 50000] [--out test_claims.json]

The generator ensures coverage of all major DRG code paths:
- All 8 grouper versions (FY 2023–2026)
- All 36 valid CMS discharge status codes (ALIVE, AMA, DIED, XFRNBA branches)
- All 3 hospital statuses (EXEMPT, NOT_EXEMPT, UNKNOWN)
- All 3 severity levels (MCC, CC, NONE)
- Surgical vs medical DRG paths
- Sex-specific code conflicts (male/female codes with opposite sex)
- Age-specific code conflicts (neonatal codes with adult age)
- HAC-relevant claims (POA Y/N/U/W with HAC codes)
- Multiple MDCs for broad coverage
- Admit DX codes
"""

import random
import json
import argparse

# Configuration
NUM_CLAIMS = 50_000

# Grouper versions with discharge dates
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
VALID_DISCHARGE_STATUSES = [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    20,
    21,
    30,
    43,
    50,
    51,
    61,
    62,
    63,
    64,
    65,
    66,
    69,
    70,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
]

# Discharge status groups for targeted scenarios
DS_ALIVE = [1, 2, 3, 4, 5, 6, 21, 30, 43, 50, 51, 61, 62, 63, 64, 65, 66, 69, 70]
DS_DIED = [20]
DS_AMA = [7]
DS_XFRNBA = [2, 5, 66, 82, 85, 94]  # Transfer facility codes

# Hospital status weights (NOT_EXEMPT is the standard/default)
HOSPITAL_STATUSES = ["NOT_EXEMPT", "EXEMPT", "UNKNOWN"]
HOSPITAL_STATUS_WEIGHTS = [0.5, 0.25, 0.25]

POA_VALUES = ["Y", "N", "U", "W"]

# ---------------------------------------------------------------------------
# Diagnosis codes by MDC — curated for broad DRG coverage
# ---------------------------------------------------------------------------

DX_CODES = {
    # MDC 1: Nervous System
    "neuro": ["G20", "G4733", "G40909", "G40011", "G40B09", "I639", "G931", "G4011"],
    # MDC 2: Eye
    "eye": ["H2510", "H2129", "H353233", "H4011X0", "S0510XA"],
    # MDC 3: ENT
    "ent": ["J069", "J189", "J441", "J4520", "H6692", "J0190", "C329", "K076"],
    # MDC 4: Respiratory
    "resp": ["J189", "J440", "J9600", "J8410", "J9311", "Z9981", "J9801", "J441"],
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
        "I5022",
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
    # MDC 12: Male-specific
    "male": ["N400", "C61", "N200"],
    # MDC 13: Female-specific
    "female": ["N8501", "N809", "C541"],
    # MDC 14: Pregnancy
    "pregnancy": ["O80", "O34219", "O26851", "O7021"],
    # MDC 15: Neonate
    "neonate": ["P0739", "P220", "Z3800", "P580"],
    # MDC 16: Blood
    "blood": ["D596", "D61818", "D6862", "D7589"],
    # MDC 17: Oncology
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

# Known severity classifications (for targeted MCC/CC generation)
MCC_DX_CODES = ["J189", "I2109", "I7100", "A419", "K7030", "R6520", "E1010", "I5022"]
CC_DX_CODES = ["I5020", "E1165", "N179", "F1327", "K810", "S52202H", "F320", "G40909"]
NONE_DX_CODES = ["I10", "Z951", "Z8673", "Z23", "Z4889", "Z5111", "D7589", "E785"]

# Sex-specific codes (for conflict testing)
FEMALE_ONLY_CODES = ["O80", "O34219", "O26851", "O7021", "N8501", "N809", "C541"]
MALE_ONLY_CODES = ["N400", "C61"]

# Age-specific codes (for conflict testing)
NEONATAL_CODES = ["P0739", "P220", "Z3800", "P580"]

# ---------------------------------------------------------------------------
# Procedure codes by category — curated for surgical/medical DRG coverage
# ---------------------------------------------------------------------------

PROC_CODES = {
    # Major cardiac surgery (surgical DRGs)
    "cardio_surg": ["02100Z6", "021609P", "02703DZ", "027034Z", "02703D6", "02703D7"],
    # Cardiac stenting (stent marking)
    "stent": ["02703DZ", "027034Z", "02713DZ", "027134Z", "02733DZ", "02733FZ"],
    # Joint replacement
    "joint": ["0SRB0JZ", "0SRD0JZ", "0SPD4JC", "0PHJ4BZ", "0SR90JZ"],
    # General surgery
    "general_surg": ["0DTJ0ZZ", "0DB68ZZ", "0DB78ZZ", "0DNJ4ZZ", "0DJD8ZZ", "0DTC4ZZ"],
    # Respiratory procedures
    "resp_proc": ["0B110F4", "0B113F4", "0B114F4", "0BH17EZ", "0BH18EZ"],
    # Neuro procedures
    "neuro_proc": ["00B60ZZ", "00B63ZZ", "00B64ZZ", "0016070", "0016370"],
    # Renal procedures
    "renal_proc": ["0TS10ZZ", "0TB10ZZ", "0TT10ZZ", "0TB14ZZ"],
    # Eye procedures
    "eye_proc": ["08BQ0ZZ", "08DQ0ZZ", "08CQ0ZZ"],
    # Non-OR procedures (medical DRGs)
    "non_or": ["B226Y0Z", "B311ZZZ", "BW20ZZZ", "4A023N7", "4A02X4G"],
    # Spinal fusion (surgical with fusion attributes)
    "spinal_fusion": ["0RG13J1", "0RG00AJ", "0SB10ZZ"],
    # ECMO/tracheostomy (MDC 0 special DRGs)
    "ecmo_trach": ["5A1522G", "0B110F4", "0B113F4"],
}

# Flatten all codes
ALL_DX_CODES = []
ALL_DX_CODE_SET = set()
for codes in DX_CODES.values():
    for c in codes:
        if c not in ALL_DX_CODE_SET:
            ALL_DX_CODES.append(c)
            ALL_DX_CODE_SET.add(c)

ALL_PROC_CODES = []
ALL_PROC_CODE_SET = set()
for codes in PROC_CODES.values():
    for c in codes:
        if c not in ALL_PROC_CODE_SET:
            ALL_PROC_CODES.append(c)
            ALL_PROC_CODE_SET.add(c)


def _pick_codes(pool: list, count: int, exclude: set) -> list:
    """Pick `count` codes from pool, excluding any in `exclude`."""
    available = [c for c in pool if c not in exclude]
    return random.sample(available, min(count, len(available)))


def _make_claim(
    idx,
    version,
    age,
    sex,
    discharge_status,
    hospital_status,
    pdx_code,
    pdx_poa,
    sdx_codes,
    proc_codes,
    admit_dx=None,
):
    """Build a claim dict from components."""
    claim = {
        "id": f"TEST-{idx + 1:04d}",
        "version": version,
        "discharge_date": GROUPERS[version]["discharge_date"],
        "age": age,
        "sex": sex,
        "discharge_status": discharge_status,
        "hospital_status": hospital_status,
        "length_of_stay": random.randint(1, 45),
        "pdx": {"code": pdx_code, "poa": pdx_poa},
        "sdx": [{"code": c, "poa": random.choice(POA_VALUES)} for c in sdx_codes],
        "procedures": [{"code": c} for c in proc_codes],
    }
    if admit_dx:
        claim["admit_dx"] = {"code": admit_dx, "poa": random.choice(POA_VALUES)}
    return claim


def _random_version():
    return random.choice(list(GROUPERS.keys()))


def generate_scenario_claims(start_idx: int, count: int) -> list[dict]:
    """Generate claims covering specific DRG formula scenarios."""
    claims = []
    idx = start_idx

    # --- Scenario 1: All discharge status formula branches ---
    # ALIVE (ds != 20)
    for _ in range(count):
        ds = random.choice(DS_ALIVE)
        hs = random.choices(HOSPITAL_STATUSES, weights=HOSPITAL_STATUS_WEIGHTS)[0]
        pdx = random.choice(ALL_DX_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                ds,
                hs,
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 5), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 5)),
                random.choice(ALL_DX_CODES) if random.random() < 0.3 else None,
            )
        )
        idx += 1

    # DIED (ds=20)
    for _ in range(count):
        pdx = random.choice(ALL_DX_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                20,
                random.choices(HOSPITAL_STATUSES, weights=HOSPITAL_STATUS_WEIGHTS)[0],
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 5), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 5)),
            )
        )
        idx += 1

    # AMA (ds=7)
    for _ in range(count):
        pdx = random.choice(ALL_DX_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                7,
                random.choices(HOSPITAL_STATUSES, weights=HOSPITAL_STATUS_WEIGHTS)[0],
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 5), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 5)),
            )
        )
        idx += 1

    # XFRNBA (transfer facilities: 2, 5, 66, 82, 85, 94)
    for _ in range(count):
        ds = random.choice(DS_XFRNBA)
        pdx = random.choice(ALL_DX_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                ds,
                random.choices(HOSPITAL_STATUSES, weights=HOSPITAL_STATUS_WEIGHTS)[0],
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 5), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 5)),
            )
        )
        idx += 1

    return claims


def generate_severity_claims(start_idx: int, count: int) -> list[dict]:
    """Generate claims that exercise MCC/CC/NONE severity branches."""
    claims = []
    idx = start_idx

    # MCC-only SDX (for MCC severity)
    for _ in range(count):
        pdx = random.choice(NONE_DX_CODES)
        sdx = _pick_codes(MCC_DX_CODES, random.randint(1, 3), {pdx})
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                1,
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                sdx,
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    # CC-only SDX (for CC severity, no MCC)
    for _ in range(count):
        pdx = random.choice(NONE_DX_CODES)
        sdx = _pick_codes(CC_DX_CODES, random.randint(1, 3), {pdx})
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                1,
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                sdx,
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    # NONE-only SDX (no MCC, no CC)
    for _ in range(count):
        pdx = random.choice(NONE_DX_CODES)
        sdx = _pick_codes(NONE_DX_CODES, random.randint(1, 3), {pdx})
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                1,
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                sdx,
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    return claims


def generate_surgical_claims(start_idx: int, count: int) -> list[dict]:
    """Generate claims that exercise surgical vs medical DRG paths."""
    claims = []
    idx = start_idx

    # Surgical claims (with OR procedures)
    for _ in range(count):
        pdx = random.choice(ALL_DX_CODES)
        proc_pool = random.choice(
            [
                PROC_CODES["cardio_surg"],
                PROC_CODES["joint"],
                PROC_CODES["general_surg"],
                PROC_CODES["neuro_proc"],
            ]
        )
        procs = random.sample(proc_pool, random.randint(1, min(4, len(proc_pool))))
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(18, 90),
                random.randint(0, 2),
                1,
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 3), {pdx}),
                procs,
            )
        )
        idx += 1

    # Medical claims (no procedures or non-OR only)
    for _ in range(count):
        pdx = random.choice(ALL_DX_CODES)
        procs = random.sample(PROC_CODES["non_or"], random.randint(0, 2))
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 124),
                random.randint(0, 2),
                1,
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 5), {pdx}),
                procs,
            )
        )
        idx += 1

    return claims


def generate_conflict_claims(start_idx: int, count: int) -> list[dict]:
    """Generate claims that exercise sex/age conflict paths."""
    claims = []
    idx = start_idx

    # Female codes with male patient (sex conflict)
    for _ in range(count):
        pdx = random.choice(FEMALE_ONLY_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(18, 80),
                0,  # Male
                random.choice(VALID_DISCHARGE_STATUSES),
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 3), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    # Male codes with female patient (sex conflict)
    for _ in range(count):
        pdx = random.choice(MALE_ONLY_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(18, 80),
                1,  # Female
                random.choice(VALID_DISCHARGE_STATUSES),
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 3), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    # Neonatal codes with adult age
    for _ in range(count):
        pdx = random.choice(NEONATAL_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(18, 80),
                random.randint(0, 2),
                random.choice(VALID_DISCHARGE_STATUSES),
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 3), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    # Neonatal codes with neonatal age (correct pairing)
    for _ in range(count):
        pdx = random.choice(NEONATAL_CODES)
        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(0, 3),
                random.randint(0, 2),
                random.choice(VALID_DISCHARGE_STATUSES),
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 5), {pdx}),
                random.sample(ALL_PROC_CODES, random.randint(0, 3)),
            )
        )
        idx += 1

    return claims


def generate_stent_claims(start_idx: int, count: int) -> list[dict]:
    """Generate claims with stent procedures for stent marking coverage."""
    claims = []
    idx = start_idx

    for _ in range(count):
        pdx = random.choice(ALL_DX_CODES)
        # 1-4 stent procedures
        num_stents = random.randint(1, 4)
        stent_procs = random.sample(
            PROC_CODES["stent"], min(num_stents, len(PROC_CODES["stent"]))
        )
        # Add non-stent procs
        other_procs = random.sample(ALL_PROC_CODES, random.randint(0, 2))
        procs = list(set(stent_procs + other_procs))

        claims.append(
            _make_claim(
                idx,
                _random_version(),
                random.randint(18, 80),
                random.randint(0, 2),
                1,
                "NOT_EXEMPT",
                pdx,
                random.choice(POA_VALUES),
                _pick_codes(ALL_DX_CODES, random.randint(0, 3), {pdx}),
                procs,
            )
        )
        idx += 1

    return claims


def generate_random_claims(start_idx: int, count: int) -> list[dict]:
    """Generate fully random claims for broad coverage."""
    claims = []
    idx = start_idx

    for _ in range(count):
        version = _random_version()
        age = random.randint(0, 124)
        sex = random.choice([0, 1, 2])
        ds = random.choice(VALID_DISCHARGE_STATUSES)
        hs = random.choices(HOSPITAL_STATUSES, weights=HOSPITAL_STATUS_WEIGHTS)[0]

        pdx = random.choice(ALL_DX_CODES)
        pdx_poa = random.choice(POA_VALUES)

        num_sdx = random.randint(0, 9)
        sdx = _pick_codes(ALL_DX_CODES, num_sdx, {pdx})

        num_proc = random.randint(0, 10)
        procs = random.sample(ALL_PROC_CODES, min(num_proc, len(ALL_PROC_CODES)))

        admit_dx = random.choice(ALL_DX_CODES) if random.random() < 0.3 else None

        claims.append(
            _make_claim(
                idx, version, age, sex, ds, hs, pdx, pdx_poa, sdx, procs, admit_dx
            )
        )
        idx += 1

    return claims


def generate_claims(count: int, output_file: str):
    """Generate a complete test claim set with targeted scenario coverage."""
    random.seed(42)  # Reproducible

    print(f"Generating {count} claims...")

    # Allocate: ~60% random, ~40% targeted scenarios
    total_scenario = count * 2 // 5  # 40% for scenarios
    per_category = total_scenario // 5  # 8% each
    random_count = count - total_scenario

    idx = 0
    all_claims = []

    # Discharge status formula branches (4 sub-types, split evenly)
    ds_per_type = per_category // 4
    c = generate_scenario_claims(idx, ds_per_type)
    all_claims.extend(c)
    idx += len(c)
    print(f"  Discharge status scenarios: {len(c)} claims")

    # Severity branches (MCC/CC/NONE, split evenly)
    sev_per_type = per_category // 3
    c = generate_severity_claims(idx, sev_per_type)
    all_claims.extend(c)
    idx += len(c)
    print(f"  Severity scenarios: {len(c)} claims")

    # Surgical vs medical (split evenly)
    surg_per_type = per_category // 2
    c = generate_surgical_claims(idx, surg_per_type)
    all_claims.extend(c)
    idx += len(c)
    print(f"  Surgical/medical scenarios: {len(c)} claims")

    # Sex/age conflicts (4 sub-types, split evenly)
    conf_per_type = per_category // 4
    c = generate_conflict_claims(idx, conf_per_type)
    all_claims.extend(c)
    idx += len(c)
    print(f"  Conflict scenarios: {len(c)} claims")

    # Stent procedures
    c = generate_stent_claims(idx, per_category)
    all_claims.extend(c)
    idx += len(c)
    print(f"  Stent scenarios: {len(c)} claims")

    # Random fill for remaining coverage
    c = generate_random_claims(idx, random_count)
    all_claims.extend(c)
    idx += len(c)
    print(f"  Random claims: {len(c)} claims")

    print(f"\n  Total: {len(all_claims)} claims")
    print(f"  {len(ALL_DX_CODES)} unique diagnosis codes across {len(DX_CODES)} MDCs")
    print(
        f"  {len(ALL_PROC_CODES)} unique procedure codes across {len(PROC_CODES)} categories"
    )
    print(f"  {len(GROUPERS)} grouper versions")
    print(f"  {len(VALID_DISCHARGE_STATUSES)} discharge status codes")
    print("  3 hospital statuses (EXEMPT, NOT_EXEMPT, UNKNOWN)")

    with open(output_file, "w") as f:
        json.dump(all_claims, f, indent=2)
    print(f"\nWrote {len(all_claims)} claims to {output_file}")


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
