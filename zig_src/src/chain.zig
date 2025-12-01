const std = @import("std");
const models = @import("models.zig");

pub const LinkResult = struct {
    context: models.ProcessingContext,
    continue_processing: bool,
};

pub const Link = struct {
    ptr: *anyopaque,
    executeFn: *const fn (ptr: *anyopaque, context: models.ProcessingContext) anyerror!LinkResult,
    deinitFn: ?*const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void = null,

    pub fn execute(self: Link, context: models.ProcessingContext) !LinkResult {
        const result = try self.executeFn(self.ptr, context);
        if (!result.continue_processing) {
            std.log.debug("Link: Stopping chain execution.", .{});
        }
        return result;
    }

    pub fn deinit(self: Link, allocator: std.mem.Allocator) void {
        if (self.deinitFn) |func| {
            func(self.ptr, allocator);
        }
    }
};

pub fn compose(first: Link, second: Link, allocator: std.mem.Allocator) !Link {
    const ComposedLink = struct {
        first: Link,
        second: Link,

        pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !LinkResult {
            const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
            const result = try self.first.execute(context);
            if (!result.continue_processing) {
                return result;
            }
            return self.second.execute(result.context);
        }

        pub fn deinit(ptr: *anyopaque, alloc: std.mem.Allocator) void {
            const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
            self.first.deinit(alloc);
            self.second.deinit(alloc);
            alloc.destroy(self);
        }
    };

    const instance = try allocator.create(ComposedLink);
    instance.* = .{ .first = first, .second = second };

    return Link{
        .ptr = instance,
        .executeFn = ComposedLink.execute,
        .deinitFn = ComposedLink.deinit,
    };
}

// Helper to create a chain from a slice of Links
pub fn createChain(allocator: std.mem.Allocator, links: []const Link) !Link {
    if (links.len == 0) {
        return error.EmptyChain;
    }

    var current = links[0];
    for (links[1..]) |next| {
        current = try compose(current, next, allocator);
    }
    return current;
}

test "chain basic usage" {
    const allocator = std.testing.allocator;

    const TestLink = struct {
        id: i32,
        should_continue: bool,

        pub fn execute(ptr: *anyopaque, context: models.ProcessingContext) !LinkResult {
            const self = @as(*@This(), @ptrCast(@alignCast(ptr)));
            var ctx = context;
            try ctx.initial_mdc.append(ctx.allocator, self.id);
            return LinkResult{
                .context = ctx,
                .continue_processing = self.should_continue,
            };
        }
    };

    var link1_impl = TestLink{ .id = 1, .should_continue = true };
    const link1 = Link{
        .ptr = &link1_impl,
        .executeFn = TestLink.execute,
    };

    var link2_impl = TestLink{ .id = 2, .should_continue = true };
    const link2 = Link{
        .ptr = &link2_impl,
        .executeFn = TestLink.execute,
    };

    const composed = try compose(link1, link2, allocator);
    defer composed.deinit(allocator);

    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    const context = models.ProcessingContext.init(allocator, &data, .{});
    // context is initially empty, so no allocation yet.
    // If execute succeeds, it returns a new context with allocations.
    // If execute fails, context is still empty (no leak).

    const result = try composed.execute(context);

    // The result context owns the memory now.
    var final_ctx = result.context;
    defer final_ctx.deinit();

    try std.testing.expect(result.continue_processing);
    try std.testing.expectEqual(final_ctx.initial_mdc.items.len, 2);
    try std.testing.expectEqual(final_ctx.initial_mdc.items[0], 1);
    try std.testing.expectEqual(final_ctx.initial_mdc.items[1], 2);
}
