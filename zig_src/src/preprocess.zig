const std = @import("std");
const models = @import("models.zig");
const chain = @import("chain.zig");
const msdrg_data = @import("msdrg_data.zig");
const cluster = @import("cluster.zig");
const common = @import("common.zig");
const code_map = @import("code_map.zig");
const pattern = @import("pattern.zig");
const exclusion = @import("exclusion.zig");
const diagnosis = @import("diagnosis.zig");
const description = @import("description.zig");
const gender = @import("gender.zig");
const hac = @import("hac.zig");

// --- MsdrgClusters ---
pub const MsdrgClusters = struct {
    cluster_info: *const cluster.ClusterInfoData,
    cluster_map: *const cluster.ClusterMapData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        std.log.debug("MsdrgClusters: Executing...", .{});

        if (data.procedure_codes.items.len > 0) {
            // 1. Identify candidate clusters
            var candidate_clusters = std.AutoHashMap(u16, void).init(allocator);
            defer candidate_clusters.deinit();

            for (data.procedure_codes.items) |proc| {
                const code_slice = proc.value.toSlice();
                if (self.cluster_map.getEntry(code_slice, self.version)) |entry| {
                    const clusters = self.cluster_map.getClusters(entry);
                    for (clusters) |c_idx| {
                        try candidate_clusters.put(c_idx, {});
                    }
                }
            }

            // 2. Process candidate clusters
            var it = candidate_clusters.keyIterator();
            while (it.next()) |c_idx_ptr| {
                const c_idx = c_idx_ptr.* - 1;

                if (c_idx >= self.cluster_info.mapped.header.num_clusters) {
                    std.log.err("MsdrgClusters: Cluster index {d} out of bounds (max {d})", .{ c_idx, self.cluster_info.mapped.header.num_clusters });
                    continue;
                }

                std.log.debug("MsdrgClusters: Processing cluster index {d}", .{c_idx});
                const cl = self.cluster_info.getCluster(c_idx);
                std.log.debug("MsdrgClusters: Got cluster, getting choices...", .{});
                var choices = cl.getChoices();
                const choice_count = choices.count;
                std.log.debug("MsdrgClusters: Choice count: {d}", .{choice_count});

                var choice_tracker = try std.DynamicBitSet.initEmpty(allocator, choice_count);
                defer choice_tracker.deinit();

                var chosen_procs = std.StringHashMap(void).init(allocator);
                defer chosen_procs.deinit();

                // Optimization: Load all choices for this cluster into a HashMap
                var code_to_choice = std.StringHashMap(u8).init(allocator);
                defer code_to_choice.deinit();

                var choice_iter = cl.getChoices();
                var choice_idx: u8 = 0;
                while (choice_iter.next()) |choice| {
                    std.log.debug("MsdrgClusters: Processing choice {d}", .{choice_idx});
                    var code_iter = choice.getCodes();
                    while (code_iter.next()) |code| {
                        try code_to_choice.put(code, choice_idx);
                    }
                    choice_idx += 1;
                }
                std.log.debug("MsdrgClusters: Choices mapped.", .{});

                // Now iterate patient procedures
                for (data.procedure_codes.items) |*proc| {
                    const code = proc.value.toSlice();
                    if (code_to_choice.get(code)) |c_index| {
                        choice_tracker.set(c_index);
                        try chosen_procs.put(code, {});
                    }

                    if (choice_tracker.count() == choice_count) {
                        // Cluster satisfied!
                        const cluster_code_str = cl.getName();
                        std.log.debug("MsdrgClusters: Cluster satisfied: {s}", .{cluster_code_str});

                        const cluster_proc = try models.ProcedureCode.init(cluster_code_str);

                        // Set MDC suppression
                        const supp_mdcs = cl.getSuppressionMdcs();
                        // NOTE: We do NOT apply suppression to the cluster code itself.
                        // The suppression applies to the COMPONENT procedures that make up the cluster.
                        // This allows the cluster code (and its attributes) to be active, while the
                        // individual components are suppressed to avoid double counting.

                        try data.clusters.append(allocator, cluster_proc);

                        // Update original procedures
                        for (data.procedure_codes.items) |*p| {
                            const p_code = p.value.toSlice();
                            if (chosen_procs.contains(p_code)) {
                                for (supp_mdcs) |mdc| {
                                    if (mdc < 32) {
                                        p.mdc_suppression.set(mdc);
                                    }
                                }
                                try p.cluster_ids.append(allocator, cluster_code_str);
                            }
                        }

                        break; // Done with this cluster
                    }
                }
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

// --- MsdrgExclusions ---
pub const MsdrgExclusions = struct {
    exclusion_ids: *const code_map.CodeMapData,
    exclusion_groups: *const exclusion.ExclusionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;

        std.log.debug("MsdrgExclusions: Executing...", .{});

        if (data.principal_dx) |pdx| {
            const pdx_slice = pdx.value.toSlice();
            // Look up PDX in exclusion_ids to get group ID
            if (self.exclusion_ids.getEntry(pdx_slice, self.version)) |entry| {
                const group_id = @as(i32, @intCast(entry.value));
                std.log.debug("MsdrgExclusions: PDX {s} maps to exclusion group {d}", .{ pdx_slice, group_id });
                // Look up group ID in exclusion_groups
                if (self.exclusion_groups.getGroup(group_id)) |group| {
                    const excluded_codes = self.exclusion_groups.getCodes(group);

                    // Mark excluded SDX codes
                    for (data.sdx_codes.items) |*sdx| {
                        const sdx_slice = sdx.value.toSlice();
                        for (excluded_codes) |ex_code| {
                            if (std.mem.eql(u8, sdx_slice, ex_code.toSlice())) {
                                std.log.debug("MsdrgExclusions: Excluding SDX {s}", .{sdx_slice});
                                sdx.mark(.EXCLUDED);
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Death exclusions
        if (data.discharge_status == .DIED) {
            for (data.sdx_codes.items) |*sdx| {
                for (sdx.attributes.items) |attr| {
                    if (std.mem.eql(u8, attr.list_name, "mccalive") or std.mem.eql(u8, attr.list_name, "MCCALIVE")) {
                        std.log.debug("MsdrgExclusions: Death exclusion for SDX {s}", .{sdx.value.toSlice()});
                        sdx.mark(.DEATH_EXCLUSION);
                        break;
                    }
                }
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

// --- MsdrgLifeStatus ---
pub const MsdrgLifeStatus = struct {
    // descriptionAccess: *const description.DescriptionData, // Not used for logic, only for error message

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        _ = ptr;
        const data = context.data;

        for (data.sdx_codes.items) |*sdx| {
            var has_mcc_alive = false;
            for (sdx.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.list_name, "MCCALIVE") or std.mem.eql(u8, attr.list_name, "mccalive")) {
                    has_mcc_alive = true;
                    break;
                }
            }

            if (has_mcc_alive and data.discharge_status == .NONE) {
                // Invalid discharge status
                data.initial_result.return_code = .INVALID_DISCHARGE_STATUS;
                data.final_result.return_code = .INVALID_DISCHARGE_STATUS;
                return chain.LinkResult{
                    .context = context,
                    .continue_processing = false,
                };
            }

            if (has_mcc_alive and data.discharge_status == .DIED) {
                sdx.mark(.DEATH_EXCLUSION);
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

// --- PdxAttributeProcessor ---
pub const PdxAttributeProcessor = struct {
    diagnosis_data: *const diagnosis.DiagnosisData,
    description_data: *const description.DescriptionData,
    dx_patterns: *const pattern.PatternData,
    gender_mdc: *const gender.GenderMdcData,
    hac_descriptions: *const hac.HacDescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        if (data.principal_dx) |*pdx| {
            const pdx_slice = pdx.value.toSlice();
            if (self.diagnosis_data.getDiagnosis(pdx_slice, self.version)) |entry| {
                const schemes = self.diagnosis_data.getSchemes();
                if (entry.scheme_id >= 0 and entry.scheme_id < schemes.len) {
                    const scheme = schemes[@as(usize, @intCast(entry.scheme_id))];

                    // Get Attributes
                    if (scheme.operands_pattern >= 0) {
                        if (self.dx_patterns.getPattern(@as(u32, @intCast(scheme.operands_pattern)))) |pat| {
                            const attrs = self.dx_patterns.getAttributes(pat);
                            const base = self.dx_patterns.mapped.base_ptr;
                            for (attrs) |attr_ref| {
                                const attr_str = attr_ref.get(base);
                                try pdx.attributes.append(allocator, models.Attribute{ .list_name = attr_str });
                            }
                        }
                    }

                    // Get Dx Cat Attributes
                    if (scheme.dx_cat_list_pattern >= 0) {
                        if (self.dx_patterns.getPattern(@as(u32, @intCast(scheme.dx_cat_list_pattern)))) |pat| {
                            const attrs = self.dx_patterns.getAttributes(pat);
                            const base = self.dx_patterns.mapped.base_ptr;
                            for (attrs) |attr_ref| {
                                const attr_str = attr_ref.get(base);
                                try pdx.dx_cat_attributes.append(allocator, models.Attribute{ .list_name = attr_str });
                            }
                        }
                    }

                    // Get HAC Attributes
                    if (scheme.hac_operand_pattern >= 0) {
                        if (self.dx_patterns.getPattern(@as(u32, @intCast(scheme.hac_operand_pattern)))) |pat| {
                            const attrs = self.dx_patterns.getAttributes(pat);
                            const base = self.dx_patterns.mapped.base_ptr;
                            for (attrs) |attr_ref| {
                                const attr_str = attr_ref.get(base);
                                try pdx.hac_attributes.append(allocator, models.Attribute{ .list_name = attr_str });
                            }
                        }
                    }

                    // Gender Check and MDC
                    var mdc_set = false;
                    if (self.gender_mdc.getEntry(pdx_slice, self.version)) |g_entry| {
                        // Code is on gender list
                        if (data.sex == .MALE) {
                            if (g_entry.male_mdc >= 0) {
                                pdx.mdc = g_entry.male_mdc;
                                mdc_set = true;
                            }
                        } else if (data.sex == .FEMALE) {
                            if (g_entry.female_mdc >= 0) {
                                pdx.mdc = g_entry.female_mdc;
                                mdc_set = true;
                            }
                        }

                        if (!mdc_set) {
                            pdx.mark(.SEX_CONFLICT);
                        }
                    }

                    if (!mdc_set) {
                        pdx.mdc = scheme.mdc;
                    }

                    // Set Severity
                    const sev_str = &scheme.severity;
                    if (std.mem.startsWith(u8, sev_str, "MCC")) {
                        pdx.severity = .MCC;
                    } else if (std.mem.startsWith(u8, sev_str, "CC")) {
                        pdx.severity = .CC;
                    } else {
                        pdx.severity = .NONE;
                    }
                }
            }

            // Check for hac11_pdx
            var has_hac11 = false;
            for (pdx.attributes.items) |attr| {
                if (std.mem.endsWith(u8, attr.list_name, "hac11_pdx")) {
                    has_hac11 = true;
                    break;
                }
            }

            if (has_hac11) {
                var desc: []const u8 = "";
                if (self.hac_descriptions.getEntry(11, self.version)) |hac_desc_entry| {
                    desc = hac_desc_entry.getDescription(self.hac_descriptions.mapped.base_ptr);
                }

                const hac_obj = models.Hac{
                    .hac_status = .NOT_ON_HAC_LIST,
                    .hac_list = "hac11_pdx",
                    .hac_number = 11,
                    .description = desc,
                };
                try pdx.hacs.append(allocator, hac_obj);
            }

            // Validate code
            if (self.diagnosis_data.getDiagnosis(pdx_slice, self.version) != null) {
                pdx.mark(.VALID);
            }
        }

        if (data.admit_dx) |*admit_dx| {
            const admit_slice = admit_dx.value.toSlice();
            if (self.diagnosis_data.getDiagnosis(admit_slice, self.version) != null) {
                admit_dx.mark(.VALID);
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

// --- SdxAttributeProcessor ---
pub const SdxAttributeProcessor = struct {
    diagnosis_data: *const diagnosis.DiagnosisData,
    dx_patterns: *const pattern.PatternData,
    hac_descriptions: *const hac.HacDescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        for (data.sdx_codes.items) |*sdx| {
            const sdx_slice = sdx.value.toSlice();
            if (self.diagnosis_data.getDiagnosis(sdx_slice, self.version)) |entry| {
                sdx.mark(.VALID);

                const schemes = self.diagnosis_data.getSchemes();
                if (entry.scheme_id >= 0 and entry.scheme_id < schemes.len) {
                    const scheme = schemes[@as(usize, @intCast(entry.scheme_id))];

                    // Set Severity
                    const sev_str = &scheme.severity;
                    std.log.debug("SdxAttributeProcessor: Code {s}, Scheme {d}, Severity {s}", .{ sdx_slice, entry.scheme_id, sev_str });
                    if (std.mem.startsWith(u8, sev_str, "MCC")) {
                        sdx.severity = .MCC;
                    } else if (std.mem.startsWith(u8, sev_str, "CC")) {
                        sdx.severity = .CC;
                    } else {
                        sdx.severity = .NONE;
                    }

                    // Get Attributes
                    if (scheme.operands_pattern >= 0) {
                        if (self.dx_patterns.getPattern(@as(u32, @intCast(scheme.operands_pattern)))) |pat| {
                            const attrs = self.dx_patterns.getAttributes(pat);
                            const base = self.dx_patterns.mapped.base_ptr;
                            for (attrs) |attr_ref| {
                                const attr_str = attr_ref.get(base);
                                try sdx.attributes.append(allocator, models.Attribute{ .list_name = attr_str });
                            }
                        }
                    }

                    // Get Dx Cat Attributes
                    if (scheme.dx_cat_list_pattern >= 0) {
                        if (self.dx_patterns.getPattern(@as(u32, @intCast(scheme.dx_cat_list_pattern)))) |pat| {
                            const attrs = self.dx_patterns.getAttributes(pat);
                            const base = self.dx_patterns.mapped.base_ptr;
                            for (attrs) |attr_ref| {
                                const attr_str = attr_ref.get(base);
                                try sdx.dx_cat_attributes.append(allocator, models.Attribute{ .list_name = attr_str });
                            }
                        }
                    }

                    // Get HAC Attributes
                    if (scheme.hac_operand_pattern >= 0) {
                        if (self.dx_patterns.getPattern(@as(u32, @intCast(scheme.hac_operand_pattern)))) |pat| {
                            const attrs = self.dx_patterns.getAttributes(pat);
                            const base = self.dx_patterns.mapped.base_ptr;
                            for (attrs) |attr_ref| {
                                const attr_str = attr_ref.get(base);
                                try sdx.hac_attributes.append(allocator, models.Attribute{ .list_name = attr_str });
                            }
                        }
                    }
                }
            }

            // HACs
            for (sdx.hac_attributes.items) |attr| {
                if (attr.list_name.len > 3 and (std.mem.startsWith(u8, attr.list_name, "hac") or std.mem.startsWith(u8, attr.list_name, "HAC"))) {
                    const num_start: usize = 3;
                    var num_end: usize = 3;
                    while (num_end < attr.list_name.len) : (num_end += 1) {
                        const c = attr.list_name[num_end];
                        if (c < '0' or c > '9') break;
                    }

                    if (num_end > num_start) {
                        const num_str = attr.list_name[num_start..num_end];
                        const hac_num = std.fmt.parseInt(u16, num_str, 10) catch continue;

                        var desc: []const u8 = "";
                        if (self.hac_descriptions.getEntry(hac_num, self.version)) |hac_desc_entry| {
                            desc = hac_desc_entry.getDescription(self.hac_descriptions.mapped.base_ptr);
                        }

                        const hac_obj = models.Hac{
                            .hac_status = .NOT_ON_HAC_LIST,
                            .hac_list = attr.list_name,
                            .hac_number = @as(i32, @intCast(hac_num)),
                            .description = desc,
                        };
                        try sdx.hacs.append(allocator, hac_obj);
                    }
                }
            }

            // hac06_show
            for (sdx.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.list_name, "hac06_show")) {
                    sdx.mark(.ON_SHOW_LIST);
                    break;
                }
            }

            // Clinical Significance
            // TODO: Missing source for clinical significance rank.
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
}; // --- ProcedureAttributeProcessor ---
pub const ProcedureAttributeProcessor = struct {
    procedure_attributes: *const code_map.CodeMapData,
    pr_patterns: *const pattern.PatternData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;
        // Process procedures
        for (data.procedure_codes.items) |*proc| {
            try self.processCode(proc, allocator);
        }

        // Process clusters
        for (data.clusters.items) |*cluster_proc| {
            try self.processCode(cluster_proc, allocator);
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }

    fn processCode(self: *const ProcedureAttributeProcessor, proc: *models.ProcedureCode, allocator: std.mem.Allocator) !void {
        const code_slice = proc.value.toSlice();
        // Lookup in code map (version 400 assumed)
        if (self.procedure_attributes.getEntry(code_slice, self.version)) |entry| {
            const pattern_id = @as(u32, @intCast(entry.value));
            std.log.debug("ProcedureAttributeProcessor: Code {s} -> Pattern ID {d}", .{ code_slice, pattern_id });
            if (self.pr_patterns.getPattern(pattern_id)) |pat| {
                const attrs = self.pr_patterns.getAttributes(pat);
                const base = self.pr_patterns.mapped.base_ptr;

                var has_d477 = false;
                var has_d468 = false;

                for (attrs) |attr_ref| {
                    const attr_str = attr_ref.get(base);
                    std.log.debug("ProcedureAttributeProcessor: Code {s} -> Attribute {s}", .{ code_slice, attr_str });

                    var attr = models.Attribute{ .list_name = attr_str };
                    // Apply MDC suppression to attributes
                    attr.mdc_suppression = proc.mdc_suppression;

                    try proc.attributes.append(allocator, attr);

                    if (std.mem.eql(u8, attr_str, "d477")) has_d477 = true;
                    if (std.mem.eql(u8, attr_str, "d468")) has_d468 = true;
                }

                // Add ORPROC if needed
                if (has_d477 or has_d468) {
                    var or_attr = models.Attribute{ .list_name = "ORPROC" };
                    or_attr.mdc_suppression = proc.mdc_suppression;
                    try proc.attributes.append(allocator, or_attr);
                }

                proc.is_valid_code = proc.attributes.items.len > 0;
            }
        }
    }
};
