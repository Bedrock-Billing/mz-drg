const std = @import("std");
const models = @import("models.zig");
const formula = @import("formula.zig");
const description = @import("description.zig");
const chain = @import("chain.zig");
const common = @import("common.zig");

pub const Cumulatives = struct {
    bilateral_mask: u8,
    non_eluting_stent_count: u16,
    eluting_stent_count: u16,
    vessel_count: u16,
    single_fusion_count: u16,
    anterior_fusion_count: u16,
    posterior_fusion_count: u16,
    single_fusion_counter: u16,
    single_anterior_fusion_count: u16,
    single_posterior1_fusion_count: u16,
};

pub const MsdrgMaskBuilder = struct {
    const SIG_TRAUMAS = [_][]const u8{ "sthead", "stchest", "stabdom", "stkidney", "sturin", "stpel", "stuplimb", "stlolimb" };
    const BILATERALS = std.StaticStringMap(u3).initComptime(.{
        .{ "righthip", 0 },
        .{ "lefthip", 1 },
        .{ "leftknee", 2 },
        .{ "rightknee", 3 },
        .{ "leftankle", 4 },
        .{ "rightankle", 5 },
    });
    const MULTFUSIONS = std.StaticStringMap(u2).initComptime(.{
        .{ "sglantfuse", 0 },
        .{ "sglpostfuse1", 1 },
    });
    //Not sure why sglpostfuse is not suffixed with a number like sglpostfuse1 but the Java
    // code uses this so keeping it the same for now.
    const SNGLFUSIONCTR = std.StaticStringMap(u2).initComptime(.{
        .{ "sglantfuse", 0 },
        .{ "sglpostfuse", 1 },
    });

    pub fn buildMask(data: *models.ProcessingData, allocator: std.mem.Allocator) !std.StringHashMap(u32) {
        std.log.debug("MsdrgMaskBuilder: Building mask...", .{});
        var mask = std.StringHashMap(u32).init(allocator);
        errdefer mask.deinit();

        // Variables needed for cumulative attribute checks
        // Bitmask for found bilateral attributes
        var cumulatives: Cumulatives = .{
            .bilateral_mask = 0,
            .non_eluting_stent_count = 0,
            .eluting_stent_count = 0,
            .vessel_count = 0,
            .single_fusion_count = 0,
            .anterior_fusion_count = 0,
            .posterior_fusion_count = 0,
            .single_fusion_counter = 0,
            .single_anterior_fusion_count = 0,
            .single_posterior1_fusion_count = 0,
        };
        // Helper to add attribute
        const addAttr = struct {
            fn call(m: *std.StringHashMap(u32), attr: models.Attribute, alloc: std.mem.Allocator, c_attrs: *Cumulatives) !void {
                const key = try attr.toString(alloc);
                const attr_mask = attr.mdc_suppression.mask;

                if (m.getPtr(key)) |existing_mask| {
                    existing_mask.* &= attr_mask;
                    alloc.free(key);
                } else {
                    std.log.debug("MsdrgMaskBuilder: Adding attribute: {s} (suppression: {x})", .{ key, attr_mask });
                    try m.put(key, attr_mask);
                }

                if (BILATERALS.get(attr.list_name)) |bit_idx| {
                    c_attrs.bilateral_mask |= (@as(u8, 1) << bit_idx);
                }

                if (std.mem.startsWith(u8, attr.list_name, "vessel")) {
                    const last_char = attr.list_name[attr.list_name.len - 1];
                    if (last_char >= '1' and last_char <= '9') {
                        // - '0' to remove the null terminator
                        c_attrs.vessel_count += @as(u16, @intCast(last_char - '0'));
                    }
                }

                // Also add ANY:list_name
                const any_key = try std.fmt.allocPrint(alloc, "ANY:{s}", .{attr.list_name});
                if (m.getPtr(any_key)) |existing_mask| {
                    existing_mask.* &= attr_mask;
                    alloc.free(any_key);
                } else {
                    try m.put(any_key, attr_mask);
                }
            }
        }.call;

        // SDX Attributes
        for (data.sdx_codes.items) |sdx| {
            for (sdx.attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);
                const sdx_key = try std.fmt.allocPrint(allocator, "SDX:{s}", .{attr.list_name});
                const attr_mask = attr.mdc_suppression.mask;
                if (mask.getPtr(sdx_key)) |existing_mask| {
                    existing_mask.* &= attr_mask;
                    allocator.free(sdx_key);
                } else {
                    try mask.put(sdx_key, attr_mask);
                }
            }
            for (sdx.dx_cat_attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);
                const sdx_key = try std.fmt.allocPrint(allocator, "SDX:{s}", .{attr.list_name});
                const attr_mask = attr.mdc_suppression.mask;
                if (mask.getPtr(sdx_key)) |existing_mask| {
                    existing_mask.* &= attr_mask;
                    allocator.free(sdx_key);
                } else {
                    try mask.put(sdx_key, attr_mask);
                }
            }
            for (sdx.hac_attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);
                const sdx_key = try std.fmt.allocPrint(allocator, "SDX:{s}", .{attr.list_name});
                const attr_mask = attr.mdc_suppression.mask;
                if (mask.getPtr(sdx_key)) |existing_mask| {
                    existing_mask.* &= attr_mask;
                    allocator.free(sdx_key);
                } else {
                    try mask.put(sdx_key, attr_mask);
                }
            }
        }

        // Procedure Attributes
        for (data.procedure_codes.items) |proc| {
            var stent_weight: u16 = 0;
            var has_nordrugstent = false;
            var has_norstent = false;

            for (proc.attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);

                if (std.mem.startsWith(u8, attr.list_name, "stent")) {
                    const last_char = attr.list_name[attr.list_name.len - 1];
                    if (last_char >= '1' and last_char <= '4') {
                        stent_weight = @as(u16, @intCast(last_char - '0'));
                    }
                }
                if (std.mem.eql(u8, attr.list_name, models.SourceLogicLists.NORDRUGSTENT)) {
                    has_nordrugstent = true;
                }
                if (std.mem.eql(u8, attr.list_name, models.SourceLogicLists.NORSTENT)) {
                    has_norstent = true;
                }
                if (MULTFUSIONS.get(attr.list_name)) |bit_idx| {
                    cumulatives.single_fusion_count += 1;
                    if (bit_idx == 0) {
                        cumulatives.single_anterior_fusion_count += 1;
                    } else if (bit_idx == 1) {
                        cumulatives.single_posterior1_fusion_count += 1;
                    }
                }
                if (std.mem.eql(u8, attr.list_name, "sglantsectXfuse")) {
                    cumulatives.anterior_fusion_count += 1;
                }

                if (std.mem.eql(u8, attr.list_name, "sglpostfuse")) {
                    cumulatives.posterior_fusion_count += 1;
                }

                if (SNGLFUSIONCTR.has(attr.list_name)) {
                    cumulatives.single_fusion_counter += 1;
                }
            }

            if (has_nordrugstent) {
                cumulatives.eluting_stent_count += stent_weight;
            }
            if (has_norstent) {
                cumulatives.non_eluting_stent_count += stent_weight;
            }
        }

        // Cluster Attributes
        for (data.clusters.items) |cluster| {
            for (cluster.attributes.items) |attr| try addAttr(&mask, attr, allocator, &cumulatives);
        }

        // PDX Attributes
        if (data.principal_dx) |pdx| {
            for (pdx.attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);
                var pdx_attr = attr;
                pdx_attr.prefix = .PDX;
                try addAttr(&mask, pdx_attr, allocator, &cumulatives);
            }
            for (pdx.hac_attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);
                var pdx_attr = attr;
                pdx_attr.prefix = .PDX;
                try addAttr(&mask, pdx_attr, allocator, &cumulatives);
            }
            for (pdx.dx_cat_attributes.items) |attr| {
                try addAttr(&mask, attr, allocator, &cumulatives);
                var pdx_attr = attr;
                pdx_attr.prefix = .PDX;
                try addAttr(&mask, pdx_attr, allocator, &cumulatives);
            }

            if (!pdx.is(.VALID)) {
                try addAttr(&mask, models.Attribute{ .prefix = .PDX, .list_name = models.SourceLogicLists.INVALID_PDX }, allocator, &cumulatives);
            }

            // PDX ECODE check (starts with V, W, X, Y)
            const val = pdx.value.toSlice();
            if (val.len > 0) {
                const c = val[0];
                if (c == 'V' or c == 'W' or c == 'X' or c == 'Y') {
                    try addAttr(&mask, models.Attribute{ .prefix = .PDX, .list_name = models.SourceLogicLists.PDX_ECODE }, allocator, &cumulatives);
                }
            }

            // Incident check
            var has_incident = false;
            for (pdx.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.list_name, "incident")) {
                    has_incident = true;
                    break;
                }
            }

            if (has_incident) {
                var is_on_incident_list = true;
                for (data.sdx_codes.items) |sdx| {
                    if (!sdx.is(.VALID)) continue;
                    var sdx_incident = false;
                    for (sdx.attributes.items) |attr| {
                        if (std.mem.eql(u8, attr.list_name, "incident")) {
                            sdx_incident = true;
                            break;
                        }
                    }
                    if (!sdx_incident) {
                        is_on_incident_list = false;
                        break;
                    }
                }
                if (is_on_incident_list) {
                    try addAttr(&mask, models.Attribute{ .prefix = .ONLY, .list_name = "incident" }, allocator, &cumulatives);
                }
            }

            if (data.sex == .UNKNOWN and pdx.is(.SEX_CONFLICT)) {
                try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.INVALID_SEX }, allocator, &cumulatives);
            }

            // For MDC 20 add MDC 20 FALL Through
            if (pdx.mdc == 20) {
                try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.MDC_20_FALL_THRU }, allocator, &cumulatives);
            }
        }

        // Discharge Status
        if (data.discharge_status != .DIED) {
            try addAttr(&mask, models.Attribute{ .list_name = "ALIVE" }, allocator, &cumulatives);
        }

        if (data.discharge_status.formulaString()) |fs| {
            try addAttr(&mask, models.Attribute{ .list_name = fs }, allocator, &cumulatives);
        }

        const ds_int = @intFromEnum(data.discharge_status);
        if (ds_int == 2 or ds_int == 5 or ds_int == 66 or ds_int == 82 or ds_int == 85 or ds_int == 94) {
            try addAttr(&mask, models.Attribute{ .list_name = "XFRNBA" }, allocator, &cumulatives);
        }

        try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.ANYDX }, allocator, &cumulatives);

        // MULTST Logic
        var sig_traumas_found = std.StringHashMap(void).init(allocator);
        defer sig_traumas_found.deinit();

        const checkSigTrauma = struct {
            fn call(attrs: std.ArrayList(models.Attribute), found: *std.StringHashMap(void)) void {
                for (attrs.items) |attr| {
                    for (SIG_TRAUMAS) |st| {
                        if (std.mem.eql(u8, attr.list_name, st)) {
                            found.put(st, {}) catch {};
                        }
                    }
                }
            }
        }.call;

        if (data.principal_dx) |pdx| {
            checkSigTrauma(pdx.attributes, &sig_traumas_found);
        }
        for (data.sdx_codes.items) |sdx| {
            checkSigTrauma(sdx.attributes, &sig_traumas_found);
        }

        if (sig_traumas_found.count() >= 2) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.MULTST }, allocator, &cumulatives);
        }

        if (@popCount(cumulatives.bilateral_mask) > 1) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.BILATERAL }, allocator, &cumulatives);
        }

        if (cumulatives.non_eluting_stent_count >= 4) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.FOUR_NON_DRUG_ELUTING_STENTS }, allocator, &cumulatives);
        }

        if (cumulatives.eluting_stent_count >= 4) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.FOUR_DRUG_ELUTING_STENTS }, allocator, &cumulatives);
        }

        if (cumulatives.vessel_count >= 4) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.FOUR_VESSELS }, allocator, &cumulatives);
        }

        if (cumulatives.eluting_stent_count + cumulatives.non_eluting_stent_count >= 4) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.FOUR_STENTS }, allocator, &cumulatives);
        }

        if (cumulatives.single_fusion_count > 1) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.MULTFUSE }, allocator, &cumulatives);
        }

        if (cumulatives.single_fusion_count > 1) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.MULTFUSE }, allocator, &cumulatives);
        }

        if (cumulatives.anterior_fusion_count > 1) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.SGLANTSECTXCTR }, allocator, &cumulatives);
        }

        if (cumulatives.posterior_fusion_count > 1) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.SGLPOSTFUSECTR }, allocator, &cumulatives);
        }

        if (cumulatives.single_fusion_counter >= 3) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.SINGLEFUSIONCTR }, allocator, &cumulatives);
        }

        if (cumulatives.single_anterior_fusion_count >= 2) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.SGLANTFUSECTR }, allocator, &cumulatives);
        }

        if (cumulatives.single_posterior1_fusion_count >= 2) {
            try addAttr(&mask, models.Attribute{ .list_name = models.SourceLogicLists.SGLPOST1FUSECTR }, allocator, &cumulatives);
        }

        std.log.debug("Cumulative attributes: {any}", .{cumulatives});

        return mask;
    }
};

pub const MsdrgSeverityProcessor = struct {
    pub fn processClaimSeverity(sdx_codes: []models.DiagnosisCode, suppression_list: []const common.StringRef, base: [*]const u8) models.Severity {
        var max_sev = models.Severity.NONE;

        for (sdx_codes) |*sdx| {
            // Skip HAC codes — Java MsdrgFormulaEvaluation filters these out:
            //   nonHacCodes = sdxCodes.stream().filter(code -> !MsdrgHacProcessor.isHac(code, hospitalStatus))
            // After HAC processing, codes with HAC_CRITERIA_MET should not contribute to severity.
            var is_hac = false;
            for (sdx.hacs.items) |hac| {
                if (hac.hac_status == .HAC_CRITERIA_MET) {
                    is_hac = true;
                    break;
                }
            }
            // Also check hacs_flags (post-evaluation list)
            if (!is_hac) {
                for (sdx.hacs_flags.items) |hac| {
                    if (hac.hac_status == .HAC_CRITERIA_MET and hac.hac_number != 0) {
                        is_hac = true;
                        break;
                    }
                }
            }
            if (is_hac) continue;

            // Check suppression
            var suppressed = false;

            // The suppression list contains attribute names.
            // We check if the SDX has any of these attributes.
            for (suppression_list) |supp_ref| {
                const supp_str = supp_ref.get(base);
                for (sdx.attributes.items) |attr| {
                    if (std.mem.eql(u8, attr.list_name, supp_str)) {
                        suppressed = true;
                        break;
                    }
                }
                if (suppressed) break;
            }

            if (suppressed or sdx.is(.EXCLUDED) or sdx.is(.DEATH_EXCLUSION)) continue;

            if (@intFromEnum(sdx.severity) > @intFromEnum(max_sev)) {
                max_sev = sdx.severity;
            }
        }
        return max_sev;
    }
};

pub const GroupingExecutor = struct {
    pub fn group(
        formula_data: *const formula.FormulaData,
        data: *models.ProcessingData,
        allocator: std.mem.Allocator,
        mdc: i32,
        version: i32,
    ) !?struct { formula: formula.DrgFormula, severity: models.Severity, new_mdc: ?i32 } {
        std.log.debug("GroupingExecutor: Grouping for MDC {d}", .{mdc});

        // 1. Build Mask
        var mask = try MsdrgMaskBuilder.buildMask(data, allocator);

        defer {
            var it = mask.keyIterator();
            while (it.next()) |key| {
                allocator.free(key.*);
            }
            mask.deinit();
        }

        // 2. Get Formulas for MDC
        if (formula_data.getEntry(mdc, version)) |entry| {
            const formulas = formula_data.getFormulas();
            const start = entry.start_index;
            const end = start + entry.count;

            std.log.debug("GroupingExecutor: Found {d} formulas for MDC {d}", .{ entry.count, mdc });

            var i = start;
            while (i < end) : (i += 1) {
                const drg_formula = formulas[i];

                // Calculate Severity
                const supp_list = formula_data.getSuppressionList(drg_formula.supp_offset, drg_formula.supp_count);
                const base = formula_data.mapped.base_ptr;

                const severity = MsdrgSeverityProcessor.processClaimSeverity(data.sdx_codes.items, supp_list, base);

                // Add severity to mask temporarily
                const sev_str = switch (severity) {
                    .MCC => "MCC",
                    .CC => "CC",
                    .NONE => "NONE",
                };

                const sev_key = try allocator.dupe(u8, sev_str);
                try mask.put(sev_key, 0);

                // Evaluate Formula
                const formula_str = drg_formula.getFormula(base);
                std.log.debug("GroupingExecutor: Evaluating formula for DRG {d}: {s} (Severity: {s})", .{ drg_formula.drg, formula_str, sev_str });

                var lexer = formula.Lexer.init(formula_str);
                var tokens = try lexer.tokenize(allocator);
                defer tokens.deinit(allocator);

                var parser = formula.Parser.init(allocator, tokens.items);
                const root = parser.parse() catch |err| {
                    std.debug.print("Error parsing formula: {s}\n", .{formula_str});
                    return err;
                };
                defer formula.Evaluator.free(root, allocator);

                const is_match = formula.Evaluator.evaluate(root, &mask, mdc);

                // Remove severity from mask
                _ = mask.remove(sev_key);
                allocator.free(sev_key);

                if (is_match) {
                    if (drg_formula.drg == 0 and drg_formula.reroute_mdc_id == 0) {
                        std.log.debug("GroupingExecutor: Matched DRG 0, ignoring...", .{});
                        continue;
                    }

                    if (drg_formula.reroute_mdc_id != 0) {
                        std.log.debug("GroupingExecutor: DRG {d} triggers reroute to MDC {d}", .{ drg_formula.drg, drg_formula.reroute_mdc_id });
                        // Rerouting is now handled by MsdrgInitialRerouting/MsdrgFinalRerouting
                        // Return the matched formula with reroute info, let the chain handle the reroute
                    } else {
                        std.log.debug("GroupingExecutor: Match found! DRG: {d}", .{drg_formula.drg});
                    }

                    if (mdc == 0) {
                        if (data.principal_dx) |pdx| {
                            // If MDC is 0, use MDC of the principal DX as final MDC
                            return .{ .formula = drg_formula, .severity = severity, .new_mdc = pdx.mdc };
                        }
                    }
                    return .{ .formula = drg_formula, .severity = severity, .new_mdc = null };
                }
            }
        } else {
            std.log.debug("GroupingExecutor: No formulas found for MDC {d}", .{mdc});
        }
        return null;
    }
};

pub const MsdrgInitialPreGrouping = struct {
    formula_data: *const formula.FormulaData,
    description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        if (data.principal_dx) |pdx| {
            for (pdx.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.list_name, "ecode")) {
                    data.initial_result.drg = 999;
                    data.initial_result.mdc = 0;
                    data.initial_result.return_code = .DX_CANNOT_BE_PDX;

                    data.final_result.drg = 999;
                    data.final_result.mdc = 0;
                    data.final_result.return_code = .DX_CANNOT_BE_PDX;

                    return chain.LinkResult{
                        .context = context,
                        .continue_processing = false,
                    };
                }
            }
        }

        const result = try GroupingExecutor.group(self.formula_data, data, allocator, 0, self.version);

        if (result) |res| {
            data.initial_result.base_drg = res.formula.base_drg;
            data.initial_result.drg = res.formula.drg;
            if (res.new_mdc) |rr| {
                data.initial_result.mdc = rr;
            } else {
                data.initial_result.mdc = 0;
            }
            data.initial_result.reroute_mdc_id = res.formula.reroute_mdc_id;
            data.initial_severity = res.severity;

            var ctx = context;
            ctx.initial_grouping_context.pre_match = res.formula;
            try ctx.initial_mdc.append(allocator, 0);

            return chain.LinkResult{
                .context = ctx,
                .continue_processing = true,
            };
        } else {
            return chain.LinkResult{
                .context = context,
                .continue_processing = true,
            };
        }
    }
};

pub const MsdrgInitialRerouting = struct {
    formula_data: *const formula.FormulaData,
    description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        // Check if reroute is needed - check both pre_match and pdx_match
        // Track which match we're using to determine MDC handling
        const is_pre_match = context.initial_grouping_context.pdx_match == null and context.initial_grouping_context.pre_match != null;
        const match_to_check: ?formula.DrgFormula = context.initial_grouping_context.pdx_match orelse context.initial_grouping_context.pre_match;

        if (match_to_check) |matched_formula| {
            if (matched_formula.reroute_mdc_id != 0) {
                const reroute_mdc = matched_formula.reroute_mdc_id;

                const result = try GroupingExecutor.group(self.formula_data, data, allocator, reroute_mdc, self.version);

                if (result) |res| {
                    data.initial_result.base_drg = res.formula.base_drg;
                    data.initial_result.drg = res.formula.drg;
                    // If rerouting from pre_match (MDC 0), use the reroute MDC
                    // If rerouting from pdx_match, keep the original PDX MDC
                    if (is_pre_match) {
                        data.initial_result.mdc = reroute_mdc;
                    }
                    data.initial_result.reroute_mdc_id = res.formula.reroute_mdc_id;
                    data.initial_severity = res.severity;

                    var ctx = context;
                    ctx.initial_grouping_context.reroute_match = res.formula;
                    try ctx.initial_mdc.append(allocator, reroute_mdc);

                    if (res.formula.reroute_mdc_id != 0) {
                        const reroute_mdc_2 = res.formula.reroute_mdc_id;
                        const result_2 = try GroupingExecutor.group(self.formula_data, data, allocator, reroute_mdc_2, self.version);
                        if (result_2) |res_2| {
                            data.initial_result.base_drg = res_2.formula.base_drg;
                            data.initial_result.drg = res_2.formula.drg;
                            // For nested reroutes, DON'T update MDC - keep the first reroute MDC
                            // The MDC was already set to reroute_mdc above
                            data.initial_result.reroute_mdc_id = res_2.formula.reroute_mdc_id;
                            data.initial_severity = res_2.severity;

                            ctx.initial_grouping_context.reroute_match = res_2.formula;
                            try ctx.initial_mdc.append(allocator, reroute_mdc_2);
                        }
                    }

                    return chain.LinkResult{
                        .context = ctx,
                        .continue_processing = true,
                    };
                }
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const MsdrgInitialPdxGrouping = struct {
    formula_data: *const formula.FormulaData,
    description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        if (context.initial_grouping_context.hasMatch()) {
            return chain.LinkResult{
                .context = context,
                .continue_processing = true,
            };
        }

        if (data.principal_dx) |pdx| {
            if (pdx.mdc) |mdc| {
                const result = try GroupingExecutor.group(self.formula_data, data, allocator, mdc, self.version);

                if (result) |res| {
                    data.initial_result.base_drg = res.formula.base_drg;
                    data.initial_result.drg = res.formula.drg;
                    data.initial_result.mdc = mdc;
                    data.initial_result.reroute_mdc_id = res.formula.reroute_mdc_id;
                    data.initial_severity = res.severity;

                    var ctx = context;
                    ctx.initial_grouping_context.pdx_match = res.formula;
                    try ctx.initial_mdc.append(allocator, mdc);

                    return chain.LinkResult{
                        .context = ctx,
                        .continue_processing = true,
                    };
                }
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const MsdrgInitialDrgResults = struct {
    description_data: *const description.DescriptionData,
    mdc_description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;

        if (data.initial_result.drg == null) {
            data.initial_result.drg = 999;
            data.initial_result.mdc = 0;
            data.initial_result.return_code = .UNGROUPABLE;
        } else {
            data.initial_result.return_code = .OK;
        }

        // Fetch DRG description
        if (data.initial_result.drg) |drg| {
            if (self.description_data.getEntry(@intCast(drg), self.version)) |entry| {
                data.initial_result.drg_description = entry.getDescription(self.description_data.mapped.base_ptr);
            }
        }

        // Fetch MDC description
        if (data.initial_result.mdc) |mdc| {
            if (self.mdc_description_data.getEntry(@intCast(mdc), self.version)) |entry| {
                data.initial_result.mdc_description = entry.getDescription(self.mdc_description_data.mapped.base_ptr);
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const MsdrgFinalPreGrouping = struct {
    formula_data: *const formula.FormulaData,
    description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        const result = try GroupingExecutor.group(self.formula_data, data, allocator, 0, self.version);

        if (result) |res| {
            data.final_result.base_drg = res.formula.base_drg;
            data.final_result.drg = res.formula.drg;
            if (res.new_mdc) |rr| {
                data.final_result.mdc = rr;
            } else {
                data.final_result.mdc = 0;
            }
            data.final_result.reroute_mdc_id = res.formula.reroute_mdc_id;
            data.final_severity = res.severity;

            var ctx = context;
            ctx.final_grouping_context.pre_match = res.formula;
            try ctx.final_mdc.append(allocator, 0);

            return chain.LinkResult{
                .context = ctx,
                .continue_processing = true,
            };
        } else {
            return chain.LinkResult{
                .context = context,
                .continue_processing = true,
            };
        }
    }
};

pub const MsdrgFinalRerouting = struct {
    formula_data: *const formula.FormulaData,
    description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        // Check if reroute is needed - check both pdx_match and pre_match
        // Track which match we're using to determine MDC handling
        const is_pre_match = context.final_grouping_context.pdx_match == null and context.final_grouping_context.pre_match != null;
        const match_to_check: ?formula.DrgFormula = context.final_grouping_context.pdx_match orelse context.final_grouping_context.pre_match;

        if (match_to_check) |matched_formula| {
            if (matched_formula.reroute_mdc_id != 0) {
                const reroute_mdc = matched_formula.reroute_mdc_id;

                const result = try GroupingExecutor.group(self.formula_data, data, allocator, reroute_mdc, self.version);

                if (result) |res| {
                    data.final_result.base_drg = res.formula.base_drg;
                    data.final_result.drg = res.formula.drg;
                    // If rerouting from pre_match (MDC 0), use the reroute MDC
                    // If rerouting from pdx_match, keep the original PDX MDC
                    if (is_pre_match) {
                        data.final_result.mdc = reroute_mdc;
                    }
                    data.final_result.reroute_mdc_id = res.formula.reroute_mdc_id;
                    data.final_severity = res.severity;

                    var ctx = context;
                    ctx.final_grouping_context.reroute_match = res.formula;
                    try ctx.final_mdc.append(allocator, reroute_mdc);

                    if (res.formula.reroute_mdc_id != 0) {
                        const reroute_mdc_2 = res.formula.reroute_mdc_id;
                        const result_2 = try GroupingExecutor.group(self.formula_data, data, allocator, reroute_mdc_2, self.version);
                        if (result_2) |res_2| {
                            data.final_result.base_drg = res_2.formula.base_drg;
                            data.final_result.drg = res_2.formula.drg;
                            // For nested reroutes, DON'T update MDC - keep the first reroute MDC
                            // The MDC was already set to reroute_mdc above
                            data.final_result.reroute_mdc_id = res_2.formula.reroute_mdc_id;
                            data.final_severity = res_2.severity;

                            ctx.final_grouping_context.reroute_match = res_2.formula;
                            try ctx.final_mdc.append(allocator, reroute_mdc_2);
                        }
                    }

                    return chain.LinkResult{
                        .context = ctx,
                        .continue_processing = true,
                    };
                }
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const MsdrgFinalPdxGrouping = struct {
    formula_data: *const formula.FormulaData,
    description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;

        if (context.final_grouping_context.hasMatch()) {
            return chain.LinkResult{
                .context = context,
                .continue_processing = true,
            };
        }

        if (data.principal_dx) |pdx| {
            if (pdx.mdc) |mdc| {
                const result = try GroupingExecutor.group(self.formula_data, data, allocator, mdc, self.version);

                if (result) |res| {
                    data.final_result.base_drg = res.formula.base_drg;
                    data.final_result.drg = res.formula.drg;
                    data.final_result.mdc = mdc;
                    data.final_result.reroute_mdc_id = res.formula.reroute_mdc_id;
                    data.final_severity = res.severity;

                    var ctx = context;
                    ctx.final_grouping_context.pdx_match = res.formula;
                    try ctx.final_mdc.append(allocator, mdc);

                    return chain.LinkResult{
                        .context = ctx,
                        .continue_processing = true,
                    };
                }
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const MsdrgFinalDrgResults = struct {
    description_data: *const description.DescriptionData,
    mdc_description_data: *const description.DescriptionData,
    version: i32,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        if (data.final_result.drg == null) {
            data.final_result.drg = 999;
            data.final_result.mdc = 0;
            data.final_result.return_code = .UNGROUPABLE;
        } else {
            data.final_result.return_code = .OK;
        }

        // Fetch DRG description
        if (data.final_result.drg) |drg| {
            if (self.description_data.getEntry(@intCast(drg), self.version)) |entry| {
                data.final_result.drg_description = entry.getDescription(self.description_data.mapped.base_ptr);
            }
        }

        // Fetch MDC description
        if (data.final_result.mdc) |mdc| {
            if (self.mdc_description_data.getEntry(@intCast(mdc), self.version)) |entry| {
                data.final_result.mdc_description = entry.getDescription(self.mdc_description_data.mapped.base_ptr);
            }
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};
