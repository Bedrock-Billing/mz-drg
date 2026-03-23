const std = @import("std");
const models = @import("models.zig");
const formula = @import("formula.zig");
const marking = @import("marking.zig");
const chain = @import("chain.zig");

test "InitialDiagnosisMarking execution" {
    const allocator = std.testing.allocator;

    // 1. Create temporary formula file
    const filename = "test_marking_formula.bin";
    const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, filename, .{ .read = true });
    defer {
        std.Io.File.close(file, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.Io.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    const writeI32 = struct {
        fn call(f: std.Io.File, v: i32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Formula string: "MCC"
    const formula_str = "MCC";
    const formula_len = formula_str.len;

    // Header
    try writeU32(file, 0x464F524D);
    try writeU32(file, 0); // num_entries
    try writeU32(file, 1); // num_formulas
    try writeU32(file, 100); // entries_offset (dummy)
    try writeU32(file, 64); // formulas_offset
    try writeU32(file, 200); // strings_offset (dummy)

    // Padding to 64 bytes
    try file.seekTo(64);

    // Formula 1: offset to string at 128
    try writeI32(file, 1); // mdc
    try writeI32(file, 1); // rank
    try writeI32(file, 100); // base_drg
    try writeI32(file, 101); // drg
    try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8); // surgical
    try writeI32(file, 0); // reroute
    try writeI32(file, 1); // severity
    try writeU32(file, 128); // formula_offset
    try writeU32(file, @intCast(formula_len)); // formula_len
    try writeU32(file, 0); // supp_offset
    try writeU32(file, 0); // supp_count

    // Write formula string at 128
    try std.Io.File.writePositionalAll(file, std.testing.io, formula_str, 128);

    // 2. Init FormulaData
    var formula_data = try formula.FormulaData.init(filename);
    defer formula_data.deinit();

    // 3. Init Data and Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 4. Add SDX code with attribute "MCC"
    var sdx = try models.DiagnosisCode.init("D001", 'Y');
    try sdx.attributes.append(allocator, models.Attribute{ .list_name = "MCC" });
    try data.sdx_codes.append(allocator, sdx);

    // 5. Set up winning formula
    const formulas = formula_data.getFormulas();
    context.initial_grouping_context.pdx_match = formulas[0];

    // 6. Execute Marking
    var mark_link = marking.InitialDiagnosisMarking{ .formula_data = &formula_data };
    _ = try marking.InitialDiagnosisMarking.execute(&mark_link, context);

    // 7. Assertions
    const marked_sdx = &data.sdx_codes.items[0];
    try std.testing.expect(marked_sdx.is(.MARKED_FOR_INITIAL));
    try std.testing.expectEqual(models.GroupingImpact.INITIAL, marked_sdx.drg_impact);
    try std.testing.expectEqualStrings("MCC", marked_sdx.attribute_marked_for.?.list_name);
}

test "InitialDiagnosisMarking no match" {
    const allocator = std.testing.allocator;

    // 1. Create temporary formula file
    const filename = "test_marking_formula_nomatch.bin";
    const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, filename, .{ .read = true });
    defer {
        std.Io.File.close(file, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.Io.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    const writeI32 = struct {
        fn call(f: std.Io.File, v: i32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Formula string: "CC"
    const formula_str = "CC";
    const formula_len = formula_str.len;

    // Header
    try writeU32(file, 0x464F524D);
    try writeU32(file, 0); // num_entries
    try writeU32(file, 1); // num_formulas
    try writeU32(file, 100); // entries_offset (dummy)
    try writeU32(file, 64); // formulas_offset
    try writeU32(file, 200); // strings_offset (dummy)

    // Padding to 64 bytes
    try file.seekTo(64);

    // Formula 1: offset to string at 128
    try writeI32(file, 1); // mdc
    try writeI32(file, 1); // rank
    try writeI32(file, 100); // base_drg
    try writeI32(file, 101); // drg
    try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8); // surgical
    try writeI32(file, 0); // reroute
    try writeI32(file, 1); // severity
    try writeU32(file, 128); // formula_offset
    try writeU32(file, @intCast(formula_len)); // formula_len
    try writeU32(file, 0); // supp_offset
    try writeU32(file, 0); // supp_count

    // Write formula string at 128
    try std.Io.File.writePositionalAll(file, std.testing.io, formula_str, 128);

    // 2. Init FormulaData
    var formula_data = try formula.FormulaData.init(filename);
    defer formula_data.deinit();

    // 3. Init Data and Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 4. Add SDX code with attribute "MCC" (not "CC")
    var sdx = try models.DiagnosisCode.init("D001", 'Y');
    try sdx.attributes.append(allocator, models.Attribute{ .list_name = "MCC" });
    try data.sdx_codes.append(allocator, sdx);

    // 5. Set up winning formula
    const formulas = formula_data.getFormulas();
    context.initial_grouping_context.pdx_match = formulas[0];

    // 6. Execute Marking
    var mark_link = marking.InitialDiagnosisMarking{ .formula_data = &formula_data };
    _ = try marking.InitialDiagnosisMarking.execute(&mark_link, context);

    // 7. Assertions
    const marked_sdx = &data.sdx_codes.items[0];
    try std.testing.expect(!marked_sdx.is(.MARKED_FOR_INITIAL));
    try std.testing.expectEqual(models.GroupingImpact.NONE, marked_sdx.drg_impact);
}

test "InitialProcedureMarking execution" {
    const allocator = std.testing.allocator;

    // 1. Create temporary formula file
    const filename = "test_proc_marking_formula.bin";
    const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, filename, .{ .read = true });
    defer {
        std.Io.File.close(file, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.Io.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    const writeI32 = struct {
        fn call(f: std.Io.File, v: i32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Formula string: "PROC_ATTR"
    const formula_str = "PROC_ATTR";
    const formula_len = formula_str.len;

    // Header
    try writeU32(file, 0x464F524D);
    try writeU32(file, 0); // num_entries
    try writeU32(file, 1); // num_formulas
    try writeU32(file, 100); // entries_offset (dummy)
    try writeU32(file, 64); // formulas_offset
    try writeU32(file, 200); // strings_offset (dummy)

    // Padding to 64 bytes
    try file.seekTo(64);

    // Formula 1: offset to string at 128
    try writeI32(file, 1); // mdc
    try writeI32(file, 1); // rank
    try writeI32(file, 100); // base_drg
    try writeI32(file, 101); // drg
    try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8); // surgical
    try writeI32(file, 0); // reroute
    try writeI32(file, 1); // severity
    try writeU32(file, 128); // formula_offset
    try writeU32(file, @intCast(formula_len)); // formula_len
    try writeU32(file, 0); // supp_offset
    try writeU32(file, 0); // supp_count

    // Write formula string at 128
    try std.Io.File.writePositionalAll(file, std.testing.io, formula_str, 128);

    // 2. Init FormulaData
    var formula_data = try formula.FormulaData.init(filename);
    defer formula_data.deinit();

    // 3. Init Data and Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 4. Add Procedure code with attribute "PROC_ATTR"
    var proc = try models.ProcedureCode.init("P001");
    try proc.attributes.append(allocator, models.Attribute{ .list_name = "PROC_ATTR" });
    try data.procedure_codes.append(allocator, proc);

    // 5. Set up winning formula
    const formulas = formula_data.getFormulas();
    context.initial_grouping_context.pdx_match = formulas[0];

    // 6. Execute Marking
    var mark_link = marking.InitialProcedureMarking{ .formula_data = &formula_data };
    _ = try marking.InitialProcedureMarking.execute(&mark_link, context);

    // 7. Assertions
    const marked_proc = &data.procedure_codes.items[0];
    try std.testing.expect(marked_proc.is(.MARKED_FOR_INITIAL));
    try std.testing.expectEqual(models.GroupingImpact.INITIAL, marked_proc.drg_impact);
}
