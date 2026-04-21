const std = @import("std");
const mce_data = @import("mce_data.zig");
const mce_enums = @import("mce_enums.zig");
const mce_validation = @import("mce_validation.zig");

const Attribute = mce_enums.Attribute;
const Edit = mce_enums.Edit;
const MceDiagnosisCode = mce_enums.MceDiagnosisCode;
const MceProcedureCode = mce_enums.MceProcedureCode;

// --- Edit Counter ---

pub const EditCounter = struct {
    counts: [mce_enums.ALL_EDITS.len]u32 = [_]u32{0} ** mce_enums.ALL_EDITS.len,
    pdx_suppressions: []const usize = &.{},
    sdx_suppressions: []const usize = &.{},
    sg_suppressions: []const usize = &.{},

    /// Increment edit count (no code, no suppression check).
    pub fn increment(self: *EditCounter, edit_index: usize) void {
        self.counts[edit_index] += 1;
    }

    /// Increment edit count for a diagnosis code, checking suppression.
    pub fn incrementDx(self: *EditCounter, edit_index: usize, code: *MceDiagnosisCode, allocator: std.mem.Allocator) !void {
        if (self.isSuppressed(edit_index, code)) return;
        self.counts[edit_index] += 1;
        try code.addEdit(allocator, edit_index);
    }

    /// Increment edit count for a procedure code, checking suppression.
    pub fn incrementSg(self: *EditCounter, edit_index: usize, code: *MceProcedureCode, allocator: std.mem.Allocator) !void {
        if (self.isSuppressedSg(edit_index)) return;
        self.counts[edit_index] += 1;
        try code.addEdit(allocator, edit_index);
    }

    fn isSuppressed(self: *EditCounter, edit_index: usize, code: *const MceDiagnosisCode) bool {
        if (code.is_principal) {
            for (self.pdx_suppressions) |s| {
                if (s == edit_index) return true;
            }
        } else {
            for (self.sdx_suppressions) |s| {
                if (s == edit_index) return true;
            }
        }
        return false;
    }

    fn isSuppressedSg(self: *EditCounter, edit_index: usize) bool {
        for (self.sg_suppressions) |s| {
            if (s == edit_index) return true;
        }
        return false;
    }

    pub fn getCount(self: *const EditCounter, edit_index: usize) u32 {
        return self.counts[edit_index];
    }
};

// --- Edit Index Constants ---
// These match the ordinals in mce_enums.ALL_EDITS

pub const EDIT_INVALID_CODE: usize = 0;
pub const EDIT_SEX_CONFLICT: usize = 1;
pub const EDIT_AGE_CONFLICT: usize = 2;
pub const EDIT_QUESTIONABLE_ADMISSION: usize = 3;
pub const EDIT_MANIFESTATION_AS_PDX: usize = 4;
pub const EDIT_NONSPECIFIC_PDX: usize = 5;
pub const EDIT_E_CODE_AS_PDX: usize = 6;
pub const EDIT_UNACCEPTABLE_PDX: usize = 7;
pub const EDIT_DUPLICATE_OF_PDX: usize = 8;
pub const EDIT_MEDICARE_IS_SECONDARY_PAYER: usize = 9;
pub const EDIT_REQUIRES_SDX: usize = 10;
pub const EDIT_NONSPECIFIC_OR: usize = 11;
pub const EDIT_OPEN_BIOPSY: usize = 12;
pub const EDIT_NON_COVERED: usize = 13;
pub const EDIT_BILATERAL: usize = 14;
pub const EDIT_LIMITED_COVERAGE_LVRS: usize = 15;
pub const EDIT_LIMITED_COVERAGE: usize = 16;
pub const EDIT_LIMITED_COVERAGE_LUNG_TRANSPLANT: usize = 17;
pub const EDIT_QUESTIONABLE_OBSTETRIC_ADMISSION: usize = 18;
pub const EDIT_LIMITED_COVERAGE_COMBINATION_HEART_LUNG: usize = 19;
pub const EDIT_LIMITED_COVERAGE_HEART_TRANSPLANT: usize = 20;
pub const EDIT_LIMITED_COVERAGE_HEART_IMPLANT: usize = 21;
pub const EDIT_LIMITED_COVERAGE_INTESTINE: usize = 22;
pub const EDIT_LIMITED_COVERAGE_LIVER: usize = 23;
pub const EDIT_INVALID_ADMIT_DX: usize = 24;
pub const EDIT_INVALID_AGE: usize = 25;
pub const EDIT_INVALID_SEX: usize = 26;
pub const EDIT_INVALID_DISCHARGE_STATUS: usize = 27;
pub const EDIT_LIMITED_COVERAGE_KIDNEY: usize = 28;
pub const EDIT_LIMITED_COVERAGE_PANCREAS: usize = 29;
pub const EDIT_WRONG_PROCEDURE_PERFORMED: usize = 33;
pub const EDIT_INCONSISTENT_WITH_LENGTH_OF_STAY: usize = 34;
pub const EDIT_UNSPECIFIED: usize = 35;

// --- Code Logic (shared DX/SG edits) ---

/// Check for sex conflict. After 2024-10-01, UNKNOWN sex is accepted.
pub fn doSexConflictEdit(code_attributes: []const Attribute, sex: i32, date: i32) ?usize {
    if (date >= mce_validation.SEX_UNKNOWN_VALID_DATE and sex == mce_validation.SEX_UNKNOWN) {
        return null;
    }

    for (code_attributes) |attr| {
        if (attr == .MALE and sex != mce_validation.SEX_MALE) return EDIT_SEX_CONFLICT;
        if (attr == .FEMALE and sex != mce_validation.SEX_FEMALE) return EDIT_SEX_CONFLICT;
    }
    return null;
}

// --- Principal Diagnosis Logic ---

pub fn doECodeEdit(pdx_attributes: []const Attribute) ?usize {
    for (pdx_attributes) |attr| {
        if (attr == .ECODEPDX) return EDIT_E_CODE_AS_PDX;
    }
    return null;
}

pub fn doManifestationEdit(pdx_attributes: []const Attribute) ?usize {
    for (pdx_attributes) |attr| {
        if (attr == .MANIF) return EDIT_MANIFESTATION_AS_PDX;
    }
    return null;
}

pub fn doUnacceptableEdit(pdx_attributes: []const Attribute, is_sdx_empty: bool) ?usize {
    const has_unacceptable = hasAttr(pdx_attributes, .UNACCEPTABLE);
    const has_reqsdx = hasAttr(pdx_attributes, .REQSDX);

    if (has_unacceptable and has_reqsdx) {
        if (is_sdx_empty) return EDIT_REQUIRES_SDX;
    } else if (has_unacceptable) {
        return EDIT_UNACCEPTABLE_PDX;
    }
    return null;
}

pub fn doNonSpecificEdit(pdx_attributes: []const Attribute, discharge_status: i32) ?usize {
    if (hasAttr(pdx_attributes, .NONSPECIFIC) and discharge_status != mce_validation.DISCHARGE_STATUS_DIED) {
        return EDIT_NONSPECIFIC_PDX;
    }
    return null;
}

pub fn doQuestionableAdmissionEdit(pdx_attributes: []const Attribute) ?usize {
    for (pdx_attributes) |attr| {
        if (attr == .QADM) return EDIT_QUESTIONABLE_ADMISSION;
    }
    return null;
}

pub fn doDuplicateOfPdxEdit(pdx_code: []const u8, sdx_code: []const u8) ?usize {
    if (std.mem.eql(u8, pdx_code, sdx_code)) return EDIT_DUPLICATE_OF_PDX;
    return null;
}

// --- Diagnosis Logic ---

pub fn doAgeConflictEdit(
    code_attributes: []const Attribute,
    age: i32,
    date: i32,
    age_data: *const mce_data.AgeRangeData,
) !?struct { edit: usize, conflict_type: mce_enums.AgeConflictType } {
    // Check age group attributes — order matches Java (PEDIATRIC, NEWBORN, MATERNITY, ADULT)
    const ordered = [_]struct { attr: Attribute, name: []const u8 }{
        .{ .attr = .PEDIATRIC, .name = "Pediatric" },
        .{ .attr = .NEWBORN, .name = "Newborn" },
        .{ .attr = .MATERNITY, .name = "Maternity" },
        .{ .attr = .ADULT, .name = "Adult" },
    };

    for (ordered) |group| {
        if (!hasAttr(code_attributes, group.attr)) continue;
        if (!try age_data.isAgeInGroup(age, group.name, date)) {
            if (mce_enums.AgeConflictType.fromGroupName(group.name)) |ct| {
                return .{ .edit = EDIT_AGE_CONFLICT, .conflict_type = ct };
            }
        }
    }
    return null;
}

pub fn doWrongProcedurePerformedEdit(code_attributes: []const Attribute) ?usize {
    for (code_attributes) |attr| {
        if (attr == .WRNGPROC) return EDIT_WRONG_PROCEDURE_PERFORMED;
    }
    return null;
}

pub fn doUnspecifiedEdit(code_attributes: []const Attribute) ?usize {
    for (code_attributes) |attr| {
        if (attr == .UNSPECIFIED) return EDIT_UNSPECIFIED;
    }
    return null;
}

pub fn doMedicareAsSecondaryPayer(code_attributes: []const Attribute) ?usize {
    for (code_attributes) |attr| {
        if (attr == .MSP) return EDIT_MEDICARE_IS_SECONDARY_PAYER;
    }
    return null;
}

// --- Procedure Logic ---

pub fn doNonSpecificORProcedureEdit(code_attributes: []const Attribute, not_all_nonspecific: bool) ?usize {
    if (!not_all_nonspecific and hasAttr(code_attributes, .NONSPECIFIC)) {
        return EDIT_NONSPECIFIC_OR;
    }
    return null;
}

pub fn doOpenBiopsyCheck(code_attributes: []const Attribute) ?usize {
    for (code_attributes) |attr| {
        if (attr == .BIOPSY) return EDIT_OPEN_BIOPSY;
    }
    return null;
}

pub fn doInconsistentWithLOS(code_attributes: []const Attribute, los: i32, icd_version: u8) ?usize {
    const min_los: i32 = if (icd_version == 9) 4 else 5;
    if (hasAttr(code_attributes, .LOS) and los < min_los) {
        return EDIT_INCONSISTENT_WITH_LENGTH_OF_STAY;
    }
    return null;
}

pub const NonCoveredContext = struct {
    is_procedure_kidney_transplant_present: bool,
    is_procedure_ncov9_present: bool,
    is_procedure_ncov13b_present: bool,
    is_procedure_z006a_present: bool,
    is_procedure_z006b_present: bool,
    is_diagnosis_type1_diabetes_present: bool,
    is_diagnosis_clintrial_present: bool,
    is_diagnosis_ncov_d_present: bool,
    is_diagnosis_ncov_e_present: bool,
    is_diagnosis_ncov_g_present: bool,
    is_diagnosis_ncov2_present: bool,
    is_diagnosis_ncov2_age_lt64_present: bool,
    is_diagnosis_ncov2_age_lt78_present: bool,
    is_secondary_diagnosis_ncov89_present: bool,
    is_diagnosis_ncov3_present: bool,
    is_diagnosis_ncov4_present: bool,
    is_diagnosis_ncov5_present: bool,
    age: i32,
    discharge_date: i32,
};

pub fn doNonCoveredProcedureEdit(code_attributes: []const Attribute, ctx: NonCoveredContext) ?usize {
    // Part A: NCOV_A flag
    if (hasAttr(code_attributes, .NCOV_A)) return EDIT_NON_COVERED;

    // Part B: NCOV_B_PXP (kidney transplant related)
    if (hasAttr(code_attributes, .NCOV_B_PXP)) {
        if (ctx.discharge_date < 20060426) {
            if (!ctx.is_diagnosis_ncov4_present or !ctx.is_diagnosis_ncov5_present) {
                return EDIT_NON_COVERED;
            }
        } else {
            if (!ctx.is_procedure_kidney_transplant_present and !ctx.is_diagnosis_type1_diabetes_present) {
                return EDIT_NON_COVERED;
            }
        }
    }

    // Part C: COV_Z006A/B
    if ((hasAttr(code_attributes, .COV_Z006A) or hasAttr(code_attributes, .COV_Z006B)) and
        ctx.is_procedure_z006a_present and ctx.is_procedure_z006b_present and
        !ctx.is_diagnosis_clintrial_present)
    {
        return EDIT_NON_COVERED;
    }

    // Part D: NCOV_D
    if (hasAttr(code_attributes, .NCOV_D) and ctx.is_diagnosis_ncov_d_present) {
        return EDIT_NON_COVERED;
    }

    // Part E: NCOV_E
    if (hasAttr(code_attributes, .NCOV_E) and ctx.is_diagnosis_ncov_e_present) {
        return EDIT_NON_COVERED;
    }

    // Part F: NCOV_F (age > 60)
    if (hasAttr(code_attributes, .NCOV_F) and (ctx.age < 0 or ctx.age > 60)) {
        return EDIT_NON_COVERED;
    }

    // Part G: NCOV_G
    if (hasAttr(code_attributes, .NCOV_G) and ctx.is_diagnosis_ncov_g_present) {
        return EDIT_NON_COVERED;
    }

    // Part 2: NCOV2
    if (hasAttr(code_attributes, .NCOV2)) {
        if (!ctx.is_diagnosis_ncov2_present) {
            if (ctx.is_diagnosis_ncov2_age_lt64_present) {
                if (ctx.age < 0 or ctx.age >= 64) return EDIT_NON_COVERED;
            } else if (ctx.is_diagnosis_ncov2_age_lt78_present) {
                if (ctx.age < 0 or ctx.age >= 78) return EDIT_NON_COVERED;
            } else {
                return EDIT_NON_COVERED;
            }
        }
    }

    // Part 3: NCOV3
    if (hasAttr(code_attributes, .NCOV3) and !ctx.is_diagnosis_ncov3_present) {
        return EDIT_NON_COVERED;
    }

    // Part 8: NCOV8
    if (hasAttr(code_attributes, .NCOV8) and (!ctx.is_secondary_diagnosis_ncov89_present or !ctx.is_procedure_ncov9_present)) {
        return EDIT_NON_COVERED;
    }

    // Part 13A: NCOV13A
    if (hasAttr(code_attributes, .NCOV13A) and !ctx.is_procedure_ncov13b_present) {
        return EDIT_NON_COVERED;
    }

    // Artificial heart: LCOV_ARTHEARTXP without clinical trial
    if (hasAttr(code_attributes, .LCOV_ARTHEARTXP) and !ctx.is_diagnosis_clintrial_present) {
        return EDIT_NON_COVERED;
    }

    return null;
}

pub fn doLimitedCoverage(code_attributes: []const Attribute, is_diagnosis_clintrial_present: bool, is_procedure_z006a_present: bool, is_procedure_z006b_present: bool) ?usize {
    // Part A: LCOV flag
    if (hasAttr(code_attributes, .LCOV)) return EDIT_LIMITED_COVERAGE;

    // Part B: COV_Z006A/B with clinical trial
    if ((hasAttr(code_attributes, .COV_Z006A) or hasAttr(code_attributes, .COV_Z006B)) and
        is_procedure_z006a_present and is_procedure_z006b_present and
        is_diagnosis_clintrial_present)
    {
        return EDIT_LIMITED_COVERAGE;
    }

    return null;
}

pub fn doLimitedCoverageI9(code_attributes: []const Attribute) ?usize {
    if (hasAttr(code_attributes, .LCOV_LVRS)) return EDIT_LIMITED_COVERAGE_LVRS;
    if (hasAttr(code_attributes, .LCOV_LUNGXP)) return EDIT_LIMITED_COVERAGE_LUNG_TRANSPLANT;
    if (hasAttr(code_attributes, .LCOV_HEARTLUNGXP)) return EDIT_LIMITED_COVERAGE_COMBINATION_HEART_LUNG;
    if (hasAttr(code_attributes, .LCOV_HEARTXP)) return EDIT_LIMITED_COVERAGE_HEART_TRANSPLANT;
    if (hasAttr(code_attributes, .LCOV_HEARTSYS)) return EDIT_LIMITED_COVERAGE_HEART_IMPLANT;
    if (hasAttr(code_attributes, .LCOV_INTXP)) return EDIT_LIMITED_COVERAGE_INTESTINE;
    if (hasAttr(code_attributes, .LCOV_LIVERXP)) return EDIT_LIMITED_COVERAGE_LIVER;
    if (hasAttr(code_attributes, .LCOV_KIDNEYXP)) return EDIT_LIMITED_COVERAGE_KIDNEY;
    if (hasAttr(code_attributes, .LCOV_PANCREASXP)) return EDIT_LIMITED_COVERAGE_PANCREAS;
    if (hasAttr(code_attributes, .LCOV_ARTHEARTXP)) return EDIT_LIMITED_COVERAGE;
    return null;
}

pub fn doBilateralProcedureEdit(code_attributes: []const Attribute, is_pdx_mdc08: bool, num_bilateral: usize) ?usize {
    if (hasAttr(code_attributes, .BILATERAL) and is_pdx_mdc08 and num_bilateral >= 2) {
        return EDIT_BILATERAL;
    }
    return null;
}

pub fn doQuestionableObstetricAdmissionEdit(code_attributes: []const Attribute, is_sdx_delout_present: bool) ?usize {
    if ((hasAttr(code_attributes, .CSECT) or hasAttr(code_attributes, .VAGDEL)) and !is_sdx_delout_present) {
        return EDIT_QUESTIONABLE_OBSTETRIC_ADMISSION;
    }
    return null;
}

// --- Helpers ---

fn hasAttr(attributes: []const Attribute, target: Attribute) bool {
    for (attributes) |a| {
        if (a == target) return true;
    }
    return false;
}

// --- Tests ---

test "doSexConflictEdit" {
    const male_attrs = [_]Attribute{.MALE};
    const female_attrs = [_]Attribute{.FEMALE};
    const no_sex_attrs = [_]Attribute{.ADULT};

    // Male code with female sex → conflict
    try std.testing.expectEqual(@as(?usize, EDIT_SEX_CONFLICT), doSexConflictEdit(&male_attrs, 2, 20250101));
    // Male code with male sex → no conflict
    try std.testing.expectEqual(@as(?usize, null), doSexConflictEdit(&male_attrs, 1, 20250101));
    // Female code with male sex → conflict
    try std.testing.expectEqual(@as(?usize, EDIT_SEX_CONFLICT), doSexConflictEdit(&female_attrs, 1, 20250101));
    // No sex attribute → no conflict
    try std.testing.expectEqual(@as(?usize, null), doSexConflictEdit(&no_sex_attrs, 0, 20250101));
    // UNKNOWN after 2024-10-01 → no conflict
    try std.testing.expectEqual(@as(?usize, null), doSexConflictEdit(&male_attrs, 0, 20250101));
    // UNKNOWN before 2024-10-01 → conflict
    try std.testing.expectEqual(@as(?usize, EDIT_SEX_CONFLICT), doSexConflictEdit(&male_attrs, 0, 20240930));
}

test "doECodeEdit" {
    const ecode_attrs = [_]Attribute{.ECODEPDX};
    const normal_attrs = [_]Attribute{.ADULT};

    try std.testing.expectEqual(@as(?usize, EDIT_E_CODE_AS_PDX), doECodeEdit(&ecode_attrs));
    try std.testing.expectEqual(@as(?usize, null), doECodeEdit(&normal_attrs));
}

test "doManifestationEdit" {
    const manif_attrs = [_]Attribute{.MANIF};
    try std.testing.expectEqual(@as(?usize, EDIT_MANIFESTATION_AS_PDX), doManifestationEdit(&manif_attrs));
    try std.testing.expectEqual(@as(?usize, null), doManifestationEdit(&[_]Attribute{.ADULT}));
}

test "doUnacceptableEdit" {
    const unacc_attrs = [_]Attribute{.UNACCEPTABLE};
    const unacc_reqsdx = [_]Attribute{ .UNACCEPTABLE, .REQSDX };

    // UNACCEPTABLE without REQSDX
    try std.testing.expectEqual(@as(?usize, EDIT_UNACCEPTABLE_PDX), doUnacceptableEdit(&unacc_attrs, false));
    // UNACCEPTABLE with REQSDX, no SDX → REQUIRES_SDX
    try std.testing.expectEqual(@as(?usize, EDIT_REQUIRES_SDX), doUnacceptableEdit(&unacc_reqsdx, true));
    // UNACCEPTABLE with REQSDX, has SDX → no edit
    try std.testing.expectEqual(@as(?usize, null), doUnacceptableEdit(&unacc_reqsdx, false));
}

test "doNonSpecificEdit" {
    const nonspec_attrs = [_]Attribute{.NONSPECIFIC};

    // Non-specific with normal discharge → edit
    try std.testing.expectEqual(@as(?usize, EDIT_NONSPECIFIC_PDX), doNonSpecificEdit(&nonspec_attrs, 1));
    // Non-specific with died status → no edit
    try std.testing.expectEqual(@as(?usize, null), doNonSpecificEdit(&nonspec_attrs, 20));
}

test "doDuplicateOfPdxEdit" {
    try std.testing.expectEqual(@as(?usize, EDIT_DUPLICATE_OF_PDX), doDuplicateOfPdxEdit("I5020", "I5020"));
    try std.testing.expectEqual(@as(?usize, null), doDuplicateOfPdxEdit("I5020", "E1165"));
}

test "doQuestionableAdmissionEdit" {
    const qadm_attrs = [_]Attribute{.QADM};
    try std.testing.expectEqual(@as(?usize, EDIT_QUESTIONABLE_ADMISSION), doQuestionableAdmissionEdit(&qadm_attrs));
    try std.testing.expectEqual(@as(?usize, null), doQuestionableAdmissionEdit(&[_]Attribute{.ADULT}));
}

test "doWrongProcedurePerformedEdit" {
    const wrngproc = [_]Attribute{.WRNGPROC};
    try std.testing.expectEqual(@as(?usize, EDIT_WRONG_PROCEDURE_PERFORMED), doWrongProcedurePerformedEdit(&wrngproc));
    try std.testing.expectEqual(@as(?usize, null), doWrongProcedurePerformedEdit(&[_]Attribute{.ADULT}));
}

test "doUnspecifiedEdit" {
    const unspec = [_]Attribute{.UNSPECIFIED};
    try std.testing.expectEqual(@as(?usize, EDIT_UNSPECIFIED), doUnspecifiedEdit(&unspec));
}

test "doMedicareAsSecondaryPayer" {
    const msp = [_]Attribute{.MSP};
    try std.testing.expectEqual(@as(?usize, EDIT_MEDICARE_IS_SECONDARY_PAYER), doMedicareAsSecondaryPayer(&msp));
}

test "doOpenBiopsyCheck" {
    const biopsy = [_]Attribute{.BIOPSY};
    try std.testing.expectEqual(@as(?usize, EDIT_OPEN_BIOPSY), doOpenBiopsyCheck(&biopsy));
}

test "doNonCoveredProcedureEdit" {
    const ncov_a = [_]Attribute{.NCOV_A};
    const ctx = NonCoveredContext{
        .is_procedure_kidney_transplant_present = false,
        .is_procedure_ncov9_present = false,
        .is_procedure_ncov13b_present = false,
        .is_procedure_z006a_present = false,
        .is_procedure_z006b_present = false,
        .is_diagnosis_type1_diabetes_present = false,
        .is_diagnosis_clintrial_present = false,
        .is_diagnosis_ncov_d_present = false,
        .is_diagnosis_ncov_e_present = false,
        .is_diagnosis_ncov_g_present = false,
        .is_diagnosis_ncov2_present = false,
        .is_diagnosis_ncov2_age_lt64_present = false,
        .is_diagnosis_ncov2_age_lt78_present = false,
        .is_secondary_diagnosis_ncov89_present = false,
        .is_diagnosis_ncov3_present = false,
        .is_diagnosis_ncov4_present = false,
        .is_diagnosis_ncov5_present = false,
        .age = 65,
        .discharge_date = 20250101,
    };

    // NCOV_A → always non-covered
    try std.testing.expectEqual(@as(?usize, EDIT_NON_COVERED), doNonCoveredProcedureEdit(&ncov_a, ctx));

    // No ncov attributes → not non-covered
    const no_ncov = [_]Attribute{.OR_INDC};
    try std.testing.expectEqual(@as(?usize, null), doNonCoveredProcedureEdit(&no_ncov, ctx));
}
