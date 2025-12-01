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

    pub fn deinit(self: *DescriptionData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const DescriptionData) []const DescriptionEntry {
        const entries_ptr = @as([*]const DescriptionEntry, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getEntry(self: *const DescriptionData, id: u16, version: i32) ?DescriptionEntry {
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

test "DescriptionData lookup" {
    const filename = "test_description.bin";
    const file = try std.fs.cwd().createFile(filename, .{ .read = true });
    defer {
        file.close();
        std.fs.cwd().deleteFile(filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.fs.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try f.writeAll(&b);
        }
    }.call;

    const writeU16 = struct {
        fn call(f: std.fs.File, v: u16) !void {
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, v, .little);
            try f.writeAll(&b);
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
    try file.writeAll("Desc1");
    try file.writeAll("Desc2");

    var data = try DescriptionData.init(filename, 0x42445247);
    defer data.deinit();

    const d1 = data.getEntry(1, 405);
    try std.testing.expect(d1 != null);
    try std.testing.expectEqual(@as(u16, 1), d1.?.id);

    const d2 = data.getEntry(2, 420);
    try std.testing.expect(d2 != null);
    try std.testing.expectEqual(@as(u16, 2), d2.?.id);

    const d3 = data.getEntry(1, 420); // Version mismatch
    try std.testing.expect(d3 == null);
}
