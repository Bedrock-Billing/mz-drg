# MS-DRG Grouper (Java ↔ Zig)

Overview
--------

This repository contains a Zig port of the CMS MS-DRG grouper (decompiled from the original Java implementation), supporting tools for preparing data, a Python wrapper for interacting with the Zig library, and test/benchmark utilities to compare the Zig and Java groupers.

Key features
- Zig implementation of MS-DRG grouping logic.
- Python wrapper for the Zig library (`python_client/msdrg.py`).
- Scripts to extract and compile data into binary forms used by the Zig grouper.
- Test and compare utilities in `tests/` for functional comparison and benchmarking vs the Java grouper.

Requirements
------------

- Python 3.10 or greater. Recommended: create a Python virtual environment (venv).
- Java 17 or greater (only required if you will run comparisons against the Java grouper).
- Zig (tested with): `0.16.0-dev.1225+bf9082518`.
- Python dependencies are listed in `requirements.txt` (e.g. `jpype1`, `packaging`).

Quick setup
-----------

1. Create and activate a Python venv and install dependencies:

```bash
# from repository root
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Verify Java (if you will run the Java grouper):

```bash
java -version
# If needed:
export JAVA_HOME=/path/to/java17
```

Data preparation (required for the Zig grouper)
---------------------------------------------

The Zig grouper requires binary data files that are generated from the CSV data in the `data/` directory. Run the following sequence from the repository root to create those files (order matters):

1. Run the extraction script to normalize/prepare raw data:

```bash
python scripts/extract_data.py
```

2. Import data into the local SQLite representations used by compile scripts:

```bash
python scripts/import_to_sqlite.py
```

3. Run the compile scripts to transform CSV/DB data into the binary blobs expected by the Zig grouper:

```bash
for s in scripts/compile*; do
	bash "$s"
done
```

Notes: these steps should populate `data/bin/` (and possibly other `data/` subfolders) with the binary artifacts used by the Zig grouper.

Convenience script
------------------

You can run all of the data-prep steps and the Zig build using the convenience script:

```bash
# run via bash (recommended)
bash scripts/setup_data.sh

# or make it executable and run directly
chmod +x scripts/setup_data.sh
./scripts/setup_data.sh
```

The script will try to activate `.venv` if it exists and will use the `PYTHON` environment variable if provided (for example `PYTHON=/usr/bin/python3.11 bash scripts/setup_data.sh`).


Build the Zig library
---------------------

From the repo root:

```bash
cd zig_src
zig build
cd -
```

After a successful build the Zig artifacts will be placed under `zig_src/zig-out/` (for example, the shared library the Python wrapper uses is typically under `zig_src/zig-out/lib/`).

Python wrapper and usage
------------------------

- The Python wrapper for the Zig library lives at `python_client/msdrg.py`. It provides a convenient wrapper class to load the Zig library and call the grouper from Python test harnesses.
- The `tests/compare_groupers.py` script runs claims through both the Java and Zig groupers and compares outputs (or runs benchmarks when requested).

Generating test claims and running comparisons
--------------------------------------------

Generate test claims (optional):

```bash
.venv/bin/python tests/generate_test_claims.py --count 100 --out tests/test_claims.json
```

Compare Java vs Zig using a claims file (example):

```bash
.venv/bin/python tests/compare_groupers.py --file tests/test_claims.json
```

Run the benchmark mode:

```bash
.venv/bin/python tests/compare_groupers.py --file tests/test_claims.json --benchmark
```

Example: run a single compare using the venv Python

```bash
.venv/bin/python ./tests/compare_groupers.py --file ./tests/test_claims.json
```

Troubleshooting
---------------

- Zig build issues: ensure you have the Zig version tested above or a compatible release. Check `zig build` output and confirm binaries exist under `zig_src/zig-out/`.
- Java errors launching the JVM: verify Java 17+ is installed and `JAVA_HOME` (or PATH) points to it, and that `jars/` contains the Java artifacts used by the comparison script.
- Missing data: if the Zig grouper fails because of missing data files, re-run the extraction/import/compile sequence.

Repository layout (important locations)
-------------------------------------

- `zig_src/` — Zig sources and `zig build` project.
- `python_client/` — Python wrapper for the Zig library (`msdrg.py`) and a small Python test harness.
- `jars/` — Java artifacts used to run the Java grouper for comparison.
- `data/` — CSVs and compiled binary data. `data/bin/` is used by the Zig grouper after running the scripts.
- `scripts/` — Data extraction, import, and compile scripts.
- `tests/` — `generate_test_claims.py` and `compare_groupers.py` for testing and comparison.

Recommended next steps / improvements
-----------------------------------

- Add a convenience script (e.g. `scripts/setup_data.sh`) to run: `extract_data.py`, `import_to_sqlite.py`, all `compile*` scripts, and `zig build`.
- Add CI workflow that runs the data setup and `tests/compare_groupers.py` (benchmark or a small functional check) on a runner with Java and Zig installed.
- Add a `LICENSE` file if you plan to publish the repository.


License
-------

This project is licensed under the MIT License — see `LICENSE` in the repository root.

If you want, I can add a small `scripts/setup_data.sh` convenience script to the repo that automates the extract → import → compile → zig build sequence. Would you like me to add that now?
