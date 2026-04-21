# Data Pipeline

The library uses a single, high-performance LMDB database (`msdrg.mdb`) to store all reference data. This provides zero-copy binary access and sub-microsecond lookups while keeping the memory footprint minimal.

## Regenerate from raw CMS data

```bash
bash scripts/setup_data.sh
```

This script extracts raw data from CMS CSV files, imports it into a temporary SQLite database for normalization, compiles it into optimized binary blobs, and finally packages everything into the monolithic `msdrg.mdb` file.

## Individual steps

```bash
# 1. Extract and normalize raw data
python scripts/extract_data.py

# 2. Import to SQLite for processing
python scripts/import_to_sqlite.py

# 3. Compile optimized binary blobs
for s in scripts/compile*; do bash "$s"; done

# 4. Consolidate into LMDB database
python scripts/package_lmdb.py
```

## Database Contents

The `msdrg.mdb` file contains various data structures used by the grouper and MCE:

| Category | Description |
|------|----------|
| **Core** | Diagnosis definitions, DRG formula rules, MDC mappings |
| **Grouping** | Diagnosis clusters, exclusion groups, gender/MDC rules |
| **MCE** | ICD-10 DX/SG master tables, age ranges, discharge status |
| **Conversion** | ICD-10-CM/PCS version-to-version conversion tables |

!!! tip
    The database is opened in read-only mode with no locking (`MDB_NOLOCK`), making it extremely fast for concurrent analytical workloads across multiple threads.

