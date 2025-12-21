const std = @import("std");

const LockerError = @import("error.zig").LockerError;

pub const Logger = struct {
    file: ?std.fs.File = null,
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Logger {
        return Logger{
            .allocator = allocator,
        };
    }

    pub fn open(self: *Logger) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        const directory = try std.fs.getAppDataDir(allocator, "locker");

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        const path = try std.fs.path.join(allocator, &[_][]const u8{ directory, "locker.log" });

        self.file = try std.fs.createFileAbsolute(path, .{ .read = true, .truncate = false });
        try self.file.?.seekFromEnd(0);
    }

    pub fn deinit(self: *Logger) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }
    }

    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        if (self.file == null) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = std.time.timestamp();
        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = datetime.getDaySeconds();

        var buffer: [4096]u8 = undefined;

        const timestamp_str = std.fmt.bufPrint(&buffer, "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        }) catch return;

        _ = self.file.?.writeAll(timestamp_str) catch return;

        const message = std.fmt.bufPrint(buffer[timestamp_str.len..], fmt ++ "\n", args) catch return;
        _ = self.file.?.writeAll(message) catch return;
    }
};
