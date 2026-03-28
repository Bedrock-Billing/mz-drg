# Data Pipeline

Binary data files in `data/bin/` are precompiled and included in the repo.

## Regenerate from raw CMS data

```bash
bash scripts/setup_data.sh
```

## Individual steps

```bash
# Extract and normalize raw data
python scripts/extract_data.py

# Import to SQLite
python scripts/import_to_sqlite.py

# Compile to binary
for s in scripts/compile*; do bash "$s"; done

# MCE data
python scripts/extract_mce_data.py
python scripts/compile_mce_data.py
```

## Data files

| File | Contents |
|------|----------|
| `diagnosis.bin` | Diagnosis code definitions |
| `drg_formulas.bin` | DRG formula rules |
| `cluster_*.bin` | Diagnosis cluster mappings |
| `exclusion_*.bin` | Exclusion groups |
| `mce_i10dx_master.bin` | ICD-10 diagnosis master |
| `mce_i10sg_master.bin` | ICD-10 procedure master |
| `mce_age_ranges.bin` | Age range definitions |
