const std = @import("std");
const builtin = @import("builtin");
const mce = @import("mce.zig");
const mce_json_api = @import("mce_json_api.zig");

// Use c_allocator when linking libc (shared library), page_allocator otherwise (tests)
const mce_allocator = if (builtin.link_libc) std.heap.c_allocator else std.heap.page_allocator;

// --- Opaque Types ---

pub const MceContext = opaque {};

// --- Context Management ---

pub export fn mce_context_init(data_path: [*c]const u8) ?*MceContext {
    if (data_path == null) return null;

    const path_slice = std.mem.span(data_path);

    const ctx = mce_allocator.create(mce.MceComponent) catch return null;
    ctx.* = mce.MceComponent.init(path_slice, mce_allocator) catch {
        mce_allocator.destroy(ctx);
        return null;
    };

    return @ptrCast(ctx);
}

pub export fn mce_context_free(ctx: ?*MceContext) void {
    if (ctx) |c| {
        const self = @as(*mce.MceComponent, @ptrCast(@alignCast(c)));
        self.deinit();
        mce_allocator.destroy(self);
    }
}

// --- JSON API ---

pub export fn mce_edit_json(ctx: ?*MceContext, json_str: [*c]const u8) [*c]const u8 {
    if (ctx == null or json_str == null) return null;

    const comp = @as(*mce.MceComponent, @ptrCast(@alignCast(ctx.?)));
    const json_slice = std.mem.span(json_str);

    const result_json = mce_json_api.processMceJson(mce_allocator, comp, json_slice) catch return null;
    defer mce_allocator.free(result_json);

    // Allocate null-terminated copy
    const terminated = mce_allocator.allocSentinel(u8, result_json.len, 0) catch return null;
    @memcpy(terminated, result_json);

    return terminated.ptr;
}

// --- Thread Safety ---
// MceContext is thread-safe after initialization and can be safely shared
// across multiple threads. This matches the MsdrgContext behavior.

// --- Tests ---

test "mce_context_init null data_dir" {
    const result = mce_context_init(null);
    try std.testing.expectEqual(@as(?*MceContext, null), result);
}

test "mce_context_free null context" {
    mce_context_free(null); // Should not crash
}

test "mce_edit_json null inputs" {
    try std.testing.expectEqual(@as([*c]const u8, null), mce_edit_json(null, null));

    const data_path = "../data/msdrg.mdb";
    const ctx = mce_context_init(data_path.ptr) orelse return;
    defer mce_context_free(ctx);

    try std.testing.expectEqual(@as([*c]const u8, null), mce_edit_json(ctx, null));
}

test "mce_context_init and edit valid claim" {
    const data_path = "../data/msdrg.mdb";
    const ctx = mce_context_init(data_path.ptr) orelse return;
    defer mce_context_free(ctx);

    const json_input = "{\"age\":65,\"sex\":0,\"discharge_status\":1,\"discharge_date\":20250101,\"pdx\":{\"code\":\"I5020\"},\"sdx\":[],\"procedures\":[]}";

    const result_ptr = mce_edit_json(ctx, json_input);
    try std.testing.expect(result_ptr != null);
    defer mce_allocator.free(result_ptr[0 .. std.mem.len(result_ptr) + 1]);
}
