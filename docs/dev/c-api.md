# C API

The shared library exposes a C ABI for integration with any language that supports foreign function calls.

## Function signatures

| Function | Signature | Description |
|----------|-----------|-------------|
| `msdrg_context_init` | `void*(const char* data_dir)` | Create a grouper context |
| `msdrg_group_json` | `const char*(void* ctx, const char* json)` | Group a claim (JSON in → JSON out) |
| `msdrg_context_free` | `void(void* ctx)` | Free a grouper context |
| `mce_context_init` | `void*(const char* data_dir)` | Create an MCE context |
| `mce_edit_json` | `const char*(void* ctx, const char* json)` | Run MCE (JSON in → JSON out) |
| `mce_context_free` | `void(void* ctx)` | Free an MCE context |
| `msdrg_string_free` | `void(const char* str)` | Free a returned JSON string |

## MS-DRG Grouper

```c
#include <stdio.h>

// Initialize context with path to binary data directory
void* ctx = msdrg_context_init("/path/to/data");
if (!ctx) {
    fprintf(stderr, "Failed to initialize grouper\n");
    return 1;
}

// Group a claim (JSON in, JSON out)
const char* result = msdrg_group_json(ctx, "{\"version\":431,\"age\":65,\"sex\":0,\"discharge_status\":1,\"pdx\":{\"code\":\"I5020\"},\"sdx\":[],\"procedures\":[]}");
printf("%s\n", result);

// Free the returned string, then the context
msdrg_string_free(result);
msdrg_context_free(ctx);
```

## MCE Editor

```c
// Initialize MCE context (same data directory)
void* mce = mce_context_init("/path/to/data");
if (!mce) {
    fprintf(stderr, "Failed to initialize MCE\n");
    return 1;
}

// Edit a claim
const char* result = mce_edit_json(mce, "{\"discharge_date\":20250101,\"age\":65,\"sex\":0,\"discharge_status\":1,\"pdx\":{\"code\":\"I5020\"},\"sdx\":[],\"procedures\":[]}");
printf("%s\n", result);

// Free
msdrg_string_free(result);
mce_context_free(mce);
```

## Error handling

- `msdrg_context_init` / `mce_context_init` return `NULL` if the data directory is invalid or data files cannot be loaded.
- `msdrg_group_json` / `mce_edit_json` return `NULL` if the input JSON is malformed or processing fails.
- Always check for `NULL` before using the returned string.

## Thread safety

Contexts are immutable after initialization and safe to share across threads. Each call to `msdrg_group_json` / `mce_edit_json` is independently thread-safe — no external locking is required.

!!! tip
    Both contexts can coexist in the same process and share the same shared library. Initialize once, call from any thread.
