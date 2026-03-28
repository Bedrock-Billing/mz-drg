# Installation

## From PyPI

=== "pip"

    ```bash
    pip install msdrg
    ```

=== "uv"

    ```bash
    uv add msdrg
    ```

Prebuilt wheels are available for:

| Platform | Architecture |
|----------|-------------|
| Linux | x86_64, aarch64 |
| macOS | x86_64, Apple Silicon (aarch64) |
| Windows | x86_64 |

!!! note
    Prebuilt wheels include the compiled Zig shared library — you do **not** need Zig installed to use `pip install msdrg`.

## From source

Building from source requires **Zig 0.16+** at build time. Install from [ziglang.org/download](https://ziglang.org/download/) and make sure `zig` is on your `PATH`.

```bash
git clone https://github.com/Bedrock-Billing/mz-drg.git
cd mz-drg

python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

Alternatively, set the `ZIG` environment variable to a custom path:

```bash
export ZIG=/path/to/zig
pip install -e .
```

## Verify installation

```bash
python -c "import msdrg; print(msdrg.__version__)"
# Expected: 0.1.3 (or current version)
```

```python
>>> import msdrg
>>> dir(msdrg)
['ClaimInput', 'DiagnosisInput', 'DiagnosisOutput', 'GroupResult',
 'MceDiagnosisInput', 'MceEditDetail', 'MceEditor', 'MceInput',
 'MceProcedureInput', 'MceResult', 'MsdrgGrouper', 'ProcedureInput',
 'ProcedureOutput', 'create_claim', 'create_mce_input', ...]
```

## Troubleshooting

??? question "ImportError: shared library not found"
    The prebuilt wheel may not exist for your platform. Install from source (requires Zig 0.16+):
    ```bash
    pip install msdrg --no-binary msdrg
    ```

??? question "Zig compilation fails during install"
    Make sure you have Zig **0.16 or newer**. Older versions are not compatible.
    ```bash
    zig version  # should be 0.16.x or higher
    ```

??? question "Data directory not found"
    The binary data files should be bundled with the package. If installing in development mode (`pip install -e .`), verify that `data/bin/` exists and contains `.bin` files.
