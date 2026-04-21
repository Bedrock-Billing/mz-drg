const std = @import("std");
const models = @import("models.zig");
const grouping = @import("grouping.zig");
const formula = @import("formula.zig");
const description = @import("description.zig");
const common = @import("common.zig");

test "MsdrgFinalPreGrouping logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Formula Data: MDC 0, Formula "MCC" -> DRG 1
    const formula_filename = "test_final_grouping_formula.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, formula_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);

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

        // Header
        try writeU32(file, 0x464F524D);
        try writeU32(file, 1); // 1 entry
        try writeU32(file, 1); // 1 formula
        try writeU32(file, 24); // entries offset
        try writeU32(file, 44); // formulas offset
        try writeU32(file, 100); // strings offset

        // Entry: MDC 0
        try writeI32(file, 0);
        try writeI32(file, 400);
        try writeI32(file, 410);
        try writeU32(file, 0); // start_index
        try writeU32(file, 1); // count

        // Formula: MDC 0, DRG 1, Formula "MCC"
        try writeI32(file, 0); // mdc
        try writeI32(file, 1); // rank
        try writeI32(file, 1); // base_drg
        try writeI32(file, 1); // drg
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8); // surgical
        try writeI32(file, 0); // reroute
        try writeI32(file, 0); // severity
        try writeU32(file, 100); // formula_offset
        try writeU32(file, 3); // formula_len
        try writeU32(file, 0); // supp_offset
        try writeU32(file, 0); // supp_count

        // Strings
        try std.Io.File.writePositionalAll(file, std.testing.io, "MCC", 100);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, formula_filename) catch {};

    // Description Data (Dummy)
    const desc_filename = "test_final_grouping_desc.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, desc_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x44455343, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, desc_filename) catch {};

    var formula_data = try formula.FormulaData.init(formula_filename);
    defer formula_data.deinit();
    var desc_data = try description.DescriptionData.init(desc_filename, 0x44455343);
    defer desc_data.deinit();

    // 2. Setup Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    // Patient has MCC severity
    var sdx = try models.DiagnosisCode.init("S001", 'Y');
    sdx.severity = .MCC;
    try data.sdx_codes.append(allocator, sdx);

    var ast_cache = formula.AstCache.init(allocator);
    defer ast_cache.deinit();
    var context = models.ProcessingContext.init(allocator, &data, .{}, &ast_cache);
    defer context.deinit();

    // 3. Execute FinalPreGrouping
    var processor = grouping.MsdrgFinalPreGrouping{
        .formula_data = &formula_data,
        .description_data = &desc_data,
        .version = 400,
    };

    const result = try grouping.MsdrgFinalPreGrouping.execute(&processor, context);
    context = result.context;

    // 4. Verify Results
    try std.testing.expectEqual(@as(i32, 1), data.final_result.drg.?);
    try std.testing.expectEqual(models.Severity.MCC, data.final_severity);
    try std.testing.expectEqual(@as(usize, 1), context.final_mdc.items.len);
    try std.testing.expectEqual(@as(i32, 0), context.final_mdc.items[0]);
    try std.testing.expect(context.final_grouping_context.pre_match != null);
}

test "MsdrgFinalDrgResults logic" {
    const allocator = std.testing.allocator;

    // Setup dummy description data
    const desc_filename = "test_final_results_desc.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, desc_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x44455343, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, desc_filename) catch {};

    var desc_data = try description.DescriptionData.init(desc_filename, 0x44455343);
    defer desc_data.deinit();

    // Case 1: Match found
    {
        var data = models.ProcessingData.init(allocator);
        defer data.deinit();
        data.final_result.drg = 100;

        var ast_cache = formula.AstCache.init(allocator);
    defer ast_cache.deinit();
    var context = models.ProcessingContext.init(allocator, &data, .{}, &ast_cache);
        defer context.deinit();

        var results_step = grouping.MsdrgFinalDrgResults{
            .description_data = &desc_data,
        };

        _ = try grouping.MsdrgFinalDrgResults.execute(&results_step, context);

        try std.testing.expectEqual(models.GrouperReturnCode.OK, data.final_result.return_code);
    }

    // Case 2: No match found
    {
        var data = models.ProcessingData.init(allocator);
        defer data.deinit();
        // drg is null by default

        var ast_cache = formula.AstCache.init(allocator);
    defer ast_cache.deinit();
    var context = models.ProcessingContext.init(allocator, &data, .{}, &ast_cache);
        defer context.deinit();

        var results_step = grouping.MsdrgFinalDrgResults{
            .description_data = &desc_data,
        };

        _ = try grouping.MsdrgFinalDrgResults.execute(&results_step, context);

        try std.testing.expectEqual(models.GrouperReturnCode.UNGROUPABLE, data.final_result.return_code);
    }
}
