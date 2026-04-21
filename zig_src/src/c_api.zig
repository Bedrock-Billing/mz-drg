const std = @import("std");
const msdrg = @import("msdrg.zig");
const json_api = @import("json_api.zig");

// MCE module — comptime reference forces export functions into shared library
const mce_c_api = @import("mce_c_api.zig");

// --- Thread Safety ---
// This C API is designed for thread-safe concurrent access:
//
// After msdrg_context_init() completes, the MsdrgContext is immutable and can be
// safely shared across multiple threads. The following functions are thread-safe
// and can be called concurrently without external locking:
//   - msdrg_group_json()
//
// NOT thread-safe (call only from main thread):
//   - msdrg_context_init()
//   - msdrg_context_free()

// --- Allocator ---
// Use C allocator (malloc/free) for shared library:
// - C callers expect malloc/free semantics
// - Mixing allocators across FFI boundaries causes crashes
// - malloc is thread-safe on all major platforms
const allocator = std.heap.c_allocator;

// --- Opaque Types for C ---
pub const MsdrgContext = opaque {};

// --- Context Management ---

export fn msdrg_context_init(data_path: [*c]const u8) ?*MsdrgContext {
    if (data_path == null) return null;

    const path_slice = std.mem.span(data_path);

    const ctx = allocator.create(msdrg.GrouperChain) catch return null;
    ctx.* = msdrg.GrouperChain.init(allocator, path_slice) catch {
        allocator.destroy(ctx);
        return null;
    };

    // Initialize pre-built links now that the struct is in its final heap location
    ctx.initLinks() catch {
        ctx.deinit();
        allocator.destroy(ctx);
        return null;
    };

    return @ptrCast(ctx);
}

export fn msdrg_context_free(ctx: ?*MsdrgContext) void {
    if (ctx) |c| {
        const self = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(c)));
        self.deinit();
        allocator.destroy(self);
    }
}

export fn msdrg_string_free(s: [*c]const u8) void {
    if (s) |ptr| {
        const len = std.mem.len(ptr);
        const slice = ptr[0 .. len + 1];
        allocator.free(slice);
    }
}

// --- JSON API ---

export fn msdrg_group_json(ctx: *MsdrgContext, json_str: [*c]const u8) [*c]const u8 {
    if (json_str == null) return null;

    const chain_ptr = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));
    const json_slice = std.mem.span(json_str);

    // Use allocPrintZ to allocate with null terminator in one shot
    const result_json = json_api.processJson(allocator, chain_ptr, json_slice) catch return null;
    return result_json.ptr;
}

// --- ICD-10 Code Conversion ---

export fn msdrg_convert_dx(ctx: *MsdrgContext, code: [*c]const u8, source_year: u32, target_year: u32) [*c]const u8 {
    if (code == null) return null;
    const chain_ptr = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));
    const code_slice = std.mem.span(code);

    const converted = chain_ptr.convertDxCode(code_slice, source_year, target_year, allocator) catch return null;
    if (converted) |c| return c.ptr;
    return null;
}

export fn msdrg_convert_pr(ctx: *MsdrgContext, code: [*c]const u8, source_year: u32, target_year: u32) [*c]const u8 {
    if (code == null) return null;
    const chain_ptr = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));
    const code_slice = std.mem.span(code);

    const converted = chain_ptr.convertPrCode(code_slice, source_year, target_year, allocator) catch return null;
    if (converted) |c| return c.ptr;
    return null;
}

// --- Tests ---

test "msdrg_context_init null data_dir" {
    const result = msdrg_context_init(null);
    try std.testing.expectEqual(@as(?*MsdrgContext, null), result);
}

test "msdrg_context_free null context" {
    // Should not crash
    msdrg_context_free(null);
}

test "msdrg_group_json null json_str" {
    // Create a minimal context — this test needs data files so skip if not available
    const ctx = msdrg_context_init("../data/msdrg.mdb") orelse return error.SkipZigTest;
    defer msdrg_context_free(ctx);

    const result = msdrg_group_json(ctx, null);
    try std.testing.expectEqual(@as([*c]const u8, null), result);
}

// --- MCE Symbol Anchors ---
// These comptime references force the MCE export functions to be included
// in the shared library. Without them, zig's dead code elimination strips
// the export functions from mce_c_api.zig since they're in a separate module.

comptime {
    _ = mce_c_api.mce_context_init;
    _ = mce_c_api.mce_context_free;
    _ = mce_c_api.mce_edit_json;
}
