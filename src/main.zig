const std = @import("std");

const arc = @import("arc");
const umbra = @import("umbra");

const Application = @import("application.zig").Application;
const directory_name = @import("config.zig").directory_name;

const assert = std.debug.assert;

const log_backup_count: u32 = 5;
const log_bytes_max: u32 = 5 * 1024 * 1024;
const log_name = "locker.log";
const exit_failure: u8 = 1;
const exit_success: u8 = 0;

comptime {
    assert(log_backup_count <= arc.limits.rotating_backup_count_max);
    assert(log_name.len > 0);
    assert(umbra.limits.path_bytes_max > log_name.len);
    assert(exit_failure != exit_success);
}

pub fn main() u8 {
    var application: Application = undefined;
    var core: arc.Core = undefined;
    var rotating_file: arc.RotatingFile = undefined;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const rotating = init_rotating(io, &rotating_file);
    defer if (rotating) |file| file.deinit(io);

    const logger = init_logger(io, &core, rotating);
    defer if (logger) |log| flush(log);

    application.init(io, logger) catch |err| {
        report(logger, "Unable to initialise the application", err);

        return exit_failure;
    };

    defer application.deinit();

    if (logger) |log| {
        log.information("Starting application", &.{}, &@src());
    }

    application.run() catch |err| {
        report(logger, "Unable to run the application", err);

        return exit_failure;
    };

    return exit_success;
}

fn init_logger(io: std.Io, target: *arc.Core, writer: ?*arc.RotatingFile) ?*const arc.Logger {
    const file = writer orelse return null;

    var encoding: arc.Encoding = .development;

    encoding.level = .capital;
    encoding.time = .rfc3339_nano;

    const sinks = [_]arc.Core.Sink{.{
        .encoding = encoding,
        .level = .debug,
        .writer = .{ .rotating_file = file },
    }};

    var options: arc.Core.Options = .development;

    options.caller = false;
    options.level = .information;
    options.sinks = &sinks;
    options.thread_safe = true;

    target.init(io, &options);

    return &target.logger;
}

fn init_rotating(io: std.Io, target: *arc.RotatingFile) ?*arc.RotatingFile {
    var directory_buffer: [umbra.limits.path_bytes_max]u8 = undefined;

    const directory = umbra.paths.state_dir(&directory_buffer, directory_name) catch {
        return null;
    };

    assert(directory.len > 0);

    std.Io.Dir.cwd().createDirPath(io, directory) catch {
        return null;
    };

    var path_buffer: [umbra.limits.path_bytes_max]u8 = undefined;

    const path = std.mem.print(
        &path_buffer,
        "{s}{c}{s}",
        .{ directory, std.Io.Dir.path.sep, log_name },
    ) catch {
        return null;
    };

    assert(path.len > directory.len);

    target.init(io, &.{
        .backup_count = log_backup_count,
        .path = path,
        .roll_daily = true,
        .size_max = log_bytes_max,
    }) catch {
        return null;
    };

    return target;
}

fn flush(logger: *const arc.Logger) void {
    logger.core.flush() catch {
        return;
    };
}

fn report(logger: ?*const arc.Logger, message: []const u8, err: anyerror) void {
    assert(message.len > 0);

    const log = logger orelse return;

    log.err(message, &.{.{ .key = "error", .value = .{ .string = @errorName(err) } }}, &@src());
}
