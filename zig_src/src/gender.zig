const std = @import("std");
const common = @import("common.zig");

pub const GenderMdcHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
};

pub const GenderMdcEntry = extern struct {
    code: common.Code,
    version_start: i32,
    version_end: i32,
    male_mdc: i32,
    female_mdc: i32,
};

pub const GenderMdcData = struct {
    mapped: common.MappedFile(GenderMdcHeader),

    pub fn init(path: []const u8) !GenderMdcData {
        const mapped = try common.MappedFile(GenderMdcHeader).init(path, 0x47454E44);
        return GenderMdcData{ .mapped = mapped };
    }

    pub fn initWithData(data: []const u8) !GenderMdcData {
        const mapped = try common.MappedFile(GenderMdcHeader).initWithData(data, 0x47454E44);
        return GenderMdcData{ .mapped = mapped };
    }

    pub fn deinit(self: *GenderMdcData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const GenderMdcData) ![]align(1) const GenderMdcEntry {
        return try self.mapped.getSlice(GenderMdcEntry, self.mapped.header.entries_offset, self.mapped.header.num_entries);
    }

    pub fn getEntry(self: *const GenderMdcData, code: []const u8, version: i32) !?GenderMdcEntry {
        const entries = try self.getEntries();

        const Adapter = common.search.codeKey(GenderMdcEntry);
        return common.search.versionedBinarySearch(GenderMdcEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, entries, code, version);
    }
};

test "GenderMdcData lookup" {
    const filename = "test_gender.bin";
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

    const writeEntry = struct {
        fn call(f: std.Io.File, code: []const u8, v_start: i32, v_end: i32, male: i32, female: i32) !void {
            var code_buf: [8]u8 = [_]u8{0} ** 8;
            @memcpy(code_buf[0..code.len], code);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &code_buf);

            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v_start, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, v_end, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, male, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, female, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Header: magic(4), num_entries(4), entries_offset(4)
    try writeU32(file, 0x47454E44);
    try writeU32(file, 3); // 3 entries
    try writeU32(file, 12); // entries offset (header size)

    // Entries (Sorted by code)
    // A001, v400-410
    try writeEntry(file, "A001", 400, 410, 1, 2);
    // A001, v411-430
    try writeEntry(file, "A001", 411, 430, 3, 4);
    // B002, v400-430
    try writeEntry(file, "B002", 400, 430, 5, 6);

    var data = try GenderMdcData.init(filename);
    defer data.deinit();

    // Test lookup
    const e1 = try data.getEntry("A001", 405);
    try std.testing.expect(e1 != null);
    try std.testing.expectEqual(@as(i32, 1), e1.?.male_mdc);
    try std.testing.expectEqual(@as(i32, 2), e1.?.female_mdc);

    const e2 = try data.getEntry("A001", 420);
    try std.testing.expect(e2 != null);
    try std.testing.expectEqual(@as(i32, 3), e2.?.male_mdc);

    const e3 = try data.getEntry("B002", 400);
    try std.testing.expect(e3 != null);
    try std.testing.expectEqual(@as(i32, 5), e3.?.male_mdc);

    const e4 = try data.getEntry("C999", 400);
    try std.testing.expect(e4 == null);

    const e5 = try data.getEntry("A001", 399); // Version mismatch
    try std.testing.expect(e5 == null);
}
