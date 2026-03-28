# Cross-Compilation

Zig cross-compiles all platforms from a single machine.

## Build for target

```bash
# Linux x86_64 (default)
zig build

# Windows
zig build -Dtarget=x86_64-windows-gnu

# macOS ARM
zig build -Dtarget=aarch64-macos-none

# macOS x86_64
zig build -Dtarget=x86_64-macos-none

# Linux ARM
zig build -Dtarget=aarch64-linux-gnu
```

## Build all wheels

```bash
python scripts/build_wheels.py
```

## Supported targets

| Target | Output |
|--------|--------|
| `x86_64-linux-gnu` | `libmsdrg.so` |
| `aarch64-linux-gnu` | `libmsdrg.so` |
| `x86_64-windows-gnu` | `msdrg.dll` |
| `x86_64-macos-none` | `libmsdrg.dylib` |
| `aarch64-macos-none` | `libmsdrg.dylib` |
