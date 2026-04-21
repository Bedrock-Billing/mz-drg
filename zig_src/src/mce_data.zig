const std = @import("std");
const common = @import("common.zig");

// --- Constants ---

pub const CODE_MASTER_MAGIC: u32 = 0x4D434544; // "MCED"
pub const AGE_RANGE_MAGIC: u32 = 0x4D434147; // "MCAG"
pub const DISCHARGE_MAGIC: u32 = 0x4D434453; // "MCDS"

pub const ONGOING_DATE: i32 = 99991231;
pub const VALID_DATE_BEGIN: i32 = 19851001;

// --- Code Master Table ---

pub const CodeMasterHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    strings_offset: u32,
    termination_date: i32,
    _pad: [12]u8 = [_]u8{0} ** 12,
};

pub const CodeMasterEntry = extern struct {
    code: [8]u8,
    date_start: i32,
    date_end: i32,
    flags_offset: u32,
    flags_count: u16,
    _pad: [2]u8 = [_]u8{0} ** 2,

    pub fn getCode(self: *align(1) const CodeMasterEntry) []const u8 {
        var len: usize = 0;
        while (len < 8 and self.code[len] != 0) : (len += 1) {}
        return self.code[0..len];
    }

    /// Check if a date falls within this entry's valid range.
    pub fn isActive(self: *align(1) const CodeMasterEntry, date: i32) bool {
        return date >= self.date_start and date <= self.date_end;
    }

    /// Get the flags as a slice of null-terminated strings from the string block.
    pub fn getFlags(self: *const CodeMasterEntry, strings_base: [*]const u8) []const []const u8 {
        // flags are stored as sequential null-terminated strings
        // We can't return a stable slice without allocating, so we return
        // a pointer + count that the caller must iterate
        _ = self;
        _ = strings_base;
        @compileError("Use getFlagIterator instead");
    }
};

/// Iterates over flags in a CodeMasterEntry without allocation.
pub const FlagIterator = struct {
    strings_base: [*]const u8,
    offset: usize,
    remaining: u16,

    pub fn init(entry: *align(1) const CodeMasterEntry, strings_base: [*]const u8) FlagIterator {
        return FlagIterator{
            .strings_base = strings_base,
            .offset = entry.flags_offset,
            .remaining = entry.flags_count,
        };
    }

    pub fn next(self: *FlagIterator) ?[]const u8 {
        if (self.remaining == 0) return null;
        const start = self.offset;
        // Find null terminator
        var end = start;
        while (self.strings_base[end] != 0) : (end += 1) {}
        self.offset = end + 1;
        self.remaining -= 1;
        return self.strings_base[start..end];
    }
};

pub const CodeMasterData = struct {
    mapped: common.MappedFile(CodeMasterHeader),

    pub fn init(path: []const u8) !CodeMasterData {
        const mapped = try common.MappedFile(CodeMasterHeader).init(path, CODE_MASTER_MAGIC);
        return CodeMasterData{ .mapped = mapped };
    }

    pub fn initWithData(data: []const u8) !CodeMasterData {
        const mapped = try common.MappedFile(CodeMasterHeader).initWithData(data, CODE_MASTER_MAGIC);
        return CodeMasterData{ .mapped = mapped };
    }

    pub fn deinit(self: *CodeMasterData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const CodeMasterData) ![]align(1) const CodeMasterEntry {
        return try self.mapped.getSlice(CodeMasterEntry, self.mapped.header.entries_offset, self.mapped.header.num_entries);
    }

    pub fn getStringBlock(self: *const CodeMasterData) [*]const u8 {
        return self.mapped.base_ptr() + self.mapped.header.strings_offset;
    }

    pub fn flagIterator(self: *const CodeMasterData, entry: *align(1) const CodeMasterEntry) FlagIterator {
        return FlagIterator.init(entry, self.getStringBlock());
    }

    /// Binary search for a code. Returns the first matching entry or null.
    /// Multiple entries may exist for the same code with different date ranges.
    pub fn lookup(self: *const CodeMasterData, code: []const u8) !?*align(1) const CodeMasterEntry {
        const entries = try self.getEntries();
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry_code = entries[mid].getCode();
            const order = std.mem.order(u8, entry_code, code);

            switch (order) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => {
                    // Scan backwards to find first entry with this code
                    var first = mid;
                    while (first > 0) {
                        if (!std.mem.eql(u8, entries[first - 1].getCode(), code)) break;
                        first -= 1;
                    }
                    return &entries[first];
                },
            }
        }
        return null;
    }

    /// Find all entries for a given code that are active on the given date.
    /// Returns a slice of entries (up to `max_results`).
    pub fn lookupActive(self: *const CodeMasterData, code: []const u8, date: i32, results: []?*align(1) const CodeMasterEntry) !usize {
        const entries = try self.getEntries();

        // Find first entry with this code
        var left: usize = 0;
        var right: usize = entries.len;
        var first: ?usize = null;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry_code = entries[mid].getCode();
            const order = std.mem.order(u8, entry_code, code);

            switch (order) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => {
                    // Scan backwards
                    var f = mid;
                    while (f > 0) {
                        if (!std.mem.eql(u8, entries[f - 1].getCode(), code)) break;
                        f -= 1;
                    }
                    first = f;
                    break;
                },
            }
        }

        if (first == null) return 0;

        // Scan forward collecting active entries
        var count: usize = 0;
        var i = first.?;
        while (i < entries.len and count < results.len) : (i += 1) {
            if (!std.mem.eql(u8, entries[i].getCode(), code)) break;
            if (entries[i].isActive(date)) {
                results[count] = &entries[i];
                count += 1;
            }
        }
        return count;
    }

    /// Check if a code exists in the table (any date range).
    pub fn hasCode(self: *const CodeMasterData, code: []const u8) !bool {
        return try self.lookup(code) != null;
    }

    /// Check if a code has a specific flag active on a given date.
    pub fn hasFlag(self: *const CodeMasterData, code: []const u8, flag: []const u8, date: i32) !bool {
        var buf: [4]?*align(1) const CodeMasterEntry = .{ null, null, null, null };
        const count = try self.lookupActive(code, date, &buf);

        const strings = self.getStringBlock();
        for (0..count) |i| {
            if (buf[i]) |entry| {
                var iter = FlagIterator.init(entry, strings);
                while (iter.next()) |f| {
                    if (std.mem.eql(u8, f, flag)) return true;
                }
            }
        }
        return false;
    }
};

// --- Age Range Table ---

pub const AgeRangeHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    strings_offset: u32,
    _pad: [16]u8 = [_]u8{0} ** 16,
};

pub const AgeRangeEntry = extern struct {
    age_group_offset: u32,
    age_group_len: u32,
    start_age: i32,
    end_age: i32,
    date_start: i32,
    date_end: i32,

    pub fn getAgeGroup(self: *const AgeRangeEntry, strings_base: [*]const u8) []const u8 {
        return strings_base[self.age_group_offset .. self.age_group_offset + self.age_group_len];
    }

    pub fn isActive(self: *const AgeRangeEntry, date: i32) bool {
        return date >= self.date_start and date <= self.date_end;
    }

    pub fn containsAge(self: *const AgeRangeEntry, age: i32) bool {
        return age >= self.start_age and age <= self.end_age;
    }
};

pub const AgeRangeData = struct {
    mapped: common.MappedFile(AgeRangeHeader),

    pub fn init(path: []const u8) !AgeRangeData {
        const mapped = try common.MappedFile(AgeRangeHeader).init(path, AGE_RANGE_MAGIC);
        return AgeRangeData{ .mapped = mapped };
    }

    pub fn initWithData(data: []const u8) !AgeRangeData {
        const mapped = try common.MappedFile(AgeRangeHeader).initWithData(data, AGE_RANGE_MAGIC);
        return AgeRangeData{ .mapped = mapped };
    }

    pub fn deinit(self: *AgeRangeData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const AgeRangeData) ![]align(1) const AgeRangeEntry {
        return try self.mapped.getSlice(AgeRangeEntry, self.mapped.header.entries_offset, self.mapped.header.num_entries);
    }

    pub fn getStringBlock(self: *const AgeRangeData) [*]const u8 {
        return self.mapped.base_ptr() + self.mapped.header.strings_offset;
    }

    /// Check if an age is within a named age group for a given date.
    pub fn isAgeInGroup(self: *const AgeRangeData, age: i32, group: []const u8, date: i32) !bool {
        const entries = try self.getEntries();
        const strings = self.getStringBlock();

        for (entries) |entry| {
            if (!entry.isActive(date)) continue;
            const entry_group = entry.getAgeGroup(strings);
            if (std.mem.eql(u8, entry_group, group) and entry.containsAge(age)) {
                return true;
            }
        }
        return false;
    }

    /// Get all age groups that contain the given age on the given date.
    pub fn getMatchingGroups(self: *const AgeRangeData, age: i32, date: i32, results: [][]const u8) !usize {
        const entries = try self.getEntries();
        const strings = self.getStringBlock();
        var count: usize = 0;

        for (entries) |entry| {
            if (!entry.isActive(date)) continue;
            if (!entry.containsAge(age)) continue;
            if (count >= results.len) break;
            results[count] = entry.getAgeGroup(strings);
            count += 1;
        }
        return count;
    }
};

// --- Discharge Status Table ---

pub const DischargeStatusHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    _pad: [20]u8 = [_]u8{0} ** 20,
};

pub const DischargeStatusEntry = extern struct {
    code: i32,
    date_start: i32,
    date_end: i32,

    pub fn isActive(self: *align(1) const DischargeStatusEntry, date: i32) bool {
        return date >= self.date_start and date <= self.date_end;
    }
};

pub const DischargeStatusData = struct {
    mapped: common.MappedFile(DischargeStatusHeader),

    pub fn init(path: []const u8) !DischargeStatusData {
        const mapped = try common.MappedFile(DischargeStatusHeader).init(path, DISCHARGE_MAGIC);
        return DischargeStatusData{ .mapped = mapped };
    }

    pub fn initWithData(data: []const u8) !DischargeStatusData {
        const mapped = try common.MappedFile(DischargeStatusHeader).initWithData(data, DISCHARGE_MAGIC);
        return DischargeStatusData{ .mapped = mapped };
    }

    pub fn deinit(self: *DischargeStatusData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const DischargeStatusData) ![]align(1) const DischargeStatusEntry {
        return try self.mapped.getSlice(DischargeStatusEntry, self.mapped.header.entries_offset, self.mapped.header.num_entries);
    }

    /// Check if a discharge status code is valid for a given date.
    pub fn isValid(self: *const DischargeStatusData, code: i32, date: i32) !bool {
        const entries = try self.getEntries();

        // Binary search (entries are sorted by code)
        var left: usize = 0;
        var right: usize = entries.len;
        while (left < right) {
            const mid = left + (right - left) / 2;
            if (entries[mid].code < code) {
                left = mid + 1;
            } else if (entries[mid].code > code) {
                right = mid;
            } else {
                return entries[mid].isActive(date);
            }
        }
        return false;
    }
};

// --- Tests ---

test "CodeMasterEntry code extraction" {
    var entry = CodeMasterEntry{
        .code = [_]u8{ 'A', '0', '0', '1', 0, 0, 0, 0 },
        .date_start = 20151001,
        .date_end = 20260930,
        .flags_offset = 0,
        .flags_count = 0,
    };
    try std.testing.expectEqualStrings("A001", entry.getCode());

    // Test empty code
    entry.code = [_]u8{0} ** 8;
    try std.testing.expectEqualStrings("", entry.getCode());
}

test "CodeMasterEntry isActive" {
    const entry = CodeMasterEntry{
        .code = [_]u8{ 'A', '0', '0', '1', 0, 0, 0, 0 },
        .date_start = 20151001,
        .date_end = 20260930,
        .flags_offset = 0,
        .flags_count = 0,
    };
    try std.testing.expect(entry.isActive(20200101));
    try std.testing.expect(entry.isActive(20151001)); // boundary
    try std.testing.expect(entry.isActive(20260930)); // boundary
    try std.testing.expect(!entry.isActive(20150930)); // before
    try std.testing.expect(!entry.isActive(20261001)); // after
}

test "AgeRangeEntry containsAge" {
    const entry = AgeRangeEntry{
        .age_group_offset = 0,
        .age_group_len = 5,
        .start_age = 0,
        .end_age = 17,
        .date_start = 19840301,
        .date_end = ONGOING_DATE,
    };
    try std.testing.expect(entry.containsAge(0));
    try std.testing.expect(entry.containsAge(10));
    try std.testing.expect(entry.containsAge(17));
    try std.testing.expect(!entry.containsAge(18));
    try std.testing.expect(!entry.containsAge(-1));
}

test "FlagIterator" {
    // Create a mock string block: "male\0female\0"
    const string_data = "male\x00female\x00";
    const entry = CodeMasterEntry{
        .code = [_]u8{ 'A', '0', '0', '1', 0, 0, 0, 0 },
        .date_start = 20151001,
        .date_end = ONGOING_DATE,
        .flags_offset = 0,
        .flags_count = 2,
    };

    var iter = FlagIterator.init(&entry, @as([*]const u8, @ptrCast(string_data)));
    const f1 = iter.next().?;
    try std.testing.expectEqualStrings("male", f1);
    const f2 = iter.next().?;
    try std.testing.expectEqualStrings("female", f2);
    try std.testing.expect(iter.next() == null);
}

test "CodeMasterData real file lookup" {
    const data_dir = "../data/bin/";
    const i10dx_path = data_dir ++ "mce_i10dx_master.bin";

    var dx_data = CodeMasterData.init(i10dx_path) catch |err| {
        std.debug.print("Skipping: could not load {s}: {}\n", .{ i10dx_path, err });
        return;
    };
    defer dx_data.deinit();

    // Verify header
    try std.testing.expectEqual(CODE_MASTER_MAGIC, dx_data.mapped.header.magic);
    try std.testing.expect(dx_data.mapped.header.num_entries > 80000);

    // Lookup code I5020 (Heart Failure)
    const entry = (try dx_data.lookup("I5020")).?;
    try std.testing.expectEqualStrings("I5020", entry.getCode());
    try std.testing.expect(entry.isActive(20250101));

    // Lookup nonexistent code
    try std.testing.expect(try dx_data.lookup("ZZZZZ") == null);

    // Check flag on a code with flags (Z9989 has "unacceptable")
    const z_entry = (try dx_data.lookup("Z9989")).?;
    try std.testing.expectEqualStrings("Z9989", z_entry.getCode());
    try std.testing.expectEqual(@as(u16, 1), z_entry.flags_count);

    var z_iter = dx_data.flagIterator(z_entry);
    const z_flag = z_iter.next().?;
    try std.testing.expectEqualStrings("unacceptable", z_flag);

    try std.testing.expect(try dx_data.hasFlag("Z9989", "unacceptable", 20250101));
    try std.testing.expect(!try dx_data.hasFlag("Z9989", "male", 20250101));

    // A000 has no flags
    try std.testing.expect(!try dx_data.hasFlag("A000", "male", 20250101));
}

test "AgeRangeData real file" {
    const data_dir = "../data/bin/";
    const age_path = data_dir ++ "mce_age_ranges.bin";

    var age_data = AgeRangeData.init(age_path) catch |err| {
        std.debug.print("Skipping: could not load {s}: {}\n", .{ age_path, err });
        return;
    };
    defer age_data.deinit();

    try std.testing.expectEqual(AGE_RANGE_MAGIC, age_data.mapped.header.magic);
    try std.testing.expectEqual(@as(u32, 5), age_data.mapped.header.num_entries);

    // Age 0 is newborn and pediatric
    try std.testing.expect(try age_data.isAgeInGroup(0, "Newborn", 20250101));
    try std.testing.expect(try age_data.isAgeInGroup(0, "Pediatric", 20250101));
    try std.testing.expect(!try age_data.isAgeInGroup(0, "Adult", 20250101));

    // Age 30 is adult only
    try std.testing.expect(try age_data.isAgeInGroup(30, "Adult", 20250101));
    try std.testing.expect(!try age_data.isAgeInGroup(30, "Pediatric", 20250101));
    try std.testing.expect(!try age_data.isAgeInGroup(30, "Newborn", 20250101));

    // Age 25 is adult and maternity
    try std.testing.expect(try age_data.isAgeInGroup(25, "Adult", 20250101));
    try std.testing.expect(try age_data.isAgeInGroup(25, "Maternity", 20250101));
}

test "DischargeStatusData real file" {
    const data_dir = "../data/bin/";
    const ds_path = data_dir ++ "mce_discharge_status.bin";

    var ds_data = DischargeStatusData.init(ds_path) catch |err| {
        std.debug.print("Skipping: could not load {s}: {}\n", .{ ds_path, err });
        return;
    };
    defer ds_data.deinit();

    try std.testing.expectEqual(DISCHARGE_MAGIC, ds_data.mapped.header.magic);
    try std.testing.expectEqual(@as(u32, 45), ds_data.mapped.header.num_entries);

    // Valid codes
    try std.testing.expect(try ds_data.isValid(1, 20250101)); // Home/Self Care
    try std.testing.expect(try ds_data.isValid(20, 20250101)); // Died
    try std.testing.expect(try ds_data.isValid(30, 20250101)); // Still a Patient

    // Invalid codes
    try std.testing.expect(!try ds_data.isValid(99, 20250101));
    try std.testing.expect(!try ds_data.isValid(0, 20250101));
    try std.testing.expect(!try ds_data.isValid(-1, 20250101));
}
