const std = @import("std");

const Application = @import("application.zig").Application;
const Logger = @import("logger.zig").Logger;

const log_size_max: usize = 5 * 1024 * 1024;

pub fn main() !void {
    var logger = init_logger();
    defer deinit_logger(&logger);

    var application = Application.init(if (logger) |*log| log else null) catch |err| {
        if (logger) |*log| {
            log.log("Failed to initialize application: {}", .{err});
        }
        return err;
    };

    defer application.deinit();

    if (logger) |*log| {
        log.log("Starting application", .{});
    }

    application.run();
}

fn deinit_logger(logger: *?Logger) void {
    if (logger.*) |*log| {
        log.deinit();
    }
}

fn init_logger() ?Logger {
    return Logger.init(.{ .size = log_size_max }) catch null;
}

test {
    _ = @import("application.zig");
    _ = @import("config.zig");
    _ = @import("handler.zig");
    _ = @import("icon.zig");
    _ = @import("logger.zig");
    _ = @import("menu.zig");
    _ = @import("notification.zig");
    _ = @import("path.zig");
    _ = @import("remap.zig");
    _ = @import("settings.zig");
    _ = @import("state.zig");
}
