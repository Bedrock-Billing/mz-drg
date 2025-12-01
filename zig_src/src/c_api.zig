const std = @import("std");
const msdrg = @import("msdrg.zig");
const models = @import("models.zig");
const chain = @import("chain.zig");
const json_api = @import("json_api.zig");

// --- Allocator ---
// Use C allocator (malloc/free) for shared library to avoid GPA issues and integrate better with system.
const c_allocator = std.heap.c_allocator;
fn getAllocator() std.mem.Allocator {
    return c_allocator;
}

// --- Opaque Types for C ---
pub const MsdrgContext = opaque {};
pub const MsdrgVersion = opaque {};
pub const MsdrgInput = opaque {};
pub const MsdrgResult = opaque {};

// --- Context Management ---

export fn msdrg_context_init(data_dir: [*c]const u8) ?*MsdrgContext {
    const allocator = getAllocator();
    const dir_slice = std.mem.span(data_dir);

    const ctx = allocator.create(msdrg.GrouperChain) catch return null;
    ctx.* = msdrg.GrouperChain.init(allocator, dir_slice) catch {
        allocator.destroy(ctx);
        return null;
    };

    return @ptrCast(ctx);
}

export fn msdrg_context_free(ctx: ?*MsdrgContext) void {
    const allocator = getAllocator();
    if (ctx) |c| {
        const self = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(c)));
        self.deinit();
        allocator.destroy(self);
    }
}

// --- Version Management ---

export fn msdrg_version_create(ctx: *MsdrgContext, version: i32) ?*MsdrgVersion {
    const allocator = getAllocator();
    const self = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));

    const link_ptr = allocator.create(chain.Link) catch return null;
    link_ptr.* = self.create(version) catch {
        allocator.destroy(link_ptr);
        return null;
    };

    return @ptrCast(link_ptr);
}

export fn msdrg_version_free(ver: ?*MsdrgVersion) void {
    const allocator = getAllocator();
    if (ver) |v| {
        const link = @as(*chain.Link, @ptrCast(@alignCast(v)));
        link.deinit(allocator);
        allocator.destroy(link);
    }
}

// --- Input Management ---

const InputWrapper = struct {
    data: models.ProcessingData,
};

export fn msdrg_input_create() ?*MsdrgInput {
    const allocator = getAllocator();
    const wrapper = allocator.create(InputWrapper) catch return null;
    wrapper.data = models.ProcessingData.init(allocator);
    return @ptrCast(wrapper);
}

export fn msdrg_input_free(input: ?*MsdrgInput) void {
    const allocator = getAllocator();
    if (input) |i| {
        const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(i)));
        wrapper.data.deinit();
        allocator.destroy(wrapper);
    }
}

export fn msdrg_input_set_pdx(input: *MsdrgInput, code: [*c]const u8, poa: u8) bool {
    const allocator = getAllocator();
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const dx = models.DiagnosisCode.init(code_slice, poa) catch return false;

    // If there was already a PDX, deinit it (though init starts null)
    if (wrapper.data.principal_dx) |*old| {
        old.deinit(allocator);
    }
    wrapper.data.principal_dx = dx;
    return true;
}

export fn msdrg_input_set_admit_dx(input: *MsdrgInput, code: [*c]const u8, poa: u8) bool {
    const allocator = getAllocator();
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
    const allocator = getAllocator();
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const dx = models.DiagnosisCode.init(code_slice, poa) catch return false;
    wrapper.data.sdx_codes.append(allocator, dx) catch return false;
    return true;
}

export fn msdrg_input_add_procedure(input: *MsdrgInput, code: [*c]const u8) bool {
    const allocator = getAllocator();
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    const code_slice = std.mem.span(code);

    const proc = models.ProcedureCode.init(code_slice) catch return false;
    wrapper.data.procedure_codes.append(allocator, proc) catch return false;
    return true;
}

export fn msdrg_input_set_demographics(input: *MsdrgInput, age: i32, sex: i32, discharge_status: i32) void {
    const wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));
    wrapper.data.age = age;

    // Map integers to enums.
    // Sex: 0=MALE, 1=FEMALE, 2=UNKNOWN (Assuming 0/1/2 mapping, need to verify models.zig)
    wrapper.data.sex = @enumFromInt(sex);

    // DischargeStatus: enum(i32)
    wrapper.data.discharge_status = @enumFromInt(discharge_status);
}

// --- Execution ---

const ResultWrapper = struct {
    context: models.ProcessingContext,
};

export fn msdrg_group(ver: *MsdrgVersion, input: *MsdrgInput) ?*MsdrgResult {
    const allocator = getAllocator();
    const link = @as(*chain.Link, @ptrCast(@alignCast(ver)));
    const input_wrapper = @as(*InputWrapper, @ptrCast(@alignCast(input)));

    // Create a new context for this run
    const context = models.ProcessingContext.init(allocator, &input_wrapper.data, .{});

    const result = link.execute(context) catch return null;

    // The result contains the context which contains the data.
    // We need to return something that holds the result context.

    const res_wrapper = allocator.create(ResultWrapper) catch return null;
    res_wrapper.context = result.context;

    return @ptrCast(res_wrapper);
}

// --- Result Access ---

export fn msdrg_result_free(res: ?*MsdrgResult) void {
    const allocator = getAllocator();
    if (res) |r| {
        const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(r)));
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

// --- Python Helper: JSON Output ---
// It's often easier to just get a JSON string back in Python than calling 50 getters.

export fn msdrg_result_to_json(res: *MsdrgResult) [*c]const u8 {
    const allocator = getAllocator();
    const wrapper = @as(*ResultWrapper, @ptrCast(@alignCast(res)));
    const data = wrapper.context.data;

    const json_str = std.fmt.allocPrint(allocator, "{{\"initial_drg\":{?},\"final_drg\":{?},\"initial_mdc\":{?},\"final_mdc\":{?},\"return_code\":\"{s}\"}}\x00", .{ data.initial_result.drg, data.final_result.drg, data.initial_result.mdc, data.final_result.mdc, @tagName(data.final_result.return_code) }) catch return null;

    return json_str.ptr;
}

export fn msdrg_string_free(s: [*c]const u8) void {
    const allocator = getAllocator();
    if (s) |ptr| {
        const len = std.mem.len(ptr);
        // We assume the string was allocated with a null terminator included in the allocation.
        // std.mem.len returns the length excluding the null terminator.
        // So we need to free len + 1 bytes.
        const slice = ptr[0 .. len + 1];
        allocator.free(slice);
    }
}

// --- One-Shot JSON API ---

export fn msdrg_group_json(ctx: *MsdrgContext, json_str: [*c]const u8) [*c]const u8 {
    const allocator = getAllocator();
    const chain_ptr = @as(*msdrg.GrouperChain, @ptrCast(@alignCast(ctx)));
    const json_slice = std.mem.span(json_str);

    const result_json = json_api.processJson(allocator, chain_ptr, json_slice) catch return null;

    // Let's just append null here.
    const terminated = allocator.realloc(result_json, result_json.len + 1) catch {
        allocator.free(result_json);
        return null;
    };
    terminated[result_json.len] = 0;

    return terminated.ptr;
}
