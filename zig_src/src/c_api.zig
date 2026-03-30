const std = @import("std");
const msdrg = @import("msdrg.zig");
const models = @import("models.zig");
const common = @import("common.zig");
const chain = @import("chain.zig");
const json_api = @import("json_api.zig");

// MCE module — import ensures MCE export functions are included in the shared library
const mce_c_api = @import("mce_c_api.zig");
const mce_json_api = @import("mce_json_api.zig");
const mce = @import("mce.zig");
const mce_data = @import("mce_data.zig");
const mce_enums = @import("mce_enums.zig");
const mce_validation = @import("mce_validation.zig");
const mce_editing = @import("mce_editing.zig");

// --- Thread Safety ---
// This C API is designed for thread-safe concurrent access:
//
// After msdrg_context_init() completes, the MsdrgContext is immutable and can be
// safely shared across multiple threads. The following functions are thread-safe
// and can be called concurrently without external locking:
//   - msdrg_group_json()
//   - msdrg_group()
//
// The msdrg_version_create/msdrg_input_create API are also thread-safe, but each
// thread should create its own MsdrgVersion and MsdrgInput instances.
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
pub const MsdrgVersion = opaque {};
pub const MsdrgInput = opaque {};
pub const MsdrgResult = opaque {};

// --- Context Management ---

export fn msdrg_context_init(data_dir: [*c]const u8) ?*MsdrgContext {
    if (data_dir == null) return null;

    const dir_slice = std.mem.span(data_dir);

    const ctx = allocator.create(msdrg.GrouperChain) catch return null;
    ctx.* = msdrg.GrouperChain.init(allocator, dir_slice) catch {
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

// --- Version Management ---

export fn msdrg_version_create(ctx: *MsdrgContext, version: i32) ?*MsdrgVersion {
    const self = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));

    const link_ptr = allocator.create(chain.Link) catch return null;
    link_ptr.* = self.create(version) catch {
        allocator.destroy(link_ptr);
        return null;
    };

    return @ptrCast(link_ptr);
}

export fn msdrg_version_free(ver: ?*MsdrgVersion) void {
    if (ver) |v| {
        const link = @as(*chain.Link, @ptrCast(@alignCast(v)));
        link.deinit(allocator);
        allocator.destroy(link);
    }
}

// --- Input Management ---

const InputWrapper = struct {
    data: models.ProcessingData,
    hospital_status: models.HospitalStatusOptionFlag = .NOT_EXEMPT,
};

export fn msdrg_input_create() ?*MsdrgInput {
    const wrapper = allocator.create(InputWrapper) catch return null;
    wrapper.data = models.ProcessingData.init(allocator);
    wrapper.hospital_status = .NOT_EXEMPT;
    return @ptrCast(wrapper);
}

export fn msdrg_input_free(input: ?*MsdrgInput) void {
    if (input) |i| {
        const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(i)));
        wrapper.data.deinit();
        allocator.destroy(wrapper);
    }
}

export fn msdrg_input_set_pdx(input: *MsdrgInput, code: [*c]const u8, poa: u8) bool {
    if (code == null) return false;
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const dx = models.DiagnosisCode.init(code_slice, poa) catch return false;

    if (wrapper.data.principal_dx) |*old| {
        old.deinit(allocator);
    }
    wrapper.data.principal_dx = dx;
    return true;
}

export fn msdrg_input_set_admit_dx(input: *MsdrgInput, code: [*c]const u8, poa: u8) bool {
    if (code == null) return false;
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const dx = models.DiagnosisCode.init(code_slice, poa) catch return false;

    if (wrapper.data.admit_dx) |*old| {
        old.deinit(allocator);
    }
    wrapper.data.admit_dx = dx;
    return true;
}

export fn msdrg_input_add_sdx(input: *MsdrgInput, code: [*c]const u8, poa: u8) bool {
    if (code == null) return false;
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const dx = models.DiagnosisCode.init(code_slice, poa) catch return false;
    wrapper.data.sdx_codes.append(allocator, dx) catch return false;
    return true;
}

export fn msdrg_input_add_procedure(input: *MsdrgInput, code: [*c]const u8) bool {
    if (code == null) return false;
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const proc = models.ProcedureCode.init(code_slice) catch return false;
    wrapper.data.procedure_codes.append(allocator, proc) catch return false;
    return true;
}

export fn msdrg_input_set_demographics(input: *MsdrgInput, age: i32, sex: i32, discharge_status: i32) void {
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    wrapper.data.age = age;

    // Safely convert integers to enums — invalid values get a default
    wrapper.data.sex = intToSex(sex);
    wrapper.data.discharge_status = intToDischargeStatus(discharge_status);
}

fn intToSex(v: i32) models.Sex {
    inline for (std.meta.fields(models.Sex)) |f| {
        if (v == f.value) return @enumFromInt(f.value);
    }
    return .UNKNOWN;
}

fn intToDischargeStatus(v: i32) models.DischargeStatus {
    inline for (std.meta.fields(models.DischargeStatus)) |f| {
        if (v == f.value) return @enumFromInt(f.value);
    }
    return .NONE;
}

// --- Execution ---

const ResultWrapper = struct {
    context: models.ProcessingContext,
    arena: std.heap.ArenaAllocator,
};

export fn msdrg_group(ver: *MsdrgVersion, input: *MsdrgInput) ?*MsdrgResult {
    const link = @as(*chain.Link, @ptrCast(@alignCast(ver)));
    const input_wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));

    const context = models.ProcessingContext.init(allocator, &input_wrapper.data, .{
        .poa_reporting_exempt = input_wrapper.hospital_status,
    });

    const result = link.execute(context) catch return null;

    const res_wrapper = allocator.create(ResultWrapper) catch return null;
    res_wrapper.context = result.context;
    res_wrapper.arena = std.heap.ArenaAllocator.init(allocator);

    return @ptrCast(res_wrapper);
}

// --- Result Access ---

export fn msdrg_result_free(res: ?*MsdrgResult) void {
    if (res) |r| {
        const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(r)));
        wrapper.arena.deinit();
        wrapper.context.deinit();
        allocator.destroy(wrapper);
    }
}

export fn msdrg_result_get_initial_drg(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return wrapper.context.data.initial_result.drg orelse -1;
}

export fn msdrg_result_get_final_drg(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return wrapper.context.data.final_result.drg orelse -1;
}

export fn msdrg_result_get_initial_mdc(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return wrapper.context.data.initial_result.mdc orelse -1;
}

export fn msdrg_result_get_final_mdc(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return wrapper.context.data.final_result.mdc orelse -1;
}

export fn msdrg_result_get_return_code(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return @intFromEnum(wrapper.context.data.final_result.return_code);
}

export fn msdrg_result_get_return_code_name(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return @tagName(wrapper.context.data.final_result.return_code);
}

// --- Result Description Getters ---
// Returned strings are owned by the result and valid until msdrg_result_free.

export fn msdrg_result_get_initial_drg_description(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.initial_result.drg_description) |desc| return desc.ptr;
    return "";
}

export fn msdrg_result_get_final_drg_description(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.final_result.drg_description) |desc| return desc.ptr;
    return "";
}

export fn msdrg_result_get_initial_mdc_description(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.initial_result.mdc_description) |desc| return desc.ptr;
    return "";
}

export fn msdrg_result_get_final_mdc_description(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.final_result.mdc_description) |desc| return desc.ptr;
    return "";
}

// --- Per-Code Output Getters ---
// Returned strings are owned by the result and valid until msdrg_result_free.

export fn msdrg_result_get_sdx_count(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return @intCast(wrapper.context.data.sdx_codes.items.len);
}

export fn msdrg_result_get_sdx_code(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.sdx_codes.items.len) return "";
    return codeStr(wrapper.arena.allocator(), wrapper.context.data.sdx_codes.items[idx].value);
}

export fn msdrg_result_get_sdx_mdc(res: *MsdrgResult, index: i32) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.sdx_codes.items.len) return -1;
    return wrapper.context.data.sdx_codes.items[idx].mdc orelse -1;
}

export fn msdrg_result_get_sdx_severity(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.sdx_codes.items.len) return "";
    return @tagName(wrapper.context.data.sdx_codes.items[idx].severity);
}

export fn msdrg_result_get_sdx_drg_impact(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.sdx_codes.items.len) return "";
    return @tagName(wrapper.context.data.sdx_codes.items[idx].drg_impact);
}

export fn msdrg_result_get_sdx_poa_error(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.sdx_codes.items.len) return "";
    return @tagName(wrapper.context.data.sdx_codes.items[idx].poa_error_code_flag);
}

export fn msdrg_result_get_proc_count(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return @intCast(wrapper.context.data.procedure_codes.items.len);
}

export fn msdrg_result_get_proc_code(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.procedure_codes.items.len) return "";
    return codeStr(wrapper.arena.allocator(), wrapper.context.data.procedure_codes.items[idx].value);
}

export fn msdrg_result_get_proc_is_or(res: *MsdrgResult, index: i32) bool {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.procedure_codes.items.len) return false;
    return wrapper.context.data.procedure_codes.items[idx].is_operating_room;
}

export fn msdrg_result_get_proc_drg_impact(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.procedure_codes.items.len) return "";
    return @tagName(wrapper.context.data.procedure_codes.items[idx].drg_impact);
}

export fn msdrg_result_get_proc_is_valid(res: *MsdrgResult, index: i32) bool {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.procedure_codes.items.len) return false;
    return wrapper.context.data.procedure_codes.items[idx].is_valid_code;
}

// --- PDX Output Getters ---

export fn msdrg_result_has_pdx(res: *MsdrgResult) bool {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    return wrapper.context.data.principal_dx != null;
}

export fn msdrg_result_get_pdx_code(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.principal_dx) |pdx| return codeStr(wrapper.arena.allocator(), pdx.value);
    return "";
}

export fn msdrg_result_get_pdx_mdc(res: *MsdrgResult) i32 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.principal_dx) |pdx| return pdx.mdc orelse -1;
    return -1;
}

export fn msdrg_result_get_pdx_severity(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.principal_dx) |pdx| return @tagName(pdx.severity);
    return "";
}

export fn msdrg_result_get_pdx_drg_impact(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.principal_dx) |pdx| return @tagName(pdx.drg_impact);
    return "";
}

export fn msdrg_result_get_pdx_poa_error(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.principal_dx) |pdx| return @tagName(pdx.poa_error_code_flag);
    return "";
}

// --- Flag Getters ---
// Returns comma-separated active flag names (e.g. "VALID,MARKED_FOR_INITIAL").
// Memory is allocated with the result and freed with msdrg_result_free.

fn codeStr(arena: std.mem.Allocator, code: common.Code) [*c]const u8 {
    const slice = code.toSlice();
    const copy = arena.allocSentinel(u8, slice.len, 0) catch return "";
    @memcpy(copy, slice);
    return copy.ptr;
}

fn formatFlags(arena: std.mem.Allocator, code: anytype) [*c]const u8 {
    const T = @TypeOf(code);
    const has_is = @hasDecl(T, "is");
    if (!has_is) return "";

    var buf: std.Io.Writer.Allocating = .init(arena);
    var first = true;
    inline for (std.meta.fields(models.CodeFlag)) |f| {
        if (code.is(@enumFromInt(f.value))) {
            if (!first) buf.writer.writeAll(",") catch {};
            buf.writer.writeAll(@tagName(@as(models.CodeFlag, @enumFromInt(f.value)))) catch {};
            first = false;
        }
    }
    const slice = buf.toOwnedSlice() catch return "";
    // Copy to null-terminated buffer so C callers see proper string end
    const copy = arena.allocSentinel(u8, slice.len, 0) catch return "";
    @memcpy(copy, slice);
    arena.free(slice);
    return copy.ptr;
}

export fn msdrg_result_get_pdx_flags(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    if (wrapper.context.data.principal_dx) |pdx| {
        return formatFlags(wrapper.arena.allocator(), pdx);
    }
    return "";
}

export fn msdrg_result_get_sdx_flags(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.sdx_codes.items.len) return "";
    return formatFlags(wrapper.arena.allocator(), wrapper.context.data.sdx_codes.items[idx]);
}

export fn msdrg_result_get_proc_flags(res: *MsdrgResult, index: i32) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const idx = @as(usize, @intCast(index));
    if (idx >= wrapper.context.data.procedure_codes.items.len) return "";
    return formatFlags(wrapper.arena.allocator(), wrapper.context.data.procedure_codes.items[idx]);
}

// --- Hospital Status ---

export fn msdrg_input_set_hospital_status(input: *MsdrgInput, status: i32) void {
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    // 0=EXEMPT, 1=NOT_EXEMPT, 2=UNKNOWN
    wrapper.hospital_status = switch (status) {
        0 => .EXEMPT,
        2 => .UNKNOWN,
        else => .NOT_EXEMPT,
    };
}

// --- Python Helper: JSON Output ---

export fn msdrg_result_to_json(res: *MsdrgResult) [*c]const u8 {
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const data = wrapper.context.data;

    // Allocate with null terminator
    const json_str = std.fmt.allocPrintSentinel(allocator, "{{\"initial_drg\":{?},\"final_drg\":{?},\"initial_mdc\":{?},\"final_mdc\":{?},\"return_code\":\"{s}\"}}", .{ data.initial_result.drg, data.final_result.drg, data.initial_result.mdc, data.final_result.mdc, @tagName(data.final_result.return_code) }, 0) catch return null;

    return json_str.ptr;
}

export fn msdrg_string_free(s: [*c]const u8) void {
    if (s) |ptr| {
        const len = std.mem.len(ptr);
        const slice = ptr[0 .. len + 1];
        allocator.free(slice);
    }
}

// --- One-Shot JSON API ---

export fn msdrg_group_json(ctx: *MsdrgContext, json_str: [*c]const u8) [*c]const u8 {
    if (json_str == null) return null;

    const chain_ptr = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));
    const json_slice = std.mem.span(json_str);

    // Use allocPrintZ to allocate with null terminator in one shot
    const result_json = json_api.processJson(allocator, chain_ptr, json_slice) catch return null;
    defer allocator.free(result_json);

    // Allocate null-terminated copy
    const terminated = allocator.allocSentinel(u8, result_json.len, 0) catch return null;
    @memcpy(terminated, result_json);

    return terminated.ptr;
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

test "msdrg_input_create and free" {
    const input = msdrg_input_create() orelse return error.FailedToCreate;
    msdrg_input_free(input);
}

test "msdrg_input_free null" {
    msdrg_input_free(null);
}

test "msdrg_input_set_pdx null code" {
    const input = msdrg_input_create() orelse return error.FailedToCreate;
    defer msdrg_input_free(input);

    const result = msdrg_input_set_pdx(input, null, 'Y');
    try std.testing.expect(!result);
}

test "msdrg_input_add_sdx null code" {
    const input = msdrg_input_create() orelse return error.FailedToCreate;
    defer msdrg_input_free(input);

    const result = msdrg_input_add_sdx(input, null, 'Y');
    try std.testing.expect(!result);
}

test "msdrg_input_add_procedure null code" {
    const input = msdrg_input_create() orelse return error.FailedToCreate;
    defer msdrg_input_free(input);

    const result = msdrg_input_add_procedure(input, null);
    try std.testing.expect(!result);
}

test "msdrg_input_set_demographics clamps invalid sex" {
    const input = msdrg_input_create() orelse return error.FailedToCreate;
    defer msdrg_input_free(input);

    // sex=99 is out of range — should not crash
    msdrg_input_set_demographics(input, 65, 99, 1);
}

test "msdrg_group_json null json_str" {
    // Create a minimal context — this test needs data files so skip if not available
    const ctx = msdrg_context_init("data/bin") orelse return error.SkipZigTest;
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
