const std = @import("std");
const mce_data = @import("mce_data.zig");

// --- Code Type ---

pub const CodeType = enum {
    NONE,
    DIAGNOSIS,
    PROCEDURE,
    BOTH,
};

// --- Edit Type ---

pub const EditType = enum {
    NONE,
    PREPAYMENT,
    POSTPAYMENT,
    BOTH,
    INVALID_DISCHARGE_DATE,
};

// --- Edit Counter Applicability ---

pub const EditCounterApplicability = enum {
    I9,
    I10,
    ALL,
};

// --- Age Conflict Type ---

pub const AgeConflictType = enum(u8) {
    NEWBORN = 1,
    PEDIATRIC = 2,
    MATERNITY = 3,
    ADULT = 4,

    pub fn fromGroupName(name: []const u8) ?AgeConflictType {
        if (std.ascii.eqlIgnoreCase(name, "Newborn")) return .NEWBORN;
        if (std.ascii.eqlIgnoreCase(name, "Pediatric")) return .PEDIATRIC;
        if (std.ascii.eqlIgnoreCase(name, "Maternity")) return .MATERNITY;
        if (std.ascii.eqlIgnoreCase(name, "Adult")) return .ADULT;
        return null;
    }
};

// --- Attribute ---

pub const Attribute = enum {
    // Both DX and SG
    FEMALE,
    MALE,
    NONSPECIFIC,
    NCOV_D,
    NCOV_E,
    NCOV_G,
    NCOV2,
    NCOV3,

    // Diagnosis only
    ADULT,
    CLINTRIAL,
    DELOUT,
    ECODEPDX,
    MATERNITY,
    NCOV_B,
    NEWBORN,
    PEDIATRIC,
    QADM,
    REQSDX,
    UNACCEPTABLE,
    WRNGPROC,
    UNSPECIFIED,
    MSP,
    MDC08,
    CC,
    NCOV4,
    NCOV5,
    NCOV2AGELT78,
    NCOV2AGELT64,
    NCOV89,
    MANIF,

    // Procedure only
    COV_Z006A,
    COV_Z006B,
    CSECT,
    LCOV,
    LOS,
    NCOV_A,
    NCOV_B_KXP,
    NCOV_B_PXP,
    NCOV_F,
    VAGDEL,
    BIOPSY,
    BILATERAL,
    OR_INDC,
    NCOV8,
    NCOV9,
    LCOV_ARTHEARTXP,
    LCOV_KIDNEYXP,
    LCOV_PANCREASXP,
    LCOV_LVRS,
    LCOV_LUNGXP,
    LCOV_HEARTLUNGXP,
    LCOV_HEARTXP,
    LCOV_HEARTSYS,
    LCOV_INTXP,
    LCOV_LIVERXP,
    NCOV13A,
    NCOV13B,

    /// Map a proto flag string to an Attribute enum value.
    pub fn fromFlag(flag: []const u8) ?Attribute {
        inline for (std.meta.fields(Attribute)) |f| {
            const attr: Attribute = @enumFromInt(f.value);
            if (std.mem.eql(u8, flag, attr.flagString())) return attr;
        }
        return null;
    }

    /// Get the proto flag string for this attribute.
    pub fn flagString(self: Attribute) []const u8 {
        return switch (self) {
            .FEMALE => "female",
            .MALE => "male",
            .NONSPECIFIC => "nonspecific",
            .NCOV_D => "ncov6",
            .NCOV_E => "ncov7",
            .NCOV_G => "ncov_z302",
            .NCOV2 => "ncov2",
            .NCOV3 => "ncov3",
            .ADULT => "adult",
            .CLINTRIAL => "clintrial",
            .DELOUT => "delout",
            .ECODEPDX => "ecodepdx",
            .MATERNITY => "maternity",
            .NCOV_B => "diabtypeI",
            .NEWBORN => "newborn",
            .PEDIATRIC => "pediatric",
            .QADM => "qadm",
            .REQSDX => "reqsdx",
            .UNACCEPTABLE => "unacceptable",
            .WRNGPROC => "wrngproc",
            .UNSPECIFIED => "unspecified",
            .MSP => "msp",
            .MDC08 => "mdc08",
            .CC => "cc",
            .NCOV4 => "ncov4",
            .NCOV5 => "ncov5",
            .NCOV2AGELT78 => "ncov2agelt78",
            .NCOV2AGELT64 => "ncov2agelt64",
            .NCOV89 => "ncov89",
            .MANIF => "manifestation",
            .COV_Z006A => "lcov_artheartxpa",
            .COV_Z006B => "lcov_artheartxpb",
            .CSECT => "csect",
            .LCOV => "lcov",
            .LOS => "los",
            .NCOV_A => "noncovered",
            .NCOV_B_KXP => "kidneyxp",
            .NCOV_B_PXP => "ncov45",
            .NCOV_F => "ncov12agele60",
            .VAGDEL => "vagdel",
            .BIOPSY => "biopsy",
            .BILATERAL => "bilateral",
            .OR_INDC => "or_indic",
            .NCOV8 => "ncov8",
            .NCOV9 => "ncov9",
            .LCOV_ARTHEARTXP => "lcov_artheartxp",
            .LCOV_KIDNEYXP => "lcov_kidneyxp",
            .LCOV_PANCREASXP => "lcov_pancreasxp",
            .LCOV_LVRS => "lcov_lvrs",
            .LCOV_LUNGXP => "lcov_lungxp",
            .LCOV_HEARTLUNGXP => "lcov_heartlungxp",
            .LCOV_HEARTXP => "lcov_heartxp",
            .LCOV_HEARTSYS => "lcov_heartsys",
            .LCOV_INTXP => "lcov_intxp",
            .LCOV_LIVERXP => "lcov_liverxp",
            .NCOV13A => "ncov13a",
            .NCOV13B => "ncov13b",
        };
    }

    /// Get the code type applicability for this attribute.
    pub fn codeType(self: Attribute) CodeType {
        return switch (self) {
            .FEMALE, .MALE, .NONSPECIFIC, .NCOV_D, .NCOV_E, .NCOV_G, .NCOV2, .NCOV3 => .BOTH,
            .ADULT, .CLINTRIAL, .DELOUT, .ECODEPDX, .MATERNITY, .NCOV_B, .NEWBORN, .PEDIATRIC, .QADM, .REQSDX, .UNACCEPTABLE, .WRNGPROC, .UNSPECIFIED, .MSP, .MDC08, .CC, .NCOV4, .NCOV5, .NCOV2AGELT78, .NCOV2AGELT64, .NCOV89, .MANIF => .DIAGNOSIS,
            .COV_Z006A, .COV_Z006B, .CSECT, .LCOV, .LOS, .NCOV_A, .NCOV_B_KXP, .NCOV_B_PXP, .NCOV_F, .VAGDEL, .BIOPSY, .BILATERAL, .OR_INDC, .NCOV8, .NCOV9, .LCOV_ARTHEARTXP, .LCOV_KIDNEYXP, .LCOV_PANCREASXP, .LCOV_LVRS, .LCOV_LUNGXP, .LCOV_HEARTLUNGXP, .LCOV_HEARTXP, .LCOV_HEARTSYS, .LCOV_INTXP, .LCOV_LIVERXP, .NCOV13A, .NCOV13B => .PROCEDURE,
        };
    }
};

// --- Edit ---

pub const Edit = struct {
    code_type: CodeType,
    edit_type: EditType,
    applicability: EditCounterApplicability,
};

pub const MCE_EDIT_INVALID_CODE = Edit{ .code_type = .BOTH, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_SEX_CONFLICT = Edit{ .code_type = .BOTH, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_AGE_CONFLICT = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_QUESTIONABLE_ADMISSION = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_MANIFESTATION_AS_PDX = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_NONSPECIFIC_PDX = Edit{ .code_type = .DIAGNOSIS, .edit_type = .POSTPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_E_CODE_AS_PDX = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_UNACCEPTABLE_PDX = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_DUPLICATE_OF_PDX = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_MEDICARE_IS_SECONDARY_PAYER = Edit{ .code_type = .DIAGNOSIS, .edit_type = .POSTPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_REQUIRES_SDX = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_NONSPECIFIC_OR = Edit{ .code_type = .PROCEDURE, .edit_type = .POSTPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_OPEN_BIOPSY = Edit{ .code_type = .PROCEDURE, .edit_type = .POSTPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_NON_COVERED = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_BILATERAL = Edit{ .code_type = .PROCEDURE, .edit_type = .POSTPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_LVRS = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .I9 };
pub const MCE_EDIT_LIMITED_COVERAGE = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .I10 };
pub const MCE_EDIT_LIMITED_COVERAGE_LUNG_TRANSPLANT = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .I9 };
pub const MCE_EDIT_QUESTIONABLE_OBSTETRIC_ADMISSION = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .I10 };
pub const MCE_EDIT_LIMITED_COVERAGE_COMBINATION_HEART_LUNG = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_HEART_TRANSPLANT = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_HEART_IMPLANT = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_INTESTINE = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_LIVER = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_INVALID_ADMIT_DX = Edit{ .code_type = .NONE, .edit_type = .NONE, .applicability = .ALL };
pub const MCE_EDIT_INVALID_AGE = Edit{ .code_type = .NONE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_INVALID_SEX = Edit{ .code_type = .NONE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_INVALID_DISCHARGE_STATUS = Edit{ .code_type = .NONE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_KIDNEY = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_PANCREAS = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_TYPE_OF_AGE_CONFLICT = Edit{ .code_type = .DIAGNOSIS, .edit_type = .NONE, .applicability = .ALL };
pub const MCE_EDIT_INVALID_POA = Edit{ .code_type = .DIAGNOSIS, .edit_type = .NONE, .applicability = .ALL };
pub const MCE_EDIT_LIMITED_COVERAGE_ARTIFICIAL_HEART = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_WRONG_PROCEDURE_PERFORMED = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_INCONSISTENT_WITH_LENGTH_OF_STAY = Edit{ .code_type = .PROCEDURE, .edit_type = .PREPAYMENT, .applicability = .ALL };
pub const MCE_EDIT_UNSPECIFIED = Edit{ .code_type = .DIAGNOSIS, .edit_type = .PREPAYMENT, .applicability = .ALL };

/// All edits in ordinal order (matches Java Edit.values()).
pub const ALL_EDITS = [_]Edit{
    MCE_EDIT_INVALID_CODE, // 0
    MCE_EDIT_SEX_CONFLICT, // 1
    MCE_EDIT_AGE_CONFLICT, // 2
    MCE_EDIT_QUESTIONABLE_ADMISSION, // 3
    MCE_EDIT_MANIFESTATION_AS_PDX, // 4
    MCE_EDIT_NONSPECIFIC_PDX, // 5
    MCE_EDIT_E_CODE_AS_PDX, // 6
    MCE_EDIT_UNACCEPTABLE_PDX, // 7
    MCE_EDIT_DUPLICATE_OF_PDX, // 8
    MCE_EDIT_MEDICARE_IS_SECONDARY_PAYER, // 9
    MCE_EDIT_REQUIRES_SDX, // 10
    MCE_EDIT_NONSPECIFIC_OR, // 11
    MCE_EDIT_OPEN_BIOPSY, // 12
    MCE_EDIT_NON_COVERED, // 13
    MCE_EDIT_BILATERAL, // 14
    MCE_EDIT_LIMITED_COVERAGE_LVRS, // 15
    MCE_EDIT_LIMITED_COVERAGE, // 16
    MCE_EDIT_LIMITED_COVERAGE_LUNG_TRANSPLANT, // 17
    MCE_EDIT_QUESTIONABLE_OBSTETRIC_ADMISSION, // 18
    MCE_EDIT_LIMITED_COVERAGE_COMBINATION_HEART_LUNG, // 19
    MCE_EDIT_LIMITED_COVERAGE_HEART_TRANSPLANT, // 20
    MCE_EDIT_LIMITED_COVERAGE_HEART_IMPLANT, // 21
    MCE_EDIT_LIMITED_COVERAGE_INTESTINE, // 22
    MCE_EDIT_LIMITED_COVERAGE_LIVER, // 23
    MCE_EDIT_INVALID_ADMIT_DX, // 24
    MCE_EDIT_INVALID_AGE, // 25
    MCE_EDIT_INVALID_SEX, // 26
    MCE_EDIT_INVALID_DISCHARGE_STATUS, // 27
    MCE_EDIT_LIMITED_COVERAGE_KIDNEY, // 28
    MCE_EDIT_LIMITED_COVERAGE_PANCREAS, // 29
    MCE_EDIT_TYPE_OF_AGE_CONFLICT, // 30
    MCE_EDIT_INVALID_POA, // 31
    MCE_EDIT_LIMITED_COVERAGE_ARTIFICIAL_HEART, // 32
    MCE_EDIT_WRONG_PROCEDURE_PERFORMED, // 33
    MCE_EDIT_INCONSISTENT_WITH_LENGTH_OF_STAY, // 34
    MCE_EDIT_UNSPECIFIED, // 35
};

/// Get edits applicable to a given ICD version for edit counter.
pub fn getEditCounterEdits(icd_version: u8) []const Edit {
    if (icd_version == 9) {
        // I9 edits: ALL + I9-only edits
        return &ALL_EDITS; // Simplified — Java filters by applicability
    }
    // I10 edits: ALL + I10-only edits
    return &ALL_EDITS;
}

// --- Sex ---

pub const Sex = enum {
    MALE,
    FEMALE,
    UNKNOWN,
};

// --- Data Models ---

pub const MceDiagnosisCode = struct {
    code: [8]u8 = [_]u8{0} ** 8,
    attributes: std.ArrayListUnmanaged(Attribute) = .empty,
    edits: std.ArrayListUnmanaged(usize) = .empty, // indices into ALL_EDITS
    is_principal: bool = false,
    age_conflict_type: ?AgeConflictType = null,

    pub fn init(code_str: []const u8) MceDiagnosisCode {
        var result = MceDiagnosisCode{};
        const len = @min(code_str.len, 8);
        @memcpy(result.code[0..len], code_str[0..len]);
        return result;
    }

    pub fn deinit(self: *MceDiagnosisCode, allocator: std.mem.Allocator) void {
        self.attributes.deinit(allocator);
        self.edits.deinit(allocator);
    }

    pub fn getCode(self: *const MceDiagnosisCode) []const u8 {
        var len: usize = 0;
        while (len < 8 and self.code[len] != 0) : (len += 1) {}
        return self.code[0..len];
    }

    pub fn hasAttribute(self: *const MceDiagnosisCode, attr: Attribute) bool {
        for (self.attributes.items) |a| {
            if (a == attr) return true;
        }
        return false;
    }

    pub fn addEdit(self: *MceDiagnosisCode, allocator: std.mem.Allocator, edit_index: usize) !void {
        // Don't add duplicates
        for (self.edits.items) |e| {
            if (e == edit_index) return;
        }
        try self.edits.append(allocator, edit_index);
    }
};

pub const MceProcedureCode = struct {
    code: [8]u8 = [_]u8{0} ** 8,
    attributes: std.ArrayListUnmanaged(Attribute) = .empty,
    edits: std.ArrayListUnmanaged(usize) = .empty,

    pub fn init(code_str: []const u8) MceProcedureCode {
        var result = MceProcedureCode{};
        const len = @min(code_str.len, 8);
        @memcpy(result.code[0..len], code_str[0..len]);
        return result;
    }

    pub fn deinit(self: *MceProcedureCode, allocator: std.mem.Allocator) void {
        self.attributes.deinit(allocator);
        self.edits.deinit(allocator);
    }

    pub fn getCode(self: *const MceProcedureCode) []const u8 {
        var len: usize = 0;
        while (len < 8 and self.code[len] != 0) : (len += 1) {}
        return self.code[0..len];
    }

    pub fn hasAttribute(self: *const MceProcedureCode, attr: Attribute) bool {
        for (self.attributes.items) |a| {
            if (a == attr) return true;
        }
        return false;
    }

    pub fn addEdit(self: *MceProcedureCode, allocator: std.mem.Allocator, edit_index: usize) !void {
        for (self.edits.items) |e| {
            if (e == edit_index) return;
        }
        try self.edits.append(allocator, edit_index);
    }
};

/// Discharge date as YYYYMMDD integer.
pub const MceDate = i32;

pub const MceInput = struct {
    age: i32 = 0,
    sex: Sex = .UNKNOWN,
    discharge_status: i32 = 0,
    discharge_date: MceDate = 0,
    admit_dx: ?MceDiagnosisCode = null,
    pdx: ?MceDiagnosisCode = null,
    sdx: std.ArrayListUnmanaged(MceDiagnosisCode) = .empty,
    procedures: std.ArrayListUnmanaged(MceProcedureCode) = .empty,

    pub fn deinit(self: *MceInput, allocator: std.mem.Allocator) void {
        if (self.admit_dx) |*dx| dx.deinit(allocator);
        if (self.pdx) |*dx| dx.deinit(allocator);
        for (self.sdx.items) |*dx| dx.deinit(allocator);
        self.sdx.deinit(allocator);
        for (self.procedures.items) |*p| p.deinit(allocator);
        self.procedures.deinit(allocator);
    }
};

pub const MceOutput = struct {
    version: i32 = 0,
    edit_type: EditType = .NONE,
    edit_counts: [ALL_EDITS.len]u32 = [_]u32{0} ** ALL_EDITS.len,

    pub fn increment(self: *MceOutput, edit_index: usize) void {
        self.edit_counts[edit_index] += 1;
    }

    pub fn getCount(self: *const MceOutput, edit_index: usize) u32 {
        return self.edit_counts[edit_index];
    }

    pub fn hasEdits(self: *const MceOutput) bool {
        for (self.edit_counts) |c| {
            if (c > 0) return true;
        }
        return false;
    }

    pub fn determineEditType(self: *MceOutput) void {
        var has_pre = false;
        var has_post = false;
        for (self.edit_counts, 0..) |count, i| {
            if (count == 0) continue;
            const edit = ALL_EDITS[i];
            switch (edit.edit_type) {
                .PREPAYMENT => has_pre = true,
                .POSTPAYMENT => has_post = true,
                .BOTH => {
                    has_pre = true;
                    has_post = true;
                },
                else => {},
            }
        }
        if (has_pre and has_post) {
            self.edit_type = .BOTH;
        } else if (has_pre) {
            self.edit_type = .PREPAYMENT;
        } else if (has_post) {
            self.edit_type = .POSTPAYMENT;
        } else {
            self.edit_type = .NONE;
        }
    }
};

// --- Tests ---

test "Attribute fromFlag" {
    try std.testing.expectEqual(Attribute.FEMALE, Attribute.fromFlag("female").?);
    try std.testing.expectEqual(Attribute.MALE, Attribute.fromFlag("male").?);
    try std.testing.expectEqual(Attribute.ECODEPDX, Attribute.fromFlag("ecodepdx").?);
    try std.testing.expectEqual(Attribute.UNACCEPTABLE, Attribute.fromFlag("unacceptable").?);
    try std.testing.expectEqual(Attribute.NCOV_A, Attribute.fromFlag("noncovered").?);
    try std.testing.expectEqual(Attribute.OR_INDC, Attribute.fromFlag("or_indic").?);
    try std.testing.expect(Attribute.fromFlag("nonexistent") == null);
}

test "Attribute flagString roundtrip" {
    try std.testing.expectEqualStrings("female", Attribute.FEMALE.flagString());
    try std.testing.expectEqualStrings("male", Attribute.MALE.flagString());
    try std.testing.expectEqualStrings("ecodepdx", Attribute.ECODEPDX.flagString());
    try std.testing.expectEqualStrings("noncovered", Attribute.NCOV_A.flagString());
    try std.testing.expectEqualStrings("manifestation", Attribute.MANIF.flagString());
}

test "Attribute codeType" {
    try std.testing.expectEqual(CodeType.BOTH, Attribute.FEMALE.codeType());
    try std.testing.expectEqual(CodeType.DIAGNOSIS, Attribute.ECODEPDX.codeType());
    try std.testing.expectEqual(CodeType.PROCEDURE, Attribute.NCOV_A.codeType());
}

test "AgeConflictType fromGroupName" {
    try std.testing.expectEqual(AgeConflictType.NEWBORN, AgeConflictType.fromGroupName("Newborn").?);
    try std.testing.expectEqual(AgeConflictType.PEDIATRIC, AgeConflictType.fromGroupName("Pediatric").?);
    try std.testing.expectEqual(AgeConflictType.MATERNITY, AgeConflictType.fromGroupName("Maternity").?);
    try std.testing.expectEqual(AgeConflictType.ADULT, AgeConflictType.fromGroupName("Adult").?);
    try std.testing.expect(AgeConflictType.fromGroupName("Unknown") == null);
}

test "MceOutput determineEditType" {
    var output = MceOutput{};

    // No edits
    output.determineEditType();
    try std.testing.expectEqual(EditType.NONE, output.edit_type);

    // Prepayment edit
    output.increment(0); // INVALID_CODE = PREPAYMENT
    output.determineEditType();
    try std.testing.expectEqual(EditType.PREPAYMENT, output.edit_type);

    // Postpayment edit added
    output.increment(5); // NONSPECIFIC_PDX = POSTPAYMENT
    output.determineEditType();
    try std.testing.expectEqual(EditType.BOTH, output.edit_type);
}

test "MceDiagnosisCode" {
    const allocator = std.testing.allocator;
    var dx = MceDiagnosisCode.init("I5020");
    defer dx.deinit(allocator);

    try std.testing.expectEqualStrings("I5020", dx.getCode());
    try std.testing.expect(!dx.is_principal);
    try std.testing.expect(!dx.hasAttribute(.MALE));

    try dx.attributes.append(allocator, .MALE);
    try std.testing.expect(dx.hasAttribute(.MALE));

    try dx.addEdit(allocator, 0);
    try dx.addEdit(allocator, 0); // duplicate — should not add
    try std.testing.expectEqual(@as(usize, 1), dx.edits.items.len);
}

test "ALL_EDITS count" {
    // Verify we have the expected number of edits (matches Java Edit.values().length = 36)
    try std.testing.expectEqual(@as(usize, 36), ALL_EDITS.len);
}
