const std = @import("std");
const testing = std.testing;

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

        try self.file.?.writer().print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1, day_seconds.getHoursIntoDay(), day_seconds.getMinutesIntoHour(), day_seconds.getSecondsIntoMinute() });
        try self.file.?.writer().print(fmt ++ "\n", args);
        try self.file.?.sync();
    }
};

test "Initialization" {
    var logger = try Logger.init(testing.allocator);
    defer logger.deinit();

    try testing.expect(logger.file == null);
    try testing.expect(logger.allocator.ptr == testing.allocator.ptr);
}
