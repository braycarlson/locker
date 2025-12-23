const std = @import("std");

const Locker = @import("locker.zig").Locker;
const Logger = @import("logger.zig").Logger;

fn getLogPath(allocator: std.mem.Allocator) ![]u8 {
    const directory = try std.fs.getAppDataDir(allocator, "locker");

    defer allocator.free(directory);

    std.debug.assert(directory.len > 0);

    const result = try std.fs.path.join(allocator, &[_][]const u8{ directory, "locker.log" });

    std.debug.assert(result.len > 0);
    std.debug.assert(result.len > directory.len);

    return result;
}

fn initLogger(allocator: std.mem.Allocator) ?Logger {
    const log_path = getLogPath(allocator) catch return null;

    defer allocator.free(log_path);

    std.debug.assert(log_path.len > 0);

    return Logger.init(log_path, .{ .size = 5 * 1024 * 1024 }) catch null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const allocator = gpa.allocator();

    var logger = initLogger(allocator);

    defer {
        if (logger) |*l| {
            l.deinit();
        }
    }

    defer {
        const check = gpa.deinit();

        if (check == .leak) {
            std.debug.print("Memory leak detected!\n", .{});

            if (logger) |*l| {
                l.log("Memory leak detected!", .{});
            }
        }
    }

    var app: Locker = undefined;

    Locker.initInPlace(&app, allocator, &logger) catch |err| {
        if (logger) |*l| {
            l.log("Failed to initialize Locker: {}", .{err});
        }

        return err;
    };

    defer app.deinit();

    if (logger) |*l| {
        l.log("Starting Locker", .{});
    }

    app.run();
}

test {
    _ = @import("input/keycode.zig");
    _ = @import("buffer.zig");
    _ = @import("config.zig");
    _ = @import("constant.zig");
    _ = @import("error.zig");
    _ = @import("logger.zig");
    _ = @import("locker.zig");
}
