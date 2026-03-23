const std = @import("std");
const models = @import("models.zig");
const preprocess = @import("preprocess.zig");
const code_map = @import("code_map.zig");
const exclusion = @import("exclusion.zig");
const diagnosis = @import("diagnosis.zig");
const pattern = @import("pattern.zig");
const common = @import("common.zig");
const gender = @import("gender.zig");
const hac = @import("hac.zig");
const description = @import("description.zig");

// Mock Data Structures
// We need to create mock versions of the data structures used by the processors.
// Since the processors take pointers to the data structs, we can create
// dummy structs with the same layout or use the real structs pointing to
// temporary files created for the test. Using temporary files is safer
// and ensures the binary parsing logic is also tested, although it's more setup.

// Helper to create a temporary file with content
fn createTempFile(content: []const u8) ![]const u8 {
    var buf: [64]u8 = undefined;
    const filename = try std.fmt.bufPrint(&buf, "test_{d}.bin", .{std.time.nanoTimestamp()});
    const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, filename, .{ .read = true });
    defer std.Io.File.close(file, std.testing.io);
    try std.Io.File.writeStreamingAll(file, std.testing.io, content);
    return try std.testing.allocator.dupe(u8, filename);
}

test "MsdrgExclusions logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Exclusion IDs: Map PDX "A001" -> Group ID 1
    const excl_ids_filename = "test_excl_ids.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, excl_ids_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x45584944, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Magic
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Num entries
        std.mem.writeInt(u32, &b, 12, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Offset

        // Entry: A001 -> 1
        var code_buf: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code_buf[0..4], "A001");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);
        std.mem.writeInt(i32, &b, 400, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Start
        std.mem.writeInt(i32, &b, 410, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // End
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Value (Group ID)
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, excl_ids_filename) catch {};

    // Exclusion Groups: Group 1 -> ["B002"]
    const excl_groups_filename = "test_excl_groups.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, excl_groups_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x4D534452, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Magic (MSDR)
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Num groups

        // Index Entry: Key 1, Count 1, Offset 20 (8 header + 12 index)
        std.mem.writeInt(i32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Key
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Count
        std.mem.writeInt(u32, &b, 20, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Offset

        // List Data: "B002"
        var code_buf: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code_buf[0..4], "B002");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, excl_groups_filename) catch {};

    var excl_ids = try code_map.CodeMapData.init(excl_ids_filename, 0x45584944);
    defer excl_ids.deinit();

    var excl_groups = try exclusion.ExclusionData.init(excl_groups_filename);
    defer excl_groups.deinit();

    // 2. Setup Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    // PDX: A001
    data.principal_dx = try models.DiagnosisCode.init("A001", 'Y');

    // SDX: B002 (Should be excluded), C003 (Should remain)
    try data.sdx_codes.append(allocator, try models.DiagnosisCode.init("B002", 'Y'));
    try data.sdx_codes.append(allocator, try models.DiagnosisCode.init("C003", 'Y'));

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 3. Execute Processor
    var processor = preprocess.MsdrgExclusions{
        .exclusion_ids = &excl_ids,
        .exclusion_groups = &excl_groups,
        .version = 400,
    };

    _ = try preprocess.MsdrgExclusions.execute(&processor, context);

    // 4. Verify Results
    try std.testing.expect(data.sdx_codes.items[0].is(.EXCLUDED));
    try std.testing.expect(!data.sdx_codes.items[1].is(.EXCLUDED));
}

test "PdxAttributeProcessor logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Diagnosis Data: "A001" -> Scheme 0
    const dx_filename = "test_dx.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, dx_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header: Magic(4), NumSchemes(4), NumDiagnoses(4), SchemesOff(4), DiagnosesOff(4)
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x44494147, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Num Schemes
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Num Diagnoses
        std.mem.writeInt(u32, &b, 20, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Schemes Offset (after header)
        std.mem.writeInt(u32, &b, 40, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Diagnoses Offset (after 1 scheme)

        // Scheme 0 (20 bytes): MDC 5, Sev "MCC ", Patterns 0, 0, 0
        std.mem.writeInt(i32, &b, 5, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // MDC
        try std.Io.File.writeStreamingAll(file, std.testing.io, "MCC "); // Severity (4 bytes)
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Operands Pattern
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // HAC Pattern
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Dx Cat Pattern

        // Diagnosis 0 (20 bytes): "A001", v400-410, Scheme 0
        var code_buf: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code_buf[0..4], "A001");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);
        std.mem.writeInt(i32, &b, 400, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(i32, &b, 410, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Scheme ID
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, dx_filename) catch {};

    // Pattern Data: Pattern 0 -> ["attr1"]
    const pat_filename = "test_pat.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, pat_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header: Magic(4), NumEntries(4), EntriesOff(4), ListDataOff(4), StringsOff(4)
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x44585054, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 20, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Entries Offset
        std.mem.writeInt(u32, &b, 32, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // List Data Offset (20 + 12)
        std.mem.writeInt(u32, &b, 40, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Strings Offset (32 + 8)

        // Entry: ID 0, Count 1, Offset 32
        std.mem.writeInt(u32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // ID
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Count
        std.mem.writeInt(u32, &b, 32, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Offset (Points to List Data)

        // List Data: StringRef { offset: 40, len: 5 }
        std.mem.writeInt(u32, &b, 40, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Offset
        std.mem.writeInt(u32, &b, 5, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Len

        // Strings: "attr1"
        try std.Io.File.writeStreamingAll(file, std.testing.io, "attr1");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0});
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, pat_filename) catch {};

    // Gender Data: "A001" -> Male MDC 5, Female MDC 6
    const gender_filename = "test_gender.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, gender_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x47454E44, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 12, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);

        // Entry
        var code_buf: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code_buf[0..4], "A001");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);
        std.mem.writeInt(i32, &b, 400, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(i32, &b, 410, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(i32, &b, 5, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Male
        std.mem.writeInt(i32, &b, 6, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Female
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, gender_filename) catch {};

    // HAC Desc Data (Dummy)
    const hac_filename = "test_hac_desc.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, hac_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x48414344, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, hac_filename) catch {};

    // Description Data (Dummy)
    const desc_filename = "test_desc.bin";
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

    var dx_data = try diagnosis.DiagnosisData.init(dx_filename);
    defer dx_data.deinit();
    var pat_data = try pattern.PatternData.init(pat_filename, 0x44585054);
    defer pat_data.deinit();
    var gender_data = try gender.GenderMdcData.init(gender_filename);
    defer gender_data.deinit();
    var hac_data = try hac.HacDescriptionData.init(hac_filename);
    defer hac_data.deinit();
    var desc_data = try description.DescriptionData.init(desc_filename, 0x44455343);
    defer desc_data.deinit();

    // 2. Setup Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();
    data.principal_dx = try models.DiagnosisCode.init("A001", 'Y');
    data.sex = .FEMALE; // Should pick MDC 6

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 3. Execute Processor
    var processor = preprocess.PdxAttributeProcessor{
        .diagnosis_data = &dx_data,
        .description_data = &desc_data,
        .dx_patterns = &pat_data,
        .gender_mdc = &gender_data,
        .hac_descriptions = &hac_data,
        .version = 400,
    };

    _ = try preprocess.PdxAttributeProcessor.execute(&processor, context);

    // 4. Verify Results
    const pdx = &data.principal_dx.?;
    try std.testing.expectEqual(models.Severity.MCC, pdx.severity);
    try std.testing.expectEqual(@as(i32, 6), pdx.mdc.?); // Female MDC
    try std.testing.expect(pdx.is(.VALID));
    try std.testing.expectEqual(@as(usize, 1), pdx.attributes.items.len);
    try std.testing.expectEqualStrings("attr1", pdx.attributes.items[0].list_name);
}

test "SdxAttributeProcessor logic" {
    const allocator = std.testing.allocator;

    // 1. Setup Mock Data
    // Diagnosis Data: "B002" -> Scheme 0
    const dx_filename = "test_sdx_dx.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, dx_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x44494147, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Num Schemes
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Num Diagnoses
        std.mem.writeInt(u32, &b, 20, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Schemes Offset
        std.mem.writeInt(u32, &b, 40, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Diagnoses Offset

        // Scheme 0: MDC 0, Sev "CC  ", Patterns 0, 0, 0
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // MDC
        try std.Io.File.writeStreamingAll(file, std.testing.io, "CC  "); // Severity
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Operands Pattern
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // HAC Pattern (Using pattern 0)
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Dx Cat Pattern

        // Diagnosis 0: "B002"
        var code_buf: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code_buf[0..4], "B002");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);
        std.mem.writeInt(i32, &b, 400, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(i32, &b, 410, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(i32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Scheme ID
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, dx_filename) catch {};

    // Pattern Data: Pattern 0 -> ["hac01"]
    const pat_filename = "test_sdx_pat.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, pat_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x44585054, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 20, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Entries Offset
        std.mem.writeInt(u32, &b, 32, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // List Data Offset
        std.mem.writeInt(u32, &b, 40, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Strings Offset

        // Entry 0
        std.mem.writeInt(u32, &b, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // ID
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Count
        std.mem.writeInt(u32, &b, 32, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Offset

        // List Data: StringRef { offset: 40, len: 5 }
        std.mem.writeInt(u32, &b, 40, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 5, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);

        // Strings: "hac01"
        try std.Io.File.writeStreamingAll(file, std.testing.io, "hac01");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0});
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, pat_filename) catch {};

    // HAC Desc Data: HAC 1 -> "Foreign Object"
    const hac_filename = "test_sdx_hac.bin";
    {
        const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, hac_filename, .{ .read = true });
        defer std.Io.File.close(file, std.testing.io);
        // Header: Magic(4), NumEntries(4), EntriesOff(4), StringsOff(4)
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, 0x48414344, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b);
        std.mem.writeInt(u32, &b, 16, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Entries Offset
        std.mem.writeInt(u32, &b, 36, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // Strings Offset (16 + 20)

        // Entry: ID 1, v400-410, Offset 36, Len 14
        var b2: [2]u8 = undefined;
        std.mem.writeInt(u16, &b2, 1, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b2); // ID
        std.mem.writeInt(u16, &b2, 0, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b2); // Pad
        std.mem.writeInt(i32, &b, 400, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // VStart
        std.mem.writeInt(i32, &b, 410, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // VEnd
        std.mem.writeInt(u32, &b, 36, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // DescOffset
        std.mem.writeInt(u32, &b, 14, .little);
        try std.Io.File.writeStreamingAll(file, std.testing.io, &b); // DescLen

        // Strings
        try std.Io.File.writeStreamingAll(file, std.testing.io, "Foreign Object");
        try std.Io.File.writeStreamingAll(file, std.testing.io, &[_]u8{0});
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, hac_filename) catch {};

    var dx_data = try diagnosis.DiagnosisData.init(dx_filename);
    defer dx_data.deinit();
    var pat_data = try pattern.PatternData.init(pat_filename, 0x44585054);
    defer pat_data.deinit();
    var hac_data = try hac.HacDescriptionData.init(hac_filename);
    defer hac_data.deinit();

    // 2. Setup Context
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();
    try data.sdx_codes.append(allocator, try models.DiagnosisCode.init("B002", 'Y'));

    var context = models.ProcessingContext.init(allocator, &data);
    defer context.deinit();

    // 3. Execute Processor
    var processor = preprocess.SdxAttributeProcessor{
        .diagnosis_data = &dx_data,
        .dx_patterns = &pat_data,
        .hac_descriptions = &hac_data,
        .version = 400,
    };

    _ = try preprocess.SdxAttributeProcessor.execute(&processor, context);

    // 4. Verify Results
    const sdx = &data.sdx_codes.items[0];
    try std.testing.expectEqual(models.Severity.CC, sdx.severity);
    try std.testing.expect(sdx.is(.VALID));

    // Check HACs
    try std.testing.expectEqual(@as(usize, 1), sdx.hacs.items.len);
    try std.testing.expectEqual(@as(i32, 1), sdx.hacs.items[0].hac_number);
    try std.testing.expectEqualStrings("hac01", sdx.hacs.items[0].hac_list);
    try std.testing.expectEqualStrings("Foreign Object", sdx.hacs.items[0].description);
}
