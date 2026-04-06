const std = @import("std");
const chain = @import("chain.zig");
const models = @import("models.zig");
const preprocess = @import("preprocess.zig");
const grouping = @import("grouping.zig");
const marking = @import("marking.zig");
const hac = @import("hac.zig");
const cluster = @import("cluster.zig");
const code_map = @import("code_map.zig");
const pattern = @import("pattern.zig");
const exclusion = @import("exclusion.zig");
const diagnosis = @import("diagnosis.zig");
const description = @import("description.zig");
const gender = @import("gender.zig");
const formula = @import("formula.zig");
const conversion = @import("conversion.zig");

/// Chain link that builds the attribute mask once after preprocessing.
/// Stored on ProcessingData for reuse by grouping, marking, and HAC.
const BuildMask = struct {
    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        _ = ptr;
        const data = context.data;
        data.mask = try grouping.MsdrgMaskBuilder.buildMask(data, data.allocator);
        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const GrouperChain = struct {
    // Data sources
    cluster_info: cluster.ClusterInfoData,
    cluster_map: cluster.ClusterMapData,
    procedure_attributes: code_map.CodeMapData,
    pr_patterns: pattern.PatternData,
    diagnosis_data: diagnosis.DiagnosisData,
    dx_patterns: pattern.PatternData,
    exclusion_ids: code_map.CodeMapData,
    exclusion_groups: exclusion.ExclusionData,
    description_data: description.DescriptionData,
    mdc_description_data: description.DescriptionData,
    gender_mdc: gender.GenderMdcData,
    hac_descriptions: hac.HacDescriptionData,
    hac_formula_data: hac.HacFormulaData,
    formula_data: formula.FormulaData,

    // ICD-10 conversion tables (optional, loaded if files exist)
    cm_conversions: ?conversion.ConversionData = null,
    pcs_conversions: ?conversion.ConversionData = null,

    allocator: std.mem.Allocator,

    // Pre-built Links for supported versions (immutable after init, thread-safe)
    link_v400: ?chain.Link = null,
    link_v401: ?chain.Link = null,
    link_v410: ?chain.Link = null,
    link_v411: ?chain.Link = null,
    link_v420: ?chain.Link = null,
    link_v421: ?chain.Link = null,
    link_v430: ?chain.Link = null,
    link_v431: ?chain.Link = null,

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !GrouperChain {
        // Helper to join paths
        const join = std.fs.path.join;

        // Load all data files
        // Note: In a real app, we might want to handle errors more gracefully or lazy load
        // For now, we assume files exist and are valid.

        const cluster_info_path = try join(allocator, &[_][]const u8{ data_dir, "cluster_info.bin" });
        defer allocator.free(cluster_info_path);
        const cluster_info = try cluster.ClusterInfoData.init(cluster_info_path);

        const cluster_map_path = try join(allocator, &[_][]const u8{ data_dir, "cluster_map.bin" });
        defer allocator.free(cluster_map_path);
        const cluster_map = try cluster.ClusterMapData.init(cluster_map_path);

        const pr_attr_path = try join(allocator, &[_][]const u8{ data_dir, "procedure_attributes.bin" });
        defer allocator.free(pr_attr_path);
        const procedure_attributes = try code_map.CodeMapData.init(pr_attr_path, 0x50524154);

        const pr_patterns_path = try join(allocator, &[_][]const u8{ data_dir, "pr_patterns.bin" });
        defer allocator.free(pr_patterns_path);
        const pr_patterns = try pattern.PatternData.init(pr_patterns_path, 0x50525054);

        const dx_data_path = try join(allocator, &[_][]const u8{ data_dir, "diagnosis.bin" });
        defer allocator.free(dx_data_path);
        const diagnosis_data = try diagnosis.DiagnosisData.init(dx_data_path);

        const dx_patterns_path = try join(allocator, &[_][]const u8{ data_dir, "dx_patterns.bin" });
        defer allocator.free(dx_patterns_path);
        const dx_patterns = try pattern.PatternData.init(dx_patterns_path, 0x44585054);

        const ex_ids_path = try join(allocator, &[_][]const u8{ data_dir, "exclusion_ids.bin" });
        defer allocator.free(ex_ids_path);
        const exclusion_ids = try code_map.CodeMapData.init(ex_ids_path, 0x45584944);

        const ex_groups_path = try join(allocator, &[_][]const u8{ data_dir, "exclusion_groups.bin" });
        defer allocator.free(ex_groups_path);
        const exclusion_groups = try exclusion.ExclusionData.init(ex_groups_path);

        const desc_path = try join(allocator, &[_][]const u8{ data_dir, "drg_descriptions.bin" });
        defer allocator.free(desc_path);
        const description_data = try description.DescriptionData.init(desc_path, 0x44524744); // Magic for DRGD

        const mdc_desc_path = try join(allocator, &[_][]const u8{ data_dir, "mdc_descriptions.bin" });
        defer allocator.free(mdc_desc_path);
        const mdc_description_data = try description.DescriptionData.init(mdc_desc_path, 0x4D444344); // Magic for MDCD

        const gender_path = try join(allocator, &[_][]const u8{ data_dir, "gender_mdcs.bin" });
        defer allocator.free(gender_path);
        const gender_mdc = try gender.GenderMdcData.init(gender_path);

        const hac_desc_path = try join(allocator, &[_][]const u8{ data_dir, "hac_descriptions.bin" });
        defer allocator.free(hac_desc_path);
        const hac_descriptions = try hac.HacDescriptionData.init(hac_desc_path);

        const hac_formula_path = try join(allocator, &[_][]const u8{ data_dir, "hac_formulas.bin" });
        defer allocator.free(hac_formula_path);
        const hac_formula_data = try hac.HacFormulaData.init(hac_formula_path);

        const formula_path = try join(allocator, &[_][]const u8{ data_dir, "drg_formulas.bin" });
        defer allocator.free(formula_path);
        const formula_data = try formula.FormulaData.init(formula_path);

        // ICD-10 conversion tables (optional)
        const cm_conv_path = try join(allocator, &[_][]const u8{ data_dir, "icd10cm_conversions.bin" });
        defer allocator.free(cm_conv_path);
        const cm_conversions = conversion.ConversionData.init(cm_conv_path, 0x49434443) catch null;

        const pcs_conv_path = try join(allocator, &[_][]const u8{ data_dir, "icd10pcs_conversions.bin" });
        defer allocator.free(pcs_conv_path);
        const pcs_conversions = conversion.ConversionData.init(pcs_conv_path, 0x49434450) catch null;

        const self = GrouperChain{
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
            .cm_conversions = cm_conversions,
            .pcs_conversions = pcs_conversions,
            .allocator = allocator,
        };

        return self;
    }

    /// Initialize pre-built Links for all supported versions.
    /// MUST be called after the GrouperChain is in its final memory location (e.g., after heap allocation).
    /// This is necessary because the Links contain pointers back to GrouperChain's data fields.
    pub fn initLinks(self: *GrouperChain) !void {
        // Pre-build Links for all supported versions
        // These are immutable after init, enabling lock-free thread-safe access
        self.link_v400 = try self.createInternal(400);
        self.link_v401 = try self.createInternal(401);
        self.link_v410 = try self.createInternal(410);
        self.link_v411 = try self.createInternal(411);
        self.link_v420 = try self.createInternal(420);
        self.link_v421 = try self.createInternal(421);
        self.link_v430 = try self.createInternal(430);
        self.link_v431 = try self.createInternal(431);
    }

    pub fn deinit(self: *GrouperChain) void {
        // Free pre-built links
        if (self.link_v400) |*l| l.deinit(self.allocator);
        if (self.link_v401) |*l| l.deinit(self.allocator);
        if (self.link_v410) |*l| l.deinit(self.allocator);
        if (self.link_v411) |*l| l.deinit(self.allocator);
        if (self.link_v420) |*l| l.deinit(self.allocator);
        if (self.link_v421) |*l| l.deinit(self.allocator);
        if (self.link_v430) |*l| l.deinit(self.allocator);
        if (self.link_v431) |*l| l.deinit(self.allocator);

        // Free data sources
        self.cluster_info.deinit();
        self.cluster_map.deinit();
        self.procedure_attributes.deinit();
        self.pr_patterns.deinit();
        self.diagnosis_data.deinit();
        self.dx_patterns.deinit();
        self.exclusion_ids.deinit();
        self.exclusion_groups.deinit();
        self.description_data.deinit();
        self.mdc_description_data.deinit();
        self.gender_mdc.deinit();
        self.hac_descriptions.deinit();
        self.hac_formula_data.deinit();
        self.formula_data.deinit();

        // Free conversion data if loaded
        if (self.cm_conversions) |*c| c.deinit();
        if (self.pcs_conversions) |*c| c.deinit();
    }

    /// Convert MS-DRG version number to ICD-10 fiscal year.
    pub fn versionToYear(version: i32) u32 {
        return switch (version) {
            400, 401 => 2023,
            410, 411 => 2024,
            420, 421 => 2025,
            430, 431 => 2026,
            else => 0,
        };
    }

    /// Look up a single DX code conversion.
    /// Returns the converted code as a sentinel string allocated with `alloc`, or null if no mapping.
    pub fn convertDxCode(self: *const GrouperChain, code: []const u8, source_year: u32, target_year: u32, alloc: std.mem.Allocator) !?[:0]const u8 {
        if (self.cm_conversions) |*conv| {
            return try conv.convertCode(code, source_year, target_year, alloc);
        }
        return null;
    }

    /// Look up a single procedure code conversion.
    pub fn convertPrCode(self: *const GrouperChain, code: []const u8, source_year: u32, target_year: u32, alloc: std.mem.Allocator) !?[:0]const u8 {
        if (self.pcs_conversions) |*conv| {
            return try conv.convertCode(code, source_year, target_year, alloc);
        }
        return null;
    }

    /// Returns the pre-built Link for the given version.
    /// This is lock-free and thread-safe since the Link struct is small and
    /// only contains pointers to immutable data.
    /// Returns error.VersionNotSupported if version is not one of: 400, 401, 410, 411, 420, 421, 430, 431.
    pub fn getLink(self: *const GrouperChain, version: i32) !chain.Link {
        return switch (version) {
            400 => self.link_v400 orelse error.VersionNotSupported,
            401 => self.link_v401 orelse error.VersionNotSupported,
            410 => self.link_v410 orelse error.VersionNotSupported,
            411 => self.link_v411 orelse error.VersionNotSupported,
            420 => self.link_v420 orelse error.VersionNotSupported,
            421 => self.link_v421 orelse error.VersionNotSupported,
            430 => self.link_v430 orelse error.VersionNotSupported,
            431 => self.link_v431 orelse error.VersionNotSupported,
            else => error.VersionNotSupported,
        };
    }

    fn makeDeinit(comptime T: type) fn (*anyopaque, std.mem.Allocator) void {
        return struct {
            fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self = @as(*T, @ptrCast(@alignCast(ptr)));
                allocator.destroy(self);
            }
        }.deinit;
    }

    /// Creates a new Link for the given version. This allocates memory.
    /// Prefer using getLink() for thread-safe, lock-free access to pre-built links.
    /// This method is kept for backward compatibility.
    pub fn create(self: *const GrouperChain, version: i32) !chain.Link {
        return self.createInternal(version);
    }

    fn createInternal(self: *const GrouperChain, version: i32) !chain.Link {
        const allocator = self.allocator;

        // 1. Preprocessing Link
        const l_clusters = try allocator.create(preprocess.MsdrgClusters);
        l_clusters.* = preprocess.MsdrgClusters{ .cluster_info = &self.cluster_info, .cluster_map = &self.cluster_map, .version = version };

        const l_proc_attr = try allocator.create(preprocess.ProcedureAttributeProcessor);
        l_proc_attr.* = preprocess.ProcedureAttributeProcessor{ .procedure_attributes = &self.procedure_attributes, .pr_patterns = &self.pr_patterns, .version = version };

        const l_sdx_attr = try allocator.create(preprocess.SdxAttributeProcessor);
        l_sdx_attr.* = preprocess.SdxAttributeProcessor{ .diagnosis_data = &self.diagnosis_data, .dx_patterns = &self.dx_patterns, .hac_descriptions = &self.hac_descriptions, .version = version };

        const l_exclusions = try allocator.create(preprocess.MsdrgExclusions);
        l_exclusions.* = preprocess.MsdrgExclusions{ .exclusion_ids = &self.exclusion_ids, .exclusion_groups = &self.exclusion_groups, .version = version };

        const l_pdx_attr = try allocator.create(preprocess.PdxAttributeProcessor);
        l_pdx_attr.* = preprocess.PdxAttributeProcessor{ .diagnosis_data = &self.diagnosis_data, .description_data = &self.description_data, .dx_patterns = &self.dx_patterns, .gender_mdc = &self.gender_mdc, .hac_descriptions = &self.hac_descriptions, .version = version };

        const l_life_status = try allocator.create(preprocess.MsdrgLifeStatus);
        l_life_status.* = preprocess.MsdrgLifeStatus{};

        const l_code_setup = try allocator.create(preprocess.CodeSetup);
        l_code_setup.* = preprocess.CodeSetup{};

        const l_build_mask = try allocator.create(BuildMask);
        l_build_mask.* = BuildMask{};

        const preprocessing_links = [_]chain.Link{
            chain.Link{ .ptr = l_clusters, .executeFn = preprocess.MsdrgClusters.execute, .deinitFn = makeDeinit(preprocess.MsdrgClusters) },
            chain.Link{ .ptr = l_proc_attr, .executeFn = preprocess.ProcedureAttributeProcessor.execute, .deinitFn = makeDeinit(preprocess.ProcedureAttributeProcessor) },
            chain.Link{ .ptr = l_sdx_attr, .executeFn = preprocess.SdxAttributeProcessor.execute, .deinitFn = makeDeinit(preprocess.SdxAttributeProcessor) },
            chain.Link{ .ptr = l_code_setup, .executeFn = preprocess.CodeSetup.execute, .deinitFn = makeDeinit(preprocess.CodeSetup) },
            chain.Link{ .ptr = l_exclusions, .executeFn = preprocess.MsdrgExclusions.execute, .deinitFn = makeDeinit(preprocess.MsdrgExclusions) },
            chain.Link{ .ptr = l_pdx_attr, .executeFn = preprocess.PdxAttributeProcessor.execute, .deinitFn = makeDeinit(preprocess.PdxAttributeProcessor) },
            chain.Link{ .ptr = l_life_status, .executeFn = preprocess.MsdrgLifeStatus.execute, .deinitFn = makeDeinit(preprocess.MsdrgLifeStatus) },
            chain.Link{ .ptr = l_build_mask, .executeFn = BuildMask.execute, .deinitFn = makeDeinit(BuildMask) },
        };
        const preprocessing_link = try chain.createChain(allocator, &preprocessing_links);

        // 2. Initial Grouping Link
        const l_init_pre = try allocator.create(grouping.MsdrgInitialPreGrouping);
        l_init_pre.* = grouping.MsdrgInitialPreGrouping{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_init_reroute1 = try allocator.create(grouping.MsdrgInitialRerouting);
        l_init_reroute1.* = grouping.MsdrgInitialRerouting{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_init_pdx = try allocator.create(grouping.MsdrgInitialPdxGrouping);
        l_init_pdx.* = grouping.MsdrgInitialPdxGrouping{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_init_reroute2 = try allocator.create(grouping.MsdrgInitialRerouting);
        l_init_reroute2.* = grouping.MsdrgInitialRerouting{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_init_results = try allocator.create(grouping.MsdrgInitialDrgResults);
        l_init_results.* = grouping.MsdrgInitialDrgResults{ .description_data = &self.description_data, .mdc_description_data = &self.mdc_description_data, .version = version };

        const initial_grouping_links = [_]chain.Link{
            chain.Link{ .ptr = l_init_pre, .executeFn = grouping.MsdrgInitialPreGrouping.execute, .deinitFn = makeDeinit(grouping.MsdrgInitialPreGrouping) },
            chain.Link{ .ptr = l_init_reroute1, .executeFn = grouping.MsdrgInitialRerouting.execute, .deinitFn = makeDeinit(grouping.MsdrgInitialRerouting) },
            chain.Link{ .ptr = l_init_pdx, .executeFn = grouping.MsdrgInitialPdxGrouping.execute, .deinitFn = makeDeinit(grouping.MsdrgInitialPdxGrouping) },
            chain.Link{ .ptr = l_init_reroute2, .executeFn = grouping.MsdrgInitialRerouting.execute, .deinitFn = makeDeinit(grouping.MsdrgInitialRerouting) },
            chain.Link{ .ptr = l_init_results, .executeFn = grouping.MsdrgInitialDrgResults.execute, .deinitFn = makeDeinit(grouping.MsdrgInitialDrgResults) },
        };
        const initial_grouping_link = try chain.createChain(allocator, &initial_grouping_links);

        // 3. Initial Marking Link
        const l_init_dx_mark = try allocator.create(marking.InitialDiagnosisMarking);
        l_init_dx_mark.* = marking.InitialDiagnosisMarking{ .formula_data = &self.formula_data };

        const l_init_proc_mark = try allocator.create(marking.InitialProcedureMarking);
        l_init_proc_mark.* = marking.InitialProcedureMarking{ .formula_data = &self.formula_data };

        const l_init_dx_func = try allocator.create(marking.InitialDxFunctionMarking);
        l_init_dx_func.* = marking.InitialDxFunctionMarking{ .formula_data = &self.formula_data };

        const l_init_sg_func = try allocator.create(marking.InitialSgFunctionMarking);
        l_init_sg_func.* = marking.InitialSgFunctionMarking{ .formula_data = &self.formula_data };

        const initial_marking_links = [_]chain.Link{
            chain.Link{ .ptr = l_init_dx_mark, .executeFn = marking.InitialDiagnosisMarking.execute, .deinitFn = makeDeinit(marking.InitialDiagnosisMarking) },
            chain.Link{ .ptr = l_init_proc_mark, .executeFn = marking.InitialProcedureMarking.execute, .deinitFn = makeDeinit(marking.InitialProcedureMarking) },
            chain.Link{ .ptr = l_init_dx_func, .executeFn = marking.InitialDxFunctionMarking.execute, .deinitFn = makeDeinit(marking.InitialDxFunctionMarking) },
            chain.Link{ .ptr = l_init_sg_func, .executeFn = marking.InitialSgFunctionMarking.execute, .deinitFn = makeDeinit(marking.InitialSgFunctionMarking) },
        };
        const initial_marking_link = try chain.createChain(allocator, &initial_marking_links);

        // 4. HAC Processor
        const l_hac = try allocator.create(hac.MsdrgHacProcessor);
        l_hac.* = hac.MsdrgHacProcessor{ .formula_data = &self.hac_formula_data, .description_data = &self.hac_descriptions, .version = version };
        const hac_link = chain.Link{ .ptr = l_hac, .executeFn = hac.MsdrgHacProcessor.execute, .deinitFn = makeDeinit(hac.MsdrgHacProcessor) };

        // 5. Final Grouping Link
        const l_final_pre = try allocator.create(grouping.MsdrgFinalPreGrouping);
        l_final_pre.* = grouping.MsdrgFinalPreGrouping{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_final_reroute1 = try allocator.create(grouping.MsdrgFinalRerouting);
        l_final_reroute1.* = grouping.MsdrgFinalRerouting{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_final_pdx = try allocator.create(grouping.MsdrgFinalPdxGrouping);
        l_final_pdx.* = grouping.MsdrgFinalPdxGrouping{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_final_reroute2 = try allocator.create(grouping.MsdrgFinalRerouting);
        l_final_reroute2.* = grouping.MsdrgFinalRerouting{ .formula_data = &self.formula_data, .description_data = &self.description_data, .version = version };

        const l_final_results = try allocator.create(grouping.MsdrgFinalDrgResults);
        l_final_results.* = grouping.MsdrgFinalDrgResults{ .description_data = &self.description_data, .mdc_description_data = &self.mdc_description_data, .version = version };

        const final_grouping_links = [_]chain.Link{
            chain.Link{ .ptr = l_final_pre, .executeFn = grouping.MsdrgFinalPreGrouping.execute, .deinitFn = makeDeinit(grouping.MsdrgFinalPreGrouping) },
            chain.Link{ .ptr = l_final_reroute1, .executeFn = grouping.MsdrgFinalRerouting.execute, .deinitFn = makeDeinit(grouping.MsdrgFinalRerouting) },
            chain.Link{ .ptr = l_final_pdx, .executeFn = grouping.MsdrgFinalPdxGrouping.execute, .deinitFn = makeDeinit(grouping.MsdrgFinalPdxGrouping) },
            chain.Link{ .ptr = l_final_reroute2, .executeFn = grouping.MsdrgFinalRerouting.execute, .deinitFn = makeDeinit(grouping.MsdrgFinalRerouting) },
            chain.Link{ .ptr = l_final_results, .executeFn = grouping.MsdrgFinalDrgResults.execute, .deinitFn = makeDeinit(grouping.MsdrgFinalDrgResults) },
        };
        const final_grouping_link = try chain.createChain(allocator, &final_grouping_links);

        // 6. Final Marking Link
        const l_final_dx_mark = try allocator.create(marking.FinalDiagnosisMarking);
        l_final_dx_mark.* = marking.FinalDiagnosisMarking{ .formula_data = &self.formula_data };

        const l_final_proc_mark = try allocator.create(marking.FinalProcedureMarking);
        l_final_proc_mark.* = marking.FinalProcedureMarking{ .formula_data = &self.formula_data };

        const l_final_dx_func = try allocator.create(marking.FinalDxFunctionMarking);
        l_final_dx_func.* = marking.FinalDxFunctionMarking{ .formula_data = &self.formula_data };

        const l_final_sg_func = try allocator.create(marking.FinalSgFunctionMarking);
        l_final_sg_func.* = marking.FinalSgFunctionMarking{ .formula_data = &self.formula_data };

        const final_marking_links = [_]chain.Link{
            chain.Link{ .ptr = l_final_dx_mark, .executeFn = marking.FinalDiagnosisMarking.execute, .deinitFn = makeDeinit(marking.FinalDiagnosisMarking) },
            chain.Link{ .ptr = l_final_proc_mark, .executeFn = marking.FinalProcedureMarking.execute, .deinitFn = makeDeinit(marking.FinalProcedureMarking) },
            chain.Link{ .ptr = l_final_dx_func, .executeFn = marking.FinalDxFunctionMarking.execute, .deinitFn = makeDeinit(marking.FinalDxFunctionMarking) },
            chain.Link{ .ptr = l_final_sg_func, .executeFn = marking.FinalSgFunctionMarking.execute, .deinitFn = makeDeinit(marking.FinalSgFunctionMarking) },
        };
        const final_marking_link = try chain.createChain(allocator, &final_marking_links);

        // 7. Assemble Full Chain
        // Preprocessing -> InitialGrouping -> InitialMarking -> HAC -> FinalGrouping -> FinalMarking
        const full_chain_links = [_]chain.Link{
            preprocessing_link,
            initial_grouping_link,
            initial_marking_link,
            hac_link,
            final_grouping_link,
            final_marking_link,
        };

        return chain.createChain(allocator, &full_chain_links);
    }
};
