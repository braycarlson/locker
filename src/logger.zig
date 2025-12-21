const std = @import("std");
const testing = std.testing;

pub const Logger = struct {
    file: ?std.fs.File = null,
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Logger {
        return Logger{
            .allocator = allocator,
        };
    }

    pub fn open(self: *Logger) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const alloc = arena.allocator();
        const directory = try std.fs.getAppDataDir(alloc, "locker");

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        const path = try std.fs.path.join(alloc, &[_][]const u8{ directory, "locker.log" });

        self.file = try std.fs.createFileAbsolute(path, .{ .read = true, .truncate = false });
        try self.file.?.seekFromEnd(0);
    }

    pub fn deinit(self: *Logger) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }
    }

    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        const file = self.file orelse return;

        self.mutex.lock();
        defer self.mutex.unlock();

        var buffer: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        const timestamp = std.time.timestamp();
        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const yearDay = day.calculateYearDay();
        const monthDay = yearDay.calculateMonthDay();
        const daySeconds = datetime.getDaySeconds();

        writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            yearDay.year,
            monthDay.month.numeric(),
            monthDay.day_index + 1,
            daySeconds.getHoursIntoDay(),
            daySeconds.getMinutesIntoHour(),
            daySeconds.getSecondsIntoMinute(),
        }) catch return;

        writer.print(fmt ++ "\n", args) catch return;

        _ = file.write(fbs.getWritten()) catch return;
    }
};

test "Initialization" {
    var logger = Logger.init(testing.allocator);
    defer logger.deinit();

    try testing.expect(logger.file == null);
    try testing.expect(logger.allocator.ptr == testing.allocator.ptr);
}
