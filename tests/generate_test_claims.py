import csv
import random
import json

# Configuration
NUM_CLAIMS = 50_000
TARGET_VERSION = 431
OUTPUT_FILE = "test_claims.json"
DX_FILE = "data/csv/diagnosisAll.csv"
PROC_FILE = "data/csv/procedureAttributes.csv"

def load_codes(filepath, target_version):
    codes = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            v_start = int(row['version_start'])
            v_end = int(row['version_end'])
            if v_start <= target_version <= v_end:
                codes.append(row['key'])
    return codes

def generate_claims():
    print(f"Loading codes from {DX_FILE}...")
    dx_codes = load_codes(DX_FILE, TARGET_VERSION)
    print(f"Loaded {len(dx_codes)} diagnosis codes.")

    print(f"Loading codes from {PROC_FILE}...")
    proc_codes = load_codes(PROC_FILE, TARGET_VERSION)
    print(f"Loaded {len(proc_codes)} procedure codes.")

    claims = []
    for i in range(NUM_CLAIMS):
        # Randomize claim parameters
        age = random.randint(0, 124)
        sex = random.choice([0, 1]) # 0: Male, 1: Female
        discharge_status = random.choice([1, 2, 3, 4, 5, 6, 7, 20, 30, 40, 41, 42, 43, 50, 51, 61, 62, 63, 64, 65, 66, 70]) 
        # Note: Discharge status 1 is Home, 20 is Died. Using a subset of common ones or valid ones from the Enum list we saw earlier.
        discharge_status = random.choice([1, 20])

        # Randomize Codes
        num_sdx = random.randint(0, 9) # 1 PDX + 0-9 SDX = 1-10 DX
        num_proc = random.randint(0, 10)

        pdx_code = random.choice(dx_codes)
        sdx_codes = random.sample(dx_codes, num_sdx)
        poa_codes = [random.choice(["Y", "N"]) for _ in range(num_sdx)]
        selected_procs = random.sample(proc_codes, num_proc)

        claim = {
            'id': f"TEST-{i+1:04d}",
            'version': TARGET_VERSION,
            'age': age,
            'sex': sex,
            'discharge_status': discharge_status,
            'pdx': {'code': pdx_code, "poa": "Y"},
            'sdx': [{'code': c, "poa": poa_codes[i]} for i, c in enumerate(sdx_codes)],
            'procedures': [{'code': c} for c in selected_procs]
        }
        claims.append(claim)

    print(f"Generating {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(claims, f, indent=2)
    print("Done.")

if __name__ == "__main__":
    generate_claims()
