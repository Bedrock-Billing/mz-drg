const std = @import("std");

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

    pub fn get(self: *const StringRef, base: [*]const u8) []const u8 {
        return base[self.offset .. self.offset + self.len];
    }
};

pub fn MappedFile(comptime HeaderType: type) type {
    return struct {
        map: std.Io.File.MemoryMap,
        header: *const HeaderType,
        threaded: std.Io.Threaded,

        const Self = @This();

        pub fn init(path: []const u8, magic: u32) !Self {
            const allocator = std.heap.page_allocator;
            var threaded = std.Io.Threaded.init(allocator, .{});
            const io = threaded.io();
            errdefer threaded.deinit();

            const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, path, .{});
            errdefer std.Io.File.close(file, io);

            const file_size = try std.Io.File.length(file, io);
            var map = try std.Io.File.MemoryMap.create(io, file, .{
                .len = file_size,
                .protection = .{ .read = true, .write = false },
            });
            errdefer map.destroy(io);

            const header: *const HeaderType = @ptrCast(@alignCast(map.memory.ptr));
            if (header.magic != magic) {
                std.debug.print("Expected magic {x}, got {x}\n", .{ magic, header.magic });
                return error.InvalidMagic;
            }

            return Self{
                .map = map,
                .header = header,
                .threaded = threaded,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.destroy(self.threaded.io());
            self.threaded.deinit();
        }

        pub fn base_ptr(self: *const Self) [*]const u8 {
            return self.map.memory.ptr;
        }
    };
}

test "Code.toSlice" {
    const code = Code{ .value = "A123\x00\x00\x00\x00".* };
    try std.testing.expectEqualStrings("A123", code.toSlice());
}
