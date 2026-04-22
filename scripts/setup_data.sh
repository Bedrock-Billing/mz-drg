#!/usr/bin/env bash
set -euo pipefail

# Convenience script to run data extraction, import, compile scripts, and build Zig
# Usage: bash scripts/setup_data.sh
# Optionally set PYTHON env var to point to a specific python executable.

PYTHON=${PYTHON:-python3}
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"

echo "Repository root: $REPO_ROOT"
echo "Using Python: $PYTHON"

cd "$REPO_ROOT"

if [ -f .venv/bin/activate ]; then
  echo "Activating virtualenv at .venv"
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

echo "Running data extraction"
$PYTHON scripts/extract_data.py

echo "Importing data to sqlite"
$PYTHON scripts/import_to_sqlite.py

echo "Running compile scripts"
for s in scripts/compile*; do
  if [ -f "$s" ]; then
    echo "-> $s"
    $PYTHON "$s"
  fi
done

echo "Building Zig library"
cd zig_src
zig build
cd "$REPO_ROOT"

echo "Packaging reference data into LMDB"
$PYTHON scripts/package_lmdb.py

echo "Done. LMDB database created at data/msdrg.mdb."
