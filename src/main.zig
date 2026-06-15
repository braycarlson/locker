const std = @import("std");

const Application = @import("application.zig").Application;
const Logger = @import("logger.zig").Logger;
const path_util = @import("path.zig");

const log_size_max: u32 = 5 * 1024 * 1024;

pub fn main() void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var logger = init_logger(io);
    defer deinit_logger(&logger);

    var application: Application = undefined;
    application.init(io, if (logger) |*log| log else null);
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

fn init_logger(io: std.Io) ?Logger {
    var appdata_buffer: [path_util.path_length_max]u8 = undefined;

    const base = path_util.get_appdata_path(&appdata_buffer, "locker") catch return null;

    var path_buffer: [path_util.path_length_max]u8 = undefined;

    const log_path = path_util.join_path(&path_buffer, base, "locker.log") orelse return null;

    return Logger.init(io, .{ .path = log_path, .size = log_size_max }) catch null;
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
