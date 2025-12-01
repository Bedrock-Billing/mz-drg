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
        file: std.fs.File,
        data: []align(std.heap.page_size_min) u8,
        header: *const HeaderType,
        base_ptr: [*]const u8,

        const Self = @This();

        pub fn init(path: []const u8, magic: u32) !Self {
            const file = try std.fs.cwd().openFile(path, .{});
            errdefer file.close();

            const file_size = try file.getEndPos();
            const data = try std.posix.mmap(null, file_size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, file.handle, 0);
            errdefer std.posix.munmap(data);

            const header = @as(*const HeaderType, @ptrCast(data.ptr));
            if (header.magic != magic) {
                std.debug.print("Expected magic {x}, got {x}\n", .{ magic, header.magic });
                return error.InvalidMagic;
            }

            return Self{
                .file = file,
                .data = data,
                .header = header,
                .base_ptr = @as([*]const u8, @ptrCast(data.ptr)),
            };
        }

        pub fn deinit(self: *Self) void {
            std.posix.munmap(self.data);
            self.file.close();
        }
    };
}

test "Code.toSlice" {
    const code = Code{ .value = "A123\x00\x00\x00\x00".* };
    try std.testing.expectEqualStrings("A123", code.toSlice());
}
