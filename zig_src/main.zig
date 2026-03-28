const std = @import("std");
const msdrg = @import("src/msdrg.zig");
const models = @import("src/models.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    // Use cross-platform argument iterator (handles UTF-16 on Windows)
    var arg_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer arg_iter.deinit();

    // Skip argv[0] (program name)
    _ = arg_iter.next();

    const data_dir = arg_iter.next() orelse {
        std.debug.print("Usage: msdrg <data_dir>\n", .{});
        return;
    };

    std.debug.print("Initializing GrouperChain from {s}...\n", .{data_dir});

    var chain = msdrg.GrouperChain.init(allocator, data_dir) catch |err| {
        std.debug.print("Failed to initialize chain: {}\n", .{err});
        return;
    };
    defer chain.deinit();

    std.debug.print("Creating Link for version 410...\n", .{});
    var link = try chain.create(410);
    defer link.deinit(allocator);

    std.debug.print("Running sample case...\n", .{});

    var data = models.ProcessingData.init(allocator);
    defer data.deinit();

    var context = models.ProcessingContext.init(allocator, &data, .{});

    // Sample Case
    // We use a dummy code "A001" which might not be in the real data,
    // but if the data files are loaded, it will try to look it up.
    context.data.principal_dx = try models.DiagnosisCode.init("A001", 'Y');
    context.data.age = 65;
    context.data.sex = .MALE;
    context.data.discharge_status = .HOME_SELFCARE_ROUTINE;

    const result = try link.execute(context);
    var final_ctx = result.context;
    defer final_ctx.deinit();

    if (result.continue_processing) {
        std.debug.print("Grouping Complete.\n", .{});
        std.debug.print("Initial DRG: {?}\n", .{final_ctx.data.initial_result.drg});
        std.debug.print("Final DRG: {?}\n", .{final_ctx.data.final_result.drg});
    } else {
        std.debug.print("Grouping Stopped Early.\n", .{});
    }
}

test {
    _ = @import("src/integration_test.zig");
    _ = @import("src/mce_data.zig");
    _ = @import("src/mce_enums.zig");
    _ = @import("src/mce_validation.zig");
    _ = @import("src/mce_editing.zig");
    _ = @import("src/mce.zig");
    _ = @import("src/mce_json_api.zig");
    _ = @import("src/mce_c_api.zig");
}
