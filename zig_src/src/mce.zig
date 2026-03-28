const std = @import("std");
const mce_data = @import("mce_data.zig");
const mce_enums = @import("mce_enums.zig");
const mce_validation = @import("mce_validation.zig");
const mce_editing = @import("mce_editing.zig");

const Attribute = mce_enums.Attribute;
const EditType = mce_enums.EditType;
const MceInput = mce_enums.MceInput;
const MceOutput = mce_enums.MceOutput;
const MceDiagnosisCode = mce_enums.MceDiagnosisCode;
const MceProcedureCode = mce_enums.MceProcedureCode;

pub const MceComponent = struct {
    i10dx: mce_data.CodeMasterData,
    i10sg: mce_data.CodeMasterData,
    i9dx: mce_data.CodeMasterData,
    i9sg: mce_data.CodeMasterData,
    age_ranges: mce_data.AgeRangeData,
    discharge_status: mce_data.DischargeStatusData,
    version: i32,

    const Self = @This();

    pub fn init(data_dir: []const u8, allocator: std.mem.Allocator) !Self {
        const sep = if (data_dir[data_dir.len - 1] == '/') "" else "/";

        const i10dx_path = try std.fmt.allocPrint(allocator, "{s}{s}mce_i10dx_master.bin", .{ data_dir, sep });
        defer allocator.free(i10dx_path);
        const i10sg_path = try std.fmt.allocPrint(allocator, "{s}{s}mce_i10sg_master.bin", .{ data_dir, sep });
        defer allocator.free(i10sg_path);
        const i9dx_path = try std.fmt.allocPrint(allocator, "{s}{s}mce_i9dx_master.bin", .{ data_dir, sep });
        defer allocator.free(i9dx_path);
        const i9sg_path = try std.fmt.allocPrint(allocator, "{s}{s}mce_i9sg_master.bin", .{ data_dir, sep });
        defer allocator.free(i9sg_path);
        const age_path = try std.fmt.allocPrint(allocator, "{s}{s}mce_age_ranges.bin", .{ data_dir, sep });
        defer allocator.free(age_path);
        const ds_path = try std.fmt.allocPrint(allocator, "{s}{s}mce_discharge_status.bin", .{ data_dir, sep });
        defer allocator.free(ds_path);

        var result: Self = undefined;

        result.i10dx = mce_data.CodeMasterData.init(i10dx_path) catch |err| return err;
        errdefer result.i10dx.deinit();
        result.i10sg = mce_data.CodeMasterData.init(i10sg_path) catch |err| {
            result.i10dx.deinit();
            return err;
        };
        result.i9dx = mce_data.CodeMasterData.init(i9dx_path) catch |err| {
            result.i10dx.deinit();
            result.i10sg.deinit();
            return err;
        };
        result.i9sg = mce_data.CodeMasterData.init(i9sg_path) catch |err| {
            result.i10dx.deinit();
            result.i10sg.deinit();
            result.i9dx.deinit();
            return err;
        };
        result.age_ranges = mce_data.AgeRangeData.init(age_path) catch |err| {
            result.i10dx.deinit();
            result.i10sg.deinit();
            result.i9dx.deinit();
            result.i9sg.deinit();
            return err;
        };
        result.discharge_status = mce_data.DischargeStatusData.init(ds_path) catch |err| {
            result.i10dx.deinit();
            result.i10sg.deinit();
            result.i9dx.deinit();
            result.i9sg.deinit();
            result.age_ranges.deinit();
            return err;
        };
        result.version = result.i10dx.mapped.header.termination_date;

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.i10dx.deinit();
        self.i10sg.deinit();
        self.i9dx.deinit();
        self.i9sg.deinit();
        self.age_ranges.deinit();
        self.discharge_status.deinit();
    }

    /// Get the diagnosis code master data (I10 by default).
    pub fn getDxMaster(self: *const Self, icd_version: u8) *const mce_data.CodeMasterData {
        if (icd_version == 9) return &self.i9dx;
        return &self.i10dx;
    }

    /// Get the procedure code master data (I10 by default).
    pub fn getSgMaster(self: *const Self, icd_version: u8) *const mce_data.CodeMasterData {
        if (icd_version == 9) return &self.i9sg;
        return &self.i10sg;
    }

    /// Process a claim through the MCE pipeline.
    pub fn process(self: *Self, input: *MceInput, icd_version: u8, allocator: std.mem.Allocator) !MceOutput {
        var output = MceOutput{ .version = self.version };
        var counter = mce_editing.EditCounter{};

        const dx_master = self.getDxMaster(icd_version);
        const sg_master = self.getSgMaster(icd_version);

        // --- Phase 1: Validation ---

        if (!mce_validation.isValidDischargeDate(input.discharge_date, self.version)) {
            output.edit_type = .INVALID_DISCHARGE_DATE;
            return output;
        }

        // Validate admit DX
        if (input.admit_dx) |*adx| {
            if (!mce_validation.validateCode(adx.getCode(), dx_master, input.discharge_date)) {
                output.increment(mce_editing.EDIT_INVALID_ADMIT_DX);
            }
        }

        // Validate PDX (first diagnosis)
        if (input.pdx) |*pdx| {
            if (!mce_validation.validateCode(pdx.getCode(), dx_master, input.discharge_date)) {
                output.increment(mce_editing.EDIT_INVALID_CODE);
            }
            // Disallow blank/all-zeros PDX
            const code = pdx.getCode();
            if (code.len > 0) {
                var all_zeros = true;
                for (code) |c| {
                    if (c != '0') {
                        all_zeros = false;
                        break;
                    }
                }
                if (all_zeros) {
                    output.increment(mce_editing.EDIT_INVALID_CODE);
                }
            }
        }

        // Validate SDX
        for (input.sdx.items) |*sdx| {
            if (!mce_validation.validateCode(sdx.getCode(), dx_master, input.discharge_date)) {
                output.increment(mce_editing.EDIT_INVALID_CODE);
            }
        }

        // Validate procedures
        for (input.procedures.items) |*proc| {
            if (!mce_validation.validateCode(proc.getCode(), sg_master, input.discharge_date)) {
                output.increment(mce_editing.EDIT_INVALID_CODE);
            }
        }

        // Validate sex
        const sex_int: i32 = switch (input.sex) {
            .MALE => 1,
            .FEMALE => 2,
            .UNKNOWN => 0,
        };
        if (!mce_validation.validateSex(sex_int, input.discharge_date)) {
            output.increment(mce_editing.EDIT_INVALID_SEX);
        }

        // Validate discharge status
        if (!mce_validation.validateDischargeStatus(input.discharge_status, &self.discharge_status, input.discharge_date)) {
            output.increment(mce_editing.EDIT_INVALID_DISCHARGE_STATUS);
        }

        // Validate age
        if (!mce_validation.validateAge(input.age)) {
            output.increment(mce_editing.EDIT_INVALID_AGE);
        }

        // --- Phase 2: Load Attributes ---

        var attr_buf: [50]Attribute = undefined;

        if (input.pdx) |*pdx| {
            const count = mce_validation.loadAttributes(dx_master, pdx.getCode(), input.discharge_date, &attr_buf);
            for (attr_buf[0..count]) |attr| {
                try pdx.attributes.append(allocator, attr);
            }
            pdx.is_principal = true;
        }

        if (input.admit_dx) |*adx| {
            const count = mce_validation.loadAttributes(dx_master, adx.getCode(), input.discharge_date, &attr_buf);
            for (attr_buf[0..count]) |attr| {
                try adx.attributes.append(allocator, attr);
            }
        }

        for (input.sdx.items) |*sdx| {
            const count = mce_validation.loadAttributes(dx_master, sdx.getCode(), input.discharge_date, &attr_buf);
            for (attr_buf[0..count]) |attr| {
                try sdx.attributes.append(allocator, attr);
            }
        }

        for (input.procedures.items) |*proc| {
            const count = mce_validation.loadAttributes(sg_master, proc.getCode(), input.discharge_date, &attr_buf);
            for (attr_buf[0..count]) |attr| {
                try proc.attributes.append(allocator, attr);
            }
        }

        // --- Phase 3: Editing ---

        // Pre-compute attribute presence flags for procedure logic
        const sex_i32 = sex_int;

        // PDX edits
        if (input.pdx) |*pdx| {
            const attrs = pdx.attributes.items;
            const is_sdx_empty = input.sdx.items.len == 0;

            if (mce_editing.doECodeEdit(attrs)) |idx| try counter.incrementDx(idx, pdx, allocator);
            if (mce_editing.doManifestationEdit(attrs)) |idx| try counter.incrementDx(idx, pdx, allocator);
            if (mce_editing.doUnacceptableEdit(attrs, is_sdx_empty)) |idx| try counter.incrementDx(idx, pdx, allocator);
            if (mce_editing.doNonSpecificEdit(attrs, input.discharge_status)) |idx| try counter.incrementDx(idx, pdx, allocator);
            if (mce_editing.doQuestionableAdmissionEdit(attrs)) |idx| try counter.incrementDx(idx, pdx, allocator);

            // Age conflict on PDX
            if (mce_editing.doAgeConflictEdit(attrs, input.age, input.discharge_date, &self.age_ranges)) |result| {
                pdx.age_conflict_type = result.conflict_type;
                try counter.incrementDx(result.edit, pdx, allocator);
            }

            // Sex conflict on PDX
            if (mce_editing.doSexConflictEdit(attrs, sex_i32, input.discharge_date)) |idx| {
                try counter.incrementDx(idx, pdx, allocator);
            }

            if (mce_editing.doWrongProcedurePerformedEdit(attrs)) |idx| try counter.incrementDx(idx, pdx, allocator);
            if (mce_editing.doMedicareAsSecondaryPayer(attrs)) |idx| try counter.incrementDx(idx, pdx, allocator);
            if (mce_editing.doUnspecifiedEdit(attrs)) |idx| try counter.incrementDx(idx, pdx, allocator);
        }

        // Admit DX edits (age + sex only, no counter increment)
        if (input.admit_dx) |*adx| {
            const attrs = adx.attributes.items;
            if (mce_editing.doAgeConflictEdit(attrs, input.age, input.discharge_date, &self.age_ranges)) |result| {
                adx.age_conflict_type = result.conflict_type;
                try adx.addEdit(allocator, result.edit);
            }
            if (mce_editing.doSexConflictEdit(attrs, sex_i32, input.discharge_date)) |idx| {
                try adx.addEdit(allocator, idx);
            }
        }

        // SDX edits
        for (input.sdx.items) |*sdx| {
            const attrs = sdx.attributes.items;

            // Duplicate of PDX
            if (input.pdx) |pdx| {
                if (mce_editing.doDuplicateOfPdxEdit(pdx.getCode(), sdx.getCode())) |idx| {
                    try counter.incrementDx(idx, sdx, allocator);
                }
            }

            if (mce_editing.doMedicareAsSecondaryPayer(attrs)) |idx| try counter.incrementDx(idx, sdx, allocator);
            if (mce_editing.doUnspecifiedEdit(attrs)) |idx| try counter.incrementDx(idx, sdx, allocator);
            if (mce_editing.doWrongProcedurePerformedEdit(attrs)) |idx| try counter.incrementDx(idx, sdx, allocator);

            // Age + sex conflict on SDX
            if (mce_editing.doAgeConflictEdit(attrs, input.age, input.discharge_date, &self.age_ranges)) |result| {
                sdx.age_conflict_type = result.conflict_type;
                try counter.incrementDx(result.edit, sdx, allocator);
            }
            if (mce_editing.doSexConflictEdit(attrs, sex_i32, input.discharge_date)) |idx| {
                try counter.incrementDx(idx, sdx, allocator);
            }
        }

        // Procedure edits — pre-compute claim-level attribute flags
        var is_proc_kidney = false;
        var is_proc_ncov9 = false;
        var is_proc_ncov13b = false;
        var is_proc_z006a = false;
        var is_proc_z006b = false;
        var is_dx_type1diab = false;
        var is_dx_clintrial = false;
        var is_dx_ncov_d = false;
        var is_dx_ncov_e = false;
        var is_dx_ncov_g = false;
        var is_dx_ncov2 = false;
        var is_dx_ncov2_lt64 = false;
        var is_dx_ncov2_lt78 = false;
        var is_sdx_ncov89 = false;
        var is_dx_ncov3 = false;
        var is_dx_ncov4 = false;
        var is_dx_ncov5 = false;
        var is_sdx_delout = false;
        var is_pdx_mdc08 = false;
        var num_bilateral: usize = 0;
        var not_all_nonspecific_or = false;

        for (input.procedures.items) |proc| {
            for (proc.attributes.items) |attr| {
                switch (attr) {
                    .NCOV_B_KXP => is_proc_kidney = true,
                    .NCOV9 => is_proc_ncov9 = true,
                    .NCOV13B => is_proc_ncov13b = true,
                    .COV_Z006A => is_proc_z006a = true,
                    .COV_Z006B => is_proc_z006b = true,
                    .BILATERAL => {},
                    .NONSPECIFIC => {},
                    else => {},
                }
            }
        }

        // Check bilateral (distinct codes only)
        {
            var seen_codes: [100][8]u8 = undefined;
            var seen_count: usize = 0;
            for (input.procedures.items) |proc| {
                if (!hasAttrInSlice(proc.attributes.items, .BILATERAL)) continue;
                var found = false;
                for (seen_codes[0..seen_count]) |seen| {
                    if (std.mem.eql(u8, &seen, &proc.code)) {
                        found = true;
                        break;
                    }
                }
                if (!found and seen_count < seen_codes.len) {
                    seen_codes[seen_count] = proc.code;
                    seen_count += 1;
                }
            }
            num_bilateral = seen_count;
        }

        // Check not all nonspecific OR
        for (input.procedures.items) |proc| {
            if (hasAttrInSlice(proc.attributes.items, .OR_INDC) and !hasAttrInSlice(proc.attributes.items, .NONSPECIFIC)) {
                not_all_nonspecific_or = true;
                break;
            }
        }

        // Collect diagnosis attributes across PDX + SDX
        if (input.pdx) |pdx| {
            for (pdx.attributes.items) |attr| {
                switch (attr) {
                    .NCOV_B => is_dx_type1diab = true,
                    .CLINTRIAL => is_dx_clintrial = true,
                    .NCOV_D => is_dx_ncov_d = true,
                    .NCOV_E => is_dx_ncov_e = true,
                    .NCOV_G => is_dx_ncov_g = true,
                    .NCOV2 => is_dx_ncov2 = true,
                    .NCOV2AGELT64 => is_dx_ncov2_lt64 = true,
                    .NCOV2AGELT78 => is_dx_ncov2_lt78 = true,
                    .NCOV3 => is_dx_ncov3 = true,
                    .NCOV4 => is_dx_ncov4 = true,
                    .NCOV5 => is_dx_ncov5 = true,
                    .MDC08 => is_pdx_mdc08 = true,
                    else => {},
                }
            }
        }
        for (input.sdx.items) |sdx| {
            for (sdx.attributes.items) |attr| {
                switch (attr) {
                    .NCOV_B => is_dx_type1diab = true,
                    .CLINTRIAL => is_dx_clintrial = true,
                    .NCOV_D => is_dx_ncov_d = true,
                    .NCOV_E => is_dx_ncov_e = true,
                    .NCOV_G => is_dx_ncov_g = true,
                    .NCOV2 => is_dx_ncov2 = true,
                    .NCOV2AGELT64 => is_dx_ncov2_lt64 = true,
                    .NCOV2AGELT78 => is_dx_ncov2_lt78 = true,
                    .NCOV3 => is_dx_ncov3 = true,
                    .NCOV4 => is_dx_ncov4 = true,
                    .NCOV5 => is_dx_ncov5 = true,
                    .DELOUT => is_sdx_delout = true,
                    .NCOV89 => is_sdx_ncov89 = true,
                    else => {},
                }
            }
        }

        // Run procedure edits
        for (input.procedures.items) |*proc| {
            const attrs = proc.attributes.items;

            // Sex conflict
            if (mce_editing.doSexConflictEdit(attrs, sex_i32, input.discharge_date)) |idx| {
                try counter.incrementSg(idx, proc, allocator);
            }

            // Non-specific OR
            if (mce_editing.doNonSpecificORProcedureEdit(attrs, not_all_nonspecific_or)) |idx| {
                try counter.incrementSg(idx, proc, allocator);
            }

            // Biopsy
            if (mce_editing.doOpenBiopsyCheck(attrs)) |idx| {
                try counter.incrementSg(idx, proc, allocator);
            }

            // LOS inconsistency
            if (mce_editing.doInconsistentWithLOS(attrs, input.age, icd_version)) |idx| {
                try counter.incrementSg(idx, proc, allocator);
            }

            // Non-covered
            const nc_ctx = mce_editing.NonCoveredContext{
                .is_procedure_kidney_transplant_present = is_proc_kidney,
                .is_procedure_ncov9_present = is_proc_ncov9,
                .is_procedure_ncov13b_present = is_proc_ncov13b,
                .is_procedure_z006a_present = is_proc_z006a,
                .is_procedure_z006b_present = is_proc_z006b,
                .is_diagnosis_type1_diabetes_present = is_dx_type1diab,
                .is_diagnosis_clintrial_present = is_dx_clintrial,
                .is_diagnosis_ncov_d_present = is_dx_ncov_d,
                .is_diagnosis_ncov_e_present = is_dx_ncov_e,
                .is_diagnosis_ncov_g_present = is_dx_ncov_g,
                .is_diagnosis_ncov2_present = is_dx_ncov2,
                .is_diagnosis_ncov2_age_lt64_present = is_dx_ncov2_lt64,
                .is_diagnosis_ncov2_age_lt78_present = is_dx_ncov2_lt78,
                .is_secondary_diagnosis_ncov89_present = is_sdx_ncov89,
                .is_diagnosis_ncov3_present = is_dx_ncov3,
                .is_diagnosis_ncov4_present = is_dx_ncov4,
                .is_diagnosis_ncov5_present = is_dx_ncov5,
                .age = input.age,
                .discharge_date = input.discharge_date,
            };

            if (mce_editing.doNonCoveredProcedureEdit(attrs, nc_ctx)) |idx| {
                try counter.incrementSg(idx, proc, allocator);
            }

            // Limited coverage — only if NON_COVERED was NOT triggered for this proc
            if (proc.edits.items.len == 0 or !hasEditForIndex(proc.edits.items, mce_editing.EDIT_NON_COVERED)) {
                if (mce_editing.doLimitedCoverage(attrs, is_dx_clintrial, is_proc_z006a, is_proc_z006b)) |idx| {
                    try counter.incrementSg(idx, proc, allocator);
                }
                if (mce_editing.doLimitedCoverageI9(attrs)) |idx| {
                    try counter.incrementSg(idx, proc, allocator);
                }
            }

            // Bilateral (counted once across all procedures)
            if (mce_editing.doBilateralProcedureEdit(attrs, is_pdx_mdc08, num_bilateral)) |idx| {
                if (counter.getCount(idx) == 0) {
                    counter.increment(idx);
                }
                try proc.addEdit(allocator, idx);
            }

            // Obstetric
            if (mce_editing.doQuestionableObstetricAdmissionEdit(attrs, is_sdx_delout)) |idx| {
                try counter.incrementSg(idx, proc, allocator);
            }
        }

        // --- Phase 4: Copy counts to output ---
        // Note: validation-phase edits (INVALID_CODE, etc.) were incremented
        // directly on output.edit_counts. Editing-phase edits are in counter.
        // Merge: add counter counts to existing output counts.
        for (counter.counts, 0..) |count, i| {
            output.edit_counts[i] += count;
        }
        output.determineEditType();

        return output;
    }
};

fn hasAttrInSlice(attrs: []const Attribute, target: Attribute) bool {
    for (attrs) |a| {
        if (a == target) return true;
    }
    return false;
}

fn hasEditForIndex(edits: []const usize, target: usize) bool {
    for (edits) |e| {
        if (e == target) return true;
    }
    return false;
}

// --- Tests ---

test "MceComponent init/deinit" {
    const allocator = std.testing.allocator;
    const data_dir = "../data/bin/";

    var comp = MceComponent.init(data_dir, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    try std.testing.expectEqual(@as(i32, 20260930), comp.version);
    try std.testing.expect(comp.i10dx.mapped.header.num_entries > 80000);
}

test "MceComponent process valid claim" {
    const allocator = std.testing.allocator;
    const data_dir = "../data/bin/";

    var comp = MceComponent.init(data_dir, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    var input = MceInput{
        .age = 65,
        .sex = .MALE,
        .discharge_status = 1,
        .discharge_date = 20250101,
        .pdx = MceDiagnosisCode.init("I5020"),
    };
    defer input.deinit(allocator);
    try input.sdx.append(allocator, MceDiagnosisCode.init("E1165"));

    var output = try comp.process(&input, 10, allocator);

    try std.testing.expectEqual(EditType.NONE, output.edit_type);
    try std.testing.expect(!output.hasEdits());
}

test "MceComponent process E-code as PDX" {
    const allocator = std.testing.allocator;
    const data_dir = "../data/bin/";

    var comp = MceComponent.init(data_dir, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    // E-code as PDX should trigger E_CODE_AS_PDX edit
    var input = MceInput{
        .age = 65,
        .sex = .MALE,
        .discharge_status = 1,
        .discharge_date = 20250101,
        .pdx = MceDiagnosisCode.init("V0001XA"),
    };
    defer input.deinit(allocator);

    var output = try comp.process(&input, 10, allocator);

    try std.testing.expect(output.hasEdits());
    try std.testing.expectEqual(EditType.PREPAYMENT, output.edit_type);
    try std.testing.expect(output.getCount(mce_editing.EDIT_E_CODE_AS_PDX) > 0);
}

test "MceComponent process sex conflict" {
    const allocator = std.testing.allocator;
    const data_dir = "../data/bin/";

    var comp = MceComponent.init(data_dir, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    // Female-only code with male sex → SEX_CONFLICT
    // A34 is "female" + "maternity" (active 20151001-20240930)
    var input = MceInput{
        .age = 25,
        .sex = .MALE,
        .discharge_status = 1,
        .discharge_date = 20240101, // within A34's active range
        .pdx = MceDiagnosisCode.init("I5020"),
    };
    defer input.deinit(allocator);
    try input.sdx.append(allocator, MceDiagnosisCode.init("A34"));

    var output = try comp.process(&input, 10, allocator);

    try std.testing.expect(output.getCount(mce_editing.EDIT_SEX_CONFLICT) > 0);
}

test "MceComponent process age conflict" {
    const allocator = std.testing.allocator;
    const data_dir = "../data/bin/";

    var comp = MceComponent.init(data_dir, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    // Newborn code (A33) with adult age → AGE_CONFLICT
    var input = MceInput{
        .age = 65,
        .sex = .MALE,
        .discharge_status = 1,
        .discharge_date = 20250101,
        .pdx = MceDiagnosisCode.init("A33"),
    };
    defer input.deinit(allocator);

    var output = try comp.process(&input, 10, allocator);

    try std.testing.expect(output.getCount(mce_editing.EDIT_AGE_CONFLICT) > 0);
}

test "MceComponent process unacceptable PDX" {
    const allocator = std.testing.allocator;
    const data_dir = "../data/bin/";

    var comp = MceComponent.init(data_dir, allocator) catch |err| {
        std.debug.print("Skipping: {}\n", .{err});
        return;
    };
    defer comp.deinit();

    // Z9989 has "unacceptable" flag
    var input = MceInput{
        .age = 65,
        .sex = .MALE,
        .discharge_status = 1,
        .discharge_date = 20250101,
        .pdx = MceDiagnosisCode.init("Z9989"),
    };
    defer input.deinit(allocator);

    var output = try comp.process(&input, 10, allocator);

    try std.testing.expect(output.getCount(mce_editing.EDIT_UNACCEPTABLE_PDX) > 0);
}
