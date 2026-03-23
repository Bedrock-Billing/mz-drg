const std = @import("std");
const chain = @import("chain.zig");
const models = @import("models.zig");
const preprocess = @import("preprocess.zig");
const grouping = @import("grouping.zig");
const marking = @import("marking.zig");
const hac = @import("hac.zig");
const msdrg = @import("msdrg.zig");
const cluster = @import("cluster.zig");
const code_map = @import("code_map.zig");
const pattern = @import("pattern.zig");
const exclusion = @import("exclusion.zig");
const diagnosis = @import("diagnosis.zig");
const description = @import("description.zig");
const gender = @import("gender.zig");
const formula = @import("formula.zig");
const common = @import("common.zig");

// Helper to write integers
fn writeU32(f: std.Io.File, v: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, .little);
    try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
}

fn writeI32(f: std.Io.File, v: i32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(i32, &b, v, .little);
    try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
}

fn writeU8(f: std.Io.File, v: u8) !void {
    try std.Io.File.writeStreamingAll(f, std.testing.io, &[1]u8{v});
}

test "Full Grouper Chain Integration" {
    const allocator = std.testing.allocator;
    const version: i32 = 410;

    // --- 1. Create Mock Data Files ---

    // 1.1 Cluster Info
    const cluster_info_path = "test_int_cluster_info.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, cluster_info_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        // Header
        try writeU32(f, 0x434C494E); // Magic
        try writeU32(f, 1); // Num clusters
        try writeU32(f, 20); // Offsets offset
        try writeU32(f, 24); // Data offset
        try writeU32(f, 100); // Strings offset

        // Offsets
        try writeU32(f, 24); // Offset to Cluster 0 (at 24)

        // Cluster 0 Data
        try writeU32(f, 100); // Name offset
        try writeU32(f, 5); // Name len ("CODE1")
        try writeU8(f, 0); // supp_count
        try writeU8(f, 1); // choice_count

        // Choice 0
        try writeU8(f, 1); // choice_id
        try writeU8(f, 1); // code_count
        try writeU32(f, 100); // code offset
        try writeU32(f, 5); // code len

        // Strings
        try std.Io.File.writePositionalAll(f, std.testing.io, "CODE1", 100);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, cluster_info_path) catch {};

    // 1.2 Cluster Map
    const cluster_map_path = "test_int_cluster_map.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, cluster_map_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        // Header
        try writeU32(f, 0x434C4D50); // Magic
        try writeU32(f, 1); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 100); // List data offset

        // Entry 1: "A001" -> Cluster 0
        var code: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code[0..4], "A001");
        try std.Io.File.writeStreamingAll(f, std.testing.io, &code);
        try writeI32(f, 400); // v_start
        try writeI32(f, 420); // v_end
        try writeU32(f, 100); // list_offset
        try writeU32(f, 1); // list_count

        // List Data
        var cluster_idx: [2]u8 = undefined;
        std.mem.writeInt(u16, &cluster_idx, 0, .little); // Cluster 0
        try std.Io.File.writePositionalAll(f, std.testing.io, &cluster_idx, 100);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, cluster_map_path) catch {};

    // 1.3 Procedure Attributes (Empty)
    const pr_attr_path = "test_int_pr_attr.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, pr_attr_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x434F4445); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // List data offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, pr_attr_path) catch {};

    // 1.4 PR Patterns (Empty)
    const pr_patterns_path = "test_int_pr_patterns.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, pr_patterns_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x50525054); // Magic (PRPT)
        try writeU32(f, 0); // Num entries
        try writeU32(f, 20); // Entries offset
        try writeU32(f, 20); // List data offset
        try writeU32(f, 20); // Strings offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, pr_patterns_path) catch {};

    // 1.5 Diagnosis Data
    const dx_data_path = "test_int_dx_data.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, dx_data_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        // Header
        try writeU32(f, 0x44494147); // Magic
        try writeU32(f, 1); // Num schemes
        try writeU32(f, 1); // Num diagnoses
        try writeU32(f, 20); // Schemes offset
        try writeU32(f, 20 + 20); // Diagnoses offset (Scheme is 20 bytes)

        // Scheme 0 (at 20)
        // mdc(4), severity(4), operands_pattern(4), hac_operand_pattern(4), dx_cat_list_pattern(4)
        try writeI32(f, 1); // MDC 1
        try std.Io.File.writeStreamingAll(f, std.testing.io, "MCC\x00"); // Severity "MCC"
        try writeI32(f, 0); // Operands Pattern 0
        try writeI32(f, -1); // HAC Pattern -1 (None)
        try writeI32(f, -1); // Dx Cat Pattern -1 (None)

        // Diagnosis Entry (at 40)
        // code(8), v_start(4), v_end(4), scheme_id(4)
        var code: [8]u8 = [_]u8{0} ** 8;
        @memcpy(code[0..4], "A001");
        try std.Io.File.writeStreamingAll(f, std.testing.io, &code);
        try writeI32(f, 400); // v_start
        try writeI32(f, 420); // v_end
        try writeI32(f, 0); // scheme_id 0
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, dx_data_path) catch {};

    // 1.6 DX Patterns
    const dx_patterns_path = "test_int_dx_patterns.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, dx_patterns_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        // Header
        try writeU32(f, 0x44585054); // Magic (DXPT)
        try writeU32(f, 1); // Num entries
        try writeU32(f, 20); // Entries offset
        try writeU32(f, 32); // List data offset (20 + 12)
        try writeU32(f, 40); // Strings offset (32 + 8)

        // Entry 0 (at 20)
        // id(4), count(4), offset(4)
        try writeU32(f, 0); // ID 0
        try writeU32(f, 1); // Count 1
        try writeU32(f, 32); // Offset to list

        // List Data (at 32)
        // Item 0: offset(4), len(4)
        try writeU32(f, 40); // Offset to string
        try writeU32(f, 3); // Len 3

        // Strings (at 40)
        try std.Io.File.writePositionalAll(f, std.testing.io, "MCC", 40);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, dx_patterns_path) catch {};

    // 1.7 Exclusion IDs (Empty)
    const ex_ids_path = "test_int_ex_ids.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, ex_ids_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x434F4445); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // List data offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, ex_ids_path) catch {};

    // 1.8 Exclusion Groups (Empty)
    const ex_groups_path = "test_int_ex_groups.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, ex_groups_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x4D534452); // Magic (MSDR)
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // List data offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, ex_groups_path) catch {};

    // 1.9 Description Data
    const desc_path = "test_int_desc.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, desc_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x44455343); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // Strings offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, desc_path) catch {};

    // 1.9b MDC Description Data (Empty)
    const mdc_desc_path = "test_int_mdc_desc.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, mdc_desc_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x44455343); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // Strings offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, mdc_desc_path) catch {};

    // 1.10 Gender MDC (Empty)
    const gender_path = "test_int_gender.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, gender_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x47454E44); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, gender_path) catch {};

    // 1.11 HAC Descriptions (Empty)
    const hac_desc_path = "test_int_hac_desc.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, hac_desc_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x48414344); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // Strings offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, hac_desc_path) catch {};

    // 1.11b HAC Formula (Empty)
    const hac_formula_path = "test_int_hac_formula.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, hac_formula_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        try writeU32(f, 0x48414346); // Magic
        try writeU32(f, 0); // Num entries
        try writeU32(f, 16); // Entries offset
        try writeU32(f, 16); // List data offset
        try writeU32(f, 16); // Strings offset
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, hac_formula_path) catch {};

    // 1.12 Formula Data
    const formula_path = "test_int_formula.bin";
    {
        const f = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, formula_path, .{});
        defer std.Io.File.close(f, std.testing.io);
        // Header
        try writeU32(f, 0x464F524D); // Magic
        try writeU32(f, 1); // Num entries
        try writeU32(f, 1); // Num formulas
        try writeU32(f, 24); // Entries offset
        try writeU32(f, 44); // Formulas offset (24 + 20)
        try writeU32(f, 100); // Strings offset

        // Entry 1: MDC 1
        try writeI32(f, 1); // MDC
        try writeI32(f, 400); // v_start
        try writeI32(f, 420); // v_end
        try writeU32(f, 0); // start_index
        try writeU32(f, 1); // count

        // Formula 1: DRG 100
        try writeI32(f, 1); // MDC
        try writeI32(f, 1); // Rank
        try writeI32(f, 100); // Base DRG
        try writeI32(f, 100); // DRG
        try std.Io.File.writeStreamingAll(f, std.testing.io, &[_]u8{0} ** 8); // Surgical
        try writeI32(f, 0); // Reroute MDC
        try writeI32(f, 0); // Severity
        try writeU32(f, 100); // Formula offset
        try writeU32(f, 3); // Formula len ("MCC")
        try writeU32(f, 0); // Supp offset
        try writeU32(f, 0); // Supp count

        // Strings
        try std.Io.File.writePositionalAll(f, std.testing.io, "MCC", 100);
    }
    defer std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, formula_path) catch {};

    // --- 2. Initialize Data Structs ---
    const cluster_info = try cluster.ClusterInfoData.init(cluster_info_path);
    // defer cluster_info.deinit();

    const cluster_map = try cluster.ClusterMapData.init(cluster_map_path);
    // defer cluster_map.deinit();

    const procedure_attributes = try code_map.CodeMapData.init(pr_attr_path, 0x434F4445);
    // defer procedure_attributes.deinit();

    const pr_patterns = try pattern.PatternData.init(pr_patterns_path, 0x50525054);
    // defer pr_patterns.deinit();

    const diagnosis_data = try diagnosis.DiagnosisData.init(dx_data_path);
    // defer diagnosis_data.deinit();

    const dx_patterns = try pattern.PatternData.init(dx_patterns_path, 0x44585054);
    // defer dx_patterns.deinit();

    const exclusion_ids = try code_map.CodeMapData.init(ex_ids_path, 0x434F4445);
    // defer exclusion_ids.deinit();

    const exclusion_groups = try exclusion.ExclusionData.init(ex_groups_path);
    // defer exclusion_groups.deinit();

    const description_data = try description.DescriptionData.init(desc_path, 0x44455343);
    // defer description_data.deinit();

    const mdc_description_data = try description.DescriptionData.init(mdc_desc_path, 0x44455343);
    // defer mdc_description_data.deinit();

    const gender_mdc = try gender.GenderMdcData.init(gender_path);
    // defer gender_mdc.deinit();

    const hac_descriptions = try hac.HacDescriptionData.init(hac_desc_path);
    // defer hac_descriptions.deinit();

    const hac_formula_data = try hac.HacFormulaData.init(hac_formula_path);
    // defer hac_formula_data.deinit();

    const formula_data = try formula.FormulaData.init(formula_path);
    // defer formula_data.deinit();

    // --- 3. Create Grouper Chain ---
    var grouper_chain = msdrg.GrouperChain{
        .cluster_info = cluster_info,
        .cluster_map = cluster_map,
        .procedure_attributes = procedure_attributes,
        .pr_patterns = pr_patterns,
        .diagnosis_data = diagnosis_data,
        .dx_patterns = dx_patterns,
        .exclusion_ids = exclusion_ids,
        .exclusion_groups = exclusion_groups,
        .description_data = description_data,
        .mdc_description_data = mdc_description_data,
        .gender_mdc = gender_mdc,
        .hac_descriptions = hac_descriptions,
        .hac_formula_data = hac_formula_data,
        .formula_data = formula_data,
        .allocator = allocator,
    };
    defer grouper_chain.deinit();

    var link = try grouper_chain.create(version);
    defer link.deinit(allocator);

    // --- 4. Create Processing Context ---
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    var context = models.ProcessingContext.init(allocator, &data, .{});
    defer context.deinit();

    // Add Patient Data
    // PDX: A001
    const pdx = try models.DiagnosisCode.init("A001", 'Y');
    context.data.principal_dx = pdx;
    context.data.sex = .MALE;
    context.data.discharge_status = .HOME_SELFCARE_ROUTINE;
    context.data.age = 70;

    // --- 5. Run Chain ---
    const result = try link.execute(context);
    var final_ctx = result.context;
    defer final_ctx.deinit();

    try std.testing.expect(result.continue_processing);

    // --- 6. Verify Results ---

    // Check Preprocessing
    // PDX should have MDC 1 and Severity MCC
    try std.testing.expectEqual(@as(i32, 1), context.data.principal_dx.?.mdc);
    try std.testing.expectEqual(models.Severity.MCC, context.data.principal_dx.?.severity);

    // Check Attributes
    // PDX should have "MCC" attribute
    var has_mcc = false;
    for (context.data.principal_dx.?.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.list_name, "MCC")) {
            has_mcc = true;
            break;
        }
    }
    try std.testing.expect(has_mcc);

    // Check Initial Grouping
    // Should be DRG 100
    try std.testing.expectEqual(@as(i32, 100), context.data.initial_result.drg);
    try std.testing.expectEqual(@as(i32, 1), context.data.initial_result.mdc);

    // Check Final Grouping
    // Should be DRG 100
    try std.testing.expectEqual(@as(i32, 100), context.data.final_result.drg);
    try std.testing.expectEqual(@as(i32, 1), context.data.final_result.mdc);
}
