const std = @import("std");
const builtin = @import("builtin");

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
    if (builtin.os.tag == .windows) {
        return WindowsMappedFile(HeaderType);
    }
    return PosixMappedFile(HeaderType);
}

fn PosixMappedFile(comptime HeaderType: type) type {
    return struct {
        file: std.Io.File,
        data: []align(std.heap.page_size_min) u8,
        header: *const HeaderType,
        base_ptr: [*]const u8,
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
            const data = try std.posix.mmap(null, file_size, std.posix.PROT{
                .READ = true,
                .WRITE = false,
            }, .{ .TYPE = .PRIVATE }, file.handle, 0);
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
                .threaded = threaded,
            };
        }

        pub fn deinit(self: *Self) void {
            std.posix.munmap(self.data);
            std.Io.File.close(self.file, self.threaded.io());
            self.threaded.deinit();
        }
    };
}

fn WindowsMappedFile(comptime HeaderType: type) type {
    return struct {
        file: std.Io.File,
        data: []u8,
        header: *const HeaderType,
        base_ptr: [*]const u8,
        threaded: std.Io.Threaded,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(path: []const u8, magic: u32) !Self {
            const allocator = std.heap.page_allocator;
            var threaded = std.Io.Threaded.init(allocator, .{});
            const io = threaded.io();
            errdefer threaded.deinit();

            const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, path, .{});
            errdefer std.Io.File.close(file, io);

            const file_size = try std.Io.File.length(file, io);
            const data = try allocator.alloc(u8, file_size);
            errdefer allocator.free(data);

            const bytes_read = try std.Io.File.readPositionalAll(file, io, data, 0);
            if (bytes_read != file_size) {
                return error.UnexpectedEndOfFile;
            }

            const header: *const HeaderType = @ptrCast(@alignCast(data.ptr));
            if (header.magic != magic) {
                std.debug.print("Expected magic {x}, got {x}\n", .{ magic, header.magic });
                return error.InvalidMagic;
            }

            return Self{
                .file = file,
                .data = data,
                .header = header,
                .base_ptr = @as([*]const u8, @ptrCast(data.ptr)),
                .threaded = threaded,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            std.Io.File.close(self.file, self.threaded.io());
            self.threaded.deinit();
        }
    };
}

test "Code.toSlice" {
    const code = Code{ .value = "A123\x00\x00\x00\x00".* };
    try std.testing.expectEqualStrings("A123", code.toSlice());
}
