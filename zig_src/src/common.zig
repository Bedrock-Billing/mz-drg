const std = @import("std");
pub const search = @import("search.zig");

pub const Code = extern struct {
    value: [8]u8,

    pub fn toSlice(self: *const Code) []const u8 {
        var len: usize = 0;
        while (len < 8 and self.value[len] != 0) : (len += 1) {}
        return self.value[0..len];
    }
};

pub const StringRef = extern struct {
    offset: u32,
    len: u32,

    pub fn get(self: *align(1) const StringRef, base: [*]const u8, base_len: usize) ![]const u8 {
        if (@as(u64, self.offset) + @as(u64, self.len) > @as(u64, base_len)) return error.DataTooShort;
        return base[self.offset .. self.offset + self.len];
    }
};

pub fn MappedFile(comptime HeaderType: type) type {
    return struct {
        data: []const u8,
        header: HeaderType,
        map: ?std.Io.File.MemoryMap = null,
        threaded: ?std.Io.Threaded = null,

        const Self = @This();

        pub fn init(path: []const u8, magic: u32) !Self {
            const allocator = std.heap.page_allocator;
            var threaded = std.Io.Threaded.init(allocator, .{});
            const io = threaded.io();
            errdefer threaded.deinit();

            const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, path, .{});
            defer std.Io.File.close(file, io);

            const file_size = try std.Io.File.length(file, io);
            var map = try std.Io.File.MemoryMap.create(io, file, .{
                .len = file_size,
                .protection = .{ .read = true, .write = false },
            });
            errdefer map.destroy(io);

            if (map.memory.len < @sizeOf(HeaderType)) return error.DataTooShort;
            var header: HeaderType = undefined;
            @memcpy(std.mem.asBytes(&header), map.memory[0..@sizeOf(HeaderType)]);

            if (header.magic != magic) {
                std.debug.print("Expected magic {x}, got {x}\n", .{ magic, header.magic });
                return error.InvalidMagic;
            }

            return Self{
                .data = map.memory,
                .header = header,
                .map = map,
                .threaded = threaded,
            };
        }

        pub fn initWithData(data: []const u8, magic: u32) !Self {
            if (data.len < @sizeOf(HeaderType)) return error.DataTooShort;

            var header: HeaderType = undefined;
            @memcpy(std.mem.asBytes(&header), data[0..@sizeOf(HeaderType)]);

            if (header.magic != magic) {
                std.debug.print("Expected magic {x}, got {x}\n", .{ magic, header.magic });
                return error.InvalidMagic;
            }

            return Self{
                .data = data,
                .header = header,
                .map = null,
                .threaded = null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.map) |*m| {
                m.destroy(self.threaded.?.io());
                self.threaded.?.deinit();
            }
        }

        pub fn base_ptr(self: *const Self) [*]const u8 {
            return self.data.ptr;
        }

        /// Returns a typed slice into the mapped data at the given byte offset and element count.
        /// Returns error.DataTooShort if the requested range exceeds the mapped data bounds.
        pub fn getSlice(self: *const Self, comptime T: type, offset: usize, count: usize) ![]align(1) const T {
            const end = offset + (count * @sizeOf(T));
            if (end > self.data.len) return error.DataTooShort;
            const bytes = self.data[offset..end];
            return @as([*]align(1) const T, @ptrCast(bytes.ptr))[0..count];
        }
    };
}

test "Code.toSlice" {
    const code = Code{ .value = "A123\x00\x00\x00\x00".* };
    try std.testing.expectEqualStrings("A123", code.toSlice());
}
