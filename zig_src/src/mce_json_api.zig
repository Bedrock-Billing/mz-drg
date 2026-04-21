const std = @import("std");
const mce = @import("mce.zig");
const mce_enums = @import("mce_enums.zig");
const mce_editing = @import("mce_editing.zig");

const Attribute = mce_enums.Attribute;
const EditType = mce_enums.EditType;
const MceInput = mce_enums.MceInput;
const MceDiagnosisCode = mce_enums.MceDiagnosisCode;
const MceProcedureCode = mce_enums.MceProcedureCode;

// --- JSON Input ---

pub const JsonDiagnosis = struct {
    code: []const u8,
    poa: ?[]const u8 = null,
};

pub const JsonProcedure = struct {
    code: []const u8,
};

pub const MceJsonInput = struct {
    discharge_date: ?i32 = null, // YYYYMMDD integer, optional
    icd_version: i32 = 10, // 9 or 10, default 10
    age: i32 = 0,
    sex: i32 = 2, // 0=Male, 1=Female, 2=Unknown
    discharge_status: i32 = 0,
    admit_dx: ?JsonDiagnosis = null,
    pdx: ?JsonDiagnosis = null,
    sdx: []const JsonDiagnosis = &.{},
    procedures: []const JsonProcedure = &.{},
};

// --- JSON Output ---

pub const MceJsonOutput = struct {
    version: i32,
    edit_type: []const u8,
    edits: []const MceJsonEdit,
};

pub const MceJsonEdit = struct {
    name: []const u8,
    count: u32,
    code_type: []const u8,
    edit_type: []const u8,
};

// --- Processing ---

/// Process a claim through the MCE and return JSON output.
///
/// Memory: The caller owns the returned slice and must free it with
/// the same allocator.
pub fn processMceJson(
    root_allocator: std.mem.Allocator,
    mce_component: *mce.MceComponent,
    json_str: []const u8,
) ![]u8 {
    // Arena for intermediate allocations
    var arena_instance = std.heap.ArenaAllocator.init(root_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // 1. Parse JSON
    const parsed = try std.json.parseFromSlice(MceJsonInput, arena, json_str, .{ .ignore_unknown_fields = true });
    const input = parsed.value;

    // 2. Build MceInput
    var mce_input = MceInput{
        .age = input.age,
        .sex = intToSex(input.sex),
        .discharge_status = input.discharge_status,
        .discharge_date = input.discharge_date orelse 0,
    };

    if (input.admit_dx) |adx| {
        mce_input.admit_dx = MceDiagnosisCode.init(adx.code);
    }
    if (input.pdx) |pdx| {
        mce_input.pdx = MceDiagnosisCode.init(pdx.code);
    }
    for (input.sdx) |s| {
        try mce_input.sdx.append(root_allocator, MceDiagnosisCode.init(s.code));
    }
    for (input.procedures) |p| {
        try mce_input.procedures.append(root_allocator, MceProcedureCode.init(p.code));
    }
    defer mce_input.deinit(root_allocator);

    // 3. Process
    const icd_ver: u8 = if (input.icd_version == 9) 9 else 10;
    var output = try mce_component.process(&mce_input, icd_ver, root_allocator);

    // 4. Build JSON output
    var edits: std.ArrayListUnmanaged(MceJsonEdit) = .empty;
    defer edits.deinit(arena);

    inline for (mce_enums.ALL_EDITS, 0..) |edit, i| {
        const count = output.getCount(i);
        if (count > 0) {
            try edits.append(arena, MceJsonEdit{
                .name = editName(i),
                .count = count,
                .code_type = @tagName(edit.code_type),
                .edit_type = @tagName(edit.edit_type),
            });
        }
    }

    const json_output = MceJsonOutput{
        .version = output.version,
        .edit_type = @tagName(output.edit_type),
        .edits = edits.items,
    };

    // 5. Stringify
    var out: std.Io.Writer.Allocating = .init(arena);
    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .minified },
    };
    try write_stream.write(json_output);

    const json_bytes = try out.toOwnedSlice();
    return try root_allocator.dupe(u8, json_bytes);
}

fn intToSex(v: i32) mce_enums.Sex {
    return switch (v) {
        0 => .MALE,
        1 => .FEMALE,
        else => .UNKNOWN,
    };
}

fn editName(index: usize) []const u8 {
    return switch (index) {
        0 => "INVALID_CODE",
        1 => "SEX_CONFLICT",
        2 => "AGE_CONFLICT",
        3 => "QUESTIONABLE_ADMISSION",
        4 => "MANIFESTATION_AS_PDX",
        5 => "NONSPECIFIC_PDX",
        6 => "E_CODE_AS_PDX",
        7 => "UNACCEPTABLE_PDX",
        8 => "DUPLICATE_OF_PDX",
        9 => "MEDICARE_IS_SECONDARY_PAYER",
        10 => "REQUIRES_SDX",
        11 => "NONSPECIFIC_OR",
        12 => "OPEN_BIOPSY",
        13 => "NON_COVERED",
        14 => "BILATERAL",
        15 => "LIMITED_COVERAGE_LVRS",
        16 => "LIMITED_COVERAGE",
        17 => "LIMITED_COVERAGE_LUNG_TRANSPLANT",
        18 => "QUESTIONABLE_OBSTETRIC_ADMISSION",
        19 => "LIMITED_COVERAGE_COMBINATION_HEART_LUNG",
        20 => "LIMITED_COVERAGE_HEART_TRANSPLANT",
        21 => "LIMITED_COVERAGE_HEART_IMPLANT",
        22 => "LIMITED_COVERAGE_INTESTINE",
        23 => "LIMITED_COVERAGE_LIVER",
        24 => "INVALID_ADMIT_DX",
        25 => "INVALID_AGE",
        26 => "INVALID_SEX",
        27 => "INVALID_DISCHARGE_STATUS",
        28 => "LIMITED_COVERAGE_KIDNEY",
        29 => "LIMITED_COVERAGE_PANCREAS",
        30 => "TYPE_OF_AGE_CONFLICT",
        31 => "INVALID_POA",
        32 => "LIMITED_COVERAGE_ARTIFICIAL_HEART",
        33 => "WRONG_PROCEDURE_PERFORMED",
        34 => "INCONSISTENT_WITH_LENGTH_OF_STAY",
        35 => "UNSPECIFIED",
        else => "UNKNOWN",
    };
}

// --- Tests ---

test "processMceJson valid claim" {
    const allocator = std.testing.allocator;
    const data_path = "../data/msdrg.mdb";

    var comp = mce.MceComponent.init(data_path, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    const json_input =
        \\{"age":65,"sex":0,"discharge_status":1,"discharge_date":20250101,"pdx":{"code":"I5020"},"sdx":[],"procedures":[]}
    ;

    const result = try processMceJson(allocator, &comp, json_input);
    defer allocator.free(result);

    // Parse result to verify structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("NONE", obj.get("edit_type").?.string);
}

test "processMceJson E-code as PDX" {
    const allocator = std.testing.allocator;
    const data_path = "../data/msdrg.mdb";

    var comp = mce.MceComponent.init(data_path, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    const json_input =
        \\{"age":65,"sex":0,"discharge_status":1,"discharge_date":20250101,"pdx":{"code":"V0001XA"},"sdx":[],"procedures":[]}
    ;

    const result = try processMceJson(allocator, &comp, json_input);
    defer allocator.free(result);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("PREPAYMENT", obj.get("edit_type").?.string);

    // Check that E_CODE_AS_PDX edit is present
    const edits = obj.get("edits").?.array;
    var found_ecode = false;
    for (edits.items) |edit| {
        if (std.mem.eql(u8, edit.object.get("name").?.string, "E_CODE_AS_PDX")) {
            found_ecode = true;
            try std.testing.expect(edit.object.get("count").?.integer > 0);
            break;
        }
    }
    try std.testing.expect(found_ecode);
}
