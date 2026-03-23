const std = @import("std");
const common = @import("common.zig");

// --- Cluster Info ---
pub const ClusterInfoHeader = extern struct {
    magic: u32,
    num_clusters: u32,
    offsets_offset: u32,
    data_offset: u32,
    strings_offset: u32,
};

pub const ClusterInfoData = struct {
    mapped: common.MappedFile(ClusterInfoHeader),

    pub fn init(path: []const u8) !ClusterInfoData {
        const mapped = try common.MappedFile(ClusterInfoHeader).init(path, 0x434C494E);
        return ClusterInfoData{ .mapped = mapped };
    }

    pub fn deinit(self: *ClusterInfoData) void {
        self.mapped.deinit();
    }

    pub fn getClusterOffset(self: *const ClusterInfoData, cluster_index: usize) u32 {
        const offsets_ptr = @as([*]const u32, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.offsets_offset)));
        return offsets_ptr[cluster_index];
    }

    pub fn getCluster(self: *const ClusterInfoData, cluster_index: usize) Cluster {
        const offset = self.getClusterOffset(cluster_index);
        return Cluster{
            .base_ptr = self.mapped.base_ptr,
            .data_ptr = self.mapped.base_ptr + offset,
            .limit = self.mapped.base_ptr + self.mapped.data.len,
        };
    }
};

pub const Cluster = struct {
    base_ptr: [*]const u8,
    data_ptr: [*]const u8,
    limit: [*]const u8,

    pub fn getName(self: Cluster) []const u8 {
        if (@intFromPtr(self.data_ptr) + 8 > @intFromPtr(self.limit)) return "";
        const name_offset = std.mem.readInt(u32, self.data_ptr[0..4], .little);
        const len = std.mem.readInt(u32, self.data_ptr[4..8], .little);
        if (@intFromPtr(self.base_ptr) + name_offset + len > @intFromPtr(self.limit)) return "";
        return self.base_ptr[name_offset .. name_offset + len];
    }

    pub fn getSuppressionMdcs(self: Cluster) []const u8 {
        // Skip name offset (4) and len (4)
        if (@intFromPtr(self.data_ptr) + 9 > @intFromPtr(self.limit)) return &.{};
        const ptr = self.data_ptr + 8;
        const count = ptr[0];
        if (@intFromPtr(ptr) + 1 + count > @intFromPtr(self.limit)) return &.{};
        return ptr[1 .. 1 + count];
    }

    pub fn getChoices(self: Cluster) ChoiceIterator {
        // Skip name offset (4) and len (4)
        if (@intFromPtr(self.data_ptr) + 9 > @intFromPtr(self.limit)) return ChoiceIterator{
            .base_ptr = self.base_ptr,
            .ptr = self.data_ptr, // Dummy
            .count = 0,
            .index = 0,
            .limit = self.limit,
        };
        const ptr = self.data_ptr + 8;
        const supp_count = ptr[0];
        const choice_count_ptr = ptr + 1 + supp_count;

        if (@intFromPtr(choice_count_ptr) + 1 > @intFromPtr(self.limit)) return ChoiceIterator{
            .base_ptr = self.base_ptr,
            .ptr = self.data_ptr, // Dummy
            .count = 0,
            .index = 0,
            .limit = self.limit,
        };

        const choice_count = choice_count_ptr[0];
        return ChoiceIterator{
            .base_ptr = self.base_ptr,
            .ptr = choice_count_ptr + 1,
            .count = choice_count,
            .index = 0,
            .limit = self.limit,
        };
    }
};

pub const ChoiceIterator = struct {
    base_ptr: [*]const u8,
    ptr: [*]const u8,
    count: u8,
    index: u8,
    limit: [*]const u8,

    pub fn next(self: *ChoiceIterator) ?ClusterChoice {
        if (self.index >= self.count) return null;
        if (@intFromPtr(self.ptr) + 2 > @intFromPtr(self.limit)) return null;

        const id = self.ptr[0];
        const code_count = self.ptr[1];
        self.ptr += 2;

        const current_ptr = self.ptr;
        const size = @as(usize, code_count) * 8;
        if (@intFromPtr(self.ptr) + size > @intFromPtr(self.limit)) return null;

        self.ptr += size;
        self.index += 1;

        return ClusterChoice{
            .id = id,
            .base_ptr = self.base_ptr,
            .codes_ptr = current_ptr,
            .code_count = code_count,
            .limit = self.limit,
        };
    }
};

pub const ClusterChoice = struct {
    id: u8,
    base_ptr: [*]const u8,
    codes_ptr: [*]const u8,
    code_count: u8,
    limit: [*]const u8,

    pub fn getCodes(self: ClusterChoice) CodeIterator {
        return CodeIterator{
            .base_ptr = self.base_ptr,
            .ptr = self.codes_ptr,
            .count = self.code_count,
            .index = 0,
            .limit = self.limit,
        };
    }
};

pub const CodeIterator = struct {
    base_ptr: [*]const u8,
    ptr: [*]const u8,
    count: u8,
    index: u8,
    limit: [*]const u8,

    pub fn next(self: *CodeIterator) ?[]const u8 {
        if (self.index >= self.count) return null;
        if (@intFromPtr(self.ptr) + 8 > @intFromPtr(self.limit)) return null;

        const offset = std.mem.readInt(u32, self.ptr[0..4], .little);
        const len = std.mem.readInt(u32, self.ptr[4..8], .little);
        self.ptr += 8;
        self.index += 1;

        if (@intFromPtr(self.base_ptr) + offset + len > @intFromPtr(self.limit)) return null;

        return self.base_ptr[offset .. offset + len];
    }
};

test "ClusterInfoData accessors" {
    // Create a mock cluster info file
    const filename = "test_cluster_info.bin";
    const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, filename, .{ .read = true });
    defer {
        std.Io.File.close(file, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, filename) catch {};
    }

    // Construct data
    // Header: magic(4), num_clusters(4), offsets_offset(4), data_offset(4), strings_offset(4)
    // Offsets: [offset1]
    // Data:
    //   Cluster1: supp_count(1), supp_mdc(1), choice_count(1), choice_id(1), code_count(1), code_offset(4), code_len(4)
    // Strings: "CODE1"

    const writeU32 = struct {
        fn call(f: std.Io.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    const writeU8 = struct {
        fn call(f: std.Io.File, v: u8) !void {
            try std.Io.File.writeStreamingAll(f, std.testing.io, &[1]u8{v});
        }
    }.call;

    try writeU32(file, 0x434C494E); // Magic
    try writeU32(file, 1); // Num clusters
    try writeU32(file, 20); // Offsets offset (Header is 20 bytes)
    try writeU32(file, 24); // Data offset (Offsets is 4 bytes)
    try writeU32(file, 100); // Strings offset (Arbitrary)

    // Offsets
    try writeU32(file, 24); // Offset to Cluster 1

    // Cluster 1 Data (at 24)
    // Name offset (4), Name len (4), supp_count(1), supp_mdc(1), choice_count(1)
    try writeU32(file, 100); // Name offset
    try writeU32(file, 5); // Name len
    try writeU8(file, 1); // supp_count
    try writeU8(file, 5); // supp_mdc
    try writeU8(file, 1); // choice_count

    // Choice 1
    try writeU8(file, 10); // choice_id
    try writeU8(file, 1); // code_count
    try writeU32(file, 100); // code offset (reusing string)
    try writeU32(file, 5); // code len

    // Strings (at 100)
    try std.Io.File.writePositionalAll(file, std.testing.io, "CODE1", 100);

    // Test reading
    var data = try ClusterInfoData.init(filename);
    defer data.deinit();

    const cluster = data.getCluster(0);
    try std.testing.expectEqualStrings("CODE1", cluster.getName());

    const supp = cluster.getSuppressionMdcs();
    try std.testing.expectEqual(@as(usize, 1), supp.len);
    try std.testing.expectEqual(@as(u8, 5), supp[0]);

    var choices = cluster.getChoices();
    const choice = choices.next().?;
    try std.testing.expectEqual(@as(u8, 10), choice.id);

    var codes = choice.getCodes();
    const code = codes.next().?;
    try std.testing.expectEqualStrings("CODE1", code);

    try std.testing.expect(codes.next() == null);
    try std.testing.expect(choices.next() == null);
}

// --- Cluster Map ---
pub const ClusterMapHeader = extern struct {
    magic: u32,
    num_entries: u32,
    entries_offset: u32,
    list_data_offset: u32,
};

pub const ClusterMapEntry = extern struct {
    code: common.Code,
    version_start: i32,
    version_end: i32,
    list_offset: u32,
    list_count: u32,
};

pub const ClusterMapData = struct {
    mapped: common.MappedFile(ClusterMapHeader),

    pub fn init(path: []const u8) !ClusterMapData {
        const mapped = try common.MappedFile(ClusterMapHeader).init(path, 0x434C4D50);
        return ClusterMapData{ .mapped = mapped };
    }

    pub fn deinit(self: *ClusterMapData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const ClusterMapData) []const ClusterMapEntry {
        const entries_ptr = @as([*]const ClusterMapEntry, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getClusters(self: *const ClusterMapData, entry: ClusterMapEntry) []const u16 {
        const list_ptr = @as([*]const u16, @ptrCast(@alignCast(self.mapped.base_ptr + entry.list_offset)));
        return list_ptr[0..entry.list_count];
    }

    pub fn getEntry(self: *const ClusterMapData, code: []const u8, version: i32) ?ClusterMapEntry {
        const entries = self.getEntries();
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
                    if (version >= entry.version_start and version <= entry.version_end) {
                        return entry;
                    }
                    // Scan around
                    var i = mid;
                    while (i > 0) {
                        i -= 1;
                        const prev = entries[i];
                        if (!std.mem.eql(u8, prev.code.toSlice(), code)) break;
                        if (version >= prev.version_start and version <= prev.version_end) return prev;
                    }
                    i = mid + 1;
                    while (i < entries.len) {
                        const next = entries[i];
                        if (!std.mem.eql(u8, next.code.toSlice(), code)) break;
                        if (version >= next.version_start and version <= next.version_end) return next;
                        i += 1;
                    }
                    return null;
                },
            }
        }
        return null;
    }
};
