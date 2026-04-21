const std = @import("std");
const common = @import("common.zig");

pub const DescriptionHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    strings_offset: u32,
};

pub const DescriptionEntry = extern struct {
    id: u16,
    _pad: u16,
    version_start: i32,
    version_end: i32,
    desc_offset: u32,
    desc_len: u32,

    pub fn getDescription(self: *const DescriptionEntry, base: [*]const u8) []const u8 {
        return base[self.desc_offset .. self.desc_offset + self.desc_len];
    }
};

pub const DescriptionData = struct {
    mapped: common.MappedFile(DescriptionHeader),

    pub fn init(path: []const u8, magic: u32) !DescriptionData {
        const mapped = try common.MappedFile(DescriptionHeader).init(path, magic);
        return DescriptionData{ .mapped = mapped };
    }

    pub fn initWithData(data: []const u8, magic: u32) !DescriptionData {
        const mapped = try common.MappedFile(DescriptionHeader).initWithData(data, magic);
        return DescriptionData{ .mapped = mapped };
    }

    pub fn deinit(self: *DescriptionData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const DescriptionData) ![]align(1) const DescriptionEntry {
        return try self.mapped.getSlice(DescriptionEntry, self.mapped.header.entries_offset, self.mapped.header.num_entries);
    }

    pub fn getEntry(self: *const DescriptionData, id: u16, version: i32) !?DescriptionEntry {
        const entries = try self.getEntries();
        const Adapter = common.search.intKey(DescriptionEntry, u16, "id");
        return common.search.versionedBinarySearch(DescriptionEntry, u16, Adapter.getKey, Adapter.compare, Adapter.equal, entries, id, version);
    }
};

test "DescriptionData lookup" {
    const filename = "test_description.bin";
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

    // Header: magic(4), num(4), entries_off(4), strings_off(4)
    try writeU32(file, 0x42445247);
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

    var data = try DescriptionData.init(filename, 0x42445247);
    defer data.deinit();

    const d1 = try data.getEntry(1, 405);
    try std.testing.expect(d1 != null);
    try std.testing.expectEqual(@as(u16, 1), d1.?.id);

    const d2 = try data.getEntry(2, 420);
    try std.testing.expect(d2 != null);
    try std.testing.expectEqual(@as(u16, 2), d2.?.id);

    const d3 = try data.getEntry(1, 420); // Version mismatch
    try std.testing.expect(d3 == null);
}
