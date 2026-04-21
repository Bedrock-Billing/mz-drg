# Testing

## Zig tests

```bash
cd zig_src && zig build test
```

Covers unit tests for all modules: data structures, enums, validation, editing, grouping, MCE pipeline. (~70 tests).

## Python tests

```bash
python -m pytest tests/test_grouper.py tests/test_mce.py tests/test_icd_conversions.py -v
```

Covers MS-DRG grouping, MCE editing, ICD-10 conversion, lifecycle, edge cases, and error handling.

## Comparison testing

```bash
# Compare MS-DRG against Java reference
python tests/compare_groupers.py --file tests/test_claims.json

# Compare MCE against Java reference
python tests/compare_mce.py --file tests/test_claims.json
```

Requires JDK 17+ and reference JARs in `jars/`.
