const std = @import("std");
const models = @import("models.zig");
const formula = @import("formula.zig");
const chain = @import("chain.zig");
const grouping = @import("grouping.zig");

fn getWinningFormula(ctx: models.GroupingContext) ?formula.DrgFormula {
    if (ctx.pdx_match) |f| return f;
    if (ctx.reroute_match) |f| return f;
    if (ctx.pre_match) |f| return f;
    return null;
}

fn updateImpactDirection(code: anytype, impact: models.GroupingImpact) void {
    if (impact == .INITIAL) {
        if (code.drg_impact == .FINAL) {
            code.drg_impact = .BOTH;
        } else if (code.drg_impact == .NONE) {
            code.drg_impact = .INITIAL;
        }
    } else if (impact == .FINAL) {
        if (code.drg_impact == .INITIAL) {
            code.drg_impact = .BOTH;
        } else if (code.drg_impact == .NONE) {
            code.drg_impact = .FINAL;
        }
    }
}

fn markDiagnosisCodes(
    context: models.ProcessingContext,
    grouping_ctx: models.GroupingContext,
    formula_data: *const formula.FormulaData,
    allocator: std.mem.Allocator,
    mark_flag: models.CodeFlag,
    impact: models.GroupingImpact,
    severity: models.Severity,
    mdc: i32,
) !void {
    const data = context.data;

    const winning_formula = getWinningFormula(grouping_ctx);
    if (winning_formula == null) {
        std.log.debug("DiagnosisMarking: No winning formula found.", .{});
        return;
    }

    const drg_formula = winning_formula.?;
    std.log.debug("DiagnosisMarking: Winning formula found for DRG {d}", .{drg_formula.drg});

    const base = formula_data.mapped.base_ptr();
    const formula_str = drg_formula.getFormula(base);

    const mask = &data.mask.?;

    const sev_str = switch (severity) {
        .MCC => "MCC",
        .CC => "CC",
        .NONE => "NONE",
    };
    const sev_key = try allocator.dupe(u8, sev_str);
    try mask.put(sev_key, 0);
    defer {
        _ = mask.remove(sev_key);
        allocator.free(sev_key);
    }

    var lexer = formula.Lexer.init(formula_str);
    var tokens = try lexer.tokenize(allocator);
    defer tokens.deinit(allocator);

    var parser = formula.Parser.init(allocator, tokens.items);
    const root = parser.parse() catch |err| {
        std.debug.print("Error parsing formula: {s}\n", .{formula_str});
        return err;
    };
    defer formula.Evaluator.free(root, allocator);

    var formula_attributes = std.StringHashMap(void).init(allocator);
    defer {
        var it = formula_attributes.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        formula_attributes.deinit();
    }

    _ = try formula.Evaluator.collectMatchedAttributes(root, mask, &formula_attributes, allocator, mdc);

    var remaining_attributes = std.StringHashMap(void).init(allocator);
    defer remaining_attributes.deinit();

    var it = formula_attributes.keyIterator();
    while (it.next()) |key| {
        try remaining_attributes.put(key.*, {});
    }

    for (data.sdx_codes.items) |*sdx| {
        var matched_attr_key: ?[]const u8 = null;
        var matched_attr_obj: ?models.Attribute = null;

        var it_rem = remaining_attributes.keyIterator();
        while (it_rem.next()) |key_ptr| {
            const attr_str = key_ptr.*;

            if (data.principal_dx) |pdx| {
                if (std.mem.indexOf(u8, attr_str, ":") == null) {
                    var pdx_has = false;
                    for (pdx.attributes.items) |a| {
                        if (std.mem.eql(u8, a.list_name, attr_str)) {
                            pdx_has = true;
                            break;
                        }
                    }
                    if (pdx_has) continue;
                }
            }

            if (std.mem.eql(u8, attr_str, "MCC") or std.mem.eql(u8, attr_str, "CC")) {
                if (sdx.is(.DOWNGRADE_SEVERITY_SUPPRESSION) or sdx.is(.EXCLUDED) or sdx.is(.DEATH_EXCLUSION)) continue;

                const sdx_sev_str = switch (sdx.severity) {
                    .MCC => "MCC",
                    .CC => "CC",
                    .NONE => "NONE",
                };
                if (std.mem.eql(u8, sdx_sev_str, attr_str)) {
                    matched_attr_key = attr_str;
                    break;
                }
            }

            var has_attr = false;
            var check_str = attr_str;
            if (std.mem.startsWith(u8, attr_str, "SDX:")) {
                check_str = attr_str[4..];
            }

            for (sdx.attributes.items) |a| {
                if (a.matchesString(check_str)) {
                    has_attr = true;
                    matched_attr_obj = a;
                    break;
                }
            }
            if (!has_attr) {
                for (sdx.dx_cat_attributes.items) |a| {
                    if (a.matchesString(check_str)) {
                        has_attr = true;
                        matched_attr_obj = a;
                        break;
                    }
                }
            }

            if (has_attr) {
                matched_attr_key = attr_str;
                break;
            }
        }

        if (matched_attr_key) |key| {
            std.log.debug("DiagnosisMarking: Marking SDX {s} for attribute {s}", .{ sdx.value.toSlice(), key });
            sdx.mark(mark_flag);
            sdx.attribute_marked_for = matched_attr_obj;
            updateImpactDirection(sdx, impact);
            _ = remaining_attributes.remove(key);
        }
    }
}

fn markDiagnosisCodesFinalExtra(context: models.ProcessingContext) !void {
    const data = context.data;

    const final_drg = getWinningDrg(context.final_grouping_context);
    const initial_drg = getWinningDrg(context.initial_grouping_context);

    if (final_drg != null and initial_drg != null and final_drg.? != initial_drg.?) {
        for (data.sdx_codes.items) |*sdx| {
            if (sdx.hacs.items.len > 0) {
                sdx.mark(.MARKED_FOR_FINAL);
                updateImpactDirection(sdx, .FINAL);
            }
        }
    }

    var return_code = models.GrouperReturnCode.OK;
    if (data.final_result.return_code != .OK) {
        return_code = data.final_result.return_code;
    }

    if (return_code == .OK) {
        if (data.principal_dx) |*pdx| {
            pdx.drg_impact = .BOTH;
            pdx.mark(.MARKED_FOR_INITIAL);
            pdx.mark(.MARKED_FOR_FINAL);
        }
    }

    const hospital_status = context.runtime.poa_reporting_exempt;
    for (data.sdx_codes.items) |*sdx| {
        const excluded = sdx.is(.EXCLUDED);
        const death_excluded = sdx.is(.DEATH_EXCLUSION);
        const is_hac_val = isHac(sdx, hospital_status);

        if (sdx.severity != .NONE and !excluded and !death_excluded and is_hac_val) {
            sdx.markSeverityFlag(.FINAL);
        } else if (excluded and !death_excluded) {
            sdx.markSeverityFlag(.FINAL);
        } else if (!excluded and !death_excluded and sdx.severity != .NONE) {
            sdx.markSeverityFlag(.FINAL);
        }
        if ((excluded or death_excluded) and sdx.severity != .NONE) {
            sdx.markSeverityFlag(.FINAL);
        }
    }
}

pub const InitialDiagnosisMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));

        std.log.debug("InitialDiagnosisMarking: Executing...", .{});

        try markDiagnosisCodes(
            context,
            context.initial_grouping_context,
            self.formula_data,
            context.allocator,
            .MARKED_FOR_INITIAL,
            .INITIAL,
            context.data.initial_severity,
            context.data.initial_result.mdc orelse 0,
        );

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

const COMPLETE_SYSTEM = std.StaticStringMap(void).initComptime(.{.{ "revision", {} }});
const UNRELATED_DRGS = [_]i32{ 981, 982, 983, 987, 988, 989 };

fn isUnrelated(drg: i32) bool {
    for (UNRELATED_DRGS) |u| {
        if (u == drg) return true;
    }
    return false;
}

fn markProcedure(proc: *models.ProcedureCode, mark_flag: models.CodeFlag, impact: models.GroupingImpact) void {
    proc.mark(mark_flag);
    updateImpactDirection(proc, impact);
}

fn hasAttribute(proc: *models.ProcedureCode, attr_str: []const u8) bool {
    for (proc.attributes.items) |attr| {
        if (attr.matchesString(attr_str)) return true;
    }
    return false;
}

fn hasAttributes(proc: *models.ProcedureCode, required: []const []const u8) bool {
    for (required) |req| {
        var found = false;
        for (proc.attributes.items) |attr| {
            if (attr.prefix == .NONE and std.mem.eql(u8, attr.list_name, req)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn hasAllAttributes(proc: *models.ProcedureCode, required: [][]const u8) bool {
    for (required) |req| {
        if (!hasAttribute(proc, req)) return false;
    }
    return true;
}

fn calculateMdc(drg_formula: formula.DrgFormula, data: *const models.ProcessingData) i32 {
    var mdc: i32 = drg_formula.reroute_mdc_id;
    if (mdc == 0) {
        if (data.principal_dx) |pdx| {
            if (pdx.mdc) |m| mdc = m;
        }
    }
    if (isUnrelated(drg_formula.drg)) {
        mdc = 29;
    }
    return mdc;
}

fn markProcedureCodes(
    context: models.ProcessingContext,
    grouping_ctx: models.GroupingContext,
    formula_data: *const formula.FormulaData,
    allocator: std.mem.Allocator,
    mark_flag: models.CodeFlag,
    impact: models.GroupingImpact,
    severity: models.Severity,
) !i32 {
    const data = context.data;

    const winning_formula = getWinningFormula(grouping_ctx);
    if (winning_formula == null) {
        std.log.debug("ProcedureMarking: No winning formula found.", .{});
        return 0;
    }

    const drg_formula = winning_formula.?;
    std.log.debug("ProcedureMarking: Winning formula found for DRG {d}", .{drg_formula.drg});

    const mdc = calculateMdc(drg_formula, data);

    const base = formula_data.mapped.base_ptr();
    const formula_str = drg_formula.getFormula(base);

    const mask = &data.mask.?;

    const sev_str = switch (severity) {
        .MCC => "MCC",
        .CC => "CC",
        .NONE => "NONE",
    };
    const sev_key = try allocator.dupe(u8, sev_str);
    try mask.put(sev_key, 0);
    defer {
        _ = mask.remove(sev_key);
        allocator.free(sev_key);
    }

    var lexer = formula.Lexer.init(formula_str);
    var tokens = try lexer.tokenize(allocator);
    defer tokens.deinit(allocator);

    var parser = formula.Parser.init(allocator, tokens.items);
    const root = parser.parse() catch |err| {
        std.debug.print("Error parsing formula: {s}\n", .{formula_str});
        return err;
    };
    defer formula.Evaluator.free(root, allocator);

    var formula_attributes = std.StringHashMap(void).init(allocator);
    defer {
        var it = formula_attributes.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        formula_attributes.deinit();
    }

    _ = try formula.Evaluator.collectMatchedAttributes(root, mask, &formula_attributes, allocator, mdc);

    var proc_attributes: std.ArrayList([]const u8) = .empty;
    defer proc_attributes.deinit(allocator);

    var it = formula_attributes.keyIterator();
    while (it.next()) |key| {
        const k = key.*;
        if (std.mem.indexOf(u8, k, ":") != null) continue;
        if (std.mem.eql(u8, k, "MCC") or std.mem.eql(u8, k, "CC") or std.mem.eql(u8, k, "NONE")) continue;
        try proc_attributes.append(allocator, k);
    }

    if (proc_attributes.items.len > 0) {
        std.log.debug("ProcedureMarking: Found {d} procedure attributes to check", .{proc_attributes.items.len});
        var one_proc_found = false;

        for (data.procedure_codes.items) |*proc| {
            if (!proc.is(.FIRST_POSITION)) continue;
            if (proc.mdc_suppression.isSet(@intCast(mdc))) continue;

            if (hasAllAttributes(proc, proc_attributes.items)) {
                std.log.debug("ProcedureMarking: Marking first position procedure {s}", .{proc.value.toSlice()});
                markProcedure(proc, mark_flag, impact);
                one_proc_found = true;
                break;
            }
        }

        if (!one_proc_found) {
            for (data.procedure_codes.items) |*proc| {
                if (proc.mdc_suppression.isSet(@intCast(mdc))) continue;
                if (hasAllAttributes(proc, proc_attributes.items)) {
                    std.log.debug("ProcedureMarking: Marking procedure {s}", .{proc.value.toSlice()});
                    markProcedure(proc, mark_flag, impact);
                    one_proc_found = true;
                    break;
                }
            }
        }

        if (!one_proc_found) {
            for (data.clusters.items) |*cluster| {
                if (hasAllAttributes(cluster, proc_attributes.items)) {
                    std.log.debug("ProcedureMarking: Marking cluster {s}", .{cluster.value.toSlice()});
                    var proc_values = std.StringHashMap(void).init(allocator);
                    defer proc_values.deinit();

                    for (data.procedure_codes.items) |*proc| {
                        var in_cluster = false;
                        for (proc.cluster_ids.items) |cid| {
                            if (std.mem.eql(u8, cid, cluster.value.toSlice())) {
                                in_cluster = true;
                                break;
                            }
                        }
                        if (in_cluster and !proc_values.contains(proc.value.toSlice())) {
                            try proc_values.put(proc.value.toSlice(), {});
                            markProcedure(proc, mark_flag, impact);
                        }
                    }
                    one_proc_found = true;
                    break;
                }
            }
        }

        if (!one_proc_found) {
            attr_loop: for (proc_attributes.items) |attr_str| {
                if (COMPLETE_SYSTEM.has(attr_str)) {
                    var proc_codes_with_attr: std.ArrayList(*models.ProcedureCode) = .empty;
                    defer proc_codes_with_attr.deinit(allocator);

                    for (data.procedure_codes.items) |*proc| {
                        if (proc.mdc_suppression.isSet(@intCast(mdc))) continue;
                        if (hasAttribute(proc, attr_str)) {
                            try proc_codes_with_attr.append(allocator, proc);
                        }
                    }

                    var cluster_codes_with_attr: std.ArrayList(*models.ProcedureCode) = .empty;
                    defer cluster_codes_with_attr.deinit(allocator);

                    for (data.clusters.items) |*cluster| {
                        if (hasAttribute(cluster, attr_str)) {
                            try cluster_codes_with_attr.append(allocator, cluster);
                        }
                    }
                    if (proc_codes_with_attr.items.len > 0 and cluster_codes_with_attr.items.len > 0) {
                        if (data.principal_proc) |*pp| {
                            if (hasAttribute(pp, attr_str)) {
                                markProcedure(pp, mark_flag, impact);
                                continue :attr_loop;
                            }
                        }
                        if (proc_codes_with_attr.items.len > 0) {
                            markProcedure(proc_codes_with_attr.items[0], mark_flag, impact);
                            continue :attr_loop;
                        }
                    }
                }

                var count: usize = 0;
                for (data.procedure_codes.items) |*proc| {
                    if (proc.mdc_suppression.isSet(@intCast(mdc))) continue;
                    if (hasAttribute(proc, attr_str)) {
                        count += 1;
                    }
                }

                if (count >= 2) {
                    if (data.principal_proc) |*pp| {
                        if (!pp.mdc_suppression.isSet(@intCast(mdc)) and hasAttribute(pp, attr_str)) {
                            markProcedure(pp, mark_flag, impact);
                            continue :attr_loop;
                        }
                    }
                    for (data.procedure_codes.items) |*proc| {
                        if (proc.mdc_suppression.isSet(@intCast(mdc))) continue;
                        if (hasAttribute(proc, attr_str)) {
                            markProcedure(proc, mark_flag, impact);
                            continue :attr_loop;
                        }
                    }
                    continue :attr_loop;
                }

                var match_found = false;
                for (data.procedure_codes.items) |*proc| {
                    if (proc.mdc_suppression.isSet(@intCast(mdc))) continue;
                    if (hasAttribute(proc, attr_str)) {
                        markProcedure(proc, mark_flag, impact);
                        match_found = true;
                        break;
                    }
                }
                if (match_found) continue :attr_loop;

                for (data.clusters.items) |*cluster| {
                    if (hasAttribute(cluster, attr_str)) {
                        var proc_values = std.StringHashMap(void).init(allocator);
                        defer proc_values.deinit();

                        for (data.procedure_codes.items) |*proc| {
                            var in_cluster = false;
                            for (proc.cluster_ids.items) |cid| {
                                if (std.mem.eql(u8, cid, cluster.value.toSlice())) {
                                    in_cluster = true;
                                    break;
                                }
                            }
                            if (in_cluster and !proc_values.contains(proc.value.toSlice())) {
                                try proc_values.put(proc.value.toSlice(), {});
                                markProcedure(proc, mark_flag, impact);
                            }
                        }
                        continue :attr_loop;
                    }
                }
            }
        }
    }

    return mdc;
}

pub const InitialProcedureMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));

        std.log.debug("InitialProcedureMarking: Executing...", .{});

        _ = try markProcedureCodes(
            context,
            context.initial_grouping_context,
            self.formula_data,
            context.allocator,
            .MARKED_FOR_INITIAL,
            .INITIAL,
            context.data.initial_severity,
        );

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

fn isHac(code: *models.DiagnosisCode, hospital_status: models.HospitalStatusOptionFlag) bool {
    for (code.hacs.items) |hac| {
        if (hac.hac_status == .HAC_CRITERIA_MET and hospital_status != .EXEMPT) {
            return true;
        }
    }
    return false;
}

fn getWinningDrg(ctx: models.GroupingContext) ?i32 {
    if (ctx.pdx_match) |f| return f.drg;
    if (ctx.reroute_match) |f| return f.drg;
    if (ctx.pre_match) |f| return f.drg;
    return null;
}

fn markProcedureCodesFinalExtra(
    context: models.ProcessingContext,
    allocator: std.mem.Allocator,
    calculated_mdc: i32,
) !void {
    const data = context.data;

    const final_drg = getWinningDrg(context.final_grouping_context);
    const initial_drg = getWinningDrg(context.initial_grouping_context);
    const different_drgs = (final_drg != null and initial_drg != null and final_drg.? != initial_drg.?);

    var all_hacs_met = std.AutoHashMap(i32, void).init(allocator);
    defer all_hacs_met.deinit();

    for (data.sdx_codes.items) |*sdx| {
        for (sdx.hacs.items) |hac| {
            if (hac.hac_status == .HAC_CRITERIA_MET) {
                try all_hacs_met.put(hac.hac_number, {});
            }
        }
    }

    for (data.procedure_codes.items) |*proc| {
        if (proc.hac_usage_flag.count() == 0 or !different_drgs or proc.mdc_suppression.isSet(@intCast(calculated_mdc))) continue;

        var it = proc.hac_usage_flag.iterator();
        while (it.next()) |hac_usage| {
            const hac_num: i32 = switch (hac_usage) {
                .HAC_08 => 8,
                .HAC_10 => 10,
                .HAC_11 => 11,
                .HAC_12 => 12,
                .HAC_13 => 13,
                .HAC_14 => 14,
                else => 0,
            };

            if (hac_num != 0 and all_hacs_met.contains(hac_num)) {
                updateImpactDirection(proc, .FINAL);
            }
        }
    }
}

pub const FinalDiagnosisMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));

        try markDiagnosisCodes(
            context,
            context.final_grouping_context,
            self.formula_data,
            context.allocator,
            .MARKED_FOR_FINAL,
            .FINAL,
            context.data.final_severity,
            context.data.final_result.mdc orelse 0,
        );

        try markDiagnosisCodesFinalExtra(context);

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

pub const FinalProcedureMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));

        const mdc = try markProcedureCodes(
            context,
            context.final_grouping_context,
            self.formula_data,
            context.allocator,
            .MARKED_FOR_FINAL,
            .FINAL,
            context.data.final_severity,
        );

        try markProcedureCodesFinalExtra(context, context.allocator, mdc);

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }
};

const SIG_TRAUMAS = [_][]const u8{ "sthead", "stchest", "stabdom", "stkidney", "sturin", "stpel", "stuplimb", "stlolimb" };

fn updateImpact(code_impact: models.GroupingImpact, target_impact: models.GroupingImpact) models.GroupingImpact {
    if (target_impact == .INITIAL) return .INITIAL;
    if (target_impact == .FINAL) {
        if (code_impact == .INITIAL) return .BOTH;
        if (code_impact == .NONE) return .FINAL;
    }
    return code_impact;
}

fn markSigTrauma(matched_attributes: *std.StringHashMap(void), dx_codes: []models.DiagnosisCode, pdx: *models.DiagnosisCode, mark_flag: models.CodeFlag, impact: models.GroupingImpact) void {
    var sig_trauma_counter: usize = 0;
    if (pdx.is(.SIG_TRAUMA)) {
        pdx.mark(mark_flag);
        pdx.drg_impact = updateImpact(pdx.drg_impact, impact);
        sig_trauma_counter += 1;
    }

    var num_sig_trauma: usize = 0;
    for (SIG_TRAUMAS) |st| {
        if (matched_attributes.contains(st)) {
            num_sig_trauma += 1;
        }
    }

    if (num_sig_trauma > 0) {
        for (dx_codes) |*dx| {
            if (sig_trauma_counter >= 2) break;
            if (!dx.is(.SIG_TRAUMA)) continue;
            dx.mark(mark_flag);
            dx.drg_impact = updateImpact(dx.drg_impact, impact);
            sig_trauma_counter += 1;
        }
        for (SIG_TRAUMAS) |st| {
            _ = matched_attributes.remove(st);
        }
    }
}

fn markNotIncident(dx_codes: []models.DiagnosisCode, mark_flag: models.CodeFlag, impact: models.GroupingImpact) void {
    for (dx_codes) |*dx| {
        if (!dx.is(.NOT_INCIDENT)) continue;
        dx.mark(mark_flag);
        dx.drg_impact = updateImpact(dx.drg_impact, impact);
    }
}

fn commonDiagnosisFunctionMarking(
    context: models.ProcessingContext,
    grouping_ctx: models.GroupingContext,
    formula_data: *const formula.FormulaData,
    allocator: std.mem.Allocator,
    mark_flag: models.CodeFlag,
    impact: models.GroupingImpact,
) !void {
    const data = context.data;

    var winning_formula: ?formula.DrgFormula = null;
    if (grouping_ctx.pre_match) |f| {
        winning_formula = f;
    }

    if (winning_formula) |drg_formula| {
        const base = formula_data.mapped.base_ptr();
        const formula_str = drg_formula.getFormula(base);

        const mask = &data.mask.?;

        const sev = if (mark_flag == .MARKED_FOR_INITIAL) data.initial_severity else data.final_severity;
        const sev_str = switch (sev) {
            .MCC => "MCC",
            .CC => "CC",
            .NONE => "NONE",
        };
        const sev_key = try allocator.dupe(u8, sev_str);
        try mask.put(sev_key, 0);

        var lexer = formula.Lexer.init(formula_str);
        var tokens = try lexer.tokenize(allocator);
        defer tokens.deinit(allocator);

        var parser = formula.Parser.init(allocator, tokens.items);
        const root = parser.parse() catch return;
        defer formula.Evaluator.free(root, allocator);

        var matched_attributes = std.StringHashMap(void).init(allocator);
        defer {
            var it = matched_attributes.keyIterator();
            while (it.next()) |key| {
                allocator.free(key.*);
            }
            matched_attributes.deinit();
        }
        _ = try formula.Evaluator.collectMatchedAttributes(root, mask, &matched_attributes, allocator, 0);

        if (data.principal_dx) |*pdx| {
            markSigTrauma(&matched_attributes, data.sdx_codes.items, pdx, mark_flag, impact);
        }

        const drg = getWinningDrg(grouping_ctx);
        if (drg != null and drg.? == 794) {
            markNotIncident(data.sdx_codes.items, mark_flag, impact);
        }
    }
}

pub const InitialDxFunctionMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        try commonDiagnosisFunctionMarking(context, context.initial_grouping_context, self.formula_data, context.allocator, .MARKED_FOR_INITIAL, .INITIAL);
        return chain.LinkResult{ .context = context, .continue_processing = true };
    }
};

pub const FinalDxFunctionMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        try commonDiagnosisFunctionMarking(context, context.final_grouping_context, self.formula_data, context.allocator, .MARKED_FOR_FINAL, .FINAL);
        return chain.LinkResult{ .context = context, .continue_processing = true };
    }
};

// Procedure Function Marking Constants
const STENTS = [_][]const u8{ "stent1", "stent2", "stent3", "stent4" };
const VESSELS = [_][]const u8{ "vessel1", "vessel2", "vessel3", "vessel4" };
const ARTERIAL = "arterial";
const NOR_DRUG_STENT = "NORdrugstent";
const NOR_STENT = "NORstent";
const ARTERIAL_AND_NOR_DRUG_STENT = [_][]const u8{ ARTERIAL, NOR_DRUG_STENT };
const ARTERIAL_AND_NOR_STENT = [_][]const u8{ ARTERIAL, NOR_STENT };

fn markStents(matched_attributes: *std.StringHashMap(void), proc_codes: []models.ProcedureCode, mark_flag: models.CodeFlag, impact: models.GroupingImpact) void {
    var has_stent = false;
    for (STENTS) |s| {
        if (matched_attributes.contains(s)) {
            has_stent = true;
            break;
        }
    }

    if (has_stent) {
        // Phase 1: Mark all STENT_4 procedures
        for (proc_codes) |*proc| {
            if (!proc.is(.STENT_4)) continue;
            proc.mark(mark_flag);
            proc.drg_impact = updateImpact(proc.drg_impact, impact);
        }

        // Phase 2: Secondary marking — if the formula matched arterial+nordrugstent
        // (or arterial+norstent), also mark any procedure that has BOTH attributes
        // even if it doesn't have the STENT_4 flag.
        if (matched_attributes.contains(ARTERIAL) and matched_attributes.contains(NOR_DRUG_STENT)) {
            for (proc_codes) |*proc| {
                if (proc.is(mark_flag)) continue; // already marked
                if (hasAttributes(proc, &ARTERIAL_AND_NOR_DRUG_STENT)) {
                    proc.mark(mark_flag);
                    proc.drg_impact = updateImpact(proc.drg_impact, impact);
                }
            }
        } else if (matched_attributes.contains(ARTERIAL) and matched_attributes.contains(NOR_STENT)) {
            for (proc_codes) |*proc| {
                if (proc.is(mark_flag)) continue; // already marked
                if (hasAttributes(proc, &ARTERIAL_AND_NOR_STENT)) {
                    proc.mark(mark_flag);
                    proc.drg_impact = updateImpact(proc.drg_impact, impact);
                }
            }
        }

        // Phase 3: Cleanup matched attributes
        for (STENTS) |s| _ = matched_attributes.remove(s);
        _ = matched_attributes.remove(ARTERIAL);
        _ = matched_attributes.remove(NOR_DRUG_STENT);
        _ = matched_attributes.remove(NOR_STENT);
    }
}

fn markVessels(matched_attributes: *std.StringHashMap(void), proc_codes: []models.ProcedureCode, mark_flag: models.CodeFlag, impact: models.GroupingImpact) void {
    var has_vessel = false;
    for (VESSELS) |v| {
        if (matched_attributes.contains(v)) {
            has_vessel = true;
            break;
        }
    }

    if (has_vessel) {
        for (proc_codes) |*proc| {
            if (!proc.is(.VESSEL_4)) continue;
            proc.mark(mark_flag);
            proc.drg_impact = updateImpact(proc.drg_impact, impact);
        }
        for (VESSELS) |v| _ = matched_attributes.remove(v);
    }
}

fn commonProcedureFunctionMarking(
    context: models.ProcessingContext,
    grouping_ctx: models.GroupingContext,
    formula_data: *const formula.FormulaData,
    allocator: std.mem.Allocator,
    mark_flag: models.CodeFlag,
    impact: models.GroupingImpact,
) !void {
    const data = context.data;

    var winning_formula: ?formula.DrgFormula = null;
    if (grouping_ctx.pdx_match) |f| {
        winning_formula = f;
    } else if (grouping_ctx.reroute_match) |f| {
        winning_formula = f;
    } else if (grouping_ctx.pre_match) |f| {
        winning_formula = f;
    }

    if (winning_formula) |drg_formula| {
        const base = formula_data.mapped.base_ptr();
        const formula_str = drg_formula.getFormula(base);

        const mask = &data.mask.?;

        const sev = if (mark_flag == .MARKED_FOR_INITIAL) data.initial_severity else data.final_severity;
        const sev_str = switch (sev) {
            .MCC => "MCC",
            .CC => "CC",
            .NONE => "NONE",
        };
        const sev_key = try allocator.dupe(u8, sev_str);
        try mask.put(sev_key, 0);

        var lexer = formula.Lexer.init(formula_str);
        var tokens = try lexer.tokenize(allocator);
        defer tokens.deinit(allocator);

        var parser = formula.Parser.init(allocator, tokens.items);
        const root = parser.parse() catch return;
        defer formula.Evaluator.free(root, allocator);

        var matched_attributes = std.StringHashMap(void).init(allocator);
        defer {
            var it = matched_attributes.keyIterator();
            while (it.next()) |key| {
                allocator.free(key.*);
            }
            matched_attributes.deinit();
        }
        _ = try formula.Evaluator.collectMatchedAttributes(root, mask, &matched_attributes, allocator, 0);

        markStents(&matched_attributes, data.procedure_codes.items, mark_flag, impact);
        markVessels(&matched_attributes, data.procedure_codes.items, mark_flag, impact);
    }
}

pub const InitialSgFunctionMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        try commonProcedureFunctionMarking(context, context.initial_grouping_context, self.formula_data, context.allocator, .MARKED_FOR_INITIAL, .INITIAL);
        return chain.LinkResult{ .context = context, .continue_processing = true };
    }
};

pub const FinalSgFunctionMarking = struct {
    formula_data: *const formula.FormulaData,

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        try commonProcedureFunctionMarking(context, context.final_grouping_context, self.formula_data, context.allocator, .MARKED_FOR_FINAL, .FINAL);
        return chain.LinkResult{ .context = context, .continue_processing = true };
    }
};
