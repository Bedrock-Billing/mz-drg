const std = @import("std");
const common = @import("common.zig");

pub const DataHeader = extern struct {
    magic: u32,
    num_groups: u32,
};

pub const ExclusionGroupIndex = extern struct {
    key: i32,
    code_count: u32,
    code_offset: u32,
};

pub const ExclusionData = struct {
    mapped: common.MappedFile(DataHeader),

    pub fn init(path: []const u8) !ExclusionData {
        const mapped = try common.MappedFile(DataHeader).init(path, 0x4D534452);
        return ExclusionData{ .mapped = mapped };
    }

    pub fn initWithData(data: []const u8) !ExclusionData {
        const mapped = try common.MappedFile(DataHeader).initWithData(data, 0x4D534452);
        return ExclusionData{ .mapped = mapped };
    }

    pub fn deinit(self: *ExclusionData) void {
        self.mapped.deinit();
    }

    pub fn getIndices(self: *const ExclusionData) ![]align(1) const ExclusionGroupIndex {
        return try self.mapped.getSlice(ExclusionGroupIndex, @sizeOf(DataHeader), self.mapped.header.num_groups);
    }

    pub fn getGroups(self: *const ExclusionData) ![]align(1) const ExclusionGroupIndex {
        return try self.getIndices();
    }

    pub fn getGroup(self: *const ExclusionData, key: i32) !?ExclusionGroupIndex {
        const groups = try self.getGroups();
        var left: usize = 0;
        var right: usize = groups.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const group = groups[mid];

            if (group.key < key) {
                left = mid + 1;
            } else if (group.key > key) {
                right = mid;
            } else {
                return group;
            }
        }
        return null;
    }

    pub fn getCodes(self: *const ExclusionData, group: ExclusionGroupIndex) ![]align(1) const common.Code {
        return try self.mapped.getSlice(common.Code, group.code_offset, group.code_count);
    }
};

test "ExclusionData lookup" {
    const filename = "test_exclusion.bin";
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

    const writeI32 = struct {
        fn call(f: std.Io.File, v: i32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Header: magic(4), num_groups(4)
    try writeU32(file, 0x4D534452);
    try writeU32(file, 2);

    // Index (2 entries * 12 bytes)
    // Entry 1: Key 10, Count 1, Offset ?
    // Entry 2: Key 20, Count 2, Offset ?

    // Calculate offsets
    // Header: 8
    // Index: 2 * 12 = 24
    // Data start: 32

    const offset1: u32 = 32;
    const offset2: u32 = 32 + 8; // 1 code * 8 bytes

    // Write Index
    try writeI32(file, 10);
    try writeU32(file, 1);
    try writeU32(file, offset1);

    try writeI32(file, 20);
    try writeU32(file, 2);
    try writeU32(file, offset2);

    // Write Data
    // Group 1 codes
    var code_buf: [8]u8 = [_]u8{0} ** 8;
    @memcpy(code_buf[0..4], "A001");
    try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);

    // Group 2 codes
    @memcpy(code_buf[0..4], "B002");
    try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);
    @memcpy(code_buf[0..4], "C003");
    try std.Io.File.writeStreamingAll(file, std.testing.io, &code_buf);

    var data = try ExclusionData.init(filename);
    defer data.deinit();

    const g1 = try data.getGroup(10);
    try std.testing.expect(g1 != null);
    try std.testing.expectEqual(@as(i32, 10), g1.?.key);
    try std.testing.expectEqual(@as(u32, 1), g1.?.code_count);

    const codes1 = try data.getCodes(g1.?);
    try std.testing.expectEqual(@as(usize, 1), codes1.len);
    try std.testing.expect(std.mem.eql(u8, codes1[0].toSlice(), "A001"));

    const g2 = try data.getGroup(20);
    try std.testing.expect(g2 != null);
    try std.testing.expectEqual(@as(i32, 20), g2.?.key);

    const g3 = try data.getGroup(99);
    try std.testing.expect(g3 == null);
}
