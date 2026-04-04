const std = @import("std");
const msdrg = @import("msdrg.zig");
const models = @import("models.zig");

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
    hospital_status: ?[]const u8 = null, // "EXEMPT", "NOT_EXEMPT", "UNKNOWN"
    tie_breaker: ?[]const u8 = null, // "CLINICAL_SIGNIFICANCE", "ALPHABETICAL"
};

pub const GrouperFlagsOutput = struct {
    admit_dx_grouper_flag: []const u8,
    initial_drg_secondary_dx_cc_mcc: []const u8,
    final_drg_secondary_dx_cc_mcc: []const u8,
    num_hac_categories_satisfied: i32,
    hac_status_value: []const u8,
};

pub const OutputResult = struct {
    initial_drg: ?i32,
    initial_mdc: ?i32,
    initial_base_drg: ?i32 = null,
    initial_drg_description: ?[]const u8 = null,
    initial_mdc_description: ?[]const u8 = null,
    initial_return_code: []const u8,
    initial_severity: []const u8,
    final_drg: ?i32,
    final_mdc: ?i32,
    final_base_drg: ?i32 = null,
    final_drg_description: ?[]const u8 = null,
    final_mdc_description: ?[]const u8 = null,
    return_code: []const u8,
    final_severity: []const u8,
    pdx_output: ?DiagnosisOutput = null,
    sdx_output: []const DiagnosisOutput = &.{},
    proc_output: []const ProcedureOutput = &.{},
    grouper_flags: ?GrouperFlagsOutput = null,
};

pub const HacOutput = struct {
    hac_number: i32,
    hac_list: []const u8,
    hac_status: []const u8,
    description: []const u8,
};

pub const DiagnosisOutput = struct {
    code: []const u8,
    mdc: ?i32,
    severity: []const u8,
    drg_impact: []const u8,
    poa_error: []const u8,
    flags: []const []const u8,
    hacs: []const HacOutput = &.{},
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
    return ' ';
}

fn intToEnum(comptime T: type, v: i32, default: T) T {
    inline for (std.meta.fields(T)) |f| {
        if (v == f.value) return @enumFromInt(f.value);
    }
    return default;
}

fn parseHospitalStatus(str: ?[]const u8) models.HospitalStatusOptionFlag {
    if (str) |s| {
        if (std.mem.eql(u8, s, "EXEMPT")) return .EXEMPT;
        if (std.mem.eql(u8, s, "UNKNOWN")) return .UNKNOWN;
    }
    return .NOT_EXEMPT;
}

fn parseTieBreaker(str: ?[]const u8) models.MarkingLogicTieBreaker {
    if (str) |s| {
        if (std.mem.eql(u8, s, "ALPHABETICAL")) return .ALPHABETICAL;
    }
    return .CLINICAL_SIGNIFICANCE;
}

fn mapDiagnosisOutput(arena: std.mem.Allocator, dx: models.DiagnosisCode) !DiagnosisOutput {
    var flags_list: std.ArrayListUnmanaged([]const u8) = .empty;
    inline for (std.meta.fields(models.CodeFlag)) |f| {
        if (dx.is(@enumFromInt(f.value))) {
            try flags_list.append(arena, @tagName(@as(models.CodeFlag, @enumFromInt(f.value))));
        }
    }

    var hacs_list: std.ArrayListUnmanaged(HacOutput) = .empty;
    for (dx.hacs.items) |hac| {
        try hacs_list.append(arena, HacOutput{
            .hac_number = hac.hac_number,
            .hac_list = try arena.dupe(u8, hac.hac_list),
            .hac_status = @tagName(hac.hac_status),
            .description = try arena.dupe(u8, hac.description),
        });
    }

    return DiagnosisOutput{
        .code = try arena.dupe(u8, dx.value.toSlice()),
        .mdc = dx.mdc,
        .severity = @tagName(dx.severity),
        .drg_impact = @tagName(dx.drg_impact),
        .poa_error = @tagName(dx.poa_error_code_flag),
        .flags = try flags_list.toOwnedSlice(arena),
        .hacs = try hacs_list.toOwnedSlice(arena),
    };
}

fn mapProcedureOutput(arena: std.mem.Allocator, proc: models.ProcedureCode) !ProcedureOutput {
    var flags_list: std.ArrayListUnmanaged([]const u8) = .empty;
    inline for (std.meta.fields(models.CodeFlag)) |f| {
        if (proc.is(@enumFromInt(f.value))) {
            try flags_list.append(arena, @tagName(@as(models.CodeFlag, @enumFromInt(f.value))));
        }
    }

    return ProcedureOutput{
        .code = try arena.dupe(u8, proc.value.toSlice()),
        .is_or = proc.is_operating_room,
        .drg_impact = @tagName(proc.drg_impact),
        .flags = try flags_list.toOwnedSlice(arena),
    };
}

/// Process a claim as JSON and return a JSON result string.
///
/// Memory: The caller owns the returned slice and must free it with the
/// same allocator passed as `root_allocator`. All intermediate allocations
/// are scoped to an internal arena that is freed before return.
pub fn processJson(root_allocator: std.mem.Allocator, grouper_chain: *const msdrg.GrouperChain, json_str: []const u8) ![]u8 {
    // Arena for all intermediate allocations — freed in one shot.
    // This prevents leaks on partial failure (e.g. mapDiagnosisOutput
    // succeeds but the append after it fails).
    var arena_instance = std.heap.ArenaAllocator.init(root_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // 1. Parse JSON
    const parsed = try std.json.parseFromSlice(InputClaim, arena, json_str, .{ .ignore_unknown_fields = true });
    const input = parsed.value;

    // 2. Get pre-built Link for requested version (thread-safe, no allocation)
    const link = try grouper_chain.getLink(input.version);

    // 3. Setup Processing Data (uses root_allocator since it outlives the arena)
    var data = models.ProcessingData.init(root_allocator);
    defer data.deinit();

    data.age = input.age;
    // Safely convert integers to enums — invalid values get defaults
    data.sex = intToEnum(models.Sex, input.sex, .UNKNOWN);
    data.discharge_status = intToEnum(models.DischargeStatus, input.discharge_status, .NONE);

    if (input.pdx) |p| {
        data.principal_dx = try models.DiagnosisCode.init(p.code, parsePoa(p.poa));
    }
    if (input.admit_dx) |a| {
        data.admit_dx = try models.DiagnosisCode.init(a.code, parsePoa(a.poa));
    }

    for (input.sdx) |s| {
        const dx = try models.DiagnosisCode.init(s.code, parsePoa(s.poa));
        try data.sdx_codes.append(root_allocator, dx);
    }

    for (input.procedures) |p| {
        const proc = try models.ProcedureCode.init(p.code);
        try data.procedure_codes.append(root_allocator, proc);
    }

    // 4. Execute
    const runtime_options = models.RuntimeOptions{
        .poa_reporting_exempt = parseHospitalStatus(input.hospital_status),
        .tie_breaker = parseTieBreaker(input.tie_breaker),
    };
    const context = models.ProcessingContext.init(root_allocator, &data, runtime_options);
    const result = try link.execute(context);
    var final_ctx = result.context;
    defer final_ctx.deinit();

    // 5. Map Output (arena-allocated — no individual frees needed)
    var sdx_out: std.ArrayListUnmanaged(DiagnosisOutput) = .empty;
    for (final_ctx.data.sdx_codes.items) |dx| {
        try sdx_out.append(arena, try mapDiagnosisOutput(arena, dx));
    }

    var proc_out: std.ArrayListUnmanaged(ProcedureOutput) = .empty;
    for (final_ctx.data.procedure_codes.items) |pr| {
        try proc_out.append(arena, try mapProcedureOutput(arena, pr));
    }

    var pdx_out: ?DiagnosisOutput = null;
    if (final_ctx.data.principal_dx) |pdx| {
        pdx_out = try mapDiagnosisOutput(arena, pdx);
    }
    // Calculate grouper flags
    const grouper_flags = models.calculateGrouperFlags(
        final_ctx.data,
        final_ctx.runtime.poa_reporting_exempt,
        root_allocator,
    );
    const grouper_flags_out = GrouperFlagsOutput{
        .admit_dx_grouper_flag = @tagName(grouper_flags.admit_dx_grouper_flag),
        .initial_drg_secondary_dx_cc_mcc = @tagName(grouper_flags.initial_drg_secondary_dx_cc_mcc),
        .final_drg_secondary_dx_cc_mcc = @tagName(grouper_flags.final_drg_secondary_dx_cc_mcc),
        .num_hac_categories_satisfied = grouper_flags.num_hac_categories_satisfied,
        .hac_status_value = @tagName(grouper_flags.hac_status_value),
    };

    const output = OutputResult{
        .initial_drg = final_ctx.data.initial_result.drg,
        .initial_mdc = final_ctx.data.initial_result.mdc,
        .initial_base_drg = final_ctx.data.initial_result.base_drg,
        .initial_drg_description = final_ctx.data.initial_result.drg_description,
        .initial_mdc_description = final_ctx.data.initial_result.mdc_description,
        .initial_return_code = @tagName(final_ctx.data.initial_result.return_code),
        .initial_severity = @tagName(final_ctx.data.initial_severity),
        .final_drg = final_ctx.data.final_result.drg,
        .final_mdc = final_ctx.data.final_result.mdc,
        .final_base_drg = final_ctx.data.final_result.base_drg,
        .final_drg_description = final_ctx.data.final_result.drg_description,
        .final_mdc_description = final_ctx.data.final_result.mdc_description,
        .return_code = @tagName(final_ctx.data.final_result.return_code),
        .final_severity = @tagName(final_ctx.data.final_severity),
        .pdx_output = pdx_out,
        .sdx_output = sdx_out.items,
        .proc_output = proc_out.items,
        .grouper_flags = grouper_flags_out,
    };

    // 6. Stringify (arena for the writer buffer, then copy to root_allocator)
    var out: std.Io.Writer.Allocating = .init(arena);
    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .minified },
    };
    try write_stream.write(output);

    // Copy the final JSON string out of the arena so it survives arena free
    const json_bytes = try out.toOwnedSlice();
    const owned = try root_allocator.dupe(u8, json_bytes);
    return owned;
}
