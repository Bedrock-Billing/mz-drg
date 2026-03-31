const std = @import("std");
const common = @import("common.zig");
const models = @import("models.zig");
const chain = @import("chain.zig");
const grouping = @import("grouping.zig");
const formula = @import("formula.zig");

// --- HAC Descriptions ---
pub const HacDescriptionHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    strings_offset: u32,
};

pub const HacDescriptionEntry = extern struct {
    id: u16,
    _pad: u16,
    version_start: i32,
    version_end: i32,
    desc_offset: u32,
    desc_len: u32,

    pub fn getDescription(self: *const HacDescriptionEntry, base: [*]const u8) []const u8 {
        return base[self.desc_offset .. self.desc_offset + self.desc_len];
    }
};

pub const HacDescriptionData = struct {
    mapped: common.MappedFile(HacDescriptionHeader),

    pub fn init(path: []const u8) !HacDescriptionData {
        const mapped = try common.MappedFile(HacDescriptionHeader).init(path, 0x48414344);
        return HacDescriptionData{ .mapped = mapped };
    }

    pub fn deinit(self: *HacDescriptionData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const HacDescriptionData) []const HacDescriptionEntry {
        const entries_ptr = @as([*]const HacDescriptionEntry, @ptrCast(@alignCast(self.mapped.base_ptr() + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getEntry(self: *const HacDescriptionData, id: u16, version: i32) ?HacDescriptionEntry {
        const entries = self.getEntries();
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = entries[mid];

            if (entry.id < id) {
                left = mid + 1;
            } else if (entry.id > id) {
                right = mid;
            } else {
                // Found match, check version
                if (version >= entry.version_start and version <= entry.version_end) {
                    return entry;
                }
                // Scan backwards
                var i = mid;
                while (i > 0) {
                    i -= 1;
                    const prev = entries[i];
                    if (prev.id != id) break;
                    if (version >= prev.version_start and version <= prev.version_end) return prev;
                }
                // Scan forwards
                i = mid + 1;
                while (i < entries.len) {
                    const next = entries[i];
                    if (next.id != id) break;
                    if (version >= next.version_start and version <= next.version_end) return next;
                    i += 1;
                }
                return null;
            }
        }
        return null;
    }
};

// --- HAC Formulas ---
pub const HacFormulaHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    list_data_offset: u32,
    strings_offset: u32,
};

pub const HacFormulaEntry = extern struct {
    id: u16,
    count: u16,
    version_start: i32,
    version_end: i32,
    list_offset: u32,
};

pub const HacFormulaData = struct {
    mapped: common.MappedFile(HacFormulaHeader),

    pub fn init(path: []const u8) !HacFormulaData {
        const mapped = try common.MappedFile(HacFormulaHeader).init(path, 0x48414346);
        return HacFormulaData{ .mapped = mapped };
    }

    pub fn deinit(self: *HacFormulaData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const HacFormulaData) []const HacFormulaEntry {
        const entries_ptr = @as([*]const HacFormulaEntry, @ptrCast(@alignCast(self.mapped.base_ptr() + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getEntry(self: *const HacFormulaData, id: u16, version: i32) ?HacFormulaEntry {
        const entries = self.getEntries();
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = entries[mid];

            if (entry.id < id) {
                left = mid + 1;
            } else if (entry.id > id) {
                right = mid;
            } else {
                // Found match, check version
                if (version >= entry.version_start and version <= entry.version_end) {
                    return entry;
                }
                // Scan backwards
                var i = mid;
                while (i > 0) {
                    i -= 1;
                    const prev = entries[i];
                    if (prev.id != id) break;
                    if (version >= prev.version_start and version <= prev.version_end) return prev;
                }
                // Scan forwards
                i = mid + 1;
                while (i < entries.len) {
                    const next = entries[i];
                    if (next.id != id) break;
                    if (version >= next.version_start and version <= next.version_end) return next;
                    i += 1;
                }
                return null;
            }
        }
        return null;
    }

    pub fn getFormulas(self: *const HacFormulaData, entry: HacFormulaEntry) []const common.StringRef {
        const list_ptr = @as([*]const common.StringRef, @ptrCast(@alignCast(self.mapped.base_ptr() + entry.list_offset)));
        return list_ptr[0..entry.count];
    }
};

// --- HAC Operands ---
pub const HacOperandHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    list_data_offset: u32,
};

pub const HacOperandEntry = extern struct {
    code: common.Code,
    version_start: i32,
    version_end: i32,
    list_offset: u32,
    count: u32,
};

pub const HacOperandData = struct {
    mapped: common.MappedFile(HacOperandHeader),

    pub fn init(path: []const u8) !HacOperandData {
        const mapped = try common.MappedFile(HacOperandHeader).init(path, 0x4841434F);
        return HacOperandData{ .mapped = mapped };
    }

    pub fn deinit(self: *HacOperandData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const HacOperandData) []const HacOperandEntry {
        const entries_ptr = @as([*]const HacOperandEntry, @ptrCast(@alignCast(self.mapped.base_ptr() + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getEntry(self: *const HacOperandData, code: []const u8, version: i32) ?HacOperandEntry {
        const entries = self.getEntries();
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = entries[mid];
            const entry_code = entry.code.toSlice();

            const order = std.mem.order(u8, entry_code, code);
            switch (order) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => {
                    if (version >= entry.version_start and version <= entry.version_end) {
                        return entry;
                    }
                    var i = mid;
                    while (i > 0) {
                        i -= 1;
                        const prev = entries[i];
                        if (!std.mem.eql(u8, prev.code.toSlice(), code)) break;
                        if (version >= prev.version_start and version <= prev.version_end) return prev;
                    }
                    i = mid + 1;
                    while (i < entries.len) {
                        const next = entries[i];
                        if (!std.mem.eql(u8, next.code.toSlice(), code)) break;
                        if (version >= next.version_start and version <= next.version_end) return next;
                        i += 1;
                    }
                    return null;
                },
            }
        }
        return null;
    }

    pub fn getHacs(self: *const HacOperandData, entry: HacOperandEntry) []const u8 {
        const list_ptr = self.mapped.base_ptr() + entry.list_offset;
        return list_ptr[0..entry.count];
    }
};

test "HacData lookup" {
    const filename = "test_hac.bin";
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

    const writeU16 = struct {
        fn call(f: std.Io.File, v: u16) !void {
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Test HacDescriptionData
    // Header: magic(4), num(4), entries_off(4), strings_off(4)
    try writeU32(file, 0x48414344);
    try writeU32(file, 2);
    try writeU32(file, 16);
    try writeU32(file, 16 + 2 * 20); // 2 entries * 20 bytes

    // Entry 1: ID 1, v400-410
    try writeU16(file, 1);
    try writeU16(file, 0); // pad
    try writeU32(file, 400);
    try writeU32(file, 410);
    try writeU32(file, 0); // desc_off
    try writeU32(file, 5); // desc_len

    // Entry 2: ID 2, v400-430
    try writeU16(file, 2);
    try writeU16(file, 0); // pad
    try writeU32(file, 400);
    try writeU32(file, 430);
    try writeU32(file, 5); // desc_off
    try writeU32(file, 5); // desc_len

    // Strings
    try std.Io.File.writeStreamingAll(file, std.testing.io, "Desc1");
    try std.Io.File.writeStreamingAll(file, std.testing.io, "Desc2");

    var desc_data = try HacDescriptionData.init(filename);
    defer desc_data.deinit();

    const d1 = desc_data.getEntry(1, 405);
    try std.testing.expect(d1 != null);
    try std.testing.expectEqual(@as(u16, 1), d1.?.id);

    const d2 = desc_data.getEntry(2, 420);
    try std.testing.expect(d2 != null);
    try std.testing.expectEqual(@as(u16, 2), d2.?.id);

    const d3 = desc_data.getEntry(1, 420); // Version mismatch
    try std.testing.expect(d3 == null);
}

pub const MsdrgHacProcessor = struct {
    description_data: *const HacDescriptionData,
    formula_data: *const HacFormulaData,
    version: i32,

    const HAC_NUMS_PROCS = [_]i32{ 8, 10, 11, 12, 13, 14 };

    pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !chain.LinkResult {
        const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
        const data = context.data;
        const allocator = context.allocator;
        const hospital_status = context.runtime.poa_reporting_exempt;

        if (hospital_status == .EXEMPT) {
            // Hospital is exempt from POA reporting — skip HAC processing entirely
            for (data.sdx_codes.items) |*sdx| {
                if (sdx.hacs.items.len == 0) continue;
                sdx.poa_error_code_flag = .HOSPITAL_EXEMPT;
                for (sdx.hacs.items) |*hac| {
                    hac.hac_status = .HAC_NOT_APPLICABLE_EXEMPT;
                }
            }
            try self.updateHacListAfterEvaluation(&data.principal_dx, &data.sdx_codes, allocator);
            return chain.LinkResult{
                .context = context,
                .continue_processing = true,
            };
        }

        // NON_EXEMPT or UNKNOWN — process HACs
        try self.processHospitalAcquiredCondition(data, hospital_status, allocator);

        // Rebuild mask after HAC modifications to SDX codes
        data.deinitMask();
        data.mask = try grouping.MsdrgMaskBuilder.buildMask(data, allocator);

        // If already marked ungroupable by a prior step, stop the chain
        if (data.final_result.return_code != .OK) {
            return chain.LinkResult{
                .context = context,
                .continue_processing = false,
            };
        }

        return chain.LinkResult{
            .context = context,
            .continue_processing = true,
        };
    }

    fn processHospitalAcquiredCondition(self: *const MsdrgHacProcessor, data: *models.ProcessingData, hospital_status: models.HospitalStatusOptionFlag, allocator: std.mem.Allocator) !void {
        var codes_with_hacs = std.AutoHashMap(i32, std.ArrayList(*models.DiagnosisCode)).init(allocator);
        defer {
            var it = codes_with_hacs.valueIterator();
            while (it.next()) |list| {
                list.deinit(allocator);
            }
            codes_with_hacs.deinit();
        }

        var code_on_hac6_but_not_show_list: ?[]const u8 = null;
        var has_invalid_poa_on_claim = false;

        for (data.sdx_codes.items) |*sdx| {
            if (sdx.hacs.items.len == 0) continue;

            for (sdx.hacs.items) |*hac| {
                if (sdx.poa == 'Y' or sdx.poa == 'W') {
                    hac.hac_status = .HAC_CRITERIA_NOT_MET;
                    sdx.poa_error_code_flag = getPoaErrorCode(sdx.poa);
                    continue;
                }
                if (sdx.is(.EXCLUDED)) {
                    hac.hac_status = .HAC_NOT_APPLICABLE_EXCLUSION;
                    sdx.poa_error_code_flag = getPoaErrorCode(sdx.poa);
                    continue;
                }

                const status = try self.evaluateHacConditions(data, hac, allocator);
                hac.hac_status = status;
                sdx.poa_error_code_flag = getPoaErrorCode(sdx.poa);

                if (sdx.poa == 'E' or sdx.poa == ' ' or sdx.poa == '1' or sdx.poa == 0) {
                    has_invalid_poa_on_claim = true;
                }

                if (status == .HAC_CRITERIA_MET) {
                    if (hac.hac_number == 6 and !sdx.is(.ON_SHOW_LIST)) {
                        code_on_hac6_but_not_show_list = sdx.value.toSlice();
                    }

                    const res = try codes_with_hacs.getOrPut(hac.hac_number);
                    if (!res.found_existing) {
                        res.value_ptr.* = .empty;
                    }
                    try res.value_ptr.append(allocator, sdx);
                }
            }
        }

        if (code_on_hac6_but_not_show_list == null) {
            for (data.sdx_codes.items) |*sdx| {
                if (sdx.hacs.items.len == 0) continue;
                for (sdx.hacs.items) |*hac| {
                    if (std.mem.eql(u8, hac.hac_list, "hac06_show")) {
                        hac.hac_status = .HAC_CRITERIA_NOT_MET;
                    }
                }
            }
        }

        // Procedure HAC usage
        for (data.sdx_codes.items) |*sdx| {
            if (sdx.hacs.items.len == 0) continue;
            for (sdx.hacs.items) |*hac| {
                var is_proc_hac = false;
                for (HAC_NUMS_PROCS) |n| {
                    if (hac.hac_number == n) {
                        is_proc_hac = true;
                        break;
                    }
                }

                if (!is_proc_hac or hac.hac_status != .HAC_CRITERIA_MET) continue;

                for (data.procedure_codes.items) |*proc| {
                    const hac_num = hac.hac_number;
                    for (proc.attributes.items) |attr| {
                        var match = false;
                        if (hac_num < 10) {
                            var buf: [20]u8 = undefined;
                            const s = std.fmt.bufPrint(&buf, "hac0{d}_proc", .{hac_num}) catch "";
                            if (std.mem.indexOf(u8, attr.list_name, s) != null) match = true;
                        } else {
                            var buf: [20]u8 = undefined;
                            const s = std.fmt.bufPrint(&buf, "hac{d}_proc", .{hac_num}) catch "";
                            if (std.mem.indexOf(u8, attr.list_name, s) != null) match = true;
                        }

                        if (match) {
                            switch (hac_num) {
                                8 => proc.hac_usage_flag.insert(.HAC_08),
                                10 => proc.hac_usage_flag.insert(.HAC_10),
                                11 => proc.hac_usage_flag.insert(.HAC_11),
                                12 => proc.hac_usage_flag.insert(.HAC_12),
                                13 => proc.hac_usage_flag.insert(.HAC_13),
                                14 => proc.hac_usage_flag.insert(.HAC_14),
                                else => {},
                            }
                        }
                    }
                }
            }
        }

        // Mark Ungroupable logic — branches by hospital status
        if (hospital_status == .NOT_EXEMPT) {
            // NON_EXEMPT: mark ungroupable if any HAC-eligible code has invalid POA
            var mark_ungroupable = false;

            if (codes_with_hacs.count() > 0) {
                var it = codes_with_hacs.iterator();
                while (it.next()) |entry| {
                    const hac_number = entry.key_ptr.*;
                    const dx_codes = entry.value_ptr.items;

                    if (hac_number == 6) {
                        if (code_on_hac6_but_not_show_list == null) continue;
                        for (dx_codes) |dx| {
                            if (dx.poa == 'E' or dx.poa == ' ' or dx.poa == '1' or dx.poa == 0) {
                                mark_ungroupable = true;
                            }
                        }
                        continue;
                    }

                    for (dx_codes) |dx| {
                        const is_poa_invalid = (dx.poa == 'E' or dx.poa == ' ' or dx.poa == '1' or dx.poa == 0);
                        if (is_poa_invalid) {
                            mark_ungroupable = true;
                        }
                    }
                    if (has_invalid_poa_on_claim) {
                        mark_ungroupable = true;
                    }
                }
            }

            if (mark_ungroupable) {
                data.final_result.return_code = .HAC_MISSING_ONE_POA;
                try self.updateHacListAfterEvaluation(&data.principal_dx, &data.sdx_codes, allocator);
                return;
            }
        } else if (hospital_status == .UNKNOWN) {
            // UNKNOWN: stricter POA validation per CMS rules
            if (codes_with_hacs.count() > 0) {
                for (data.sdx_codes.items) |*sdx| {
                    if (sdx.hacs.items.len == 0) continue;
                    for (sdx.hacs.items) |*hac| {
                        if (hac.hac_status != .HAC_CRITERIA_MET) continue;

                        // Count non-Y/W POA across ALL SDX codes on the claim
                        var poa_counter: usize = 0;
                        for (data.sdx_codes.items) |*dx| {
                            if (dx.poa != 'Y' and dx.poa != 'W') {
                                poa_counter += 1;
                            }
                        }
                        if (poa_counter >= 2) {
                            sdx.initial_severity_flag = .NEITHER;
                            data.final_result.return_code = .HAC_STATUS_INVALID_MULT_HACS_POA_NOT_Y_W;
                            try self.updateHacListAfterEvaluation(&data.principal_dx, &data.sdx_codes, allocator);
                            return;
                        }
                        if (sdx.poa == 'N' or sdx.poa == 'U') {
                            sdx.initial_severity_flag = .NEITHER;
                            data.final_result.return_code = .HAC_STATUS_INVALID_POA_N_OR_U;
                            try self.updateHacListAfterEvaluation(&data.principal_dx, &data.sdx_codes, allocator);
                            return;
                        }
                        if (sdx.poa == 0 or sdx.poa == ' ' or sdx.poa == 'E' or sdx.poa == '1') {
                            sdx.initial_severity_flag = .NEITHER;
                            data.final_result.return_code = .HAC_STATUS_INVALID_POA_INVALID_OR_1;
                            try self.updateHacListAfterEvaluation(&data.principal_dx, &data.sdx_codes, allocator);
                            return;
                        }
                    }
                }
            }
        }

        try self.updateHacListAfterEvaluation(&data.principal_dx, &data.sdx_codes, allocator);
    }

    fn evaluateHacConditions(self: *const MsdrgHacProcessor, data: *models.ProcessingData, hac: *models.Hac, allocator: std.mem.Allocator) !models.HacUsage {
        var hac_status = models.HacUsage.HAC_CRITERIA_NOT_MET;

        // Use pre-built mask
        const mask = &data.mask.?;

        if (self.formula_data.getEntry(@intCast(hac.hac_number), self.version)) |entry| {
            const formulas = self.formula_data.getFormulas(entry);
            const base = self.formula_data.mapped.base_ptr();

            for (formulas) |f_ref| {
                const formula_str = f_ref.get(base);

                var lexer = formula.Lexer.init(formula_str);
                var tokens = try lexer.tokenize(allocator);
                defer tokens.deinit(allocator);

                var parser = formula.Parser.init(allocator, tokens.items);
                const root = parser.parse() catch |err| {
                    std.debug.print("Error parsing HAC formula: {s}\n", .{formula_str});
                    return err;
                };
                defer formula.Evaluator.free(root, allocator);

                if (formula.Evaluator.evaluate(root, mask, 0)) {
                    hac_status = .HAC_CRITERIA_MET;
                    break;
                }
            }
        }

        return hac_status;
    }

    fn updateHacListAfterEvaluation(self: *const MsdrgHacProcessor, pdx_opt: *?models.DiagnosisCode, sdx_codes: *std.ArrayList(models.DiagnosisCode), allocator: std.mem.Allocator) !void {
        _ = self;
        for (sdx_codes.items) |*sdx| {
            var contains_six = false;
            var criteria_met = false;
            var update_hac_list: std.ArrayList(models.Hac) = .empty;

            if (sdx.hacs.items.len == 0) {
                update_hac_list.deinit(allocator);
                continue;
            }

            for (sdx.hacs.items) |*hac| {
                if (hac.hac_status == .HAC_CRITERIA_MET and (sdx.poa != 'W' and sdx.poa != 'Y')) {
                    if (hac.hac_number == 6 and !contains_six) {
                        try update_hac_list.append(allocator, hac.*);
                        contains_six = true;
                    } else {
                        if (hac.hac_number == 6 and contains_six) continue;
                        try update_hac_list.append(allocator, hac.*);
                    }
                    criteria_met = true;
                    continue;
                }
                if (hac.hac_status == .HAC_CRITERIA_NOT_MET and (sdx.poa == 'W' or sdx.poa == 'Y')) {
                    var h = hac.*;
                    h.hac_number = 0;
                    try update_hac_list.append(allocator, h);
                    criteria_met = true;
                    break;
                }
                if (hac.hac_status == .HAC_NOT_APPLICABLE_EXCLUSION) {
                    try update_hac_list.append(allocator, hac.*);
                    criteria_met = true;
                    continue;
                }
                if (hac.hac_status == .HAC_NOT_APPLICABLE_EXEMPT) {
                    var h = hac.*;
                    h.hac_number = 0;
                    try update_hac_list.append(allocator, h);
                    criteria_met = true;
                }
            }

            if (!criteria_met) {
                for (sdx.hacs.items) |*hac| {
                    var h = hac.*;
                    h.hac_number = 0;
                    try update_hac_list.append(allocator, h);
                }
            }

            sdx.hacs_flags.deinit(allocator);
            sdx.hacs_flags = update_hac_list;
        }

        var hac11present = false;
        if (pdx_opt.*) |*p| {
            if (p.hacs.items.len > 0) {
                blk: for (sdx_codes.items) |*sdx| {
                    if (sdx.hacs_flags.items.len == 0) continue;
                    for (sdx.hacs_flags.items) |*hac| {
                        if (hac.hac_number == 11 and hac.hac_status == .HAC_CRITERIA_MET) {
                            hac11present = true;
                            break :blk;
                        }
                    }
                }
            }
            if (hac11present) {
                const h = models.Hac{
                    .hac_number = 11,
                    .hac_status = .HAC_CRITERIA_MET,
                    .hac_list = "",
                    .description = "",
                };
                try p.hacs_flags.append(allocator, h);
            }
        }
    }

    fn getPoaErrorCode(poa: u8) models.PoaErrorCode {
        if (poa == 'Y' or poa == 'W') return .POA_RECOGNIZED_YES_POA;
        if (poa == 'N' or poa == 'U') return .POA_RECOGNIZED_NOT_POA;
        if (poa == 0 or poa == ' ' or poa == 'E' or poa == '1') return .POA_NOT_RECOGNIZED;
        return .POA_NOT_RECOGNIZED;
    }
};

test "MsdrgHacProcessor execution" {
    const allocator = std.testing.allocator;

    // 1. Create temporary files
    const desc_filename = "test_hac_desc_proc.bin";
    const formula_filename = "test_hac_formula_proc.bin";

    const file_desc = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, desc_filename, .{ .read = true });
    defer {
        std.Io.File.close(file_desc, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, desc_filename) catch {};
    }
    const file_formula = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, formula_filename, .{ .read = true });
    defer {
        std.Io.File.close(file_formula, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, formula_filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.Io.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    const writeU16 = struct {
        fn call(f: std.Io.File, v: u16) !void {
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Write Description File (Dummy)
    try writeU32(file_desc, 0x48414344); // Magic
    try writeU32(file_desc, 0); // Num entries
    try writeU32(file_desc, 16); // Entries offset
    try writeU32(file_desc, 16); // Strings offset

    // Write Formula File
    // Header: Magic(4), Num(4), EntriesOff(4), ListDataOff(4), StringsOff(4) -> 20 bytes
    try writeU32(file_formula, 0x48414346);
    try writeU32(file_formula, 1);
    try writeU32(file_formula, 20);
    try writeU32(file_formula, 36);
    try writeU32(file_formula, 44);

    // Entry 1: ID(2), Count(2), VStart(4), VEnd(4), ListOff(4) -> 16 bytes
    try writeU16(file_formula, 1);
    try writeU16(file_formula, 1);
    try writeU32(file_formula, 400);
    try writeU32(file_formula, 430);
    try writeU32(file_formula, 36);

    // List Data (at 36): Offset(4), Len(4) -> 8 bytes
    try writeU32(file_formula, 44);
    try writeU32(file_formula, 9);

    // Strings (at 44): "TEST_ATTR"
    try std.Io.File.writeStreamingAll(file_formula, std.testing.io, "TEST_ATTR");

    // 2. Init Processor
    var desc_data = try HacDescriptionData.init(desc_filename);
    defer desc_data.deinit();
    var formula_data = try HacFormulaData.init(formula_filename);
    defer formula_data.deinit();

    const processor = MsdrgHacProcessor{
        .description_data = &desc_data,
        .formula_data = &formula_data,
        .version = 420,
    };

    // 3. Setup Data
    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    var dx = try models.DiagnosisCode.init("A001", 'N'); // POA = N
    try dx.attributes.append(allocator, models.Attribute{ .list_name = "TEST_ATTR" });

    const hac = models.Hac{
        .hac_number = 1,
        .hac_status = .NOT_ON_HAC_LIST,
        .hac_list = "hac01",
        .description = "Test HAC",
    };
    try dx.hacs.append(allocator, hac);
    try data.sdx_codes.append(allocator, dx);

    // Build mask for the HAC evaluator
    data.mask = try grouping.MsdrgMaskBuilder.buildMask(&data, allocator);

    // 4. Execute
    try processor.processHospitalAcquiredCondition(&data, .NOT_EXEMPT, allocator);

    // 5. Verify
    const processed_dx = &data.sdx_codes.items[0];
    // Check hacs_flags (updated list)
    try std.testing.expectEqual(@as(usize, 1), processed_dx.hacs_flags.items.len);
    try std.testing.expectEqual(models.HacUsage.HAC_CRITERIA_MET, processed_dx.hacs_flags.items[0].hac_status);
    try std.testing.expectEqual(models.PoaErrorCode.POA_RECOGNIZED_NOT_POA, processed_dx.poa_error_code_flag);
}
