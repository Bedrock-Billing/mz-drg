const std = @import("std");
const exclusion = @import("exclusion.zig");
const diagnosis = @import("diagnosis.zig");
const formula = @import("formula.zig");
const pattern = @import("pattern.zig");
const code_map = @import("code_map.zig");
const gender = @import("gender.zig");
const cluster = @import("cluster.zig");
const hac = @import("hac.zig");
const description = @import("description.zig");

pub const MsdrgData = struct {
    exclusion_groups: exclusion.ExclusionData,
    diagnosis: diagnosis.DiagnosisData,
    formulas: formula.FormulaData,
    dx_patterns: pattern.PatternData,
    pr_patterns: pattern.PatternData,
    procedure_attributes: code_map.CodeMapData,
    exclusion_ids: code_map.CodeMapData,
    gender_mdc: gender.GenderMdcData,
    cluster_info: cluster.ClusterInfoData,
    cluster_map: cluster.ClusterMapData,
    hac_descriptions: hac.HacDescriptionData,
    hac_formulas: hac.HacFormulaData,
    hac_operands: hac.HacOperandData,
    base_drg_descriptions: description.DescriptionData,
    drg_descriptions: description.DescriptionData,
    mdc_descriptions: description.DescriptionData,

    /// Initialize the MS-DRG data repository.
    /// The returned struct owns the file handles and memory mappings.
    /// Call deinit() to release resources.
    /// Pass by pointer to avoid copying file handles.
    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !MsdrgData {
        var self: MsdrgData = undefined;

        self.exclusion_groups = try initData(exclusion.ExclusionData, allocator, data_dir, "exclusion_groups.bin");
        errdefer self.exclusion_groups.deinit();

        self.diagnosis = try initData(diagnosis.DiagnosisData, allocator, data_dir, "diagnosis.bin");
        errdefer self.diagnosis.deinit();

        self.formulas = try initData(formula.FormulaData, allocator, data_dir, "drg_formulas.bin");
        errdefer self.formulas.deinit();

        self.dx_patterns = try initPattern(allocator, data_dir, "dx_patterns.bin", 0x44585054);
        errdefer self.dx_patterns.deinit();

        self.pr_patterns = try initPattern(allocator, data_dir, "pr_patterns.bin", 0x50525054);
        errdefer self.pr_patterns.deinit();

        self.procedure_attributes = try initCodeMap(allocator, data_dir, "procedure_attributes.bin", 0x50524154);
        errdefer self.procedure_attributes.deinit();

        self.exclusion_ids = try initCodeMap(allocator, data_dir, "exclusion_ids.bin", 0x45584944);
        errdefer self.exclusion_ids.deinit();

        self.gender_mdc = try initData(gender.GenderMdcData, allocator, data_dir, "gender_mdcs.bin");
        errdefer self.gender_mdc.deinit();

        self.cluster_info = try initData(cluster.ClusterInfoData, allocator, data_dir, "cluster_info.bin");
        errdefer self.cluster_info.deinit();

        self.cluster_map = try initData(cluster.ClusterMapData, allocator, data_dir, "cluster_map.bin");
        errdefer self.cluster_map.deinit();

        self.hac_descriptions = try initData(hac.HacDescriptionData, allocator, data_dir, "hac_descriptions.bin");
        errdefer self.hac_descriptions.deinit();

        self.hac_formulas = try initData(hac.HacFormulaData, allocator, data_dir, "hac_formulas.bin");
        errdefer self.hac_formulas.deinit();

        self.hac_operands = try initData(hac.HacOperandData, allocator, data_dir, "hac_operands.bin");
        errdefer self.hac_operands.deinit();

        self.base_drg_descriptions = try initDescription(allocator, data_dir, "base_drg_descriptions.bin", 0x42445247);
        errdefer self.base_drg_descriptions.deinit();

        self.drg_descriptions = try initDescription(allocator, data_dir, "drg_descriptions.bin", 0x44524744);
        errdefer self.drg_descriptions.deinit();

        self.mdc_descriptions = try initDescription(allocator, data_dir, "mdc_descriptions.bin", 0x4D444344);
        errdefer self.mdc_descriptions.deinit();

        return self;
    }

    pub fn deinit(self: *MsdrgData) void {
        self.exclusion_groups.deinit();
        self.diagnosis.deinit();
        self.formulas.deinit();
        self.dx_patterns.deinit();
        self.pr_patterns.deinit();
        self.procedure_attributes.deinit();
        self.exclusion_ids.deinit();
        self.gender_mdc.deinit();
        self.cluster_info.deinit();
        self.cluster_map.deinit();
        self.hac_descriptions.deinit();
        self.hac_formulas.deinit();
        self.hac_operands.deinit();
        self.base_drg_descriptions.deinit();
        self.drg_descriptions.deinit();
        self.mdc_descriptions.deinit();
    }

    fn initData(comptime T: type, allocator: std.mem.Allocator, data_dir: []const u8, filename: []const u8) !T {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, filename });
        defer allocator.free(path);
        return T.init(path);
    }

    fn initPattern(allocator: std.mem.Allocator, data_dir: []const u8, filename: []const u8, magic: u32) !pattern.PatternData {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, filename });
        defer allocator.free(path);
        return pattern.PatternData.init(path, magic);
    }

    fn initCodeMap(allocator: std.mem.Allocator, data_dir: []const u8, filename: []const u8, magic: u32) !code_map.CodeMapData {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, filename });
        defer allocator.free(path);
        return code_map.CodeMapData.init(path, magic);
    }

    fn initDescription(allocator: std.mem.Allocator, data_dir: []const u8, filename: []const u8, magic: u32) !description.DescriptionData {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, filename });
        defer allocator.free(path);
        return description.DescriptionData.init(path, magic);
    }
};
