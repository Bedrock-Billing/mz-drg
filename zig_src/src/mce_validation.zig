const std = @import("std");
const mce_data = @import("mce_data.zig");
const mce_enums = @import("mce_enums.zig");

// --- Constants ---

pub const VALID_DATE_BEGIN: i32 = 19851001;
pub const SEX_UNKNOWN: i32 = 0;
pub const SEX_MALE: i32 = 1;
pub const SEX_FEMALE: i32 = 2;
pub const MIN_AGE: i32 = 0;
pub const MAX_AGE: i32 = 124;
pub const DISCHARGE_STATUS_DIED: i32 = 20;

/// After this date, UNKNOWN sex is accepted (CMS policy change).
pub const SEX_UNKNOWN_VALID_DATE: i32 = 20241001;

// --- Date Utilities ---

pub fn dateToYmd(date: i32) struct { year: i32, month: i32, day: i32 } {
    const y = @divTrunc(date, 10000);
    const m = @divTrunc(@mod(date, 10000), 100);
    const d = @mod(date, 100);
    return .{ .year = y, .month = m, .day = d };
}

pub fn isValidDischargeDate(date: i32, termination_date: i32) bool {
    return date >= VALID_DATE_BEGIN and date <= termination_date;
}

// --- Validation Functions ---

pub fn validateCode(
    code: []const u8,
    master: *const mce_data.CodeMasterData,
    date: i32,
) bool {
    if (code.len == 0) return true;
    var all_zeros = true;
    for (code) |c| {
        if (c != '0') {
            all_zeros = false;
            break;
        }
    }
    if (all_zeros) return true;

    var buf: [1]?*const mce_data.CodeMasterEntry = .{null};
    return master.lookupActive(code, date, &buf) > 0;
}

pub fn validateSex(sex: i32, date: i32) bool {
    if (date >= SEX_UNKNOWN_VALID_DATE) {
        return sex == SEX_UNKNOWN or sex == SEX_MALE or sex == SEX_FEMALE;
    }
    return sex == SEX_MALE or sex == SEX_FEMALE;
}

pub fn validateDischargeStatus(
    status: i32,
    discharge_status_data: *const mce_data.DischargeStatusData,
    date: i32,
) bool {
    return discharge_status_data.isValid(status, date);
}

pub fn validateAge(age: i32) bool {
    return age >= MIN_AGE and age <= MAX_AGE;
}

// --- Attribute Loading ---

pub fn loadAttributes(
    master: *const mce_data.CodeMasterData,
    code: []const u8,
    date: i32,
    result: []mce_enums.Attribute,
) usize {
    var buf: [1]?*const mce_data.CodeMasterEntry = .{null};
    if (master.lookupActive(code, date, &buf) == 0) return 0;
    const entry = buf[0].?;

    var iter = mce_data.FlagIterator.init(entry, master.getStringBlock());
    var count: usize = 0;
    while (iter.next()) |flag| {
        if (count >= result.len) break;
        if (mce_enums.Attribute.fromFlag(flag)) |attr| {
            result[count] = attr;
            count += 1;
        }
    }
    return count;
}

pub fn hasAttribute(
    master: *const mce_data.CodeMasterData,
    code: []const u8,
    attr: mce_enums.Attribute,
    date: i32,
) bool {
    return master.hasFlag(code, attr.flagString(), date);
}

// --- Tests ---

test "dateToYmd" {
    const d = dateToYmd(20250730);
    try std.testing.expectEqual(@as(i32, 2025), d.year);
    try std.testing.expectEqual(@as(i32, 7), d.month);
    try std.testing.expectEqual(@as(i32, 30), d.day);
}

test "isValidDischargeDate" {
    try std.testing.expect(isValidDischargeDate(20250101, 20260930));
    try std.testing.expect(isValidDischargeDate(19851001, 20260930));
    try std.testing.expect(isValidDischargeDate(20260930, 20260930));
    try std.testing.expect(!isValidDischargeDate(19850930, 20260930));
    try std.testing.expect(!isValidDischargeDate(20261001, 20260930));
    try std.testing.expect(!isValidDischargeDate(0, 20260930));
}

test "validateSex" {
    try std.testing.expect(validateSex(1, 20240930));
    try std.testing.expect(validateSex(2, 20240930));
    try std.testing.expect(!validateSex(0, 20240930));
    try std.testing.expect(validateSex(0, 20241001));
    try std.testing.expect(validateSex(1, 20241001));
    try std.testing.expect(validateSex(2, 20241001));
    try std.testing.expect(!validateSex(3, 20241001));
}

test "validateAge" {
    try std.testing.expect(validateAge(0));
    try std.testing.expect(validateAge(65));
    try std.testing.expect(validateAge(124));
    try std.testing.expect(!validateAge(-1));
    try std.testing.expect(!validateAge(125));
}

test "validateCode real file" {
    const data_dir = "../data/bin/";
    var dx_data = mce_data.CodeMasterData.init(data_dir ++ "mce_i10dx_master.bin") catch return;
    defer dx_data.deinit();

    // Empty code is "valid"
    try std.testing.expect(validateCode("", &dx_data, 20250101));

    // All zeros is "valid"
    try std.testing.expect(validateCode("0000", &dx_data, 20250101));

    // Real code is valid
    try std.testing.expect(validateCode("I5020", &dx_data, 20250101));

    // Fake codes are not valid
    try std.testing.expect(!validateCode("ZZZZZ", &dx_data, 20250101));
    try std.testing.expect(!validateCode("ZZZZZZZ", &dx_data, 20250101));
    try std.testing.expect(!validateCode("Z@4481", &dx_data, 20250101));

    // Verify with SG master too
    var sg_data = mce_data.CodeMasterData.init(data_dir ++ "mce_i10sg_master.bin") catch return;
    defer sg_data.deinit();
    try std.testing.expect(!validateCode("ZZZZZZZ", &sg_data, 20250101));
    try std.testing.expect(!validateCode("Z@4481", &sg_data, 20250101));
}

test "loadAttributes real file" {
    const data_dir = "../data/bin/";
    var dx_data = mce_data.CodeMasterData.init(data_dir ++ "mce_i10dx_master.bin") catch return;
    defer dx_data.deinit();

    var result: [10]mce_enums.Attribute = undefined;
    const count = loadAttributes(&dx_data, "Z9989", 20250101, &result);
    try std.testing.expect(count >= 1);

    var found_unacceptable = false;
    for (result[0..count]) |attr| {
        if (attr == .UNACCEPTABLE) found_unacceptable = true;
    }
    try std.testing.expect(found_unacceptable);

    const count2 = loadAttributes(&dx_data, "A000", 20250101, &result);
    try std.testing.expectEqual(@as(usize, 0), count2);
}

test "validateDischargeStatus real file" {
    const data_dir = "../data/bin/";
    var ds_data = mce_data.DischargeStatusData.init(data_dir ++ "mce_discharge_status.bin") catch return;
    defer ds_data.deinit();

    try std.testing.expect(validateDischargeStatus(1, &ds_data, 20250101));
    try std.testing.expect(validateDischargeStatus(20, &ds_data, 20250101));
    try std.testing.expect(!validateDischargeStatus(99, &ds_data, 20250101));
}
