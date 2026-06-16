const std = @import("std");

const arc = @import("arc");

const Application = @import("application.zig").Application;
const path_util = @import("path.zig");

const log_size_max: u32 = 5 * 1024 * 1024;

pub fn main() void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var rotating = init_rotating(io);
    defer if (rotating) |*writer| writer.deinit(io);

    var logger = init_logger(io, if (rotating) |*writer| writer else null);
    defer if (logger) |*log| log.sync() catch {};

    var application: Application = undefined;
    application.init(io, if (logger) |*log| log else null);
    defer application.deinit();

    if (logger) |*log| {
        log.info("Starting application", &.{}, @src());
    }

    application.run();
}

fn init_logger(io: std.Io, writer: ?*arc.RotatingWriter) ?arc.Logger {
    const target = writer orelse return null;

    const config = arc.Config.development()
        .with_level(.info)
        .without_caller()
        .with_stacktrace_level(.fatal)
        .with_encoder_config(arc.EncoderConfig.development()
            .with_level_encoding(.capital)
            .with_time_encoding(.rfc3339_nano))
        .with_writer(.{ .rotating = target });

    return arc.Logger.init_with_config(io, config);
}

fn init_rotating(io: std.Io) ?arc.RotatingWriter {
    var appdata_buffer: [path_util.path_length_max]u8 = undefined;

    const base = path_util.get_appdata_path(&appdata_buffer, "locker") catch return null;

    var path_buffer: [path_util.path_length_max]u8 = undefined;

    const log_path = path_util.join_path(&path_buffer, base, "locker.log") orelse return null;

    path_util.ensure_directory_exists(io, log_path) catch return null;

    return arc.RotatingWriter.init(io, .{ .path = log_path, .size_max = log_size_max }) catch null;
}

test {
    _ = @import("application.zig");
    _ = @import("config.zig");
    _ = @import("handler.zig");
    _ = @import("icon.zig");
    _ = @import("menu.zig");
    _ = @import("notification.zig");
    _ = @import("path.zig");
    _ = @import("remap.zig");
    _ = @import("settings.zig");
    _ = @import("state.zig");
}
