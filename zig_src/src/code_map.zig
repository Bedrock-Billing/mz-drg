const std = @import("std");
const common = @import("common.zig");

pub const CodeMapHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
};

pub const CodeMapEntry = extern struct {
    code: common.Code,
    version_start: i32,
    version_end: i32,
    value: i32,
};

pub const CodeMapData = struct {
    mapped: common.MappedFile(CodeMapHeader),

    pub fn init(path: []const u8, magic: u32) !CodeMapData {
        const mapped = try common.MappedFile(CodeMapHeader).init(path, magic);
        return CodeMapData{ .mapped = mapped };
    }

    pub fn deinit(self: *CodeMapData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const CodeMapData) []const CodeMapEntry {
        const entries_ptr = @as([*]const CodeMapEntry, @ptrCast(@alignCast(self.mapped.base_ptr() + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getEntry(self: *const CodeMapData, code: []const u8, version: i32) ?CodeMapEntry {
        const entries = self.getEntries();

        // Binary search for the code
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = entries[mid];
            const entry_code = entry.code.toSlice();

            const order = std.mem.order(u8, entry_code, code);
            switch (order) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => {
                    // Found a match, but there might be multiple versions.
                    // We need to find the specific version.
                    // Since we sorted by key, version_start, we can scan around.
                    // But first, let's check if this one matches.
                    if (version >= entry.version_start and version <= entry.version_end) {
                        return entry;
                    }

                    // Scan backwards
                    var i = mid;
                    while (i > 0) {
                        i -= 1;
                        const prev = entries[i];
                        if (!std.mem.eql(u8, prev.code.toSlice(), code)) break;
                        if (version >= prev.version_start and version <= prev.version_end) return prev;
                    }

                    // Scan forwards
                    i = mid + 1;
                    while (i < entries.len) {
                        const next = entries[i];
                        if (!std.mem.eql(u8, next.code.toSlice(), code)) break;
                        if (version >= next.version_start and version <= next.version_end) return next;
                        i += 1;
                    }

                    return null; // Code found, but version mismatch
                },
            }
        }
        return null;
    }
};

test "CodeMapData lookup" {
    const filename = "test_codemap.bin";
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
        fn call(f: std.Io.File, code: []const u8, v_start: i32, v_end: i32, value: i32) !void {
            var code_buf: [8]u8 = [_]u8{0} ** 8;
            @memcpy(code_buf[0..code.len], code);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &code_buf);

            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v_start, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, v_end, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, value, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Header: magic(4), num_entries(4), entries_offset(4)
    try writeU32(file, 0x12345678);
    try writeU32(file, 3); // 3 entries
    try writeU32(file, 12); // entries offset (header size)

    // Entries (Sorted by code)
    // A001, v400-410
    try writeEntry(file, "A001", 400, 410, 100);
    // A001, v411-430
    try writeEntry(file, "A001", 411, 430, 200);
    // B002, v400-430
    try writeEntry(file, "B002", 400, 430, 300);

    var data = try CodeMapData.init(filename, 0x12345678);
    defer data.deinit();

    // Test lookup
    const e1 = data.getEntry("A001", 405);
    try std.testing.expect(e1 != null);
    try std.testing.expectEqual(@as(i32, 100), e1.?.value);

    const e2 = data.getEntry("A001", 420);
    try std.testing.expect(e2 != null);
    try std.testing.expectEqual(@as(i32, 200), e2.?.value);

    const e3 = data.getEntry("B002", 400);
    try std.testing.expect(e3 != null);
    try std.testing.expectEqual(@as(i32, 300), e3.?.value);

    const e4 = data.getEntry("C999", 400);
    try std.testing.expect(e4 == null);

    const e5 = data.getEntry("A001", 399); // Version mismatch
    try std.testing.expect(e5 == null);
}
