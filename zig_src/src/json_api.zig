const std = @import("std");
const msdrg = @import("msdrg.zig");
const models = @import("models.zig");
const chain = @import("chain.zig");

pub const JsonDiagnosis = struct {
    code: []const u8,
    poa: ?[]const u8 = null,
};

pub const JsonProcedure = struct {
    code: []const u8,
};

pub const InputClaim = struct {
    version: i32,
    pdx: ?JsonDiagnosis = null,
    admit_dx: ?JsonDiagnosis = null,
    sdx: []const JsonDiagnosis = &.{},
    procedures: []const JsonProcedure = &.{},
    age: i32 = 0,
    sex: i32 = 2, // Default UNKNOWN
    discharge_status: i32 = 0,
};

pub const OutputResult = struct {
    initial_drg: ?i32,
    final_drg: ?i32,
    initial_mdc: ?i32,
    final_mdc: ?i32,
    return_code: []const u8,
    // Detailed output can be added here
    pdx_output: ?DiagnosisOutput = null,
    sdx_output: []const DiagnosisOutput = &.{},
    proc_output: []const ProcedureOutput = &.{},
};

pub const DiagnosisOutput = struct {
    code: []const u8,
    mdc: ?i32,
    severity: []const u8,
    drg_impact: []const u8,
    poa_error: []const u8,
    flags: []const []const u8,
};

pub const ProcedureOutput = struct {
    code: []const u8,
    is_or: bool,
    drg_impact: []const u8,
    flags: []const []const u8,
};

fn parsePoa(poa_str: ?[]const u8) u8 {
    if (poa_str) |s| {
        if (s.len > 0) return s[0];
    }
    return ' '; // Default or blank
}

fn mapDiagnosisOutput(allocator: std.mem.Allocator, dx: models.DiagnosisCode) !DiagnosisOutput {
    var flags_list = std.ArrayListUnmanaged([]const u8){};
    defer flags_list.deinit(allocator);
    // Iterate over flags enum
    inline for (std.meta.fields(models.CodeFlag)) |f| {
        if (dx.is(@enumFromInt(f.value))) {
            try flags_list.append(allocator, @tagName(@as(models.CodeFlag, @enumFromInt(f.value))));
        }
    }

    return DiagnosisOutput{
        .code = try allocator.dupe(u8, dx.value.toSlice()),
        .mdc = dx.mdc,
        .severity = @tagName(dx.severity),
        .drg_impact = @tagName(dx.drg_impact),
        .poa_error = @tagName(dx.poa_error_code_flag),
        .flags = try flags_list.toOwnedSlice(allocator),
    };
}

fn mapProcedureOutput(allocator: std.mem.Allocator, proc: models.ProcedureCode) !ProcedureOutput {
    var flags_list = std.ArrayListUnmanaged([]const u8){};
    defer flags_list.deinit(allocator);
    inline for (std.meta.fields(models.CodeFlag)) |f| {
        if (proc.is(@enumFromInt(f.value))) {
            try flags_list.append(allocator, @tagName(@as(models.CodeFlag, @enumFromInt(f.value))));
        }
    }

    return ProcedureOutput{
        .code = try allocator.dupe(u8, proc.value.toSlice()),
        .is_or = proc.is_operating_room,
        .drg_impact = @tagName(proc.drg_impact),
        .flags = try flags_list.toOwnedSlice(allocator),
    };
}

pub fn processJson(allocator: std.mem.Allocator, grouper_chain: *msdrg.GrouperChain, json_str: []const u8) ![]u8 {
    // 1. Parse JSON
    const parsed = try std.json.parseFromSlice(InputClaim, allocator, json_str, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const input = parsed.value;

    // 2. Create Link for requested version
    var link = try grouper_chain.create(input.version);
    defer link.deinit(allocator);

    // 3. Setup Processing Data
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    data.age = input.age;
    data.sex = @enumFromInt(input.sex);
    data.discharge_status = @enumFromInt(input.discharge_status);

    if (input.pdx) |p| {
        data.principal_dx = try models.DiagnosisCode.init(p.code, parsePoa(p.poa));
    }
    if (input.admit_dx) |a| {
        data.admit_dx = try models.DiagnosisCode.init(a.code, parsePoa(a.poa));
    }

    for (input.sdx) |s| {
        const dx = try models.DiagnosisCode.init(s.code, parsePoa(s.poa));
        try data.sdx_codes.append(allocator, dx);
    }

    for (input.procedures) |p| {
        const proc = try models.ProcedureCode.init(p.code);
        try data.procedure_codes.append(allocator, proc);
    }

    // 4. Execute
    const context = models.ProcessingContext.init(allocator, &data, .{});
    // Note: context doesn't own data, but it holds a pointer to it.
    // The result context will share the same data pointer usually, or wrap it.
    // In our chain implementation, the context is passed by value but contains pointers.

    const result = try link.execute(context);
    var final_ctx = result.context;
    defer final_ctx.deinit();

    // 5. Map Output
    var sdx_out = std.ArrayListUnmanaged(DiagnosisOutput){};
    defer sdx_out.deinit(allocator);
    for (final_ctx.data.sdx_codes.items) |dx| {
        try sdx_out.append(allocator, try mapDiagnosisOutput(allocator, dx));
    }

    var proc_out = std.ArrayListUnmanaged(ProcedureOutput){};
    defer proc_out.deinit(allocator);
    for (final_ctx.data.procedure_codes.items) |pr| {
        try proc_out.append(allocator, try mapProcedureOutput(allocator, pr));
    }

    var pdx_out: ?DiagnosisOutput = null;
    if (final_ctx.data.principal_dx) |pdx| {
        pdx_out = try mapDiagnosisOutput(allocator, pdx);
    }

    const output = OutputResult{
        .initial_drg = final_ctx.data.initial_result.drg,
        .final_drg = final_ctx.data.final_result.drg,
        .initial_mdc = final_ctx.data.initial_result.mdc,
        .final_mdc = final_ctx.data.final_result.mdc,
        .return_code = @tagName(final_ctx.data.final_result.return_code),
        .pdx_output = pdx_out,
        .sdx_output = sdx_out.items,
        .proc_output = proc_out.items,
    };

    // 6. Stringify
    var out: std.Io.Writer.Allocating = .init(allocator);
    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .minified },
    };
    try write_stream.write(output);
    return try out.toOwnedSlice();
}
