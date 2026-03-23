const std = @import("std");
const models = @import("models.zig");
const grouping = @import("grouping.zig");
const formula = @import("formula.zig");
const description = @import("description.zig");
const common = @import("common.zig");

test "MsdrgInitialPreGrouping logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Formula Data: MDC 0, Formula "MCC & AGE>65" -> DRG 1
    const formula_filename = "test_grouping_formula.bin";
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

        // Header: magic(4), num_entries(4), num_formulas(4), entries_off(4), formulas_off(4), strings_off(4)
        try writeU32(file, 0x464F524D);
        try writeU32(file, 1); // 1 entry
        try writeU32(file, 1); // 1 formula
        try writeU32(file, 24); // entries offset
        try writeU32(file, 44); // formulas offset (24 + 20)
        try writeU32(file, 100); // strings offset (arbitrary)

        // Entry: MDC 0, v400-410
        try writeI32(file, 0);
        try writeI32(file, 400);
        try writeI32(file, 410);
        try writeU32(file, 0); // start_index
        try writeU32(file, 1); // count

        // Formula: MDC 0, Rank 1, DRG 1, Formula "MCC & AGE>65"
        try writeI32(file, 0); // mdc
        try writeI32(file, 1); // rank
        try writeI32(file, 1); // base_drg
        try writeI32(file, 1); // drg
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8); // surgical
        try writeI32(file, 0); // reroute
        try writeI32(file, 0); // severity
        try writeU32(file, 100); // formula_offset
        try writeU32(file, 12); // formula_len ("MCC & AGE>65")
        try writeU32(file, 0); // supp_offset
        try writeU32(file, 0); // supp_count

        // Strings
        try std.Io.File.writePositionalAll(file, std.testing.io, "MCC & AGE>65", 100);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, formula_filename) catch {};

    // Description Data (Dummy)
    const desc_filename = "test_grouping_desc.bin";
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

    // Patient has MCC severity (via SDX) and AGE>65 (via attribute)
    var sdx = try models.DiagnosisCode.init("S001", 'Y');
    sdx.severity = .MCC;
    try data.sdx_codes.append(allocator, sdx);

    // Add "AGE>65" attribute to PDX (simulating it was added by preprocess)
    data.principal_dx = try models.DiagnosisCode.init("P001", 'Y');
    try data.principal_dx.?.attributes.append(allocator, models.Attribute{ .list_name = "AGE>65" });

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 3. Execute Processor
    var processor = grouping.MsdrgInitialPreGrouping{
        .formula_data = &formula_data,
        .description_data = &desc_data,
        .version = 400,
    };

    const result = try grouping.MsdrgInitialPreGrouping.execute(&processor, context);
    context = result.context;

    // 4. Verify Results
    try std.testing.expectEqual(@as(i32, 1), data.initial_result.drg.?);
    try std.testing.expectEqual(models.Severity.MCC, data.initial_severity);
    try std.testing.expectEqual(@as(usize, 1), context.initial_mdc.items.len);
    try std.testing.expectEqual(@as(i32, 0), context.initial_mdc.items[0]);
}

test "MsdrgInitialRerouting logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Formula Data:
    // Entry 1: MDC 0 -> Formula "MCC" -> Reroute to MDC 1
    // Entry 2: MDC 1 -> Formula "AGE>65" -> DRG 2
    const formula_filename = "test_reroute_formula.bin";
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
        try writeU32(file, 2); // 2 entries
        try writeU32(file, 2); // 2 formulas
        try writeU32(file, 24); // entries offset
        try writeU32(file, 24 + 2 * 20); // formulas offset
        try writeU32(file, 200); // strings offset

        // Entry 1: MDC 0
        try writeI32(file, 0);
        try writeI32(file, 400);
        try writeI32(file, 410);
        try writeU32(file, 0); // start_index
        try writeU32(file, 1); // count

        // Entry 2: MDC 1
        try writeI32(file, 1);
        try writeI32(file, 400);
        try writeI32(file, 410);
        try writeU32(file, 1); // start_index
        try writeU32(file, 1); // count

        // Formula 1: MDC 0, Reroute 1, Formula "MCC"
        try writeI32(file, 0);
        try writeI32(file, 1);
        try writeI32(file, 0);
        try writeI32(file, 0);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8);
        try writeI32(file, 1); // reroute to MDC 1
        try writeI32(file, 0);
        try writeU32(file, 200); // "MCC"
        try writeU32(file, 3);
        try writeU32(file, 0);
        try writeU32(file, 0);

        // Formula 2: MDC 1, DRG 2, Formula "AGE>65"
        try writeI32(file, 1);
        try writeI32(file, 1);
        try writeI32(file, 2); // base_drg 2
        try writeI32(file, 2); // drg 2
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8);
        try writeI32(file, 0); // no reroute
        try writeI32(file, 0);
        try writeU32(file, 204); // "AGE>65"
        try writeU32(file, 6);
        try writeU32(file, 0);
        try writeU32(file, 0);

        // Strings
        try std.Io.File.writePositionalAll(file, std.testing.io, "MCC", 200);
        try std.Io.File.writePositionalAll(file, std.testing.io, "AGE>65", 204);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, formula_filename) catch {};

    // Description Data (Dummy)
    const desc_filename = "test_reroute_desc.bin";
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

    // Patient has MCC and AGE>65
    var sdx = try models.DiagnosisCode.init("S001", 'Y');
    sdx.severity = .MCC;
    try data.sdx_codes.append(allocator, sdx);

    data.principal_dx = try models.DiagnosisCode.init("P001", 'Y');
    try data.principal_dx.?.attributes.append(allocator, models.Attribute{ .list_name = "AGE>65" });

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 3. Execute PreGrouping (MDC 0)
    var pre_grouper = grouping.MsdrgInitialPreGrouping{
        .formula_data = &formula_data,
        .description_data = &desc_data,
        .version = 400,
    };

    const res1 = try grouping.MsdrgInitialPreGrouping.execute(&pre_grouper, context);
    context = res1.context;

    // Verify PreGrouping found MDC 0 match with Reroute 1
    try std.testing.expect(context.initial_grouping_context.pre_match != null);
    try std.testing.expectEqual(@as(i32, 1), context.initial_grouping_context.pre_match.?.reroute_mdc_id);

    // 4. Execute Rerouting
    var rerouter = grouping.MsdrgInitialRerouting{
        .formula_data = &formula_data,
        .description_data = &desc_data,
        .version = 400,
    };

    const res2 = try grouping.MsdrgInitialRerouting.execute(&rerouter, context);
    context = res2.context;

    // Verify Rerouting found MDC 1 match -> DRG 2
    try std.testing.expectEqual(@as(i32, 2), data.initial_result.drg.?);
    try std.testing.expectEqual(@as(usize, 2), context.initial_mdc.items.len);
    try std.testing.expectEqual(@as(i32, 0), context.initial_mdc.items[0]);
    try std.testing.expectEqual(@as(i32, 1), context.initial_mdc.items[1]);
}

test "MsdrgInitialPdxGrouping logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Formula Data:
    // Entry 1: MDC 5 -> Formula "MCC" -> DRG 500
    const formula_filename = "test_pdx_formula.bin";
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

        // Entry 1: MDC 5
        try writeI32(file, 5);
        try writeI32(file, 400);
        try writeI32(file, 410);
        try writeU32(file, 0); // start_index
        try writeU32(file, 1); // count

        // Formula 1: MDC 5, DRG 500, Formula "MCC"
        try writeI32(file, 5);
        try writeI32(file, 1);
        try writeI32(file, 500); // base_drg
        try writeI32(file, 500); // drg
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0} ** 8);
        try writeI32(file, 0); // no reroute
        try writeI32(file, 0);
        try writeU32(file, 100); // "MCC"
        try writeU32(file, 3);
        try writeU32(file, 0);
        try writeU32(file, 0);

        // Strings
        try std.Io.File.writePositionalAll(file, std.testing.io, "MCC", 100);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, formula_filename) catch {};

    // Description Data (Dummy)
    const desc_filename = "test_pdx_desc.bin";
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

    // Patient has MCC
    var sdx = try models.DiagnosisCode.init("S001", 'Y');
    sdx.severity = .MCC;
    try data.sdx_codes.append(allocator, sdx);

    // PDX has MDC 5
    data.principal_dx = try models.DiagnosisCode.init("P001", 'Y');
    data.principal_dx.?.mdc = 5;

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 3. Execute PreGrouping (MDC 0) - Should fail
    var pre_grouper = grouping.MsdrgInitialPreGrouping{
        .formula_data = &formula_data,
        .description_data = &desc_data,
        .version = 400,
    };

    const res1 = try grouping.MsdrgInitialPreGrouping.execute(&pre_grouper, context);
    context = res1.context;

    try std.testing.expect(context.initial_grouping_context.pre_match == null);

    // 4. Execute PdxGrouping (MDC 5)
    var pdx_grouper = grouping.MsdrgInitialPdxGrouping{
        .formula_data = &formula_data,
        .description_data = &desc_data,
        .version = 400,
    };

    const res2 = try grouping.MsdrgInitialPdxGrouping.execute(&pdx_grouper, context);
    context = res2.context;

    // Verify PdxGrouping found MDC 5 match -> DRG 500
    try std.testing.expect(context.initial_grouping_context.pdx_match != null);
    try std.testing.expectEqual(@as(i32, 500), data.initial_result.drg.?);
    try std.testing.expectEqual(@as(usize, 1), context.initial_mdc.items.len);
    try std.testing.expectEqual(@as(i32, 5), context.initial_mdc.items[0]);
}

test "MsdrgInitialDrgResults logic" {
    const allocator = std.testing.allocator;

    // Setup dummy description data
    const desc_filename = "test_results_desc.bin";
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
        data.initial_result.drg = 100;

        var context = models.ProcessingContext.init(allocator, &data);
        defer context.deinit();

        var results_step = grouping.MsdrgInitialDrgResults{
            .description_data = &desc_data,
        };

        _ = try grouping.MsdrgInitialDrgResults.execute(&results_step, context);

        try std.testing.expectEqual(models.GrouperReturnCode.OK, data.initial_result.return_code);
    }

    // Case 2: No match found
    {
        var data = models.ProcessingData.init(allocator);
        defer data.deinit();
        // drg is null by default

        var context = models.ProcessingContext.init(allocator, &data);
        defer context.deinit();

        var results_step = grouping.MsdrgInitialDrgResults{
            .description_data = &desc_data,
        };

        _ = try grouping.MsdrgInitialDrgResults.execute(&results_step, context);

        try std.testing.expectEqual(models.GrouperReturnCode.UNGROUPABLE, data.initial_result.return_code);
    }
}
