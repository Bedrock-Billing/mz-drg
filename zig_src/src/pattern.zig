const std = @import("std");
const common = @import("common.zig");

pub const PatternHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    list_data_offset: u32,
    strings_offset: u32,
};

pub const PatternEntry = extern struct {
    id: u32,
    count: u32,
    offset: u32,
};

pub const PatternData = struct {
    mapped: common.MappedFile(PatternHeader),

    pub fn init(path: []const u8, magic: u32) !PatternData {
        const mapped = try common.MappedFile(PatternHeader).init(path, magic);
        return PatternData{ .mapped = mapped };
    }

    pub fn deinit(self: *PatternData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const PatternData) []const PatternEntry {
        const entries_ptr = @as([*]const PatternEntry, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getPattern(self: *const PatternData, id: u32) ?PatternEntry {
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
                return entry;
            }
        }
        return null;
    }

    pub fn getAttributes(self: *const PatternData, entry: PatternEntry) []const common.StringRef {
        const list_ptr = @as([*]const common.StringRef, @ptrCast(@alignCast(self.mapped.base_ptr + entry.offset)));
        return list_ptr[0..entry.count];
    }
};

test "PatternData lookup" {
    const filename = "test_pattern.bin";
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

    // Header: magic(4), num(4), entries_off(4), list_off(4), strings_off(4)
    try writeU32(file, 0x44585054);
    try writeU32(file, 2);
    try writeU32(file, 20);
    try writeU32(file, 20 + 2 * 12); // 2 entries * 12 bytes
    try writeU32(file, 20 + 2 * 12 + 2 * 8); // 2 list items * 8 bytes

    // Entry 1: ID 10, Count 1, Offset ?
    // Entry 2: ID 20, Count 1, Offset ?

    const list_start: u32 = 20 + 2 * 12;
    const strings_start: u32 = list_start + 2 * 8;

    // Write Entries
    try writeU32(file, 10);
    try writeU32(file, 1);
    try writeU32(file, list_start);

    try writeU32(file, 20);
    try writeU32(file, 1);
    try writeU32(file, list_start + 8);

    // Write List Data
    // Item 1: Offset ?, Len 3 ("ABC")
    try writeU32(file, strings_start);
    try writeU32(file, 3);

    // Item 2: Offset ?, Len 3 ("DEF")
    try writeU32(file, strings_start + 3);
    try writeU32(file, 3);

    // Write Strings
    try file.writeAll("ABC");
    try file.writeAll("DEF");

    var data = try PatternData.init(filename, 0x44585054);
    defer data.deinit();

    const p1 = data.getPattern(10);
    try std.testing.expect(p1 != null);
    try std.testing.expectEqual(@as(u32, 10), p1.?.id);

    const attrs1 = data.getAttributes(p1.?);
    try std.testing.expectEqual(@as(usize, 1), attrs1.len);
    try std.testing.expect(std.mem.eql(u8, attrs1[0].get(@as([*]const u8, @ptrCast(data.mapped.base_ptr))), "ABC"));

    const p2 = data.getPattern(20);
    try std.testing.expect(p2 != null);
    try std.testing.expectEqual(@as(u32, 20), p2.?.id);

    const p3 = data.getPattern(99);
    try std.testing.expect(p3 == null);
}
