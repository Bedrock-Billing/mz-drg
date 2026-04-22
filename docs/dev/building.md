# Building from Source

## Prerequisites

- **Zig 0.16+** — [download](https://ziglang.org/download/)
- **Python 3.11+**
- **uv** (recommended) or **pip**

## Setup

=== "uv"

    ```bash
    git clone https://github.com/Bedrock-Billing/mz-drg.git
    cd mz-drg

    uv venv
    source .venv/bin/activate
    uv pip install -e ".[dev]"
    ```

=== "pip"

    ```bash
    git clone https://github.com/Bedrock-Billing/mz-drg.git
    cd mz-drg

    python3 -m venv .venv
    source .venv/bin/activate
    pip install -e ".[dev]"
    ```

This compiles the Zig shared library and bundles the data files into the Python package.

## Run tests

```bash
# Zig unit tests (60+ tests)
cd zig_src && zig build test

# Python tests
python -m pytest tests/ -v
```

## Build wheels

```bash
# All platforms
python scripts/build_wheels.py

# Specific target
python scripts/build_wheels.py x86_64-linux
```

See [Cross-Compilation](cross-compilation.md) for the full list of supported targets.

## Project structure

```
mz-drg/
├── msdrg/                       # Python package
│   ├── __init__.py              # Public API exports
│   ├── grouper.py               # MsdrgGrouper class
│   └── mce.py                   # MceEditor class
├── zig_src/                     # Zig source
│   ├── build.zig
│   └── src/
│       ├── c_api.zig            # MS-DRG C ABI exports
│       ├── json_api.zig         # MS-DRG JSON serialization
│       ├── msdrg.zig            # GrouperChain + version routing
│       ├── chain.zig            # Composable processor chain
│       ├── mce.zig              # MCE main editor
│       ├── mce_c_api.zig        # MCE C ABI exports
│       └── ...                  # Additional modules
├── data/                        # Consolidated LMDB database (msdrg.mdb)
├── scripts/                     # Data extraction & compilation
├── tests/                       # Comparison & benchmark tools
├── docs/                        # Documentation (MkDocs)
├── pyproject.toml
└── setup.py
```
